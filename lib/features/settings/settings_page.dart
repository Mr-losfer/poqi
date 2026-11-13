import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../domain/models/settings.dart';
import '../../state/connect.dart';
import '../../state/providers.dart';
import '../shell/pq_shell.dart';

/// 设置：外观、聚合、局域网、更新与设备数据。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _deviceName;
  late final TextEditingController _mcpPort;
  late final TextEditingController _syncPort;
  late final TextEditingController _repoOwner;
  late final TextEditingController _repoName;

  double _concurrency = 4;
  double _timeoutSec = 12;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _deviceName = TextEditingController(text: _deviceLabel(s));
    _mcpPort = TextEditingController(text: '${s.mcpPort}');
    _syncPort = TextEditingController(text: '${s.syncPort}');
    _repoOwner = TextEditingController(text: s.repoOwner);
    _repoName = TextEditingController(text: s.repoName);
    _concurrency = s.searchConcurrency.toDouble();
    _timeoutSec = (s.aggregateTimeoutMs / 1000).clamp(4, 30).toDouble();
  }

  @override
  void dispose() {
    _deviceName.dispose();
    _mcpPort.dispose();
    _syncPort.dispose();
    _repoOwner.dispose();
    _repoName.dispose();
    super.dispose();
  }

  String _deviceLabel(AppSettings s) {
    if (s.deviceName.isNotEmpty) return s.deviceName;
    return ref.read(backendProvider).deviceName;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final compact = PqAdaptive.isCompact(context);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return PqBackdrop(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: compact ? MediaQuery.paddingOf(context).top + 16 : 20,
          bottom: 52,
        ),
        children: [
          PqContent(
            maxWidth: 880,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PqPageHeader(
                  title: '设置',
                  subtitle: '改动即时生效，并保存在本机',
                ),
                _SettingsGroup(
                  title: '外观',
                  children: [
                    const ListTile(
                      title: Text('主题模式'),
                      subtitle: Text('深色适合夜晚，浅色适合白天。'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('浅色'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('深色'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('跟随系统'),
                            ),
                          ],
                          selected: {s.themeMode},
                          showSelectedIcon: false,
                          onSelectionChanged: (v) =>
                              notifier.patch(themeMode: v.first),
                        ),
                      ),
                    ),
                  ],
                ),
                _SettingsGroup(
                  title: '播放与聚合',
                  children: [
                    _SliderTile(
                      title: '搜索并发数',
                      subtitle: '同时向几个站点发起搜索，数值越高越快，也越容易触发站点限流。',
                      valueLabel: '${_concurrency.round()} 路',
                      value: _concurrency,
                      min: 1,
                      max: 8,
                      divisions: 7,
                      onChanged: (v) => setState(() => _concurrency = v),
                      onDone: (v) =>
                          notifier.patch(searchConcurrency: v.round()),
                    ),
                    const Divider(height: 1),
                    _SliderTile(
                      title: '聚合超时',
                      subtitle: '单个站点超过这个时间未响应就会被跳过，不阻塞整体结果。',
                      valueLabel: '${_timeoutSec.round()} 秒',
                      value: _timeoutSec,
                      min: 4,
                      max: 30,
                      divisions: 26,
                      onChanged: (v) => setState(() => _timeoutSec = v),
                      onDone: (v) => notifier.update(
                        s.copyWith(aggregateTimeoutMs: v.round() * 1000),
                      ),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      title: Text('优先源'),
                      subtitle: Text('播放时优先尝试最近响应更快的站点，无需手动排序。'),
                    ),
                  ],
                ),
                _SettingsGroup(
                  title: '局域网',
                  children: [
                    SwitchListTile(
                      title: const Text('MCP 服务'),
                      subtitle: const Text('允许同一 Wi-Fi 下的客户端调用检索与插件工具。'),
                      value: s.mcpEnabled,
                      onChanged: (v) async {
                        final c = ref.read(connectProvider.notifier);
                        if (v) {
                          await c.startMcp(
                            int.tryParse(_mcpPort.text) ?? s.mcpPort,
                          );
                        } else {
                          await c.stopMcp();
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_ethernet),
                      title: const Text('MCP 端口'),
                      subtitle: Text('${s.mcpPort}'),
                      trailing: TextButton(
                        onPressed: () => _editPort(mcp: true),
                        child: const Text('编辑'),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('同步服务'),
                      subtitle: const Text('在两台设备之间合并插件、站点、收藏与历史。'),
                      value: s.syncEnabled,
                      onChanged: (v) async {
                        final c = ref.read(connectProvider.notifier);
                        if (v) {
                          await c.startSync(
                            int.tryParse(_syncPort.text) ?? s.syncPort,
                          );
                        } else {
                          await c.stopSync();
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_ethernet),
                      title: const Text('同步端口'),
                      subtitle: Text('${s.syncPort}'),
                      trailing: TextButton(
                        onPressed: () => _editPort(mcp: false),
                        child: const Text('编辑'),
                      ),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('端口说明'),
                      subtitle: Text(
                        '修改端口后正在运行的服务会重启一次；若端口被占用，会自动回退到可用端口。',
                      ),
                    ),
                  ],
                ),
                _SettingsGroup(
                  title: '更新',
                  children: [
                    SwitchListTile(
                      title: const Text('自动检查更新'),
                      subtitle: const Text('启动时静默检查一次，不打断当前操作。'),
                      value: s.autoCheckUpdate,
                      onChanged: (v) => notifier.patch(autoCheckUpdate: v),
                    ),
                    SwitchListTile(
                      title: const Text('优先使用 gh-proxy'),
                      subtitle: const Text('下载更新包时先走代理，失败再回落直连。'),
                      value: s.preferProxy,
                      onChanged: (v) => notifier.patch(preferProxy: v),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: const Text('更新来源'),
                      subtitle: Text(
                        'github.com/${s.repoOwner}/${s.repoName}\n换成自己的 fork 时，同时修改所有者与仓库名。',
                      ),
                      isThreeLine: true,
                      trailing: TextButton(
                        onPressed: _editRepo,
                        child: const Text('编辑'),
                      ),
                    ),
                  ],
                ),
                _SettingsGroup(
                  title: '设备与数据',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('设备名称'),
                      subtitle: Text(_deviceLabel(s)),
                      trailing: TextButton(
                        onPressed: () => _editDeviceName(s),
                        child: const Text('编辑'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.ios_share),
                      title: const Text('导出快照'),
                      subtitle: const Text('把插件、站点、收藏与历史导出为 JSON 并复制到剪贴板。'),
                      trailing: FilledButton.tonal(
                        onPressed: _exportSnapshot,
                        child: const Text('导出'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.delete_outline, color: scheme.error),
                      title: Text(
                        '清空观看历史',
                        style: TextStyle(color: scheme.error),
                      ),
                      subtitle: const Text('收藏与站点配置不受影响，仅移除播放记录与进度。'),
                      trailing: TextButton(
                        onPressed: _clearHistory,
                        style: TextButton.styleFrom(foregroundColor: scheme.error),
                        child: const Text('清空'),
                      ),
                      onTap: _clearHistory,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.settings_backup_restore),
                      title: const Text('恢复内置插件'),
                      subtitle: const Text('把被修改过的内置插件恢复为随包版本，自定义插件不受影响。'),
                      trailing: TextButton(
                        onPressed: _restoreBuiltins,
                        child: const Text('恢复'),
                      ),
                    ),
                  ],
                ),
                _SettingsGroup(
                  title: '关于',
                  children: [
                    const ListTile(
                      title: Text('应用名称'),
                      trailing: Text('Poqi'),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      title: Text('版本'),
                      trailing: Text('1.0.0'),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      title: Text('包名'),
                      trailing: Text('cn.losfer.Poqi'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('仓库'),
                      subtitle: Text('github.com/${s.repoOwner}/${s.repoName}'),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Poqi 是开源的影视聚合器：站点规则以插件形式编写，数据留在本机，'
                        '局域网内的 MCP 与同步都只依赖本地网络。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.7,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 编辑
  // ---------------------------------------------------------------------------

  Future<void> _editPort({required bool mcp}) async {
    final s = ref.read(settingsProvider);
    final current = '${mcp ? s.mcpPort : s.syncPort}';
    var draft = current;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mcp ? 'MCP 端口' : '同步端口'),
        content: TextFormField(
          initialValue: current,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '端口',
            helperText: '1024–65535',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => draft = v,
          onFieldSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(draft),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;

    final value = result.trim();
    (mcp ? _mcpPort : _syncPort).text = value;
    await _applyPort(
      mcp: mcp,
      value: value,
      enabled: mcp ? s.mcpEnabled : s.syncEnabled,
    );
  }

  Future<void> _editRepo() async {
    var owner = _repoOwner.text;
    var name = _repoName.text;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新来源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: owner,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '所有者',
                hintText: 'losfer',
              ),
              onChanged: (v) => owner = v,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: name,
              decoration: const InputDecoration(
                labelText: '仓库名',
                hintText: 'poqi',
              ),
              onChanged: (v) => name = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    _repoOwner.text = owner.trim();
    _repoName.text = name.trim();
    await _saveRepo(ref.read(settingsProvider.notifier));
  }

  Future<void> _editDeviceName(AppSettings s) async {
    var draft = _deviceName.text;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设备名称'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称',
            hintText: '例如：客厅放映机',
          ),
          onChanged: (v) => draft = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final value = draft.trim();
    if (value.isEmpty) {
      showPqToast(context, '设备名称不能为空', kind: PqToastKind.error);
      _deviceName.text = _deviceLabel(s);
      return;
    }
    _deviceName.text = value;
    await ref.read(settingsProvider.notifier).patch(deviceName: value);
    if (!mounted) return;
    showPqToast(context, '设备名称已保存', kind: PqToastKind.success);
  }

  Future<void> _exportSnapshot() async {
    final backend = ref.read(backendProvider);
    final json =
        const JsonEncoder.withIndent('  ').convert(backend.snapshot().toJson());
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    showPqToast(
      context,
      '快照已复制 · ${(json.length / 1024).toStringAsFixed(1)} KB',
      kind: PqToastKind.success,
    );
  }

  Future<void> _clearHistory() async {
    final ok = await _confirm(
      context,
      title: '清空观看历史',
      message: '${ref.read(historyProvider).length} 条观看记录将被删除，且无法恢复。',
      confirmLabel: '清空',
    );
    if (!ok) return;
    await ref.read(historyProvider.notifier).clear();
    if (!mounted) return;
    showPqToast(context, '观看历史已清空', kind: PqToastKind.success);
  }

  Future<void> _restoreBuiltins() async {
    final builtins = ref.read(pluginsProvider).where((e) => e.builtin).toList();
    if (builtins.isEmpty) {
      showPqToast(context, '没有可恢复的内置插件');
      return;
    }
    final ok = await _confirm(
      context,
      title: '恢复内置插件',
      message: '${builtins.length} 个内置插件将回到随包版本，已有的本地修改会被覆盖。',
      confirmLabel: '恢复',
    );
    if (!ok) return;
    for (final b in builtins) {
      await ref.read(pluginsProvider.notifier).restoreBuiltin(b.id);
    }
    if (!mounted) return;
    showPqToast(context, '内置插件已恢复', kind: PqToastKind.success);
  }

  Future<void> _saveRepo(SettingsNotifier notifier) async {
    final owner = _repoOwner.text.trim();
    final name = _repoName.text.trim();
    if (owner.isEmpty || name.isEmpty) {
      showPqToast(context, '所有者与仓库名都不能为空', kind: PqToastKind.error);
      return;
    }
    await notifier.patch(repoOwner: owner, repoName: name);
    if (!mounted) return;
    showPqToast(context, '更新来源已保存', kind: PqToastKind.success);
  }

  Future<void> _applyPort({
    required bool mcp,
    required String value,
    required bool enabled,
  }) async {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1024 || parsed > 65535) {
      showPqToast(context, '端口需为 1024–65535 之间的数字', kind: PqToastKind.error);
      final s = ref.read(settingsProvider);
      (mcp ? _mcpPort : _syncPort).text = '${mcp ? s.mcpPort : s.syncPort}';
      return;
    }
    final s = ref.read(settingsProvider);
    final current = mcp ? s.mcpPort : s.syncPort;
    if (parsed == current) return;

    final c = ref.read(connectProvider.notifier);
    if (mcp) {
      await ref.read(settingsProvider.notifier).patch(mcpPort: parsed);
      if (enabled) {
        await c.stopMcp();
        await c.startMcp(parsed);
      }
    } else {
      await ref.read(settingsProvider.notifier).patch(syncPort: parsed);
      if (enabled) {
        await c.stopSync();
        await c.startSync(parsed);
      }
    }
    if (!mounted) return;
    showPqToast(
      context,
      enabled ? '端口已更新，服务已重启' : '端口已保存，启动服务后生效',
      kind: PqToastKind.success,
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = '确认',
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// -----------------------------------------------------------------------------
// 基础块
// -----------------------------------------------------------------------------

/// 一组设置：小标题 + 卡片，卡片内由 [ListTile] 与 [Divider] 组成。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onDone,
  });

  final String title;
  final String subtitle;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Text(
            valueLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
            onChangeEnd: onDone,
          ),
        ),
      ],
    );
  }
}
