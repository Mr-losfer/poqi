import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/primitives.dart';
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
    final p = PqPalette.of(context);
    final s = ref.watch(settingsProvider);
    final compact = PqAdaptive.isCompact(context);
    final backend = ref.read(backendProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return PqBackdrop(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: compact ? MediaQuery.paddingOf(context).top + 14 : 20,
          bottom: 52,
        ),
        child: PqContent(
          maxWidth: 880,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PqPageHeader(
                eyebrow: 'PREFERENCES',
                title: '设置',
                subtitle: '改动即时生效，并保存在本机',
              ),
              _Group(
                eyebrow: 'APPEARANCE',
                title: '外观',
                children: [
                  _Row(
                    title: '主题模式',
                    subtitle: '深色是默认的放映厅质感，浅色适合白天。',
                    below: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: PqSegmented(
                          items: const ['深色', '浅色', '跟随系统'],
                          index: switch (s.themeMode) {
                            ThemeMode.dark => 0,
                            ThemeMode.light => 1,
                            ThemeMode.system => 2,
                          },
                          onChanged: (i) {
                            final mode = switch (i) {
                              0 => ThemeMode.dark,
                              1 => ThemeMode.light,
                              _ => ThemeMode.system,
                            };
                            notifier.patch(themeMode: mode);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _Group(
                eyebrow: 'PLAYBACK',
                title: '播放与聚合',
                children: [
                  _SliderRow(
                    title: '搜索并发数',
                    subtitle: '同时向几个站点发起搜索，数值越高越快，也越容易触发站点限流。',
                    valueLabel: '${_concurrency.round()} 路',
                    value: _concurrency,
                    min: 1,
                    max: 8,
                    divisions: 7,
                    onChanged: (v) => setState(() => _concurrency = v),
                    onDone: (v) => notifier.patch(searchConcurrency: v.round()),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  _SliderRow(
                    title: '聚合超时',
                    subtitle: '单个站点超过这个时间未响应就会被跳过，不阻塞整体结果。',
                    valueLabel: '${_timeoutSec.round()} 秒',
                    value: _timeoutSec,
                    min: 4,
                    max: 30,
                    divisions: 26,
                    onChanged: (v) => setState(() => _timeoutSec = v),
                    onDone: (v) => notifier.update(
                      s.copyWith(aggregateTimeoutMs: (v.round() * 1000)),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  const _Row(
                    title: '优先源',
                    subtitle: '播放时优先尝试最近响应更快的站点，无需手动排序。',
                  ),
                ],
              ),
              _Group(
                eyebrow: 'LOCAL NETWORK',
                title: '局域网',
                children: [
                  _Row(
                    title: 'MCP 服务',
                    subtitle: '允许同一 Wi-Fi 下的客户端调用检索与插件工具。',
                    trailing: _PqSwitch(
                      value: s.mcpEnabled,
                      onChanged: (v) async {
                        final c = ref.read(connectProvider.notifier);
                        if (v) {
                          await c.startMcp(int.tryParse(_mcpPort.text) ?? s.mcpPort);
                        } else {
                          await c.stopMcp();
                        }
                      },
                    ),
                    below: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _PortField(
                        controller: _mcpPort,
                        enabled: s.mcpEnabled,
                        onSave: (v) => _applyPort(mcp: true, value: v, enabled: s.mcpEnabled),
                      ),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  _Row(
                    title: '同步服务',
                    subtitle: '在两台设备之间合并插件、站点、收藏与历史。',
                    trailing: _PqSwitch(
                      value: s.syncEnabled,
                      onChanged: (v) async {
                        final c = ref.read(connectProvider.notifier);
                        if (v) {
                          await c.startSync(int.tryParse(_syncPort.text) ?? s.syncPort);
                        } else {
                          await c.stopSync();
                        }
                      },
                    ),
                    below: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _PortField(
                        controller: _syncPort,
                        enabled: s.syncEnabled,
                        onSave: (v) => _applyPort(mcp: false, value: v, enabled: s.syncEnabled),
                      ),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  const _Hint(
                    icon: Icons.info_outline_rounded,
                    text: '修改端口后正在运行的服务会重启一次；若端口被占用，会自动回退到可用端口。',
                  ),
                ],
              ),
              _Group(
                eyebrow: 'UPDATE',
                title: '更新',
                children: [
                  _Row(
                    title: '自动检查更新',
                    subtitle: '启动时静默检查一次，不打断当前操作。',
                    trailing: _PqSwitch(
                      value: s.autoCheckUpdate,
                      onChanged: (v) => notifier.patch(autoCheckUpdate: v),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  _Row(
                    title: '优先使用 gh-proxy',
                    subtitle: '下载更新包时先走代理，失败再回落直连。',
                    trailing: _PqSwitch(
                      value: s.preferProxy,
                      onChanged: (v) => notifier.patch(preferProxy: v),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  _Row(
                    title: '更新来源',
                    subtitle: '换成自己的 fork 时，同时修改这里的所有者与仓库名。',
                    below: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: LayoutBuilder(
                        builder: (ctx, c) {
                          final owner = _LabeledField(
                            label: '所有者',
                            controller: _repoOwner,
                            hint: 'losfer',
                            onSave: (_) => _saveRepo(notifier),
                          );
                          final name = _LabeledField(
                            label: '仓库名',
                            controller: _repoName,
                            hint: 'poqi',
                            onSave: (_) => _saveRepo(notifier),
                          );
                          final save = TextButton(
                            onPressed: () => _saveRepo(notifier),
                            child: const Text('保存'),
                          );
                          if (c.maxWidth < 420) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: owner),
                                    const SizedBox(width: 10),
                                    Expanded(child: name),
                                  ],
                                ),
                                Align(alignment: Alignment.centerRight, child: save),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: owner),
                              const SizedBox(width: 10),
                              Expanded(child: name),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: save,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              _Group(
                eyebrow: 'DEVICE & DATA',
                title: '设备与数据',
                children: [
                  _Row(
                    title: '设备名称',
                    subtitle: '显示在附近设备与配对码里，便于在两台设备间核对。',
                    below: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _LabeledField(
                        label: '名称',
                        controller: _deviceName,
                        hint: '例如：客厅放映机',
                        onSave: (v) {
                          if (v.isEmpty) {
                            showPqToast(context, '设备名称不能为空', kind: PqToastKind.error);
                            _deviceName.text = _deviceLabel(s);
                            return;
                          }
                          notifier.patch(deviceName: v);
                          showPqToast(context, '设备名称已保存', kind: PqToastKind.success);
                        },
                      ),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  _ActionRow(
                    title: '导出快照',
                    subtitle: '把插件、站点、收藏与历史导出为 JSON 并复制到剪贴板。',
                    action: OutlinedButton(
                      onPressed: () async {
                        final json = const JsonEncoder.withIndent('  ')
                            .convert(backend.snapshot().toJson());
                        await Clipboard.setData(ClipboardData(text: json));
                        if (!context.mounted) return;
                        showPqToast(
                          context,
                          '快照已复制 · ${(json.length / 1024).toStringAsFixed(1)} KB',
                          kind: PqToastKind.success,
                        );
                      },
                      child: const Text('导出'),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  _ActionRow(
                    title: '清空观看历史',
                    subtitle: '收藏与站点配置不受影响，仅移除播放记录与进度。',
                    action: OutlinedButton(
                      onPressed: () async {
                        final ok = await _confirm(
                          context,
                          title: '清空观看历史',
                          message: '${ref.read(historyProvider).length} 条观看记录将被删除，且无法恢复。',
                          confirmLabel: '清空',
                        );
                        if (!ok) return;
                        await ref.read(historyProvider.notifier).clear();
                        if (!context.mounted) return;
                        showPqToast(context, '观看历史已清空', kind: PqToastKind.success);
                      },
                      child: const Text('清空'),
                    ),
                  ),
                  Divider(color: p.lineSoft, height: 1),
                  _ActionRow(
                    title: '恢复内置插件',
                    subtitle: '把被修改过的内置插件恢复为随包版本，自定义插件不受影响。',
                    action: OutlinedButton(
                      onPressed: () async {
                        final builtins =
                            ref.read(pluginsProvider).where((e) => e.builtin).toList();
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
                        if (!context.mounted) return;
                        showPqToast(context, '内置插件已恢复', kind: PqToastKind.success);
                      },
                      child: const Text('恢复'),
                    ),
                  ),
                ],
              ),
              _Group(
                eyebrow: 'ABOUT',
                title: '关于',
                children: [
                  const _MetaRow(label: '应用名称', value: 'Poqi'),
                  Divider(color: p.lineSoft, height: 1),
                  const _MetaRow(label: '版本', value: '1.0.0'),
                  Divider(color: p.lineSoft, height: 1),
                  const _MetaRow(label: '包名', value: 'cn.losfer.Poqi'),
                  Divider(color: p.lineSoft, height: 1),
                  _MetaRow(label: '仓库', value: 'github.com/${s.repoOwner}/${s.repoName}'),
                  Divider(color: p.lineSoft, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Poqi 是开源的影视聚合器：站点规则以插件形式编写，数据留在本机，'
                      '局域网内的 MCP 与同步都只依赖本地网络。',
                      style: PqType.bodySmall.copyWith(color: p.textMuted, height: 1.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
    final p = PqPalette.of(context);
    final result = await showPqSheet<bool>(
      context,
      title: title,
      maxWidth: 420,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: PqType.bodySmall.copyWith(color: p.textMuted, height: 1.7),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.danger,
                      foregroundColor: p.isDark ? const Color(0xFF1A0908) : Colors.white,
                    ),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }
}

// -----------------------------------------------------------------------------
// 基础块
// -----------------------------------------------------------------------------

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    this.eyebrow,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PqSectionHeader(eyebrow: eyebrow, title: title),
          const SizedBox(height: 12),
          PqPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: PqType.title.copyWith(fontSize: 13.5)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          if (below != null) below!,
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PqType.title.copyWith(fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: PqType.bodySmall.copyWith(color: p.textFaint),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: PqType.bodySmall.copyWith(color: p.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: p.textFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PqSwitch extends StatelessWidget {
  const _PqSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Switch(
      value: value,
      onChanged: onChanged,
      activeColor: p.accent,
      activeTrackColor: p.accent.withOpacity(0.28),
      inactiveThumbColor: p.textFaint,
      inactiveTrackColor: p.surfaceHigh,
      trackOutlineColor: WidgetStatePropertyAll(p.line),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
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
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: PqType.title.copyWith(fontSize: 13.5)),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PqTag(valueLabel, color: p.accent),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: p.accent,
              inactiveTrackColor: p.surfaceHigher,
              thumbColor: p.accent,
              overlayColor: p.accent.withOpacity(0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onDone,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortField extends StatelessWidget {
  const _PortField({
    required this.controller,
    required this.enabled,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Row(
      children: [
        SizedBox(
          width: 132,
          child: _AutoField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSave: onSave,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            enabled ? '服务运行中，修改后会重启' : '服务停止时也可先保存',
            maxLines: 2,
            style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.onSave,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSave;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PqType.eyebrow.copyWith(fontSize: 9, color: p.textFaint),
        ),
        const SizedBox(height: 6),
        _AutoField(controller: controller, hint: hint, onSave: onSave),
      ],
    );
  }
}

/// 失焦或回车时提交，避免每敲一个字就写盘。
class _AutoField extends StatefulWidget {
  const _AutoField({
    required this.controller,
    required this.onSave,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSave;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_AutoField> createState() => _AutoFieldState();
}

class _AutoFieldState extends State<_AutoField> {
  final _node = FocusNode();
  late String _last = widget.controller.text.trim();

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_node.hasFocus) _commit();
  }

  void _commit() {
    final v = widget.controller.text.trim();
    if (v == _last) return;
    _last = v;
    widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _node,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onSubmitted: (_) => _commit(),
      style: PqType.body.copyWith(fontSize: 13),
      decoration: InputDecoration(hintText: widget.hint),
    );
  }
}
