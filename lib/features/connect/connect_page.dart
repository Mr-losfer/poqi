import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/poster.dart';
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
  bool _notesOpen = false;

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
    final compact = PqAdaptive.isCompact(context);
    final ip = st.localIps.isNotEmpty ? st.localIps.first : '';

    return PqBackdrop(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: compact ? MediaQuery.paddingOf(context).top + 14 : 20,
          bottom: 48,
        ),
        child: PqContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                const PqPageHeader(
                  eyebrow: 'LOCAL NETWORK',
                  title: '连接',
                  subtitle: '同一 Wi-Fi 下，MCP 与数据同步都在本机完成',
                ),
                _IpChip(ip: ip, onCopy: () => _copy(ip, '局域网地址')),
                const SizedBox(height: 22),
              ] else
                PqPageHeader(
                  eyebrow: 'LOCAL NETWORK',
                  title: '连接',
                  subtitle: '同一 Wi-Fi 下，MCP 与数据同步都在本机完成',
                  actions: [
                    _IpChip(ip: ip, onCopy: () => _copy(ip, '局域网地址')),
                  ],
                ),
              _serviceCards(context, st, settings, ip, compact),
              const SizedBox(height: 34),
              _peersSection(context, st, compact),
              if (st.lastReport != null) ...[
                const SizedBox(height: 20),
                _ReportCard(report: st.lastReport!),
              ],
              const SizedBox(height: 34),
              _updateSection(context, st, settings, compact),
              const SizedBox(height: 30),
              _footer(context, settings, st),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 服务卡
  // ---------------------------------------------------------------------------

  Widget _serviceCards(
    BuildContext context,
    ConnectState st,
    AppSettings settings,
    String ip,
    bool compact,
  ) {
    final mcpPort = st.mcpRunning ? st.mcpPort : settings.mcpPort;
    final syncPort = st.syncRunning ? st.syncPort : settings.syncPort;
    final flow = ip.isEmpty ? '127.0.0.1' : ip;

    final mcp = _McpCard(
      running: st.mcpRunning,
      port: mcpPort,
      endpoint: 'http://$flow:$mcpPort/mcp',
      onToggle: () {
        final c = ref.read(connectProvider.notifier);
        if (st.mcpRunning) {
          c.stopMcp();
        } else {
          c.startMcp(mcpPort);
        }
      },
      onCopy: () => _copy('http://$flow:$mcpPort/mcp', 'MCP 地址'),
      onTools: () => _showTools(context),
    );

    final sync = _SyncCard(
      running: st.syncRunning,
      port: syncPort,
      pin: st.pin.isEmpty ? '----' : st.pin,
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
      onCopyPin: () => _copy(st.pin, '配对码'),
    );

    if (compact) {
      return Column(children: [mcp, const SizedBox(height: 14), sync]);
    }
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 820) {
          return Column(children: [mcp, const SizedBox(height: 14), sync]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: mcp),
            const SizedBox(width: 14),
            Expanded(child: sync),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 附近设备
  // ---------------------------------------------------------------------------

  Widget _peersSection(BuildContext context, ConnectState st, bool compact) {
    final p = PqPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PqSectionHeader(
          eyebrow: 'NEARBY',
          title: '附近设备',
          subtitle: st.peers.isEmpty ? null : '${st.peers.length} 台在线',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (st.discoveryRunning) ...[
                PqPulseDot(color: p.sage, size: 5),
                const SizedBox(width: 6),
                Text(
                  '正在扫描',
                  style: PqType.bodySmall.copyWith(color: p.sage, fontSize: 11.5),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton.icon(
                onPressed: st.discoveryRunning
                    ? null
                    : () => ref.read(connectProvider.notifier).startDiscovery(),
                icon: const Icon(Icons.radar_rounded, size: 15),
                label: Text(st.discoveryRunning ? '扫描中' : '扫描'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  textStyle: PqType.label.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (st.peers.isEmpty)
          PqPanel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: PqEmptyState(
              icon: Icons.devices_other_rounded,
              title: '还没有发现设备',
              message: '在另一台设备上打开 Poqi 的连接页，或手动检查防火墙是否放行 UDP 47820。',
              compact: true,
              action: st.syncRunning
                  ? null
                  : TextButton(
                      onPressed: () => ref
                          .read(connectProvider.notifier)
                          .startSync(ref.read(settingsProvider).syncPort),
                      child: const Text('先启动同步服务'),
                    ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < st.peers.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == st.peers.length - 1 ? 0 : 10),
                  child: _PeerTile(
                    peer: st.peers[i],
                    compact: compact,
                    busy: _busyPeerId == st.peers[i].id,
                    disabled: st.busy && _busyPeerId != st.peers[i].id,
                    onPull: () => _runPeer(st.peers[i], pull: true),
                    onPush: () => _runPeer(st.peers[i], pull: false),
                  ),
                ),
            ],
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

  Widget _updateSection(
    BuildContext context,
    ConnectState st,
    AppSettings settings,
    bool compact,
  ) {
    final p = PqPalette.of(context);
    final outcome = st.update;
    final release = outcome?.release;
    final dl = st.download;
    final downloading = st.busy &&
        dl != null &&
        dl.received > 0 &&
        st.downloadedPath == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PqSectionHeader(
          eyebrow: 'RELEASE',
          title: '应用更新',
          subtitle: _version.isEmpty ? null : 'v$_version',
          action: OutlinedButton.icon(
            onPressed: st.busy ? null : () => _checkUpdate(),
            icon: st.busy && !downloading
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  )
                : const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('检查更新'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              textStyle: PqType.label.copyWith(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PqPanel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.lineSoft, width: 0.9),
                    ),
                    child: Icon(Icons.system_update_alt_rounded, size: 19, color: p.textMuted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          release != null ? '新版本 ${release.version}' : '当前版本 v${_version.isEmpty ? '—' : _version}',
                          style: PqType.title.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          release != null
                              ? '发布于 ${_fmtDate(release.publishedAt)}'
                              : (outcome == null
                                  ? '尚未检查更新'
                                  : outcome.failed
                                      ? '检查未完成'
                                      : '已是最新版本'),
                          style: PqType.bodySmall.copyWith(
                            color: outcome != null && outcome.failed && release == null
                                ? p.danger
                                : p.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (release == null && outcome != null && !outcome.failed)
                    PqTag('最新', color: p.sage, filled: true, icon: Icons.check_rounded),
                ],
              ),
              if (st.updateError != null && !downloading) ...[
                const SizedBox(height: 12),
                Text(
                  st.updateError!,
                  style: PqType.bodySmall.copyWith(color: p.danger, fontSize: 12),
                ),
              ],
              if (release != null) ...[
                const SizedBox(height: 16),
                Divider(color: p.lineSoft, height: 1),
                const SizedBox(height: 14),
                if (release.notes.trim().isNotEmpty) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _notesOpen = !_notesOpen),
                    child: Row(
                      children: [
                        Text(
                          '更新说明',
                          style: PqType.label.copyWith(color: p.textMuted, fontSize: 11.5),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _notesOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: p.textFaint),
                        ),
                      ],
                    ),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        release.notes.trim(),
                        maxLines: 12,
                        overflow: TextOverflow.ellipsis,
                        style: PqType.bodySmall.copyWith(color: p.textMuted, height: 1.65),
                      ),
                    ),
                    crossFadeState:
                        _notesOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                  const SizedBox(height: 14),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in release.assets.take(3))
                      PqTag('${a.name} · ${_fmtBytes(a.size)}', icon: Icons.download_rounded),
                  ],
                ),
                const SizedBox(height: 16),
                if (downloading) ...[
                  PqProgressLine(value: dl.fraction, height: 3),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Text(
                        '${_fmtBytes(dl.received)} / ${_fmtBytes(dl.total)}',
                        style: PqType.mono.copyWith(fontSize: 11, color: p.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(dl.speedBps / 1024 / 1024).toStringAsFixed(1)} MB/s',
                        style: PqType.mono.copyWith(fontSize: 11, color: p.textFaint),
                      ),
                      const Spacer(),
                      PqTag(dl.viaProxy ? 'via gh-proxy' : '直连', color: p.textFaint),
                    ],
                  ),
                ] else if (st.downloadedPath != null) ...[
                  Row(
                    children: [
                      PqTag('已下载', color: p.sage, filled: true, icon: Icons.check_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          st.downloadedPath!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.mono.copyWith(fontSize: 10.5, color: p.textFaint),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => ref.read(connectProvider.notifier).installDownloaded(),
                        icon: const Icon(Icons.install_desktop_rounded, size: 16),
                        label: const Text('安装'),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => ref.read(connectProvider.notifier).openReleasePage(release.htmlUrl),
                        child: const Text('或前往发布页'),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: st.busy
                            ? null
                            : () => ref.read(connectProvider.notifier).downloadUpdate(release),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('下载'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '下载后可直接安装，也可前往发布页手动获取。',
                          style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
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
    final p = PqPalette.of(context);
    final slug = '${settings.repoOwner}/${settings.repoName}';
    final releaseUrl = st.update?.release?.htmlUrl ?? '';
    final fallback = 'https://github.com/${settings.repoOwner}/${settings.repoName}/releases';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: p.lineSoft, height: 1),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.commit_rounded, size: 13, color: p.textFaint),
            const SizedBox(width: 8),
            Text(
              slug,
              style: PqType.mono.copyWith(fontSize: 11, color: p.textFaint),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => ref
                  .read(connectProvider.notifier)
                  .openReleasePage(releaseUrl.isEmpty ? fallback : releaseUrl),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '打开发布页',
                style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showTools(BuildContext context) {
    final p = PqPalette.of(context);
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
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '任意 MCP 客户端（Claude、Cursor、自建 Agent）连上这个地址后，即可调用以下工具。',
              style: PqType.bodySmall.copyWith(color: p.textMuted, height: 1.65),
            ),
            const SizedBox(height: 16),
            for (final t in tools)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: p.sage.withOpacity(0.7)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.$1,
                            style: PqType.mono.copyWith(
                              fontSize: 12,
                              color: p.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.$2,
                            style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
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

class _IpChip extends StatelessWidget {
  const _IpChip({required this.ip, required this.onCopy});

  final String ip;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.lineSoft, width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lan_outlined, size: 14, color: p.textFaint),
          const SizedBox(width: 7),
          Text(
            ip.isEmpty ? '未获取局域网地址' : ip,
            style: PqType.mono.copyWith(
              fontSize: 11.5,
              color: ip.isEmpty ? p.textFaint : p.text,
            ),
          ),
          const SizedBox(width: 2),
          PqIconButton(
            icon: Icons.copy_rounded,
            iconSize: 14,
            size: 28,
            tooltip: '复制地址',
            onTap: ip.isEmpty ? null : onCopy,
          ),
        ],
      ),
    );
  }
}

