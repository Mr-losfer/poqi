import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../domain/models/plugin.dart';
import '../../domain/models/site.dart';
import '../../state/providers.dart';
import '../shell/pq_shell.dart';

/// 插件工坊：左侧是"规则"，右侧是"规则 + 配置"。
class PluginsPage extends ConsumerStatefulWidget {
  const PluginsPage({super.key});

  @override
  ConsumerState<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends ConsumerState<PluginsPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final plugins = ref.watch(pluginsProvider);
    final sites = ref.watch(sitesProvider);

    return PqBackdrop(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: compact ? MediaQuery.paddingOf(context).top + 10 : 22,
          bottom: 56,
        ),
        child: PqContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PqPageHeader(
                eyebrow: 'STUDIO',
                title: '插件工坊',
                subtitle: compact ? null : '一套规则，多处复用；站点各自持有配置',
                actions: [
                  FilledButton.icon(
                    onPressed: _createPlugin,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('新建插件'),
                  ),
                ],
              ),
              Row(
                children: [
                  PqSegmented(
                    items: const ['插件', '站点'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tab == 0
                          ? '${plugins.length} 个插件 · ${plugins.where((e) => e.builtin).length} 个内置'
                          : '${sites.length} 个站点 · ${sites.where((e) => e.enabled).length} 个启用',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PqType.bodySmall.copyWith(
                        fontSize: 11.5,
                        color: p.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_tab == 0)
                _pluginsBody(plugins)
              else
                _sitesBody(sites, plugins),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 插件
  // -------------------------------------------------------------------------

  Widget _pluginsBody(List<PluginManifest> plugins) {
    if (plugins.isEmpty) {
      return PqEmptyState(
        icon: Icons.extension_off_outlined,
        title: '还没有插件',
        message: '新建一个插件，写清楚请求与解析规则；\n或者先复制一份内置规则再改。',
        action: FilledButton.icon(
          onPressed: _createPlugin,
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('新建插件'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 760 ? 2 : 1;
        const gap = 14.0;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < plugins.length; i++)
              SizedBox(
                width: width,
                child: PqStagger(
                  index: i,
                  child: _PluginCard(
                    plugin: plugins[i],
                    onOpen: () => context.push('/plugin/${plugins[i].id}'),
                    onMenu: (action) => _onPluginMenu(action, plugins[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _onPluginMenu(String action, PluginManifest plugin) async {
    switch (action) {
      case 'edit':
        await context.push('/plugin/${plugin.id}/edit');
        return;
      case 'detail':
        await context.push('/plugin/${plugin.id}');
        return;
      case 'copy':
        await _copyPlugin(plugin);
        return;
      case 'restore':
        await _restoreBuiltin(plugin);
        return;
      case 'delete':
        await _confirmDeletePlugin(plugin);
        return;
    }
  }

  Future<void> _createPlugin() async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = now.length > 6 ? now.substring(now.length - 6) : now;
    final ids = ref.read(pluginsProvider).map((e) => e.id).toSet();
    var id = 'custom.$suffix';
    var n = 2;
    while (ids.contains(id)) {
      id = 'custom.${suffix}_$n';
      n++;
    }
    final template = PluginManifest(
      id: id,
      name: '未命名插件',
      version: '1.0.0',
      engine: PluginEngine.http,
      baseUrl: 'https://example.com',
      endpoints: const {
        'home': EndpointSpec(
          request: RequestSpec(path: '/home', query: {'page': '{{page}}'}),
          parse: ParseSpec(
            format: ParseFormat.json,
            root: 'data.list',
            fields: {
              'id': 'item.id',
              'title': 'item.title',
              'poster': 'item.poster',
              'year': 'item.year',
              'remarks': 'item.remarks',
            },
          ),
        ),
        'search': EndpointSpec(
          request: RequestSpec(
            path: '/search',
            query: {'wd': '{{keyword}}', 'page': '{{page}}'},
          ),
          parse: ParseSpec(
            format: ParseFormat.json,
            root: 'data.list',
            fields: {
              'id': 'item.id',
              'title': 'item.title',
              'poster': 'item.poster',
              'remarks': 'item.remarks',
            },
          ),
        ),
        'detail': EndpointSpec(
          request: RequestSpec(path: '/detail', query: {'id': '{{id}}'}),
          parse: ParseSpec(
            format: ParseFormat.json,
            root: 'data',
            fields: {
              'id': 'item.id',
              'title': 'item.title',
              'poster': 'item.poster',
              'intro': 'item.intro',
            },
            episodes: ParseSpec(
              format: ParseFormat.json,
              root: 'data.episodes',
              fields: {
                'name': 'item.name',
                'url': 'item.url',
                'line': 'item.line',
              },
            ),
          ),
        ),
      },
    );

    await ref.read(pluginsProvider.notifier).save(template, message: '新建插件');
    if (!mounted) return;
    await context.push('/plugin/${template.id}/edit');
  }

  Future<void> _copyPlugin(PluginManifest plugin) async {
    final all = ref.read(pluginsProvider);
    final ids = all.map((e) => e.id).toSet();
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
    if (!mounted) return;
    showPqToast(context, '已复制为「${copy.name}」', kind: PqToastKind.success);
    await context.push('/plugin/${copy.id}/edit');
  }

  Future<void> _restoreBuiltin(PluginManifest plugin) async {
    final ok = await showPqSheet<bool>(
      context,
      title: '恢复内置规则？',
      builder: (ctx) => _ConfirmBody(
        message: '将丢弃对「${plugin.name}」的所有自定义改动，'
            '回到随包分发的原始版本。站点的配置不受影响。',
        confirmLabel: '恢复内置',
        danger: true,
        onCancel: () => Navigator.of(ctx).pop(false),
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok != true) return;
    await ref.read(pluginsProvider.notifier).restoreBuiltin(plugin.id);
    if (!mounted) return;
    showPqToast(context, '已恢复内置规则', kind: PqToastKind.success);
  }

  Future<void> _confirmDeletePlugin(PluginManifest plugin) async {
    if (plugin.builtin) {
      showPqToast(
        context,
        '内置插件不可删除，可以复制后修改',
        kind: PqToastKind.info,
      );
      return;
    }
    final affected =
        ref.read(sitesProvider).where((s) => s.pluginId == plugin.id).toList();
    final ok = await showPqSheet<bool>(
      context,
      title: '删除插件？',
      builder: (ctx) => _ConfirmBody(
        message: affected.isEmpty
            ? '「${plugin.name}」还没有关联站点，删除后规则与版本历史将一并移除。'
            : '「${plugin.name}」被 ${affected.length} 个站点引用：'
                '${affected.map((e) => e.name).join('、')}。'
                '删除后这些站点将无法运行，需要改绑其它插件或重新添加。',
        confirmLabel: '删除',
        danger: true,
        onCancel: () => Navigator.of(ctx).pop(false),
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok != true) return;
    await ref.read(pluginsProvider.notifier).delete(plugin.id);
    if (!mounted) return;
    showPqToast(context, '已删除「${plugin.name}」', kind: PqToastKind.success);
  }

  // -------------------------------------------------------------------------
  // 站点
  // -------------------------------------------------------------------------

  Widget _sitesBody(List<SiteBinding> sites, List<PluginManifest> plugins) {
    final p = PqPalette.of(context);
    if (sites.isEmpty) {
      return PqEmptyState(
        icon: Icons.dns_outlined,
        title: '还没有站点',
        message: '站点 = 插件 + 一份配置。\n同一个插件可以为不同域名各建一个站点。',
        action: FilledButton.icon(
          onPressed: () => context.push('/site/new'),
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('添加站点'),
        ),
      );
    }

    final ids = sites.map((e) => e.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sites.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == sites.length - 1 ? 6 : 10),
            child: PqStagger(
              index: i,
              child: _SiteRow(
                site: sites[i],
                plugin:
                    plugins.where((e) => e.id == sites[i].pluginId).firstOrNull,
                onToggle: () =>
                    ref.read(sitesProvider.notifier).toggle(sites[i].id),
                onUp: i == 0 ? null : () => _moveSite(ids, i, i - 1),
                onDown: i == sites.length - 1
                    ? null
                    : () => _moveSite(ids, i, i + 1),
                onEdit: () => context.push('/site/${sites[i].id}/edit'),
                onDelete: () => _confirmDeleteSite(sites[i]),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/site/new'),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('添加站点'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '站点只覆盖 baseUrl 与配置项；规则仍以插件为准。',
          style: PqType.bodySmall.copyWith(fontSize: 11.5, color: p.textFaint),
        ),
      ],
    );
  }

  Future<void> _moveSite(List<String> ids, int from, int to) async {
    final next = [...ids];
    final item = next.removeAt(from);
    next.insert(to, item);
    await ref.read(sitesProvider.notifier).reorder(next);
  }

  Future<void> _confirmDeleteSite(SiteBinding site) async {
    final ok = await showPqSheet<bool>(
      context,
      title: '删除站点？',
      builder: (ctx) => _ConfirmBody(
        message: '「${site.name}」的配置会一并删除，插件本身保留。'
            '该站点的收藏与历史记录不会被清除。',
        confirmLabel: '删除',
        danger: true,
        onCancel: () => Navigator.of(ctx).pop(false),
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok != true) return;
    await ref.read(sitesProvider.notifier).delete(site.id);
    if (!mounted) return;
    showPqToast(context, '已删除站点「${site.name}」', kind: PqToastKind.success);
  }
}

// ---------------------------------------------------------------------------
// 卡片
// ---------------------------------------------------------------------------

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.onOpen,
    required this.onMenu,
  });

  final PluginManifest plugin;
  final VoidCallback onOpen;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return PqPanel(
      padding: const EdgeInsets.fromLTRB(15, 14, 10, 13),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PqMonogram(text: plugin.name, size: 42),
              const SizedBox(width: 12),
              Expanded(
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
                            style: PqType.title.copyWith(fontSize: 14.5),
                          ),
                        ),
                        if (plugin.builtin) ...[
                          const SizedBox(width: 7),
                          PqTag('内置', color: p.textFaint),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plugin.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PqType.mono.copyWith(
                        fontSize: 11,
                        color: p.textFaint,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        PqTag('v${plugin.version}', color: p.textMuted),
                        PqTag(
                          plugin.engine.label,
                          color: plugin.engine == PluginEngine.http
                              ? p.accent
                              : p.sage,
                        ),
                        PqTag('${plugin.endpoints.length} 端点',
                            color: p.textFaint),
                        PqTag('${plugin.config.length} 配置', color: p.textFaint),
                      ],
                    ),
                  ],
                ),
              ),
              _MenuButton(plugin: plugin, onSelected: onMenu),
            ],
          ),
          if (plugin.description.trim().isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              plugin.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PqType.bodySmall.copyWith(
                fontSize: 11.5,
                color: p.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.plugin, required this.onSelected});

  final PluginManifest plugin;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      offset: const Offset(0, 34),
      color: p.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PqTokens.r12),
        side: BorderSide(color: p.line),
      ),
      onSelected: onSelected,
      itemBuilder: (ctx) => [
        _item(ctx, 'edit', Icons.edit_outlined, '编辑'),
        _item(ctx, 'detail', Icons.receipt_long_outlined, '详情'),
        _item(ctx, 'copy', Icons.copy_all_outlined, '复制'),
        if (plugin.builtin)
          _item(ctx, 'restore', Icons.restore_rounded, '恢复内置'),
        _item(
          ctx,
          'delete',
          Icons.delete_outline_rounded,
          plugin.builtin ? '删除（内置不可删）' : '删除',
          enabled: !plugin.builtin,
          danger: true,
        ),
      ],
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(Icons.more_horiz_rounded, size: 18, color: p.textMuted),
      ),
    );
  }

  PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
    bool danger = false,
  }) {
    final p = PqPalette.of(context);
    final color =
        !enabled ? p.textFaint.withOpacity(0.6) : (danger ? p.danger : p.text);
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 9),
          Text(
            label,
            style: PqType.bodySmall.copyWith(fontSize: 12.5, color: color),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 站点行
// ---------------------------------------------------------------------------

class _SiteRow extends StatelessWidget {
  const _SiteRow({
    required this.site,
    required this.plugin,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
    required this.onEdit,
    required this.onDelete,
  });

  final SiteBinding site;
  final PluginManifest? plugin;
  final VoidCallback onToggle;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final health = healthOf(site);
    final healthColor = switch (health) {
      SiteHealth.ok => p.sage,
      SiteHealth.degraded => p.accent,
      SiteHealth.failed => p.danger,
      SiteHealth.unknown => p.textFaint,
    };
    final healthLabel = switch (health) {
      SiteHealth.ok => '正常',
      SiteHealth.degraded => '偏慢',
      SiteHealth.failed => '失败',
      SiteHealth.unknown => '未检测',
    };

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: healthColor, shape: BoxShape.circle),
    );

    final title = Row(
      children: [
        dot,
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            site.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PqType.title.copyWith(
              fontSize: 13.5,
              color: site.enabled ? p.text : p.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (plugin == null)
          PqTag('插件缺失', color: p.danger)
        else
          Flexible(
            child: Text(
              '· ${plugin!.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PqType.bodySmall.copyWith(
                fontSize: 11,
                color: p.textFaint,
              ),
            ),
          ),
        if (!site.enabled) ...[
          const SizedBox(width: 6),
          PqTag('已停用', color: p.textFaint),
        ],
      ],
    );

    final meta = Row(
      children: [
        Expanded(
          child: Text(
            site.baseUrl.trim().isEmpty
                ? (plugin?.baseUrl ?? '未填写 baseUrl')
                : site.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PqType.mono.copyWith(fontSize: 10.5, color: p.textFaint),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          site.latencyMs != null
              ? '$healthLabel · ${site.latencyMs}ms'
              : healthLabel,
          style: PqType.bodySmall.copyWith(
            fontSize: 11,
            color: healthColor.withOpacity(0.9),
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: site.enabled,
          onChanged: (_) => onToggle(),
          activeColor: p.accent,
          activeTrackColor: p.accent.withOpacity(0.28),
          inactiveThumbColor: p.textFaint,
          inactiveTrackColor: p.surfaceHigher,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 2),
        PqIconButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: '上移',
          size: 32,
          iconSize: 16,
          onTap: onUp,
        ),
        PqIconButton(
          icon: Icons.arrow_downward_rounded,
          tooltip: '下移',
          size: 32,
          iconSize: 16,
          onTap: onDown,
        ),
        PqIconButton(
          icon: Icons.edit_outlined,
          tooltip: '编辑站点',
          size: 32,
          iconSize: 16,
          onTap: onEdit,
        ),
        PqIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: '删除站点',
          size: 32,
          iconSize: 16,
          onTap: onDelete,
        ),
      ],
    );

    return PqPanel(
      padding: EdgeInsets.fromLTRB(14, 11, compact ? 8 : 12, 11),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    Switch(
                      value: site.enabled,
                      onChanged: (_) => onToggle(),
                      activeColor: p.accent,
                      activeTrackColor: p.accent.withOpacity(0.28),
                      inactiveThumbColor: p.textFaint,
                      inactiveTrackColor: p.surfaceHigher,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                meta,
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PqIconButton(
                      icon: Icons.arrow_upward_rounded,
                      tooltip: '上移',
                      size: 30,
                      iconSize: 16,
                      onTap: onUp,
                    ),
                    PqIconButton(
                      icon: Icons.arrow_downward_rounded,
                      tooltip: '下移',
                      size: 30,
                      iconSize: 16,
                      onTap: onDown,
                    ),
                    PqIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: '编辑站点',
                      size: 30,
                      iconSize: 16,
                      onTap: onEdit,
                    ),
                    PqIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: '删除站点',
                      size: 30,
                      iconSize: 16,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [title, const SizedBox(height: 5), meta],
                  ),
                ),
                const SizedBox(width: 12),
                actions,
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 确认弹层
// ---------------------------------------------------------------------------

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.message,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.danger = false,
  });

  final String message;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: PqType.bodySmall.copyWith(
              fontSize: 13,
              height: 1.65,
              color: p.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: const Text('取消')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onConfirm,
                style: danger
                    ? FilledButton.styleFrom(
                        backgroundColor: p.danger,
                        foregroundColor: p.isDark ? p.canvas : p.surface,
                      )
                    : null,
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
