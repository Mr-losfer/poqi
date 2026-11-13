import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mcp/mcp_server.dart';
import '../data/sync/discovery.dart';
import '../data/sync/sync_server.dart';
import '../data/update/updater.dart';
import '../domain/models/release.dart';
import '../domain/models/sync.dart';
import 'home_search.dart';
import 'providers.dart';

class ConnectState {
  const ConnectState({
    this.discoveryRunning = false,
    this.peers = const [],
    this.localIps = const [],
    this.pin = '',
    this.syncRunning = false,
    this.syncPort = 0,
    this.mcpRunning = false,
    this.mcpPort = 0,
    this.busy = false,
    this.log = '',
    this.lastReport,
    this.update,
    this.download,
    this.downloadedPath,
    this.updateError,
  });

  final bool discoveryRunning;
  final List<SyncPeer> peers;
  final List<String> localIps;
  final String pin;
  final bool syncRunning;
  final int syncPort;
  final bool mcpRunning;
  final int mcpPort;
  final bool busy;
  final String log;
  final SyncReport? lastReport;
  final UpdateCheckOutcome? update;
  final DownloadProgress? download;
  final String? downloadedPath;
  final String? updateError;

  bool get serversRunning => syncRunning || mcpRunning;

  ConnectState copyWith({
    bool? discoveryRunning,
    List<SyncPeer>? peers,
    List<String>? localIps,
    String? pin,
    bool? syncRunning,
    int? syncPort,
    bool? mcpRunning,
    int? mcpPort,
    bool? busy,
    String? log,
    SyncReport? lastReport,
    UpdateCheckOutcome? update,
    DownloadProgress? download,
    String? downloadedPath,
    String? updateError,
  }) {
    return ConnectState(
      discoveryRunning: discoveryRunning ?? this.discoveryRunning,
      peers: peers ?? this.peers,
      localIps: localIps ?? this.localIps,
      pin: pin ?? this.pin,
      syncRunning: syncRunning ?? this.syncRunning,
      syncPort: syncPort ?? this.syncPort,
      mcpRunning: mcpRunning ?? this.mcpRunning,
      mcpPort: mcpPort ?? this.mcpPort,
      busy: busy ?? this.busy,
      log: log ?? this.log,
      lastReport: lastReport ?? this.lastReport,
      update: update ?? this.update,
      download: download ?? const DownloadProgress(received: 0, total: 0),
      downloadedPath: downloadedPath ?? this.downloadedPath,
      updateError: updateError ?? this.updateError,
    );
  }
}

final connectProvider = NotifierProvider<ConnectController, ConnectState>(
  ConnectController.new,
);

class ConnectController extends Notifier<ConnectState> {
  LanDiscovery? _discovery;
  SyncServer? _sync;
  McpServer? _mcp;
  final _client = SyncClient();
  final _updater = UpdateService();
  Timer? _autoCheck;

  @override
  ConnectState build() {
    ref.onDispose(() {
      _discovery?.stop();
      _sync?.stop();
      _mcp?.stop();
      _autoCheck?.cancel();
    });
    return const ConnectState();
  }

  String _pinFromSettings() {
    final code = ref.read(settingsProvider).pairCode;
    return code.isEmpty ? '2468' : code;
  }

  Future<void> bootstrap() async {
    final settings = ref.read(settingsProvider);
    final pin = _pinFromSettings();
    state = state.copyWith(pin: pin, localIps: await LanDiscovery.localAddresses());

    if (settings.mcpEnabled) {
      await startMcp(settings.mcpPort);
    }
    if (settings.syncEnabled) {
      await startSync(settings.syncPort);
    }
    await refreshIps();
  }

  Future<void> refreshIps() async {
    final ips = await LanDiscovery.localAddresses();
    state = state.copyWith(localIps: ips);
  }

  Future<void> startMcp(int port) async {
    final backend = ref.read(backendProvider);
    final settings = ref.read(settingsProvider);
    try {
      final server = McpServer(
        backend: backend,
        deviceName: settings.deviceName.isEmpty ? backend.deviceName : settings.deviceName,
        // MCP 直接写仓库，不经过 notifier；写完通知一次，界面才不会停在旧数据上。
        onMutated: () {
          ref.invalidate(pluginsProvider);
          ref.invalidate(sitesProvider);
          ref.invalidate(homeProvider);
        },
      );
      final actual = await server.start(port);
      _mcp = server;
      state = state.copyWith(mcpRunning: true, mcpPort: actual);
      await ref.read(settingsProvider.notifier).patch(mcpEnabled: true, mcpPort: actual);
    } catch (e) {
      state = state.copyWith(mcpRunning: false, log: 'MCP 启动失败：$e');
    }
  }

  Future<void> stopMcp() async {
    await _mcp?.stop();
    _mcp = null;
    state = state.copyWith(mcpRunning: false);
    await ref.read(settingsProvider.notifier).patch(mcpEnabled: false);
  }

