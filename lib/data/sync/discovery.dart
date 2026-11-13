import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/models/sync.dart';

/// 局域网设备发现（UDP 广播）。
///
/// 协议：每秒向 255.255.255.255:47820 发送一次 JSON 信标；
/// 收到信标即记录为在线设备，并回发一次以加速双向发现。
class LanDiscovery {
  LanDiscovery({
    required this.deviceId,
    required this.deviceName,
    required this.servicePort,
    this.version = '1.0.0',
    this.onPeersChanged,
  });

  static const int beaconPort = 47820;
  static const Duration _interval = Duration(seconds: 2);
  static const Duration _peerTtl = Duration(seconds: 9);

  final String deviceId;
  final String deviceName;
  final int servicePort;
  final String version;
  final ValueChanged<List<SyncPeer>>? onPeersChanged;

  RawDatagramSocket? _socket;
  Timer? _timer;
  Timer? _prune;
  bool _running = false;

  final Map<String, SyncPeer> _peers = {};

  bool get running => _running;
  List<SyncPeer> get peers => _peers.values.toList()
    ..sort((a, b) => (a.name).compareTo(b.name));

  String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  Future<void> start() async {
    if (_running || kIsWeb) return;
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort,
          reuseAddress: true);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onEvent, onError: (e) => debugPrint('discovery error: $e'));
      _running = true;
      _sendBeacon();
      _timer = Timer.periodic(_interval, (_) => _sendBeacon());
      _prune = Timer.periodic(const Duration(seconds: 3), (_) {
        final cutoff = DateTime.now().subtract(_peerTtl);
        final before = _peers.length;
        _peers.removeWhere((_, p) => p.lastSeen != null && p.lastSeen!.isBefore(cutoff));
        if (before != _peers.length) _notify();
      });
    } catch (e) {
      debugPrint('启动发现失败: $e');
      _running = false;
    }
  }

  void _sendBeacon() {
    final socket = _socket;
    if (socket == null) return;
    final payload = jsonEncode({
      'svc': 'poqi',
      'id': deviceId,
      'name': deviceName,
      'port': servicePort,
      'platform': platformName,
      'version': version,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      socket.send(
        utf8.encode(payload),
        InternetAddress('255.255.255.255'),
        beaconPort,
      );
    } catch (e) {
      debugPrint('beacon 发送失败: $e');
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    try {
      final text = utf8.decode(dg.data);
      final data = jsonDecode(text);
      if (data is! Map || data['svc'] != 'poqi') return;
      final id = '${data['id'] ?? ''}';
      if (id.isEmpty || id == deviceId) return;
      final host = dg.address.address;
      final peer = SyncPeer(
        id: id,
        name: '${data['name'] ?? '未命名设备'}',
        host: host,
        port: (data['port'] as num?)?.toInt() ?? 8766,
        platform: '${data['platform'] ?? ''}',
        version: '${data['version'] ?? ''}',
        lastSeen: DateTime.now(),
      );
      _peers[id] = peer;
      _notify();
      // 回发一次，让对方也能立即看到我。
      _sendBeacon();
    } catch (_) {
      // 忽略非法广播
    }
  }

  void _notify() => onPeersChanged?.call(peers);

  Future<void> stop() async {
    _timer?.cancel();
    _prune?.cancel();
    _socket?.close();
    _socket = null;
    _running = false;
    _peers.clear();
    _notify();
  }

  /// 本机所有 IPv4 地址，用于在界面上直接给出可填写的 MCP 地址。
  static Future<List<String>> localAddresses() async {
    if (kIsWeb) return const [];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final out = <String>[];
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (a.isLoopback) continue;
          out.add(a.address);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
