import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../domain/models/plugin.dart';
import '../../domain/models/site.dart';
import '../../domain/plugin/validator.dart';
import '../../state/providers.dart';

/// 站点编辑器：插件 + 该域名的独立配置。
class SiteEditorPage extends ConsumerStatefulWidget {
  const SiteEditorPage({super.key, this.siteId, this.presetPluginId});

  final String? siteId;
  final String? presetPluginId;

  @override
  ConsumerState<SiteEditorPage> createState() => _SiteEditorPageState();
}

class _SiteEditorPageState extends ConsumerState<SiteEditorPage> {
  SiteBinding? _site;
  bool _loaded = false;
  String? _pluginId;

  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _notes;
  final Map<String, TextEditingController> _controllers = {};
  final List<TextEditingController> _retired = [];
  final Map<String, String> _config = {};
  final Set<String> _errors = {};
  final Set<String> _revealed = {};
  bool _enabled = true;
  bool _saving = false;
  bool _testing = false;
  _TestResult? _test;

  bool get _isEdit => widget.siteId != null;

  @override
  void initState() {
    super.initState();
    _site = widget.siteId == null
        ? null
        : ref.read(sitesProvider.notifier).byId(widget.siteId!);
    _pluginId = _site?.pluginId ?? widget.presetPluginId;
    _enabled = _site?.enabled ?? true;
    _name = TextEditingController(text: _site?.name ?? '');
    _baseUrl = TextEditingController(text: _site?.baseUrl ?? '');
    _notes = TextEditingController(text: _site?.notes ?? '');
    _config.addAll(_site?.config ?? const {});
    final plugin = _findPlugin(ref.read(pluginsProvider), _pluginId);
    if (plugin != null) _seedPlugin(plugin, keepConfig: _site != null);
    _loaded = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _notes.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _retired) {
      c.dispose();
    }
    super.dispose();
  }

  PluginManifest? _findPlugin(List<PluginManifest> list, String? id) {
    if (id == null) return null;
    for (final p in list) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _defaultFor(ConfigField f) {
    final v = f.defaultValue;
    if (v != null && v.isNotEmpty) return v;
    return f.type == ConfigFieldType.boolean ? 'false' : '';
  }

  /// 选中插件后补齐默认值：名称、基础地址与配置项。
  void _seedPlugin(PluginManifest plugin, {required bool keepConfig}) {
    _retired.addAll(_controllers.values);
    _controllers.clear();
    if (!keepConfig) _config.clear();
    for (final f in plugin.config) {
      final current = _config[f.key];
      if (current == null || current.isEmpty) {
        _config[f.key] = f.type == ConfigFieldType.select && f.options.isNotEmpty
            ? f.options.first
            : _defaultFor(f);
      }
    }
    _config.removeWhere((k, _) => plugin.configField(k) == null);
    if (_name.text.trim().isEmpty) _name.text = plugin.name;
    if (_baseUrl.text.trim().isEmpty) _baseUrl.text = plugin.baseUrl;
  }

  TextEditingController _ctrlFor(ConfigField f) => _controllers.putIfAbsent(
        f.key,
        () => TextEditingController(text: _config[f.key] ?? ''),
      );

  // ---------------------------------------------------------------------------
  // 保存与测试
  // ---------------------------------------------------------------------------

  Future<void> _save(PluginManifest? plugin) async {
    _errors.clear();
    if (plugin == null) {
      showPqToast(context, '请先选择一个插件', kind: PqToastKind.error);
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _errors.add('__name'));
      showPqToast(context, '站点名称不能为空', kind: PqToastKind.error);
      return;
    }
    final missing = missingRequiredConfig(plugin, _config);
    if (missing.isNotEmpty) {
      for (final f in plugin.config) {
        if (missing.contains(f.label)) _errors.add(f.key);
      }
      setState(() {});
      showPqToast(context, '请补全：${missing.join('、')}', kind: PqToastKind.error);
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final old = _site;
    final site = SiteBinding(
      id: old?.id ?? ref.read(backendProvider).siteRepo.newId(),
      pluginId: plugin.id,
      name: name,
      baseUrl: _baseUrl.text.trim(),
      enabled: _enabled,
      order: old?.order ?? ref.read(sitesProvider).length,
      config: Map<String, String>.from(_config),
      notes: _notes.text.trim(),
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      lastCheckAt: old?.lastCheckAt,
      lastCheckOk: old?.lastCheckOk,
      lastCheckMessage: old?.lastCheckMessage,
      latencyMs: old?.latencyMs,
    );
    try {
      await ref.read(sitesProvider.notifier).save(site);
      if (!mounted) return;
      showPqToast(context, _isEdit ? '站点已更新' : '站点已添加', kind: PqToastKind.success);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPqToast(context, '保存失败：$e', kind: PqToastKind.error);
    }
  }

  Future<void> _testConnection(PluginManifest plugin) async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final probe = SiteBinding(
      id: _site?.id ?? 'preview',
      pluginId: plugin.id,
      name: _name.text.trim().isEmpty ? plugin.name : _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      config: Map<String, String>.from(_config),
    );
    final runner = ref.read(runnerFactoryProvider)(probe);
    if (runner == null) {
      setState(() {
        _testing = false;
        _test = const _TestResult(ok: false, message: '插件不存在，无法执行测试');
      });
      return;
    }
    final watch = Stopwatch()..start();
    try {
      final page = await runner.home();
      watch.stop();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _test = _TestResult(
          ok: true,
          ms: watch.elapsedMilliseconds,
          count: page.items.length,
          message: page.items.isEmpty ? '连接成功，但首页没有条目' : '连接成功',
        );
      });
    } catch (e) {
      watch.stop();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _test = _TestResult(ok: false, ms: watch.elapsedMilliseconds, message: '$e');
      });
    }
  }

  Future<void> _delete() async {
    final p = PqPalette.of(context);
    final ok = await showPqSheet<bool>(
      context,
      title: '删除站点',
      maxWidth: 420,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '「${_site?.name ?? ''}」将从聚合中移除，插件本身不受影响。',
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
                    child: const Text('删除'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(sitesProvider.notifier).delete(_site!.id);
    if (!mounted) return;
    showPqToast(context, '站点已删除', kind: PqToastKind.success);
    context.pop();
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final plugins = ref.watch(pluginsProvider);
    final plugin = _findPlugin(plugins, _pluginId);

    if (!_loaded) return const SizedBox.shrink();

    if (_isEdit && _site == null) {
      return _frame(
        context,
        compact,
        plugin: null,
        body: PqErrorState(
          title: '站点不存在',
          message: '这条站点可能已被删除，或来自另一台设备的同步。',
          onRetry: () => context.pop(),
        ),
      );
    }

    if (_isEdit && plugin == null) {
      return _frame(
        context,
        compact,
        plugin: null,
        body: PqErrorState(
          title: '插件不存在',
          message: '该站点依赖的插件「${_site!.pluginId}」已被删除。恢复插件或重新安装后再编辑。',
          onRetry: () => context.pop(),
        ),
      );
    }

    return _frame(
      context,
      compact,
      plugin: plugin,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pluginSection(plugins, plugin),
          const SizedBox(height: 26),
          _basicSection(plugin),
          const SizedBox(height: 26),
          _configSection(plugin),
          const SizedBox(height: 26),
          _notesSection(),
          const SizedBox(height: 26),
          _enableSection(),
          const SizedBox(height: 22),
          _testSection(plugin),
          if (_isEdit) ...[
            const SizedBox(height: 34),
            Divider(color: p.lineSoft, height: 1),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline_rounded, size: 16, color: p.danger),
              label: Text('删除站点', style: PqType.label.copyWith(color: p.danger, fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                side: BorderSide(color: p.danger.withOpacity(0.35)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '删除只影响这一条绑定，插件与其它站点保持不变。',
              style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11),
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _frame(
    BuildContext context,
    bool compact, {
    required PluginManifest? plugin,
    required Widget body,
  }) {
    final p = PqPalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: PqBackdrop(
        glow: false,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              PqAdaptive.gutter(context),
              compact ? 10 : 22,
              PqAdaptive.gutter(context),
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopBar(
                      title: _isEdit ? '编辑站点' : '添加站点',
                      subtitle: plugin == null ? '选择插件后填写站点信息' : plugin.name,
                      saving: _saving,
                      onBack: () => context.pop(),
                      onSave: plugin == null ? null : () => _save(plugin),
                    ),
                    const SizedBox(height: 18),
                    body,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pluginSection(List<PluginManifest> plugins, PluginManifest? plugin) {
    final p = PqPalette.of(context);
    if (plugin != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PqSectionHeader(eyebrow: 'PLUGIN', title: '插件'),
          const SizedBox(height: 12),
          PqPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                PqMonogram(text: plugin.name, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plugin.name, style: PqType.title.copyWith(fontSize: 14)),
                      const SizedBox(height: 3),
                      Text(
                        '${plugin.engine.label} · ${plugin.endpoints.length} 个端点 · v${plugin.version}',
                        style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                if (!_isEdit)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _pluginId = null;
                        _config.clear();
                        _errors.clear();
                        _test = null;
                      });
                    },
                    child: const Text('更换'),
                  )
                else
                  PqTag('不可更换', color: p.textFaint),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PqSectionHeader(
          eyebrow: 'PLUGIN',
          title: '选择插件',
          subtitle: '${plugins.length} 个可用',
        ),
        const SizedBox(height: 8),
        Text(
          '同一套站点逻辑可复用到多个域名，选一个插件即可。',
          style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        if (plugins.isEmpty)
          PqPanel(
            child: PqEmptyState(
              icon: Icons.extension_outlined,
              title: '还没有可用插件',
              message: '先安装或编写一个插件，再回来添加站点。',
              compact: true,
              action: FilledButton(
                onPressed: () => context.go('/plugins'),
                child: const Text('前往插件工坊'),
              ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < plugins.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == plugins.length - 1 ? 0 : 8),
                  child: _PluginOption(
                    plugin: plugins[i],
                    onPick: () {
                      setState(() {
                        _pluginId = plugins[i].id;
                        _errors.clear();
                        _test = null;
                      });
                      _seedPlugin(plugins[i], keepConfig: false);
                      setState(() {});
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _basicSection(PluginManifest? plugin) {
    final p = PqPalette.of(context);
    final nameError = _errors.contains('__name');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PqSectionHeader(eyebrow: 'SITE', title: '站点信息'),
        const SizedBox(height: 12),
        PqPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldLabel(label: '站点名称', required: true, error: nameError),
              const SizedBox(height: 7),
              TextField(
                controller: _name,
                style: PqType.body.copyWith(fontSize: 13.5),
                onChanged: (_) {
                  if (nameError) setState(() => _errors.remove('__name'));
                },
                decoration: InputDecoration(
                  hintText: plugin?.name ?? '例如：棱镜 · 主站',
                  errorText: nameError ? '名称不能为空' : null,
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel(label: '站点地址'),
              const SizedBox(height: 7),
              TextField(
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                style: PqType.mono.copyWith(fontSize: 12.5, color: p.text),
                decoration: InputDecoration(
                  hintText: plugin == null ? 'https://…' : plugin.baseUrl,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '留空则使用插件默认地址；同一插件可以配置多个不同域名。',
                style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _configSection(PluginManifest? plugin) {
    final p = PqPalette.of(context);
    if (plugin == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PqSectionHeader(eyebrow: 'CONFIG', title: '插件配置'),
          const SizedBox(height: 12),
          PqPanel(
            padding: const EdgeInsets.all(16),
            child: Text(
              '选择插件后，这里会出现它声明的配置项。',
              style: PqType.bodySmall.copyWith(color: p.textFaint),
            ),
          ),
        ],
      );
    }
    if (plugin.config.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PqSectionHeader(eyebrow: 'CONFIG', title: '插件配置'),
          const SizedBox(height: 12),
          PqPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 16, color: p.sage),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '这个插件不需要额外配置，填好地址即可使用。',
                    style: PqType.bodySmall.copyWith(color: p.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PqSectionHeader(
          eyebrow: 'CONFIG',
          title: '插件配置',
          subtitle: '${plugin.config.length} 项',
        ),
        const SizedBox(height: 12),
        PqPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (var i = 0; i < plugin.config.length; i++) ...[
                if (i > 0) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Divider(color: p.lineSoft, height: 1),
                ),
                _configField(plugin.config[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _configField(ConfigField f) {
    final p = PqPalette.of(context);
    final error = _errors.contains(f.key);
    final value = _config[f.key] ?? '';

    Widget input = const SizedBox.shrink();
    switch (f.type) {
      case ConfigFieldType.boolean:
        input = Row(
          children: [
            Expanded(
              child: Text(
                f.hint ?? '开启后生效',
                style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
              ),
            ),
            Switch(
              value: value == 'true',
              activeColor: p.accent,
              activeTrackColor: p.accent.withOpacity(0.28),
              inactiveThumbColor: p.textFaint,
              inactiveTrackColor: p.surfaceHigh,
              trackOutlineColor: WidgetStatePropertyAll(p.line),
              onChanged: (v) => setState(() => _config[f.key] = v ? 'true' : 'false'),
            ),
          ],
        );
      case ConfigFieldType.select:
        final options = f.options.isEmpty ? <String>[''] : f.options;
        final current = options.contains(value) ? value : options.first;
        input = DropdownButtonFormField<String>(
          value: current,
          isExpanded: true,
          dropdownColor: p.surfaceHigh,
          style: PqType.body.copyWith(fontSize: 13, color: p.text),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: p.textFaint),
          decoration: InputDecoration(errorText: error ? '必填项' : null),
          items: [
            for (final o in options)
              DropdownMenuItem<String>(
                value: o,
                child: Text(o.isEmpty ? '未选择' : o, style: PqType.body.copyWith(fontSize: 13)),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _config[f.key] = v;
              _errors.remove(f.key);
            });
          },
        );
      case ConfigFieldType.password:
        final shown = _revealed.contains(f.key);
        input = TextField(
          controller: _ctrlFor(f),
          obscureText: !shown,
          style: PqType.mono.copyWith(fontSize: 12.5, color: p.text),
          onChanged: (v) {
            _config[f.key] = v;
            if (error && v.trim().isNotEmpty) setState(() => _errors.remove(f.key));
          },
          decoration: InputDecoration(
            hintText: f.hint,
            errorText: error ? '必填项' : null,
            suffixIcon: IconButton(
              icon: Icon(
                shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 17,
                color: p.textFaint,
              ),
              onPressed: () => setState(() {
                if (shown) {
                  _revealed.remove(f.key);
                } else {
                  _revealed.add(f.key);
                }
              }),
            ),
          ),
        );
      case ConfigFieldType.number:
        input = TextField(
          controller: _ctrlFor(f),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: PqType.mono.copyWith(fontSize: 12.5, color: p.text),
          onChanged: (v) {
            _config[f.key] = v;
            if (error && v.trim().isNotEmpty) setState(() => _errors.remove(f.key));
          },
          decoration: InputDecoration(
            hintText: f.hint,
            errorText: error ? '必填项' : null,
          ),
        );
      case ConfigFieldType.text:
        input = TextField(
          controller: _ctrlFor(f),
          style: PqType.body.copyWith(fontSize: 13),
          onChanged: (v) {
            _config[f.key] = v;
            if (error && v.trim().isNotEmpty) setState(() => _errors.remove(f.key));
          },
          decoration: InputDecoration(
            hintText: f.hint,
            errorText: error ? '必填项' : null,
          ),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: _FieldLabel(
                label: f.label.isEmpty ? f.key : f.label,
                required: f.required,
                error: error,
              ),
            ),
            if (f.secret) ...[
              const SizedBox(width: 8),
              PqTag('仅保存在本机', color: p.textFaint),
            ],
          ],
        ),
        if (f.type != ConfigFieldType.boolean) ...[
          const SizedBox(height: 7),
          input,
        ] else ...[
          const SizedBox(height: 4),
          input,
        ],
        if (f.help != null && f.help!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            f.help!,
            style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11, height: 1.55),
          ),
        ],
      ],
    );
  }

  Widget _notesSection() {
    final p = PqPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PqSectionHeader(eyebrow: 'NOTES', title: '备注'),
        const SizedBox(height: 12),
        PqPanel(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 2,
            style: PqType.body.copyWith(fontSize: 13),
            decoration: InputDecoration(
              hintText: '只给自己看的说明，例如账号来源、有效期…',
              hintStyle: PqType.bodySmall.copyWith(color: p.textFaint),
            ),
          ),
        ),
      ],
    );
  }

  Widget _enableSection() {
    final p = PqPalette.of(context);
    return PqPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('启用站点', style: PqType.title.copyWith(fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(
                  '关闭后不参与首页与聚合搜索，配置会保留。',
                  style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            activeColor: p.accent,
            activeTrackColor: p.accent.withOpacity(0.28),
            inactiveThumbColor: p.textFaint,
            inactiveTrackColor: p.surfaceHigh,
            trackOutlineColor: WidgetStatePropertyAll(p.line),
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ],
      ),
    );
  }

  Widget _testSection(PluginManifest? plugin) {
    final p = PqPalette.of(context);
    final result = _test;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('连通性测试', style: PqType.title.copyWith(fontSize: 13.5)),
                  const SizedBox(height: 3),
                  Text(
                    '用当前配置请求一次首页，不会保存任何改动。',
                    style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _testing || plugin == null ? null : () => _testConnection(plugin),
              icon: _testing
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    )
                  : const Icon(Icons.bolt_rounded, size: 16),
              label: Text(_testing ? '测试中' : '测试连接'),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: result == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _TestResultCard(result: result),
                ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 组件
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.saving,
    required this.onBack,
    required this.onSave,
  });

  final String title;
  final String subtitle;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Row(
      children: [
        PqIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: '返回',
          onTap: onBack,
          size: 36,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: PqType.h2.copyWith(fontSize: 19, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              : const Icon(Icons.check_rounded, size: 17),
          label: const Text('保存'),
        ),
      ],
    );
  }
}

class _PluginOption extends StatelessWidget {
  const _PluginOption({required this.plugin, required this.onPick});

  final PluginManifest plugin;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return PqPressable(
      onTap: onPick,
      borderRadius: 14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.lineSoft, width: 0.9),
        ),
        child: Row(
          children: [
            PqMonogram(text: plugin.name, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plugin.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.title.copyWith(fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(width: 7),
                      if (plugin.builtin) PqTag('内置', color: p.textFaint),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${plugin.engine.label} · ${plugin.endpoints.length} 个端点 · v${plugin.version}',
                    style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.add_circle_outline_rounded, size: 18, color: p.textFaint),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.required = false, this.error = false});

  final String label;
  final bool required;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: PqType.label.copyWith(
            fontSize: 12,
            color: error ? p.danger : p.textMuted,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: PqType.label.copyWith(fontSize: 12, color: error ? p.danger : p.accent),
          ),
      ],
    );
  }
}

class _TestResult {
  const _TestResult({
    required this.ok,
    required this.message,
    this.ms = 0,
    this.count = 0,
  });

  final bool ok;
  final String message;
  final int ms;
  final int count;
}

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({required this.result});

  final _TestResult result;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final color = result.ok ? p.sage : p.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35), width: 0.9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.message,
                  style: PqType.bodySmall.copyWith(color: p.text, fontSize: 12.5),
                ),
                if (result.ok) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${result.ms} ms · 返回 ${result.count} 条',
                    style: PqType.mono.copyWith(fontSize: 10.5, color: p.textFaint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