class _McpCard extends StatelessWidget {
  const _McpCard({
    required this.running,
    required this.port,
    required this.endpoint,
    required this.onToggle,
    required this.onCopy,
    required this.onTools,
  });

  final bool running;
  final int port;
  final String endpoint;
  final VoidCallback onToggle;
  final VoidCallback onCopy;
  final VoidCallback onTools;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return PqPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PqPulseDot(color: running ? p.sage : p.textFaint, size: 6),
              const SizedBox(width: 4),
              Text('MCP 服务', style: PqType.title.copyWith(fontSize: 15)),
              const Spacer(),
              PqTag(
                running ? '运行中' : '已停止',
                color: running ? p.sage : p.textFaint,
                filled: running,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '把 Poqi 的检索与插件能力，交给任意 MCP 客户端。',
            style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _EndpointBox(text: endpoint, onCopy: onCopy),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(label: '端口', value: '$port'),
              const SizedBox(width: 20),
              const _Metric(label: '协议', value: 'JSON-RPC'),
              const Spacer(),
              Text(
                running ? '仅本机网络可见' : '启动后可复制地址',
                style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ToggleButton(
                  running: running,
                  startLabel: '启动服务',
                  stopLabel: '停止服务',
                  onTap: onToggle,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onTools,
                icon: const Icon(Icons.list_alt_rounded, size: 15),
                label: const Text('工具清单'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                ),
              ),
            ],
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
    required this.pin,
    required this.scanning,
    required this.onToggle,
    required this.onScan,
    required this.onCopyPin,
  });

  final bool running;
  final int port;
  final String pin;
  final bool scanning;
  final VoidCallback onToggle;
  final VoidCallback onScan;
  final VoidCallback onCopyPin;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return PqPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PqPulseDot(color: running ? p.sage : p.textFaint, size: 6),
              const SizedBox(width: 4),
              Text('同步服务', style: PqType.title.copyWith(fontSize: 15)),
              const Spacer(),
              PqTag(
                running ? '运行中' : '已停止',
                color: running ? p.sage : p.textFaint,
                filled: running,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '在设备之间合并插件、站点、收藏与观看历史。',
            style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceHigh.withOpacity(p.isDark ? 1 : 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.lineSoft, width: 0.9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '配对码',
                      style: PqType.eyebrow.copyWith(color: p.textFaint, fontSize: 9.5),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      pin,
                      style: PqType.mono.copyWith(
                        fontSize: 26,
                        height: 1.1,
                        letterSpacing: 7,
                        fontWeight: FontWeight.w600,
                        color: running ? p.accent : p.textMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                PqIconButton(
                  icon: Icons.copy_rounded,
                  iconSize: 15,
                  size: 32,
                  tooltip: '复制配对码',
                  onTap: onCopyPin,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(label: '端口', value: '$port'),
              const SizedBox(width: 20),
              _Metric(label: '发现', value: scanning ? '广播中' : '未开启'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ToggleButton(
                  running: running,
                  startLabel: '启动服务',
                  stopLabel: '停止服务',
                  onTap: onToggle,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onScan,
                icon: scanning
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : const Icon(Icons.radar_rounded, size: 15),
                label: Text(scanning ? '扫描中' : '扫描设备'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.running,
    required this.startLabel,
    required this.stopLabel,
    required this.onTap,
  });

  final bool running;
  final String startLabel;
  final String stopLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    if (running) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.stop_rounded, size: 16, color: p.danger),
        label: Text(stopLabel, style: PqType.label.copyWith(fontSize: 12.5, color: p.danger)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: BorderSide(color: p.danger.withOpacity(0.35)),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.play_arrow_rounded, size: 17),
      label: Text(startLabel),
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
    );
  }
}

class _EndpointBox extends StatelessWidget {
  const _EndpointBox({required this.text, required this.onCopy});

  final String text;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 5, 7),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.lineSoft, width: 0.9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PqType.mono.copyWith(fontSize: 11.5, color: p.textMuted),
            ),
          ),
          PqIconButton(
            icon: Icons.copy_rounded,
            iconSize: 14,
            size: 28,
            tooltip: '复制',
            onTap: onCopy,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PqType.eyebrow.copyWith(fontSize: 9, color: p.textFaint)),
        const SizedBox(height: 4),
        Text(value, style: PqType.mono.copyWith(fontSize: 12.5, color: p.text)),
      ],
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peer,
    required this.compact,
    required this.busy,
    required this.disabled,
    required this.onPull,
    required this.onPush,
  });

  final SyncPeer peer;
  final bool compact;
  final bool busy;
  final bool disabled;
  final VoidCallback onPull;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final meta = [
      if (peer.platform.isNotEmpty) peer.platform,
      if (peer.version.isNotEmpty) 'v${peer.version}',
      if (peer.rttMs != null) '${peer.rttMs} ms',
      if (peer.lastSeen != null) _ago(peer.lastSeen!),
    ].join(' · ');

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                peer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PqType.title.copyWith(fontSize: 13.5),
              ),
            ),
            const SizedBox(width: 8),
            if (peer.rttMs != null)
              PqTag(
                peer.rttMs! < 80 ? '低延迟' : '在线',
                color: peer.rttMs! < 80 ? p.sage : p.textFaint,
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          meta.isEmpty ? '未知平台' : meta,
          style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
        ),
        const SizedBox(height: 2),
        Text(
          '${peer.host}:${peer.port}',
          style: PqType.mono.copyWith(fontSize: 11, color: p.textMuted),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
          ),
        _PeerButton(label: '拉取', icon: Icons.south_rounded, onTap: disabled || busy ? null : onPull),
        const SizedBox(width: 8),
        _PeerButton(label: '推送', icon: Icons.north_rounded, onTap: disabled || busy ? null : onPush),
      ],
    );

    return PqPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PqMonogram(text: peer.name, size: 36),
                    const SizedBox(width: 11),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            )
          : Row(
              children: [
                PqMonogram(text: peer.name, size: 38),
                const SizedBox(width: 12),
                Expanded(child: info),
                const SizedBox(width: 12),
                actions,
              ],
            ),
    );
  }
}

