import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/primitives.dart';
import '../../domain/models/plugin.dart';
import '../../domain/models/site.dart';
import '../../state/providers.dart';
import '../shell/pq_shell.dart';

/// 插件工坊：插件（规则）与站点（规则 + 配置）两个页签。
class PluginsPage extends ConsumerStatefulWidget {
  const PluginsPage({super.key});

  @override
  ConsumerState<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends ConsumerState<PluginsPage> {
  @override
  Widget build(BuildContext context) {
    final compact = PqAdaptive.isCompact(context);

    return DefaultTabController(
      length: 2,
      child: PqBackdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: compact ? MediaQuery.paddingOf(context).top + 10 : 22,
              ),
              child: PqContent(
                child: PqPageHeader(
                  title: '插件工坊',
                  subtitle: compact ? null : '一套规则，多处复用；站点各自持有配置',
                ),
              ),
            ),
            PqContent(
              child: const TabBar(
                tabs: [Tab(text: '插件'), Tab(text: '站点')],
              ),
            ),
            const Expanded(child: TabBarView(children: [_PluginTab(), _SiteTab()])),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 插件页签
// ---------------------------------------------------------------------------

class _PluginTab extends ConsumerWidget {
  const _PluginTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(pluginsProvider);
    final sites = ref.watch(sitesProvider);
    final scheme = Theme.of(context).colorScheme;

    if (plugins.isEmpty) {
      return _tabScroll(
        context,
        children: [
          PqEmptyState(
            icon: Icons.extension_off_outlined,
            title: '还没有插件',
            message: '新建一个插件，写清楚请求与解析规则；\n或者先复制一份内置规则再改。',
            action: FilledButton.icon(
              onPressed: () => _createPlugin(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('新建插件'),
            ),
          ),
        ],
      );
    }

    final siteCount = <String, int>{};
    for (final s in sites) {
      siteCount[s.pluginId] = (siteCount[s.pluginId] ?? 0) + 1;
    }

    return _tabScroll(
      context,
      children: [
        _TabToolbar(
          text: '${plugins.length} 个插件 · '
              '${plugins.where((e) => e.builtin).length} 个内置',
          action: FilledButton.icon(
            onPressed: () => _createPlugin(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('新建插件'),
          ),
        ),
        for (final plugin in plugins)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: () => context.push('/plugin/${plugin.id}'),
                leading: CircleAvatar(
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.extension_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        plugin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (plugin.builtin) ...[
                      const SizedBox(width: 8),
                      PqTag('内置', color: scheme.onSurfaceVariant),
                    ],
                  ],
                ),
                subtitle: Text(
                  'v${plugin.version} · ${siteCount[plugin.id] ?? 0} 个站点'
                  ' · ${plugin.engine.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (action) =>
                      _onPluginMenu(context, ref, action, plugin),
                  itemBuilder: (ctx) => [
                    _menuItem('edit', Icons.edit_outlined, '编辑'),
                    _menuItem('detail', Icons.receipt_long_outlined, '详情'),
                    _menuItem('copy', Icons.copy_all_outlined, '复制'),
                    if (plugin.builtin)
                      _menuItem('restore', Icons.restore, '恢复内置'),
                    _menuItem(
                      'delete',
                      Icons.delete_outline,
                      plugin.builtin ? '删除（内置不可删）' : '删除',
                      enabled: !plugin.builtin,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '站点只覆盖 baseUrl 与配置项；规则仍以插件为准。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Future<void> _onPluginMenu(
    BuildContext context,
    WidgetRef ref,
    String action,
    PluginManifest plugin,
  ) async {
    switch (action) {
      case 'edit':
        await context.push('/plugin/${plugin.id}/edit');
      case 'detail':
        await context.push('/plugin/${plugin.id}');
      case 'copy':
        await _copyPlugin(context, ref, plugin);
      case 'restore':
        await _restoreBuiltin(context, ref, plugin);
      case 'delete':
        await _confirmDeletePlugin(context, ref, plugin);
    }
  }
}

// ---------------------------------------------------------------------------
// 站点页签
// ---------------------------------------------------------------------------

class _SiteTab extends ConsumerWidget {
  const _SiteTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(sitesProvider);
    final plugins = ref.watch(pluginsProvider);
    final scheme = Theme.of(context).colorScheme;

    if (sites.isEmpty) {
      return _tabScroll(
        context,
        children: [
          PqEmptyState(
            icon: Icons.dns_outlined,
            title: '还没有站点',
            message: '站点 = 插件 + 一份配置。\n同一个插件可以为不同域名各建一个站点。',
            action: FilledButton.icon(
              onPressed: () => context.push('/site/new'),
              icon: const Icon(Icons.add),
              label: const Text('添加站点'),
            ),
          ),
        ],
      );
    }

    final ids = sites.map((e) => e.id).toList();
    return _tabScroll(
      context,
      children: [
        _TabToolbar(
          text: '${sites.length} 个站点 · ${sites.where((e) => e.enabled).length} 个启用',
          action: FilledButton.tonalIcon(
            onPressed: () => context.push('/site/new'),
            icon: const Icon(Icons.add),
            label: const Text('添加站点'),
          ),
        ),
        for (var i = 0; i < sites.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SiteCard(
              site: sites[i],
              plugin: plugins.where((e) => e.id == sites[i].pluginId).firstOrNull,
              onToggle: () =>
                  ref.read(sitesProvider.notifier).toggle(sites[i].id),
              onUp: i == 0 ? null : () => _moveSite(ref, ids, i, i - 1),
              onDown: i == sites.length - 1
                  ? null
                  : () => _moveSite(ref, ids, i, i + 1),
              onEdit: () => context.push('/site/${sites[i].id}/edit'),
              onDelete: () => _confirmDeleteSite(context, ref, sites[i]),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '站点只覆盖 baseUrl 与配置项；规则仍以插件为准。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Future<void> _moveSite(WidgetRef ref, List<String> ids, int from, int to) {
    final next = [...ids];
    final item = next.removeAt(from);
    next.insert(to, item);
    return ref.read(sitesProvider.notifier).reorder(next);
  }

  Future<void> _confirmDeleteSite(
    BuildContext context,
    WidgetRef ref,
    SiteBinding site,
  ) async {
    final ok = await _confirm(
      context,
      title: '删除站点？',
      message: '「${site.name}」的配置会一并删除，插件本身保留。'
          '该站点的收藏与历史记录不会被清除。',
      confirmLabel: '删除',
    );
    if (!ok || !context.mounted) return;
    await ref.read(sitesProvider.notifier).delete(site.id);
    if (!context.mounted) return;
    showPqToast(context, '已删除站点「${site.name}」', kind: PqToastKind.success);
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({
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
    final scheme = Theme.of(context).colorScheme;
    final health = healthOf(site);
    final healthLabel = switch (health) {
      SiteHealth.ok => '正常',
      SiteHealth.degraded => '偏慢',
      SiteHealth.failed => '失败',
      SiteHealth.unknown => '未检测',
    };
    final healthColor = switch (health) {
      SiteHealth.ok => scheme.tertiary,
      SiteHealth.degraded => scheme.tertiary,
      SiteHealth.failed => scheme.error,
      SiteHealth.unknown => scheme.onSurfaceVariant,
    };
    final baseUrl = site.baseUrl.trim().isEmpty
        ? (plugin?.baseUrl ?? '未填写 baseUrl')
        : site.baseUrl;
    final meta = [
      if (plugin == null) '插件缺失' else plugin!.name,
      baseUrl,
      site.latencyMs != null ? '${site.latencyMs}ms' : healthLabel,
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(Icons.dns_outlined, color: scheme.onSurfaceVariant),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                site.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            PqTag(healthLabel, color: healthColor, filled: true),
            if (!site.enabled) ...[
              const SizedBox(width: 4),
              const PqTag('已停用'),
            ],
          ],
        ),
        subtitle: Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: site.enabled, onChanged: (_) => onToggle()),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (v) {
                switch (v) {
                  case 'up':
                    onUp?.call();
                  case 'down':
                    onDown?.call();
                  case 'edit':
                    onEdit();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (ctx) => [
                _menuItem('up', Icons.arrow_upward, '上移',
                    enabled: onUp != null),
                _menuItem('down', Icons.arrow_downward, '下移',
                    enabled: onDown != null),
                _menuItem('edit', Icons.edit_outlined, '编辑'),
                _menuItem('delete', Icons.delete_outline, '删除'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 共用
// ---------------------------------------------------------------------------

Widget _tabScroll(BuildContext context, {required List<Widget> children}) {
  final gutter = PqAdaptive.gutter(context);
  return ListView(
    padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 40),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class _TabToolbar extends StatelessWidget {
  const _TabToolbar({required this.text, required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}

PopupMenuItem<String> _menuItem(
  String value,
  IconData icon,
  String label, {
  bool enabled = true,
}) {
  return PopupMenuItem<String>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}

/// 新建插件的选择结果。
enum _TemplateKind { declarative, script }

const String _jsTemplate = r"""
// Poqi JS 插件骨架
// ---------------------------------------------------------------------------
// ctx 里能用：body（原始文本）/ json（自动解析的 JSON）/ url / status
//            base（站点地址）/ page / keyword / category / id / cfg / vars
// pq 工具：get css cssAttr select selectAll text attr html abs clean
//          matchAll first num trim uniq map
// 返回值：列表端点返回数组，详情返回对象，play 返回 {url}
// ---------------------------------------------------------------------------

function home(ctx) {
  // 例：JSON 接口
  // var list = pq.get(ctx.json, 'data.list', []);
  // return list.map(function (it) { return { id: it.id, title: it.name }; });

  // 例：HTML 站点
  // return pq.selectAll(ctx.body, '.item').map(function (node) {
  //   var a = pq.select(node, 'a');
  //   return {
  //     id: pq.attr(a, 'href'),
  //     title: pq.text(a),
  //     poster: pq.abs(ctx.base, pq.attr(pq.select(node, 'img'), 'src'))
  //   };
  // });

  return [];
}

function search(ctx) {
  return home(ctx);
}

function detail(ctx) {
  return {
    id: ctx.id,
    title: '',
    intro: '',
    lines: [
      // { name: '线路一', episodes: [{ name: '第01集', url: 'https://...' }] }
    ]
  };
}

function play(ctx) {
  // id 就是剧集地址时直接回显
  return { url: ctx.id };
}
""";

Future<void> _createPlugin(BuildContext context, WidgetRef ref) async {
  final kind = await showDialog<_TemplateKind>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建插件'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('声明式规则'),
              subtitle: const Text('用 JSON 描述请求与选择器，适合结构规整的 JSON / HTML 站点'),
              onTap: () => Navigator.of(ctx).pop(_TemplateKind.declarative),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('JavaScript 脚本'),
              subtitle: const Text('写函数把响应映射成标准结构，适合结构不规整、需要清洗的站点'),
              onTap: () => Navigator.of(ctx).pop(_TemplateKind.script),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
  if (kind == null || !context.mounted) return;

  final now = DateTime.now().millisecondsSinceEpoch.toString();
  final suffix = now.length > 6 ? now.substring(now.length - 6) : now;
  final ids = ref.read(pluginsProvider).map((e) => e.id).toSet();
  var id = 'custom.$suffix';
  var n = 2;
  while (ids.contains(id)) {
    id = 'custom.${suffix}_$n';
    n++;
  }

  final template = kind == _TemplateKind.script
      ? PluginManifest(
          id: id,
          name: '未命名插件',
          version: '1.0.0',
          engine: PluginEngine.js,
          baseUrl: 'https://example.com',
          script: _jsTemplate,
          endpoints: const {
            'home': EndpointSpec(
              request: RequestSpec(path: '/', query: {'page': '{{page}}'}),
              js: 'home',
            ),
            'search': EndpointSpec(
              request: RequestSpec(path: '/', query: {'wd': '{{keyword}}'}),
              js: 'search',
            ),
            'detail': EndpointSpec(
              request: RequestSpec(path: '/', query: {'id': '{{id}}'}),
              js: 'detail',
            ),
            'play': EndpointSpec(request: RequestSpec(path: ''), js: 'play'),
          },
        )
      : PluginManifest(
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
  if (!context.mounted) return;
  await context.push('/plugin/${template.id}/edit');
}

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

Future<void> _restoreBuiltin(
  BuildContext context,
  WidgetRef ref,
  PluginManifest plugin,
) async {
  final ok = await _confirm(
    context,
    title: '恢复内置规则？',
    message: '将丢弃对「${plugin.name}」的所有自定义改动，'
        '回到随包分发的原始版本。站点的配置不受影响。',
    confirmLabel: '恢复内置',
  );
  if (!ok || !context.mounted) return;
  await ref.read(pluginsProvider.notifier).restoreBuiltin(plugin.id);
  if (!context.mounted) return;
  showPqToast(context, '已恢复内置规则', kind: PqToastKind.success);
}

Future<void> _confirmDeletePlugin(
  BuildContext context,
  WidgetRef ref,
  PluginManifest plugin,
) async {
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
  final ok = await _confirm(
    context,
    title: '删除插件？',
    message: affected.isEmpty
        ? '「${plugin.name}」还没有关联站点，删除后规则与版本历史将一并移除。'
        : '「${plugin.name}」被 ${affected.length} 个站点引用：'
            '${affected.map((e) => e.name).join('、')}。'
            '删除后这些站点将无法运行，需要改绑其它插件或重新添加。',
    confirmLabel: '删除',
  );
  if (!ok || !context.mounted) return;
  await ref.read(pluginsProvider.notifier).delete(plugin.id);
  if (!context.mounted) return;
  showPqToast(context, '已删除「${plugin.name}」', kind: PqToastKind.success);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
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
  return ok ?? false;
}
