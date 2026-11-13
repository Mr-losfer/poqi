import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../data/repositories.dart';
import '../../domain/models/plugin.dart';
import '../../domain/plugin/validator.dart';
import '../../state/providers.dart';

/// 插件详情：规则本身 + 配置声明 + 校验结果 + 版本历史。
class PluginDetailPage extends ConsumerWidget {
  const PluginDetailPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final plugins = ref.watch(pluginsProvider);
    final plugin = plugins.where((e) => e.id == pluginId).firstOrNull;

    if (plugin == null) {
      return Scaffold(
        backgroundColor: p.canvas,
        body: PqBackdrop(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    PqAdaptive.gutter(context),
                    10,
                    PqAdaptive.gutter(context),
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _BackRow(onTap: () => _back(context)),
                  ),
                ),
                Expanded(
                  child: PqEmptyState(
                    icon: Icons.extension_off_outlined,
                    title: '插件不存在',
                    message: '「$pluginId」可能已被删除或恢复为内置版本。',
                    action: OutlinedButton(
                      onPressed: () => context.go('/plugins'),
                      child: const Text('返回插件工坊'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final issues = const PluginValidator().validate(plugin);
    final revisions = ref.read(backendProvider).pluginRepo.revisions(plugin.id);

    return Scaffold(
      backgroundColor: p.canvas,
      body: PqBackdrop(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            top: compact ? MediaQuery.paddingOf(context).top + 8 : 18,
            bottom: 64,
          ),
          child: PqContent(
            maxWidth: 1180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BackRow(onTap: () => _back(context)),
                const SizedBox(height: 10),
                _header(context, ref, plugin, compact),
                const SizedBox(height: 8),
                _overview(context, plugin),
                _Section(
                  eyebrow: 'CONFIG',
                  title: '配置项',
                  subtitle: plugin.config.isEmpty
                      ? '未声明，站点无需填写'
                      : '${plugin.config.length} 项 · 每个站点单独填写',
                  child: _configTable(context, plugin),
                ),
                if (plugin.vars.isNotEmpty)
                  _Section(
                    eyebrow: 'VARS',
                    title: '运行时变量',
                    subtitle: '${plugin.vars.length} 个 · 按 TTL 缓存',
                    child: _varsTable(context, plugin),
                  ),
                _Section(
                  eyebrow: 'ENDPOINTS',
                  title: '端点',
                  subtitle: '${plugin.endpoints.length} 个 · 点击展开字段映射',
                  child: _endpointsTable(context, plugin),
                ),
                _Section(
                  eyebrow: 'VALIDATE',
                  title: '校验结果',
                  subtitle: PluginValidator.summarize(issues),
                  child: _validation(context, issues),
                ),
                _Section(
                  eyebrow: 'HISTORY',
                  title: '版本历史',
                  subtitle: revisions.isEmpty
                      ? '尚未保存'
                      : '最近 ${revisions.length} 次 · 差量存储',
                  child: _revisions(context, ref, plugin, revisions),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/plugins');
    }
  }

  // -------------------------------------------------------------------------
  // 头部
  // -------------------------------------------------------------------------

  Widget _header(
    BuildContext context,
    WidgetRef ref,
    PluginManifest plugin,
    bool compact,
  ) {
    final p = PqPalette.of(context);
    final meta = Row(
      children: [
        Flexible(
          child: Text(
            plugin.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PqType.mono.copyWith(fontSize: 11.5, color: p.textFaint),
          ),
        ),
        Text('  ·  ',
            style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11)),
        Text('v${plugin.version}',
            style: PqType.mono.copyWith(fontSize: 11.5, color: p.textMuted)),
        if (plugin.author.trim().isNotEmpty) ...[
          Text('  ·  ',
              style:
                  PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11)),
          Flexible(
            child: Text(
              plugin.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  PqType.bodySmall.copyWith(fontSize: 11.5, color: p.textFaint),
            ),
          ),
        ],
      ],
    );

    final titleBlock = Column(
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
                style: PqType.h1.copyWith(fontSize: compact ? 21 : 24),
              ),
            ),
            const SizedBox(width: 9),
            PqTag(
              plugin.engine.label,
              color: plugin.engine == PluginEngine.http ? p.accent : p.sage,
            ),
            if (plugin.builtin) ...[
              const SizedBox(width: 6),
              PqTag('内置', color: p.textFaint),
            ],
          ],
        ),
        const SizedBox(height: 6),
        meta,
      ],
    );