class _PeerButton extends StatelessWidget {
  const _PeerButton({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? p.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: enabled ? p.line : p.lineSoft.withOpacity(0.6),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: enabled ? p.textMuted : p.textFaint.withOpacity(0.5)),
            const SizedBox(width: 5),
            Text(
              label,
              style: PqType.label.copyWith(
                fontSize: 11.5,
                color: enabled ? p.text : p.textFaint.withOpacity(0.5),
              ),
            ),
          ],
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
    final p = PqPalette.of(context);
    final entries = <(String, int)>[
      ('新增插件', report.pluginsAdded),
      ('更新插件', report.pluginsUpdated),
      ('新增站点', report.sitesAdded),
      ('更新站点', report.sitesUpdated),
      ('合并收藏', report.favoritesMerged),
      ('合并历史', report.historyMerged),
      ('跳过', report.skipped),
    ].where((e) => e.$2 > 0).toList();

    return PqPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz_rounded, size: 17, color: p.sage),
              const SizedBox(width: 8),
              Text('上次同步结果', style: PqType.title.copyWith(fontSize: 13.5)),
              const Spacer(),
              Text(
                '共 ${report.total} 项变更',
                style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Text(
              '两端已完全一致，没有需要合并的内容。',
              style: PqType.bodySmall.copyWith(color: p.textMuted),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.surfaceHigh,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: p.lineSoft, width: 0.9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.$1,
                          style: PqType.bodySmall.copyWith(color: p.textMuted, fontSize: 11.5),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+${e.$2}',
                          style: PqType.mono.copyWith(
                            fontSize: 12,
                            color: e.$1 == '跳过' ? p.textFaint : p.sage,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
