import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/primitives.dart';
import '../../domain/models/settings.dart';
import '../../domain/models/sync.dart';
import '../../state/connect.dart';
import '../../state/providers.dart';
import '../shell/pq_shell.dart';

/// 连接中心：局域网 MCP、设备同步与应用更新。
class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  String _version = '';
  String? _busyPeerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVersion();
      if (ref.read(connectProvider).localIps.isEmpty) {
        ref.read(connectProvider.notifier).refreshIps();
      }
    });
  }

  Future<void> _loadVersion() async {
    var v = '1.0.0';
    try {
      v = await ref.read(connectProvider.notifier).currentVersion();
    } catch (_) {
      // 桌面/测试环境取不到包信息时退回构建版本。
    }
    if (mounted) setState(() => _version = v);
  }

  Future<void> _copy(String text, String label) async {
    if (text.trim().isEmpty) {
      showPqToast(context, '暂无可复制的内容');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showPqToast(context, '$label已复制', kind: PqToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(connectProvider);
    final settings = ref.watch(settingsProvider);
    final ip = st.localIps.isNotEmpty ? st.localIps.first : '';

    return PqBackdrop(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 16,
          bottom: 48,
        ),
        children: [
          PqContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PqPageHeader(
                  title: '连接',
                  subtitle: '同一 Wi-Fi 下，MCP 与数据同步都在本机完成',
                ),
                _serviceSection(context, st, settings, ip),
                const SizedBox(height: 16),
                _pairingCard(context, st),
                const SizedBox(height: 32),
                _peersSection(context, st),
                if (st.lastReport != null) ...[
                  const SizedBox(height: 24),
                  _ReportCard(report: st.lastReport!),
                ],
                const SizedBox(height: 32),
                _updateSection(context, st),
                const SizedBox(height: 16),
                _footer(context, settings, st),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 服务卡
  // ---------------------------------------------------------------------------

  Widget _serviceSection(
    BuildContext context,
    ConnectState st,
    AppSettings settings,
    String ip,
  ) {
    final mcpPort = st.mcpRunning ? st.mcpPort : settings.mcpPort;
    final syncPort = st.syncRunning ? st.syncPort : settings.syncPort;
    final host = ip.isEmpty ? '127.0.0.1' : ip;

    final mcp = _McpCard(
      running: st.mcpRunning,
      host: host,
      ip: ip,
      port: mcpPort,
      onToggle: () {
        final c = ref.read(connectProvider.notifier);
        if (st.mcpRunning) {
          c.stopMcp();
        } else {
          c.startMcp(mcpPort);
        }
      },
      onCopy: _copy,
      onTools: () => _showTools(context),
    );

    final sync = _SyncCard(
      running: st.syncRunning,
      port: syncPort,
      scanning: st.discoveryRunning,
      onToggle: () {
        final c = ref.read(connectProvider.notifier);
        if (st.syncRunning) {
          c.stopSync();
        } else {
          c.startSync(syncPort);
        }
      },
      onScan: () => ref.read(connectProvider.notifier).startDiscovery(),
      onCopy: _copy,
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820) {
          return Column(
            children: [mcp, const SizedBox(height: 16), sync],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: mcp),
            const SizedBox(width: 16),
            Expanded(child: sync),
          ],
        );
      },
    );
  }

  Widget _pairingCard(BuildContext context, ConnectState st) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pin = st.pin.isEmpty ? '----' : st.pin;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pin_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('配对码', style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () => _copy(st.pin, '配对码'),
                  child: const Text('复制'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              pin,
              style: theme.textTheme.displaySmall?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '两台设备填入同一个配对码即可互相发现并同步。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 附近设备
  // ---------------------------------------------------------------------------

  Widget _peersSection(BuildContext context, ConnectState st) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('附近设备', style: theme.textTheme.titleMedium)),
            if (st.peers.isNotEmpty)
              Text(
                '${st.peers.length} 台在线',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (st.discoveryRunning) const LinearProgressIndicator(minHeight: 2),
              if (st.peers.isEmpty)
                PqEmptyState(
                  icon: Icons.devices_other_outlined,
                  title: '还没有发现设备',
                  message: '在另一台设备上打开 Poqi 的连接页，或检查防火墙是否放行 UDP 47820。',
                  compact: true,
                  action: st.syncRunning
                      ? null
                      : FilledButton.tonal(
                          onPressed: () => ref
                              .read(connectProvider.notifier)
                              .startSync(ref.read(settingsProvider).syncPort),
                          child: const Text('先启动同步服务'),
                        ),
                )
              else
                for (var i = 0; i < st.peers.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _PeerTile(
                    peer: st.peers[i],
                    busy: _busyPeerId == st.peers[i].id,
                    disabled: st.busy && _busyPeerId != st.peers[i].id,
                    onPull: () => _runPeer(st.peers[i], pull: true),
                    onPush: () => _runPeer(st.peers[i], pull: false),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _runPeer(SyncPeer peer, {required bool pull}) async {
    setState(() => _busyPeerId = peer.id);
    final c = ref.read(connectProvider.notifier);
    final report = pull ? await c.pullFrom(peer) : await c.pushTo(peer);
    if (!mounted) return;
    setState(() => _busyPeerId = null);
    if (report == null) {
      showPqToast(context, pull ? '拉取失败' : '推送失败', kind: PqToastKind.error);
      return;
    }
    showPqToast(
      context,
      '${pull ? '已从' : '已推送到'} ${peer.name} · ${report.total} 项变更',
      kind: PqToastKind.success,
    );
  }

  // ---------------------------------------------------------------------------
  // 更新
  // ---------------------------------------------------------------------------

  Widget _updateSection(BuildContext context, ConnectState st) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outcome = st.update;
    final release = outcome?.release;
    final dl = st.download;
    final downloading =
        st.busy && dl != null && dl.received > 0 && st.downloadedPath == null;
    final failed = outcome != null && outcome.failed;

    final status = outcome == null
        ? '尚未检查更新'
        : release != null
            ? '新版本 ${release.version} 可用'
            : failed
                ? '检查未完成'
                : '已是最新版本';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('应用更新'),
            subtitle: Text(
              status,
              style: failed ? TextStyle(color: scheme.error) : null,
            ),
            trailing: FilledButton(
              onPressed: st.busy ? null : () => _checkUpdate(),
              child: st.busy && !downloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('检查更新'),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('当前版本'),
            trailing: Text('v${_version.isEmpty ? '—' : _version}'),
          ),
          if (st.updateError != null && !downloading && !failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                st.updateError!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          if (release != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: Text('新版本 ${release.version}'),
              subtitle: Text('发布于 ${_fmtDate(release.publishedAt)}'),
            ),
            if (release.notes.trim().isNotEmpty)
              ExpansionTile(
                leading: const Icon(Icons.notes),
                title: const Text('更新说明'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        release.notes.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (release.assets.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.attachment),
                title: const Text('安装包'),
                subtitle: Text(
                  release.assets
                      .take(3)
                      .map((a) => '${a.name} · ${_fmtBytes(a.size)}')
                      .join('\n'),
                ),
                isThreeLine: release.assets.length > 1,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (downloading) ...[
                    Row(
                      children: [
                        Text(
                          '下载中 ${(dl.fraction * 100).round()}%',
                          style: theme.textTheme.labelLarge,
                        ),
                        const Spacer(),
                        Text(
                          '${_fmtBytes(dl.received)} / ${_fmtBytes(dl.total)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: dl.fraction, minHeight: 6),
                    const SizedBox(height: 4),
                    Text(
                      '${(dl.speedBps / 1024 / 1024).toStringAsFixed(1)} MB/s · '
                      '${dl.viaProxy ? 'via gh-proxy' : '直连'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (st.downloadedPath != null)
                          FilledButton.icon(
                            onPressed: () =>
                                ref.read(connectProvider.notifier).installDownloaded(),
                            icon: const Icon(Icons.install_desktop, size: 18),
                            label: const Text('安装'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: st.busy
                                ? null
                                : () => ref
                                    .read(connectProvider.notifier)
                                    .downloadUpdate(release),
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('下载'),
                          ),
                        TextButton(
                          onPressed: () => ref
                              .read(connectProvider.notifier)
                              .openReleasePage(release.htmlUrl),
                          child: const Text('前往发布页'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final outcome = await ref.read(connectProvider.notifier).checkUpdate();
    if (!mounted || outcome == null) return;
    if (outcome.failed) {
      showPqToast(context, outcome.message ?? '检查失败', kind: PqToastKind.error);
    } else if (outcome.hasUpdate) {
      showPqToast(context, '发现新版本 ${outcome.release!.version}', kind: PqToastKind.success);
    } else {
      showPqToast(context, '已是最新版本');
    }
  }

  // ---------------------------------------------------------------------------
  // 页脚与工具清单
  // ---------------------------------------------------------------------------

  Widget _footer(BuildContext context, AppSettings settings, ConnectState st) {
    final theme = Theme.of(context);
    final releaseUrl = st.update?.release?.htmlUrl ?? '';
    final fallback =
        'https://github.com/${settings.repoOwner}/${settings.repoName}/releases';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.commit),
        title: Text(
          '${settings.repoOwner}/${settings.repoName}',
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
        subtitle: const Text('开源仓库'),
        trailing: TextButton(
          onPressed: () => ref
              .read(connectProvider.notifier)
              .openReleasePage(releaseUrl.isEmpty ? fallback : releaseUrl),
          child: const Text('发布页'),
        ),
      ),
    );
  }

  void _showTools(BuildContext context) {
    const tools = <(String, String)>[
      ('poqi_search', '按关键词跨站搜索，返回聚合后的条目与来源站点。'),
      ('poqi_get_detail', '读取单个剧集的详情、线路与剧集列表。'),
      ('poqi_save_plugin', '写入或覆盖一个插件，附带版本记录。'),
      ('poqi_apply_patch', '以补丁方式局部修改插件，不必重传整份清单。'),
      ('poqi_list_revisions', '查看某个插件的版本历史与差异。'),
      ('poqi_list_plugins', '列出本机全部插件及其引擎、端点与版本。'),
      ('poqi_list_sites', '列出全部站点绑定与最近一次连通结果。'),
      ('poqi_export_snapshot', '导出插件、站点、收藏与历史的完整快照。'),
    ];
    showPqSheet<void>(
      context,
      title: 'MCP 工具清单',
      maxWidth: 620,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final mono = theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        );
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '任意 MCP 客户端（Claude、Cursor、自建 Agent）连上这个地址后，即可调用以下工具。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ),
            for (final t in tools)
              ListTile(
                title: Text(t.$1, style: mono),
                subtitle: Text(t.$2),
              ),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 组件
// -----------------------------------------------------------------------------

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '未知大小';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 5) return '刚刚在线';
  if (d.inSeconds < 60) return '${d.inSeconds} 秒前';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  return '${d.inHours} 小时前';
}

String _fmtDate(DateTime? d) {
  if (d == null) return '未知时间';
  final local = d.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

TextStyle? _monoStyle(BuildContext context, {Color? color}) {
  final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
  return base.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Roboto Mono', 'Menlo', 'Consolas'],
    color: color,
  );
}

class _McpCard extends StatelessWidget {
  const _McpCard({
    required this.running,
    required this.host,
    required this.ip,
    required this.port,
    required this.onToggle,
    required this.onCopy,
    required this.onTools,
  });

  final bool running;
  final String host;
  final String ip;
  final int port;
  final VoidCallback onToggle;
  final void Function(String text, String label) onCopy;
  final VoidCallback onTools;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = _monoStyle(context);
    final endpoint = 'http://$host:$port/mcp';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: Icon(
              Icons.dns_outlined,
              color: running ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: const Text('局域网 MCP'),
            subtitle: const Text('把 Poqi 的检索与插件能力交给任意 MCP 客户端。'),
            value: running,
            onChanged: (_) => onToggle(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lan_outlined),
            title: const Text('局域网地址'),
            subtitle: Text(
              ip.isEmpty ? '未获取' : ip,
              style: mono,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: '复制局域网地址',
              onPressed: ip.isEmpty ? null : () => onCopy(ip, '局域网地址'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('MCP 地址'),
            subtitle: Text(endpoint, style: mono),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: '复制 MCP 地址',
              onPressed: () => onCopy(endpoint, 'MCP 地址'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.numbers),
            title: const Text('端口'),
            subtitle: Text('$port', style: mono),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: '复制端口',
              onPressed: () => onCopy('$port', '端口'),
            ),
          ),
          const Divider(height: 1),
          ExpansionTile(
            leading: const Icon(Icons.api),
            title: const Text('MCP 端点'),
            subtitle: const Text('3 个端点 · 8 个工具'),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              ListTile(
                title: Text('POST /mcp', style: mono),
                subtitle: const Text('JSON-RPC 2.0 入口 · 8 个工具'),
              ),
              ListTile(
                title: Text('GET /mcp/tools', style: mono),
                subtitle: const Text('工具索引 · 8 个工具'),
              ),
              ListTile(
                title: Text('GET /mcp/sse', style: mono),
                subtitle: const Text('SSE 事件流 · 长连接'),
              ),
            ],
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: const Text('工具清单'),
            subtitle: const Text('查看每个工具的名称与用途'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTools,
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.running,
    required this.port,
    required this.scanning,
    required this.onToggle,
    required this.onScan,
    required this.onCopy,
  });

  final bool running;
  final int port;
  final bool scanning;
  final VoidCallback onToggle;
  final VoidCallback onScan;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = _monoStyle(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: Icon(
              Icons.sync_outlined,
              color: running ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: const Text('设备同步'),
            subtitle: const Text('在设备之间合并插件、站点、收藏与观看历史。'),
            value: running,
            onChanged: (_) => onToggle(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.numbers),
            title: const Text('端口'),
            subtitle: Text('$port', style: mono),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: '复制端口',
              onPressed: () => onCopy('$port', '端口'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.radar),
            title: const Text('设备发现'),
            subtitle: Text(scanning ? '正在扫描附近设备…' : '未在扫描'),
            trailing: TextButton(
              onPressed: scanning ? null : onScan,
              child: Text(scanning ? '扫描中' : '扫描'),
            ),
          ),
          if (scanning) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peer,
    required this.busy,
    required this.disabled,
    required this.onPull,
    required this.onPush,
  });

  final SyncPeer peer;
  final bool busy;
  final bool disabled;
  final VoidCallback onPull;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (peer.platform.isNotEmpty) peer.platform,
      if (peer.version.isNotEmpty) 'v${peer.version}',
      if (peer.rttMs != null) '${peer.rttMs} ms',
      if (peer.lastSeen != null) _ago(peer.lastSeen!),
    ].join(' · ');
    final subtitle = [
      '${peer.host}:${peer.port}',
      if (meta.isNotEmpty) meta,
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        child: Text(peer.name.isEmpty ? '?' : peer.name.substring(0, 1)),
      ),
      title: Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.south),
                  onPressed: disabled ? null : onPull,
                  child: const Text('从该设备拉取'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.north),
                  onPressed: disabled ? null : onPush,
                  child: const Text('推送到该设备'),
                ),
              ],
              builder: (context, controller, child) => FilledButton.tonal(
                onPressed: disabled
                    ? null
                    : () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                child: const Text('同步'),
              ),
            ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final SyncReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = <(String, int)>[
      ('新增插件', report.pluginsAdded),
      ('更新插件', report.pluginsUpdated),
      ('新增站点', report.sitesAdded),
      ('更新站点', report.sitesUpdated),
      ('合并收藏', report.favoritesMerged),
      ('合并历史', report.historyMerged),
      ('跳过', report.skipped),
    ].where((e) => e.$2 > 0).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.swap_horiz, color: scheme.tertiary),
            title: const Text('上次同步结果'),
            trailing: Text(
              '共 ${report.total} 项变更',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (entries.isEmpty)
            const PqEmptyState(
              icon: Icons.check_circle_outline,
              title: '两端已完全一致',
              message: '没有需要合并的内容。',
              compact: true,
            )
          else ...[
            const Divider(height: 1),
            for (final e in entries)
              ListTile(
                dense: true,
                title: Text(e.$1),
                trailing: Text(
                  e.$1 == '跳过' ? '${e.$2}' : '+${e.$2}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: e.$1 == '跳过' ? scheme.onSurfaceVariant : scheme.tertiary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