    final actions = <Widget>[
      FilledButton.icon(
        onPressed: () => context.push('/plugin/${plugin.id}/edit'),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('编辑'),
      ),
      OutlinedButton.icon(
        onPressed: () => _copyPlugin(context, ref, plugin),
        icon: const Icon(Icons.copy_all_outlined, size: 16),
        label: Text(compact ? '复制' : '复制插件'),
      ),
      if (plugin.builtin)
        OutlinedButton.icon(
          onPressed: () => _restoreBuiltin(context, ref, plugin),
          icon: const Icon(Icons.restore_rounded, size: 16),
          label: const Text('恢复内置'),
        )
      else
        OutlinedButton.icon(
          onPressed: () => _deletePlugin(context, ref, plugin),
          style: OutlinedButton.styleFrom(
            foregroundColor: p.danger,
            side: BorderSide(color: p.danger.withOpacity(0.45)),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('删除'),
        ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PqMonogram(text: plugin.name, size: 46),
              const SizedBox(width: 12),
              Expanded(child: titleBlock),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PqMonogram(text: plugin.name, size: 56),
        const SizedBox(width: 14),
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 概览
  // -------------------------------------------------------------------------

  Widget _overview(BuildContext context, PluginManifest plugin) {
    final p = PqPalette.of(context);
    return PqPanel(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PqMetaRow(
            label: 'baseUrl',
            value: plugin.baseUrl.trim().isEmpty ? '未声明' : plugin.baseUrl,
          ),
          Divider(color: p.lineSoft, height: 1),
          PqMetaRow(
            label: 'homepage',
            value: plugin.homepage.trim().isEmpty ? '未声明' : plugin.homepage,
          ),
          Divider(color: p.lineSoft, height: 1),
          PqMetaRow(
            label: '说明',
            value: plugin.description.trim().isEmpty ? '—' : plugin.description,
          ),
          if (plugin.notes.trim().isNotEmpty) ...[
            Divider(color: p.lineSoft, height: 1),
            PqMetaRow(label: '备注', value: plugin.notes),
          ],
          if (plugin.headers.isNotEmpty) ...[
            Divider(color: p.lineSoft, height: 1),
            PqMetaRow(
              label: '请求头',
              value: plugin.headers.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n'),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 配置项 / 变量
  // -------------------------------------------------------------------------

  Widget _configTable(BuildContext context, PluginManifest plugin) {
    final p = PqPalette.of(context);
    if (plugin.config.isEmpty) {
      return PqPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Text(
          '该插件不需要站点配置，添加站点时只需确认域名。',
          style: PqType.bodySmall.copyWith(color: p.textFaint),
        ),
      );
    }

    return PqPanel(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: _HScrollTable(
        minWidth: 780,
        header: const [
          ('key', 150),
          ('标签', 130),
          ('类型', 78),
          ('必填', 56),
          ('敏感', 56),
          ('默认值', 170),
          ('刷新（秒）', 92),
        ],
        rows: [
          for (final f in plugin.config)
            [
              _monoCell(f.key),
              _text(f.label),
              _text(f.type.name),
              _text(f.required ? '是' : '—'),
              _text(f.secret ? '是' : '—'),
              _monoCell(f.defaultValue ?? '—'),
              _monoCell(f.refreshSeconds?.toString() ?? '—'),
            ],
        ],
      ),
    );
  }

  Widget _varsTable(BuildContext context, PluginManifest plugin) {
    return PqPanel(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: _HScrollTable(
        minWidth: 640,
        header: const [
          ('名称', 150),
          ('表达式', 380),
          ('TTL（秒）', 100),
        ],
        rows: [
          for (final e in plugin.vars.entries)
            [
              _monoCell(e.key, color: PqPalette.of(context).accent),
              _monoCell(e.value.expr),
              _monoCell(
                  e.value.ttlSeconds > 0 ? '${e.value.ttlSeconds}' : '永久'),
            ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 端点
  // -------------------------------------------------------------------------

  Widget _endpointsTable(BuildContext context, PluginManifest plugin) {
    final p = PqPalette.of(context);
    if (plugin.endpoints.isEmpty) {
      return PqPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Text(
          '还没有声明端点。至少需要 home 端点，首页才会展示该站点的内容。',
          style: PqType.bodySmall.copyWith(color: p.textFaint),
        ),
      );
    }

    final entries = plugin.endpoints.entries.toList();
    return PqPanel(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final width = c.maxWidth > 660 ? c.maxWidth : 660.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  const _EndpointHeader(),
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) Divider(color: p.lineSoft, height: 1),
                    _EndpointRow(
                        name: entries[i].key, endpoint: entries[i].value),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 校验
  // -------------------------------------------------------------------------

  Widget _validation(BuildContext context, List<PluginIssue> issues) {
    final p = PqPalette.of(context);
    if (issues.isEmpty) {
      return PqPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 18, color: p.sage),
            const SizedBox(width: 9),
            Text(
              '校验通过',
              style: PqType.title.copyWith(fontSize: 13.5, color: p.text),
            ),
            const SizedBox(width: 8),
            Text(
              '字段、表达式与模板都能被正确解析。',
              style:
                  PqType.bodySmall.copyWith(fontSize: 11.5, color: p.textFaint),
            ),
          ],
        ),
      );
    }

    final groups = <IssueLevel, List<PluginIssue>>{
      IssueLevel.error:
          issues.where((e) => e.level == IssueLevel.error).toList(),
      IssueLevel.warning:
          issues.where((e) => e.level == IssueLevel.warning).toList(),
      IssueLevel.info: issues.where((e) => e.level == IssueLevel.info).toList(),
    };

    return PqPanel(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final level in const [
            IssueLevel.error,
            IssueLevel.warning,
            IssueLevel.info,
          ])
            if (groups[level]!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(
                  switch (level) {
                    IssueLevel.error => '错误',
                    IssueLevel.warning => '警告',
                    IssueLevel.info => '建议',
                  },
                  style: PqType.eyebrow.copyWith(
                    fontSize: 10,
                    color: switch (level) {
                      IssueLevel.error => p.danger,
                      IssueLevel.warning => p.accent,
                      IssueLevel.info => p.textMuted,
                    },
                  ),
                ),
              ),
              for (final issue in groups[level]!)
                _IssueRow(issue: issue, color: _issueColor(p, level)),
            ],
        ],
      ),
    );
  }

  Color _issueColor(PqPalette p, IssueLevel level) => switch (level) {
        IssueLevel.error => p.danger,
        IssueLevel.warning => p.accent,
        IssueLevel.info => p.textMuted,
      };

  // -------------------------------------------------------------------------
  // 版本历史
  // -------------------------------------------------------------------------

  Widget _revisions(
    BuildContext context,
    WidgetRef ref,
    PluginManifest plugin,
    List<PluginRevision> revisions,
  ) {
    final p = PqPalette.of(context);
    if (revisions.isEmpty) {
      return PqPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Text(
          '还没有版本记录。每次在编辑器保存，都会生成一条快照与差量补丁。',
          style: PqType.bodySmall.copyWith(color: p.textFaint),
        ),
      );
    }

    return PqPanel(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Column(
        children: [
          for (var i = 0; i < revisions.length; i++) ...[
            if (i > 0) Divider(color: p.lineSoft, height: 1),
            _RevisionRow(
              revision: revisions[i],
              onTap: () => _showRevision(context, ref, plugin, revisions[i]),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRevision(
    BuildContext context,
    WidgetRef ref,
    PluginManifest plugin,
    PluginRevision revision,
  ) async {
    final p = PqPalette.of(context);
    final action = await showPqSheet<String>(
      context,
      title: '版本 v${revision.seq}',
      maxWidth: 780,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              revision.message.isEmpty ? '（无说明）' : revision.message,
              style:
                  PqType.bodySmall.copyWith(fontSize: 12.5, color: p.textMuted),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 420),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: p.canvas,
                  borderRadius: BorderRadius.circular(PqTokens.r12),
                  border: Border.all(color: p.lineSoft, width: 0.9),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      revision.patch.trim().isEmpty
                          ? '（该版本没有可显示的补丁）'
                          : revision.patch.trimRight(),
                      style: PqType.mono.copyWith(
                        fontSize: 11.5,
                        height: 1.65,
                        color: p.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: revision.patch));
                    Navigator.of(ctx).pop();
                    showPqToast(context, '补丁已复制到剪贴板',
                        kind: PqToastKind.success);
                  },
                  icon: const Icon(Icons.content_copy_rounded, size: 15),
                  label: const Text('复制补丁'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop('rollback'),
                  child: const Text('回滚到此版本'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (action != 'rollback') return;
    if (!context.mounted) return;
    final ok = await showPqSheet<bool>(
      context,
      title: '回滚到 v${revision.seq}？',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前规则会被 v${revision.seq} 的快照替换，并生成一条新的版本记录。'
              '站点的配置项不会改变。',
              style: PqType.bodySmall.copyWith(
                fontSize: 12.5,
                height: 1.65,
                color: p.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('回滚'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final target = ref
          .read(backendProvider)
          .pluginRepo
          .materialize(plugin.id, revision.seq);
      await ref
          .read(pluginsProvider.notifier)
          .save(target, message: '回滚到 v${revision.seq}');
      if (!context.mounted) return;
      showPqToast(context, '已回滚到 v${revision.seq}', kind: PqToastKind.success);
    } catch (e) {
      if (!context.mounted) return;
      showPqToast(context, '回滚失败：$e', kind: PqToastKind.error);
    }
  }

  // -------------------------------------------------------------------------
  // 复制 / 删除 / 恢复
  // -------------------------------------------------------------------------

  Future<void> _copyPlugin(
    BuildContext context,
    WidgetRef ref,
    PluginManifest plugin,
  ) async {
    final ids = ref.read(pluginsProvider).map((e) => e.id).toSet();
    var candidate = '${plugin.id}.copy';
    var n = 2;
    while (ids.contains(candidate)) {
      candidate = '${plugin.id}.copy$n';
      n++;
    }
    final copy = plugin.copyWith(
      id: candidate,
      name: '${plugin.name} 副本',
      version: '1.0.0',
      builtin: false,
    );
    await ref
        .read(pluginsProvider.notifier)
        .save(copy, message: '复制插件 ${plugin.id}');
    if (!context.mounted) return;
    showPqToast(context, '已复制为「${copy.name}」', kind: PqToastKind.success);
    await context.push('/plugin/${copy.id}/edit');
  }

  Future<void> _deletePlugin(
    BuildContext context,
    WidgetRef ref,
    PluginManifest plugin,
  ) async {
    final affected =
        ref.read(sitesProvider).where((s) => s.pluginId == plugin.id).toList();
    final ok = await showPqSheet<bool>(
      context,
      title: '删除插件？',
      builder: (ctx) => _Confirm(
        message: affected.isEmpty
            ? '「${plugin.name}」删除后，规则与版本历史都会移除。'
            : '「${plugin.name}」正被 ${affected.length} 个站点引用：'
                '${affected.map((e) => e.name).join('、')}。'
                '删除后这些站点会失效。',
        confirmLabel: '删除',
        onCancel: () => Navigator.of(ctx).pop(false),
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(pluginsProvider.notifier).delete(plugin.id);
    if (!context.mounted) return;
    showPqToast(context, '已删除「${plugin.name}」', kind: PqToastKind.success);
    context.go('/plugins');
  }

  Future<void> _restoreBuiltin(
    BuildContext context,
    WidgetRef ref,
    PluginManifest plugin,
  ) async {
    final ok = await showPqSheet<bool>(
      context,
      title: '恢复内置规则？',
      builder: (ctx) => _Confirm(
        message: '将丢弃对「${plugin.name}」的全部自定义改动，回到随包分发的版本。'
            '站点配置不受影响。',
        confirmLabel: '恢复内置',
        onCancel: () => Navigator.of(ctx).pop(false),
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(pluginsProvider.notifier).restoreBuiltin(plugin.id);
    if (!context.mounted) return;
    showPqToast(context, '已恢复内置规则', kind: PqToastKind.success);
  }
}

// ---------------------------------------------------------------------------
// 通用小组件
// ---------------------------------------------------------------------------

class _BackRow extends StatelessWidget {
  const _BackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Row(
      children: [
        PqIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: '返回',
          size: 34,
          iconSize: 18,
          onTap: onTap,
        ),
        const SizedBox(width: 8),
        Text(
          'PLUGIN',
          style: PqType.eyebrow.copyWith(color: p.textFaint),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.eyebrow,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: PqType.h2.copyWith(fontSize: 16),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.bodySmall.copyWith(
                            fontSize: 11.5,
                            color: p.textFaint,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                eyebrow,
                style: PqType.eyebrow.copyWith(
                  fontSize: 9.5,
                  color: p.textFaint.withOpacity(0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

/// 横向可滚动的轻量表格：固定列宽，避免窄屏挤压。
class _HScrollTable extends StatelessWidget {
  const _HScrollTable({
    required this.minWidth,
    required this.header,
    required this.rows,
  });

  final double minWidth;
  final List<(String, double)> header;
  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth > minWidth ? c.maxWidth : minWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.lineSoft)),
                  ),
                  child: Row(
                    children: [
                      for (final col in header)
                        SizedBox(
                          width: col.$2,
                          child: Text(
                            col.$1.toUpperCase(),
                            style: PqType.eyebrow.copyWith(
                              fontSize: 9.5,
                              letterSpacing: 0.8,
                              color: p.textFaint,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < row.length; i++)
                          SizedBox(width: header[i].$2, child: row[i]),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _text(String value) => Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: PqType.bodySmall.copyWith(fontSize: 12, height: 1.5),
    );

Widget _monoCell(String value, {Color? color}) => Builder(
      builder: (context) {
        final p = PqPalette.of(context);
        return Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: PqType.mono.copyWith(
            fontSize: 11,
            height: 1.5,
            color: color ?? p.textMuted,
          ),
        );
      },
    );

class _EndpointHeader extends StatelessWidget {
  const _EndpointHeader();

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    const widths = [86.0, 62.0, 0.0, 66.0, 132.0, 52.0];
    const labels = ['名称', '方法', '路径', '解析', 'ROOT', '字段'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.lineSoft)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            if (widths[i] == 0)
              Expanded(
                child: Text(
                  labels[i].toUpperCase(),
                  style: PqType.eyebrow.copyWith(
                    fontSize: 9.5,
                    color: p.textFaint,
                  ),
                ),
              )
            else
              SizedBox(
                width: widths[i],
                child: Text(
                  labels[i].toUpperCase(),
                  style: PqType.eyebrow.copyWith(
                    fontSize: 9.5,
                    color: p.textFaint,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatefulWidget {
  const _EndpointRow({required this.name, required this.endpoint});

  final String name;
  final EndpointSpec endpoint;

  @override
  State<_EndpointRow> createState() => _EndpointRowState();
}

class _EndpointRowState extends State<_EndpointRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final ep = widget.endpoint;
    final parse = ep.parse;
    final format = parse == null ? '—' : parse.format.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          hoverColor: p.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 86,
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: _open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Icon(Icons.chevron_right_rounded,
                            size: 15, color: p.textFaint),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.mono.copyWith(
                            fontSize: 11.5,
                            color: p.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 62,
                  child: Text(
                    ep.request.method,
                    style: PqType.mono.copyWith(
                      fontSize: 11,
                      color: p.accent.withOpacity(0.9),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    ep.request.path.isEmpty ? '—' : ep.request.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PqType.mono.copyWith(
                      fontSize: 11,
                      color: p.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 66,
                  child: Text(
                    format,
                    style: PqType.bodySmall.copyWith(
                      fontSize: 11.5,
                      color: p.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: Text(
                    (parse?.root ?? '').isEmpty ? '—' : parse!.root!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PqType.mono.copyWith(
                      fontSize: 10.5,
                      color: p.textFaint,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${parse?.fields.length ?? 0}',
                    style: PqType.mono.copyWith(
                      fontSize: 11,
                      color: p.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
                  child: _fieldsPanel(context, ep),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _fieldsPanel(BuildContext context, EndpointSpec ep) {
    final p = PqPalette.of(context);
    final parse = ep.parse;
    if (parse == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.canvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.lineSoft, width: 0.8),
        ),
        child: Text(
          '该端点没有声明 parse。play 端点可直接返回地址，其余端点必须解析响应。',
          style: PqType.bodySmall.copyWith(fontSize: 11.5, color: p.textFaint),
        ),
      );
    }

    final rows = <Widget>[];
    void addFields(String label, ParseSpec spec) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 5, top: 2),
        child: Text(
          label.toUpperCase(),
          style: PqType.eyebrow.copyWith(
            fontSize: 9,
            letterSpacing: 0.9,
            color: p.textFaint,
          ),
        ),
      ));
      for (final e in spec.fields.entries) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  e.key,
                  style: PqType.mono.copyWith(
                    fontSize: 11,
                    color: p.accent.withOpacity(0.85),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('→',
                    style: PqType.mono.copyWith(
                      fontSize: 11,
                      color: p.textFaint,
                    )),
              ),
              Text(
                e.value,
                style: PqType.mono.copyWith(
                  fontSize: 11,
                  color: p.textMuted,
                ),
              ),
            ],
          ),
        ));
      }
    }

    addFields('fields', parse);
    if (parse.episodes != null) addFields('episodes.fields', parse.episodes!);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.lineSoft, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text(
                  'REQUEST',
                  style: PqType.eyebrow.copyWith(
                    fontSize: 9,
                    color: p.textFaint,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${ep.request.method} ${ep.request.path}'
                    '${ep.request.query.isEmpty ? '' : '  ?${ep.request.query.entries.map((q) => '${q.key}=${q.value}').join('&')}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PqType.mono.copyWith(
                      fontSize: 10.5,
                      color: p.textFaint,
                    ),
                  ),
                ),
                Text(
                  '${ep.request.timeoutMs}ms',
                  style: PqType.mono.copyWith(
                    fontSize: 10.5,
                    color: p.textFaint,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: p.lineSoft, height: 1),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: rows,
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.color});

  final PluginIssue issue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final icon = switch (issue.level) {
      IssueLevel.error => Icons.error_outline_rounded,
      IssueLevel.warning => Icons.warning_amber_rounded,
      IssueLevel.info => Icons.info_outline_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              issue.message,
              style: PqType.bodySmall.copyWith(
                fontSize: 12.5,
                height: 1.55,
                color: p.text,
              ),
            ),
          ),
          if (issue.path != null) ...[
            const SizedBox(width: 10),
            Text(
              issue.path!,
              style: PqType.mono.copyWith(fontSize: 10.5, color: p.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}

class _RevisionRow extends StatelessWidget {
  const _RevisionRow({required this.revision, required this.onTap});

  final PluginRevision revision;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return InkWell(
      onTap: onTap,
      hoverColor: p.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 430;
          final head = Row(
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  'v${revision.seq}',
                  style: PqType.mono.copyWith(
                    fontSize: 11.5,
                    color: p.accent.withOpacity(0.9),
                  ),
                ),
              ),
              SizedBox(
                width: narrow ? null : 126,
                child: Text(
                  _fmt(revision.savedAt),
                  style: PqType.bodySmall.copyWith(
                    fontSize: 11,
                    color: p.textFaint,
                  ),
                ),
              ),
              if (!narrow)
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          revision.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.bodySmall.copyWith(
                            fontSize: 12,
                            color: p.text,
                          ),
                        ),
                      ),
                      if (revision.full) ...[
                        const SizedBox(width: 8),
                        PqTag('全量', color: p.textFaint),
                      ],
                    ],
                  ),
                )
              else
                const Spacer(),
              if (!revision.full) ...[
                const SizedBox(width: 8),
                Text(
                  '+${revision.added}',
                  style: PqType.mono.copyWith(fontSize: 10.5, color: p.sage),
                ),
                const SizedBox(width: 6),
                Text(
                  '−${revision.removed}',
                  style: PqType.mono.copyWith(fontSize: 10.5, color: p.danger),
                ),
              ],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 16, color: p.textFaint),
            ],
          );

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      head,
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              revision.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PqType.bodySmall.copyWith(
                                fontSize: 12,
                                color: p.text,
                              ),
                            ),
                          ),
                          if (revision.full) ...[
                            const SizedBox(width: 8),
                            PqTag('全量', color: p.textFaint),
                          ],
                        ],
                      ),
                    ],
                  )
                : head,
          );
        },
      ),
    );
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  final String message;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: PqType.bodySmall.copyWith(
              fontSize: 12.5,
              height: 1.65,
              color: p.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: const Text('取消')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: p.danger,
                  foregroundColor: p.isDark ? p.canvas : p.surface,
                ),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