  Future<void> startSync(int port) async {
    final backend = ref.read(backendProvider);
    final settings = ref.read(settingsProvider);
    try {
      final server = SyncServer(
        backend: backend,
        deviceName: settings.deviceName.isEmpty ? backend.deviceName : settings.deviceName,
        pin: state.pin,
      );
      final actual = await server.start(port);
      _sync = server;
      state = state.copyWith(syncRunning: true, syncPort: actual);
      await ref.read(settingsProvider.notifier).patch(syncEnabled: true, syncPort: actual);
      if (!state.discoveryRunning) await startDiscovery();
    } catch (e) {
      state = state.copyWith(syncRunning: false, log: '同步服务启动失败：$e');
    }
  }

  Future<void> stopSync() async {
    await _sync?.stop();
    _sync = null;
    await _discovery?.stop();
    _discovery = null;
    state = state.copyWith(syncRunning: false, discoveryRunning: false, peers: const []);
    await ref.read(settingsProvider.notifier).patch(syncEnabled: false);
  }

  Future<void> startDiscovery() async {
    if (state.discoveryRunning) return;
    final backend = ref.read(backendProvider);
    final discovery = LanDiscovery(
      deviceId: backend.deviceId,
      deviceName: ref.read(settingsProvider).deviceName,
      servicePort: state.syncPort > 0 ? state.syncPort : 8766,
      onPeersChanged: (peers) {
        state = state.copyWith(peers: peers);
      },
    );
    await discovery.start();
    _discovery = discovery;
    state = state.copyWith(discoveryRunning: discovery.running);
    if (!discovery.running) {
      state = state.copyWith(log: '无法开启广播发现（端口被占用或无网络权限）');
    }
  }

  /// 拉取远端数据并合并到本机。
  Future<SyncReport?> pullFrom(SyncPeer peer) async {
    state = state.copyWith(busy: true, log: '正在从 ${peer.name} 拉取…');
    try {
      final snapshot = await _client.pull(peer, pin: state.pin);
      final report = await ref.read(backendProvider).merge(snapshot);
      _refreshAll();
      state = state.copyWith(
        busy: false,
        lastReport: report,
        log: '已从 ${peer.name} 合并 ${report.total} 项',
      );
      return report;
    } catch (e) {
      state = state.copyWith(busy: false, log: '拉取失败：$e');
      return null;
    }
  }

  /// 把本机数据推给远端。
  Future<SyncReport?> pushTo(SyncPeer peer) async {
    state = state.copyWith(busy: true, log: '正在推送到 ${peer.name}…');
    try {
      final snapshot = ref.read(backendProvider).snapshot();
      final report = await _client.push(snapshot, peer, pin: state.pin);
      state = state.copyWith(
        busy: false,
        lastReport: report,
        log: '已推送 ${snapshot.total} 项到 ${peer.name}',
      );
      return report;
    } catch (e) {
      state = state.copyWith(busy: false, log: '推送失败：$e');
      return null;
    }
  }

  void _refreshAll() {
    ref.read(pluginsProvider.notifier).reload();
    ref.read(sitesProvider.notifier).reload();
    ref.read(favoritesProvider.notifier).reload();
    ref.read(historyProvider.notifier).reload();
  }

  // ---------------- 更新 ----------------

  Future<UpdateCheckOutcome?> checkUpdate({bool silent = false}) async {
    if (!silent) state = state.copyWith(busy: true, updateError: null);
    try {
      final outcome = await _updater.check(ref.read(settingsProvider));
      state = state.copyWith(
        busy: false,
        update: outcome,
        updateError: outcome.failed ? outcome.message : null,
      );
      await ref.read(settingsProvider.notifier).patch();
      return outcome;
    } catch (e) {
      state = state.copyWith(busy: false, updateError: '检查失败：$e');
      return null;
    }
  }

  Future<void> downloadUpdate(ReleaseInfo release) async {
    state = state.copyWith(busy: true, download: const DownloadProgress(received: 0, total: 0));
    try {
      final file = await _updater.download(
        release,
        preferProxy: ref.read(settingsProvider).preferProxy,
        onProgress: (p) {
          state = state.copyWith(download: p);
        },
      );
      state = state.copyWith(busy: false, downloadedPath: file.path);
    } catch (e) {
      state = state.copyWith(busy: false, updateError: '$e');
    }
  }

  Future<void> installDownloaded() async {
    final path = state.downloadedPath;
    if (path == null) return;
    try {
      await _updater.install(File(path));
    } catch (e) {
      state = state.copyWith(updateError: '$e');
    }
  }

  Future<void> openReleasePage(String url) => _updater.openReleasePage(url);

  Future<String> currentVersion() => _updater.currentVersion();
}
