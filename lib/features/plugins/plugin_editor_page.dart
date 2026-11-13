import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../data/repositories.dart';
import '../../domain/models/media.dart';
import '../../domain/models/plugin.dart';
import '../../domain/models/site.dart';
import '../../domain/plugin/diff.dart';
import '../../domain/plugin/runner.dart';
import '../../domain/plugin/validator.dart';
import '../../state/providers.dart';
import '../media/nav.dart';
import '../media/widgets.dart';

class PluginEditorPage extends ConsumerStatefulWidget {
  const PluginEditorPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<PluginEditorPage> createState() => _PluginEditorPageState();
}

enum _EditorTab { issues, test, versions }

class _PluginEditorPageState extends ConsumerState<PluginEditorPage> {
  late TextEditingController _code;
  late String _savedText;
  bool _showDiff = false;
  _EditorTab _tab = _EditorTab.issues;

  List<PluginIssue> _issues = const [];
  String? _parseError;

  // 测试台状态
  String? _testEndpoint;
  final _testInput = TextEditingController();
  bool _testing = false;
  String? _testResult;
  List<MediaItem> _testItems = const [];
  int _testMs = 0;
  List<String> _testWarnings = const [];

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final plugin = ref.read(pluginsProvider).where((p) => p.id == widget.pluginId).firstOrNull;
    _savedText = plugin?.toJsonString() ?? '{}';
    _code = TextEditingController(text: _savedText);
    _code.addListener(_onChanged);
    _validate();
  }

  @override
  void dispose() {
    _code.dispose();
    _testInput.dispose();
    super.dispose();
  }

  void _onChanged() {
    final dirty = _code.text != _savedText;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  void _validate() {
    try {
      final decoded = jsonDecode(_code.text);
      if (decoded is! Map) {
        setState(() {
          _parseError = '根节点必须是 JSON 对象';
          _issues = const [];
        });
        return;
      }
      final manifest = PluginManifest.fromJson(decoded.cast<String, dynamic>());
      setState(() {
        _parseError = null;
        _issues = const PluginValidator().validate(manifest);
      });
    } catch (e) {
      setState(() {
        _parseError = _prettyJsonError(e);
        _issues = const [];
      });
    }
  }

  String _prettyJsonError(Object e) {
    final s = e.toString();
    if (s.contains('FormatException')) {
      return 'JSON 语法错误：${s.split(':').skip(1).join(':').trim()}';
    }
    return s;
  }

  PluginManifest? _manifest() {
    try {
      final decoded = jsonDecode(_code.text);
      if (decoded is! Map) return null;
      return PluginManifest.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final manifest = _manifest();
    if (manifest == null) {
      showPqToast(context, _parseError ?? 'JSON 无法解析', kind: PqToastKind.error);
      return;
    }
    final errors = _issues.where((e) => e.isError).toList();
    if (errors.isNotEmpty) {
      setState(() => _tab = _EditorTab.issues);
      showPqToast(
        context,
        '还有 ${errors.length} 个错误需要先修复',
        kind: PqToastKind.error,
      );
      return;
    }
    final duplicate = ref
        .read(pluginsProvider)
        .where((p) => p.id == manifest.id && p.id != widget.pluginId)
        .toList();
    if (duplicate.isNotEmpty) {
      showPqToast(context, '插件 id 已被占用', kind: PqToastKind.error);
      return;
    }

    await ref.read(pluginsProvider.notifier).save(manifest, message: '编辑器保存');
    if (!mounted) return;
    setState(() => _savedText = _code.text);
    _onChanged();
    showPqToast(context, '已保存并生成版本记录', kind: PqToastKind.success);
  }

  void _format() {
    try {
      final decoded = jsonDecode(_code.text);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      final selection = _code.selection;
      _code.text = pretty;
      _code.selection = TextSelection.collapsed(
        offset: selection.baseOffset.clamp(0, pretty.length),
      );
      _validate();
      showPqToast(context, '已格式化', kind: PqToastKind.info);
    } catch (e) {
      showPqToast(context, 'JSON 有语法错误，无法格式化', kind: PqToastKind.error);
    }
  }

  String get _currentDiff => UnifiedDiff.generate(_savedText, _code.text);

  void _copyPatch() {
    final diff = _currentDiff;
    if (diff.isEmpty) {
      showPqToast(context, '当前没有修改', kind: PqToastKind.info);
      return;
    }
    Clipboard.setData(ClipboardData(text: diff));
    showPqToast(context, '补丁已复制到剪贴板', kind: PqToastKind.success);
  }

  Future<void> _applyPatchDialog() async {
    final controller = TextEditingController();
    final result = await showPqSheet<String>(
      context,
      title: '应用补丁',
      maxWidth: 720,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '粘贴 unified diff（@@ 开头）。补丁会应用到当前编辑器内容，冲突时不会修改任何文本。',
              style: PqType.bodySmall.copyWith(color: PqPalette.of(ctx).textMuted),
            ),
            const SizedBox(height: 12),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: PqPalette.of(ctx).canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PqPalette.of(ctx).lineSoft),
              ),
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                style: PqType.mono.copyWith(fontSize: 12),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: '@@ -12,7 +12,9 @@',
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    try {
      final next = UnifiedDiff.apply(_code.text, result);
      setState(() {
        _code.text = next;
      });
      _validate();
      showPqToast(context, '补丁已应用', kind: PqToastKind.success);
    } catch (e) {
      showPqToast(context, '$e', kind: PqToastKind.error);
    }
  }

  Future<void> _runTest() async {
    final manifest = _manifest();
    if (manifest == null) {
      showPqToast(context, '插件 JSON 无法解析', kind: PqToastKind.error);
      return;
    }
    final endpoint = _testEndpoint ?? (manifest.endpoints.keys.firstOrNull ?? 'home');
    if (!manifest.endpoints.containsKey(endpoint)) {
      showPqToast(context, '该插件没有 $endpoint 端点', kind: PqToastKind.info);
      return;
    }
    final site = _tempSite(manifest);
    final runner = runnerFor(
      plugin: manifest,
      site: site,
      http: ref.read(backendProvider).http,
      varCache: ref.read(varCacheProvider),
    );

    setState(() {
      _testing = true;
      _testResult = null;
      _testItems = const [];
      _testWarnings = const [];
      _testMs = 0;
    });

    final started = DateTime.now();
    try {
      MediaPage page;
      switch (endpoint) {
        case 'home':
          page = await runner.home();
        case 'category':
          page = await runner.category();
        case 'search':
          page = await runner.search(_testInput.text.trim().isEmpty ? '测试' : _testInput.text.trim());
        case 'detail':
          final id = _testInput.text.trim();
          if (id.isEmpty) throw 'detail 端点需要填写条目 id';
          final detail = await runner.detail(id);
          page = MediaPage(items: [detail.item]);
          setState(() {
            _testResult = '解析到 ${detail.lines.length} 条线路、${detail.episodeCount} 集';
          });
        case 'play':
          final url = _testInput.text.trim();
          if (url.isEmpty) throw 'play 端点需要填写剧集地址';
          final source = await runner.play(url);
          setState(() {
            _testResult = '播放地址：${source.url}';
          });
          page = MediaPage.empty;
        default:
          page = MediaPage.empty;
      }
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testItems = page.items;
        _testMs = DateTime.now().difference(started).inMilliseconds;
        _testResult ??= '返回 ${page.items.length} 条';
        _testWarnings = runner.trace
            .where((t) => !t.ok)
            .map((t) => '${t.method} ${t.url} → ${t.error ?? t.status}')
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testMs = DateTime.now().difference(started).inMilliseconds;
        _testResult = '$e';
        _testWarnings = runner.trace
            .take(3)
            .map((t) => '${t.method} ${t.url} → ${t.error ?? t.status} (${t.durationMs}ms)')
            .toList();
      });
    }
  }

  SiteBinding _tempSite(PluginManifest manifest) {
    final bound = ref
        .read(sitesProvider)
        .where((s) => s.pluginId == manifest.id)
        .firstOrNull;
    if (bound != null) return bound;
    return SiteBinding(
      id: 'preview_${manifest.id}',
      pluginId: manifest.id,
      name: '预览',
      baseUrl: manifest.baseUrl,
      config: {
        for (final f in manifest.config)
          if (f.defaultValue != null) f.key: f.defaultValue!,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final plugin = ref.watch(pluginsProvider).where((x) => x.id == widget.pluginId).firstOrNull;
    if (plugin == null) {
      return Scaffold(
        body: SafeArea(
          child: PqEmptyState(
            icon: Icons.extension_off_outlined,
            title: '插件不存在',
            message: '它可能已被删除。',
            action: OutlinedButton(onPressed: () => context.pop(), child: const Text('返回')),
          ),
        ),
      );
    }

    final compact = PqAdaptive.isCompact(context);
    final errorCount = _issues.where((e) => e.isError).length;

    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              plugin: plugin,
              dirty: _dirty,
              errorCount: errorCount,
              issueCount: _issues.length,
              showDiff: _showDiff,
              onBack: () => context.pop(),
              onSave: _save,
              onFormat: _format,
              onToggleDiff: () => setState(() => _showDiff = !_showDiff),
              onPatch: _applyPatchDialog,
              onCopyPatch: _copyPatch,
              onValidate: _validate,
              onDelete: () => _delete(plugin),
            ),
            Divider(height: 1, color: p.lineSoft),
            Expanded(
              child: compact
                  ? _compactBody(plugin)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 6, child: _editor(context)),
                        VerticalDivider(width: 1, color: p.lineSoft),
                        Expanded(flex: 4, child: _sidePanel(plugin)),
                      ],
                    ),
            ),
            _StatusBar(
              text: _code.text,
              errorCount: errorCount,
              warningCount: _issues.where((e) => e.level == IssueLevel.warning).length,
              parseError: _parseError,
              dirty: _dirty,
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactBody(PluginManifest plugin) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [Tab(text: '代码'), Tab(text: '校验与测试')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _editor(context),
                _sidePanel(plugin),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      color: p.canvas,
      child: _showDiff ? _diffView(context) : _codeView(context),
    );
  }

  Widget _codeView(BuildContext context) {
    final p = PqPalette.of(context);
    return Stack(
      children: [
        Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 60),
            child: TextField(
              controller: _code,
              maxLines: null,
              minLines: 24,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: PqType.mono.copyWith(fontSize: 12.5, height: 1.62, color: p.text),
              cursorColor: p.accent,
              cursorWidth: 1.6,
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '{\n  "spec": 1,\n  ...\n}',
                hintStyle: PqType.mono.copyWith(color: p.textFaint, fontSize: 12.5),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.canvas.withOpacity(0), p.canvas],
              ),
            ),
            child: Row(
              children: [
                Text(
                  'JSON · UTF-8',
                  style: PqType.eyebrow.copyWith(color: p.textFaint, fontSize: 9.5),
                ),
                const Spacer(),
                if (_dirty)
                  Text(
                    '未保存',
                    style: PqType.eyebrow.copyWith(color: p.accent, fontSize: 9.5),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _diffView(BuildContext context) {
    final p = PqPalette.of(context);
    final diff = _currentDiff;
    if (diff.isEmpty) {
      return Center(
        child: Text(
          '与已保存版本一致',
          style: PqType.bodySmall.copyWith(color: p.textFaint),
        ),
      );
    }
    final lines = diff.split('\n');
    return Scrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          final isAdd = line.startsWith('+') && !line.startsWith('+++');
          final isDel = line.startsWith('-') && !line.startsWith('---');
          final isHunk = line.startsWith('@@');
          final color = isAdd
              ? p.sage
              : isDel
                  ? p.danger
                  : isHunk
                      ? p.accent
                      : p.textMuted;
          return Container(
            color: isAdd
                ? p.sage.withOpacity(0.07)
                : isDel
                    ? p.danger.withOpacity(0.07)
                    : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
            child: Text(
              line.isEmpty ? ' ' : line,
              style: PqType.mono.copyWith(fontSize: 11.5, color: color, height: 1.55),
            ),
          );
        },
      ),
    );
  }

  Widget _sidePanel(PluginManifest plugin) {
    final p = PqPalette.of(context);
    return Container(
      color: p.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: PqSegmented(
              items: const ['校验', '测试', '版本'],
              index: _tab.index,
              compact: true,
              onChanged: (i) => setState(() => _tab = _EditorTab.values[i]),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _EditorTab.issues => _issuesPanel(),
              _EditorTab.test => _testPanel(plugin),
              _EditorTab.versions => _versionsPanel(),
            },
          ),
        ],
      ),
    );
  }

  Widget _issuesPanel() {
    final p = PqPalette.of(context);
    if (_parseError != null) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _IssueTile(
            level: IssueLevel.error,
            message: _parseError!,
            path: 'root',
          ),
        ],
      );
    }
    if (_issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_outlined, size: 26, color: p.sage),
            const SizedBox(height: 10),
            Text('规则校验通过', style: PqType.title.copyWith(fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              '可以保存或直接试跑端点',
              style: PqType.bodySmall.copyWith(color: p.textFaint),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      children: [
        for (final issue in _issues)
          _IssueTile(
            level: issue.level,
            message: issue.message,
            path: issue.path ?? '',
          ),
      ],
    );
  }

  Widget _testPanel(PluginManifest plugin) {
    final p = PqPalette.of(context);
    final endpoints = plugin.endpoints.keys.toList();
    final active = _testEndpoint ?? (endpoints.firstOrNull ?? 'home');
    final needsInput = const ['search', 'detail', 'play'].contains(active);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in endpoints)
              GestureDetector(
                onTap: () => setState(() => _testEndpoint = e),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: active == e ? p.accent.withOpacity(0.15) : p.surfaceHigh,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: active == e ? p.accent.withOpacity(0.5) : p.lineSoft,
                      width: 0.9,
                    ),
                  ),
                  child: Text(
                    e,
                    style: PqType.mono.copyWith(
                      fontSize: 11,
                      color: active == e ? p.accent : p.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (needsInput)
          TextField(
            controller: _testInput,
            style: PqType.bodySmall.copyWith(fontSize: 12.5),
            decoration: InputDecoration(
              hintText: switch (active) {
                'search' => '关键词，如：长夜',
                'detail' => '条目 id 或详情路径',
                _ => '剧集 url',
              },
              isDense: true,
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _testing ? null : _runTest,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 17),
              label: Text(_testing ? '运行中' : '试跑'),
            ),
            const SizedBox(width: 8),
            if (_testMs > 0)
              Text(
                '${_testMs}ms',
                style: PqType.mono.copyWith(fontSize: 11, color: p.textFaint),
              ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: p.canvas,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: p.lineSoft),
            ),
            child: Text(
              _testResult!,
              style: PqType.bodySmall.copyWith(
                fontSize: 11.5,
                color: _testItems.isEmpty && _testResult!.startsWith('Exception')
                    ? p.danger
                    : p.textMuted,
                height: 1.6,
              ),
            ),
          ),
        ],
        if (_testWarnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final w in _testWarnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '· $w',
                style: PqType.mono.copyWith(fontSize: 10.5, color: p.danger),
              ),
            ),
        ],
        if (_testItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '解析结果',
            style: PqType.eyebrow.copyWith(color: p.textFaint),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: MediaGrid(
              items: _testItems,
              targetWidth: 92,
              minColumns: 2,
              maxColumns: 4,
              spacing: 10,
              onTap: (item) => openDetail(context, item),
            ),
          ),
        ],
      ],
    );
  }

  Widget _versionsPanel() {
    final p = PqPalette.of(context);
    final revisions = ref.read(backendProvider).pluginRepo.revisions(widget.pluginId);
    if (revisions.isEmpty) {
      return Center(
        child: Text(
          '还没有保存过',
          style: PqType.bodySmall.copyWith(color: p.textFaint),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      itemCount: revisions.length,
      separatorBuilder: (_, __) => Divider(color: p.lineSoft),
      itemBuilder: (context, i) {
        final r = revisions[i];
        return InkWell(
          onTap: () => _showRevision(r),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.surfaceHigh,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: p.lineSoft),
                  ),
                  child: Text(
                    'v${r.seq}',
                    style: PqType.mono.copyWith(fontSize: 10, color: p.accent),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PqType.bodySmall.copyWith(fontSize: 12, color: p.text),
                      ),
                      Text(
                        '${_time(r.savedAt)} · +${r.added} −${r.removed}${r.full ? ' · 全量' : ''}',
                        style: PqType.bodySmall.copyWith(
                          fontSize: 10.5,
                          color: p.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: p.textFaint),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRevision(PluginRevision rev) {
    final p = PqPalette.of(context);
    showPqSheet(
      context,
      title: 'v${rev.seq} · ${rev.message}',
      maxWidth: 760,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_time(rev.savedAt)} · 新增 ${rev.added} 行 · 删除 ${rev.removed} 行',
              style: PqType.bodySmall.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 10),
            Container(
              height: 300,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.lineSoft),
              ),
              child: SingleChildScrollView(
                child: Text(
                  rev.patch.isEmpty ? '（该版本为全量快照）' : rev.patch,
                  style: PqType.mono.copyWith(fontSize: 11, color: p.textMuted, height: 1.55),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: rev.patch));
                    showPqToast(ctx, '补丁已复制', kind: PqToastKind.success);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('复制补丁'),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _code.text = rev.snapshot;
                    });
                    _validate();
                    showPqToast(context, '已载入 v${rev.seq}，保存后才会写入', kind: PqToastKind.info);
                  },
                  child: Text('载入 v${rev.seq}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(PluginManifest plugin) async {
    final sites = ref.read(sitesProvider).where((s) => s.pluginId == plugin.id).toList();
    final confirmed = await showPqSheet<bool>(
      context,
      title: '删除插件？',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sites.isEmpty
                  ? '这会永久移除该插件的规则与版本历史。'
                  : '该插件被 ${sites.length} 个站点使用（${sites.map((e) => e.name).join('、')}），删除后这些站点将不可用。',
              style: PqType.bodySmall.copyWith(color: PqPalette.of(ctx).textMuted, height: 1.6),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: PqPalette.of(ctx).danger,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(pluginsProvider.notifier).delete(plugin.id);
    if (mounted) context.pop();
  }

  String _time(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.plugin,
    required this.dirty,
    required this.errorCount,
    required this.issueCount,
    required this.showDiff,
    required this.onBack,
    required this.onSave,
    required this.onFormat,
    required this.onToggleDiff,
    required this.onPatch,
    required this.onCopyPatch,
    required this.onValidate,
    required this.onDelete,
  });

  final PluginManifest plugin;
  final bool dirty;
  final int errorCount;
  final int issueCount;
  final bool showDiff;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onFormat;
  final VoidCallback onToggleDiff;
  final VoidCallback onPatch;
  final VoidCallback onCopyPatch;
  final VoidCallback onValidate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 6 : 12, 8, compact ? 6 : 12, 8),
      child: Row(
        children: [
          PqIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 2),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        plugin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PqType.title.copyWith(fontSize: 14),
                      ),
                    ),
                    if (dirty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: p.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  errorCount > 0 ? '$errorCount 个错误' : 'v${plugin.version} · 校验通过',
                  style: PqType.bodySmall.copyWith(
                    fontSize: 10.5,
                    color: errorCount > 0 ? p.danger : p.textFaint,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!compact) ...[
            PqSegmented(
              items: const ['代码', '差异'],
              index: showDiff ? 1 : 0,
              compact: true,
              onChanged: (i) {
                if ((i == 1) != showDiff) onToggleDiff();
              },
            ),
            const SizedBox(width: 8),
            PqIconButton(
              icon: Icons.auto_fix_high_rounded,
              tooltip: '格式化',
              onTap: onFormat,
            ),
            PqIconButton(
              icon: Icons.sync_alt_rounded,
              tooltip: '应用补丁',
              onTap: onPatch,
            ),
            PqIconButton(
              icon: Icons.content_copy_rounded,
              tooltip: '复制差量补丁',
              onTap: onCopyPatch,
            ),
            PqIconButton(
              icon: Icons.fact_check_outlined,
              tooltip: '重新校验',
              onTap: onValidate,
            ),
          ] else
            PqIconButton(
              icon: showDiff ? Icons.code_rounded : Icons.difference_rounded,
              tooltip: showDiff ? '代码' : '差异',
              onTap: onToggleDiff,
              active: showDiff,
            ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: '更多',
            color: p.surfaceHigher,
            icon: Icon(Icons.more_vert_rounded, size: 18, color: p.textMuted),
            onSelected: (v) {
              switch (v) {
                case 'format':
                  onFormat();
                case 'patch':
                  onPatch();
                case 'copy':
                  onCopyPatch();
                case 'validate':
                  onValidate();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              if (compact) ...[
                const PopupMenuItem(value: 'format', child: Text('格式化')),
                const PopupMenuItem(value: 'patch', child: Text('应用补丁')),
                const PopupMenuItem(value: 'copy', child: Text('复制差量补丁')),
                const PopupMenuItem(value: 'validate', child: Text('重新校验')),
              ],
              PopupMenuItem(
                value: 'delete',
                child: Text('删除插件', style: TextStyle(color: p.danger, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.text,
    required this.errorCount,
    required this.warningCount,
    required this.parseError,
    required this.dirty,
  });

  final String text;
  final int errorCount;
  final int warningCount;
  final String? parseError;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.lineSoft)),
      ),
      child: Row(
        children: [
          _dot(p, errorCount > 0 || parseError != null ? p.danger : p.sage),
          const SizedBox(width: 6),
          Text(
            parseError != null
                ? 'JSON 语法错误'
                : errorCount > 0
                    ? '$errorCount 错误 · $warningCount 警告'
                    : '规则有效',
            style: PqType.eyebrow.copyWith(
              fontSize: 9.5,
              color: errorCount > 0 || parseError != null ? p.danger : p.textFaint,
            ),
          ),
          const Spacer(),
          Text(
            '$lines 行 · ${text.length} 字符',
            style: PqType.mono.copyWith(fontSize: 10, color: p.textFaint),
          ),
          if (dirty) ...[
            const SizedBox(width: 10),
            Text(
              '● 未保存',
              style: PqType.eyebrow.copyWith(fontSize: 9.5, color: p.accent),
            ),
          ],
          const SizedBox(width: 10),
          Text(
            'Poqi Spec v$kPluginSpecVersion',
            style: PqType.mono.copyWith(fontSize: 10, color: p.textFaint.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _dot(PqPalette p, Color c) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.level, required this.message, required this.path});

  final IssueLevel level;
  final String message;
  final String path;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final color = switch (level) {
      IssueLevel.error => p.danger,
      IssueLevel.warning => p.accent,
      IssueLevel.info => p.textMuted,
    };
    final icon = switch (level) {
      IssueLevel.error => Icons.error_outline_rounded,
      IssueLevel.warning => Icons.warning_amber_rounded,
      IssueLevel.info => Icons.lightbulb_outline_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.22), width: 0.9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: PqType.bodySmall.copyWith(fontSize: 11.5, color: p.text, height: 1.5),
                ),
                if (path.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      path,
                      style: PqType.mono.copyWith(fontSize: 10, color: p.textFaint),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
