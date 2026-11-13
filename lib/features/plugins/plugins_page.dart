import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/primitives.dart';
import '../../domain/models/plugin.dart';
import '../../domain/plugin/js/plugin_script.dart';
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

/// 新建插件时可选的脚本模板。
enum _ScriptTemplate { html, json, blank }

/// HTML 站点模板：选择器按常见影视站结构写，改几行就能适配自己的站。
const String _templateHtml = r"""
// ===========================================================================
// 我的插件 —— 单文件脚本
// 整个插件就是这个文件：元信息、请求、解析、输出结构全在这里。
// 保存后回到插件详情点「试跑」就能验证，不需要重新打包。
// ===========================================================================

var plugin = {
  id: 'custom.mysite',        // 唯一标识，定下来就别改（站点靠它绑定）
  name: '我的站点',
  version: '1.0.0',
  author: '',
  description: 'HTML 站点：列表 / 分类 / 搜索 / 详情 / 剧集',
  base: 'https://example.com',
  headers: {
    // 'Referer': 'https://example.com/'
  },
  config: [
    // 这里声明的字段会变成「添加站点」时的表单：
    // { key: 'cookie', label: 'Cookie', type: 'password' },
    // { key: 'api', label: '接口地址', required: true }
  ]
};

// p 里有什么：
//   p.base / p.cfg / p.page / p.keyword / p.category / p.filters / p.id / p.site
// 常用工具：
//   pq.http.get(url, {headers})   发请求 → 文本（写起来是同步的）
//   pq.http.json(url)             发请求 → 已解析的对象
//   pq.selectAll(html, '.item')   取节点数组
//   pq.select(node, 'a') / pq.text() / pq.attr() / pq.abs(base, href)
//   pq.css(html, '.title')        直接取文本数组
//   pq.first(str, /re(.*?)/)      正则取第一个

function home(p) {
  return list(p, p.base + '/index.php/vod/show/id/1/page/' + p.page + '.html');
}

function category(p) {
  return list(p, p.base + '/index.php/vod/type/id/' + p.category + '/page/' + p.page + '.html');
}

function search(p) {
  return list(p, p.base + '/index.php/vod/search/page/' + p.page +
    '/wd/' + encodeURIComponent(p.keyword) + '.html');
}

function list(p, url) {
  var html = pq.http.get(url);
  var nodes = pq.selectAll(html, '.module-item, .public-list-box');
  var out = [];
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i];
    var a = pq.select(n, 'a');
    var href = pq.attr(a, 'href');
    if (!href) continue;
    var img = pq.select(n, 'img');
    out.push({
      id: pq.abs(p.base, href),          // 详情页地址，detail 会原样收到
      title: pq.text(pq.select(n, '.title, .time-title')) || pq.attr(a, 'title'),
      poster: pq.abs(p.base, pq.attr(img, 'data-src') || pq.attr(img, 'src')),
      remarks: pq.text(pq.select(n, '.module-item-note, .public-list-prb'))
    });
  }
  return { list: out, hasMore: out.length > 0 };
}

function detail(p) {
  var html = pq.http.get(p.id);
  var title = pq.css(html, 'h1.title, h1')[0] || '';
  var pic = pq.cssAttr(html, '.module-item-pic img, .detail-pic img', 'data-src')[0] || '';

  var eps = [];
  var links = pq.selectAll(html, '.module-play-list a, .playlist a');
  for (var i = 0; i < links.length; i++) {
    var href = pq.abs(p.base, pq.attr(links[i], 'href'));
    if (!href) continue;
    eps.push({ name: pq.text(links[i]) || ('第' + (i + 1) + '集'), url: href });
  }

  return {
    id: p.id,
    title: title,
    poster: pq.abs(p.base, pic),
    intro: pq.clean(pq.css(html, '.module-info-introduction, .desc')[0] || ''),
    lines: eps.length ? [{ name: '线路1', episodes: eps }] : []
  };
}

function play(p) {
  // p.id 是剧集地址。播放页若还要再解析一次真实地址，就在这里发请求：
  // var html = pq.http.get(p.id);
  // return { url: pq.first(html, /"url"\s*:\s*"([^"]+)"/) || p.id };
  return { url: p.id };
}
""";

/// JSON 接口模板：接口地址放在 config 里，一套脚本挂多个站点。
const String _templateJson = r"""
// ===========================================================================
// 我的插件 —— 单文件脚本（JSON 接口）
// 元信息 + 请求 + 解析全在这一个文件里，没有任何 JSON 规则要填。
// ===========================================================================

var plugin = {
  id: 'custom.mysite',
  name: '我的接口站',
  version: '1.0.0',
  author: '',
  description: 'JSON 接口：列表 / 分类 / 搜索 / 详情 / 剧集',
  base: 'https://example.com',
  config: [
    {
      key: 'api',
      label: '接口地址',
      required: true,
      hint: 'https://example.com/api'
    }
  ]
};

function api(p) {
  var a = pq.trim(p.cfg.api || p.base);
  if (!a) throw new Error('请先在站点设置里填写「接口地址」');
  return a;
}

function list(p, params) {
  var json = pq.http.json(api(p) + '?' + pq.query(params));
  var raw = (json && (json.data || json.list)) || [];
  var out = [];
  for (var i = 0; i < raw.length; i++) {
    var it = raw[i];
    out.push({
      id: String(it.id),
      title: pq.trim(it.name || it.title),
      poster: pq.trim(it.pic || it.poster),
      remarks: pq.trim(it.note || it.remarks)
    });
  }
  return { list: out, hasMore: out.length > 0 };
}

function home(p) {
  return list(p, { page: p.page });
}

function category(p) {
  return list(p, { type: p.category, page: p.page });
}

function search(p) {
  return list(p, { wd: p.keyword, page: p.page });
}

function detail(p) {
  var json = pq.http.json(api(p) + '?ac=detail&id=' + encodeURIComponent(p.id));
  var it = ((json && (json.data || json.list)) || [])[0] || {};
  return {
    id: p.id,
    title: pq.trim(it.name || it.title),
    poster: pq.trim(it.pic || it.poster),
    intro: pq.clean(it.desc || it.intro || ''),
    actors: pq.trim(it.actor || '').split(/[,，\/、]/).filter(function (s) { return s; }),
    lines: [{ name: '线路1', episodes: episodes(it.episodes || '') }]
  };
}

// "第01集$https://a/1.m3u8#第02集$https://a/2.m3u8"
function episodes(raw) {
  var out = [];
  var parts = String(raw || '').split('#');
  for (var i = 0; i < parts.length; i++) {
    var seg = pq.trim(parts[i]);
    if (!seg) continue;
    var cut = seg.indexOf('$');
    out.push({
      name: cut < 0 ? ('第' + (i + 1) + '集') : pq.trim(seg.slice(0, cut)),
      url: cut < 0 ? seg : pq.trim(seg.slice(cut + 1))
    });
  }
  return out;
}

function play(p) {
  return { url: p.id };
}
""";

/// 空白模板：只留骨架，适合照着文档自己写。
const String _templateBlank = r"""
// 一个 .js 文件就是一个插件。把元信息和四个函数写全就能用。

var plugin = {
  id: 'custom.mysite',
  name: '未命名插件',
  version: '1.0.0',
  base: 'https://example.com',
  config: []
};

// 列表：返回 { list: [{ id, title, poster, remarks }], hasMore }
function home(p) {
  return { list: [], hasMore: false };
}

// 搜索：p.keyword
function search(p) {
  return { list: [], hasMore: false };
}

// 详情：返回 { id, title, poster, intro, lines: [{ name, episodes: [{ name, url }] }] }
function detail(p) {
  return { id: p.id, title: '', lines: [] };
}

// 播放：返回 { url }，p.id 是剧集地址
function play(p) {
  return { url: p.id };
}
""";

Future<void> _createPlugin(BuildContext context, WidgetRef ref) async {
  final kind = await showDialog<_ScriptTemplate>(
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
              leading: const Icon(Icons.web),
              title: const Text('HTML 站点'),
              subtitle: const Text('抓网页 + CSS 选择器，最常见的一类'),
              onTap: () => Navigator.of(ctx).pop(_ScriptTemplate.html),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('JSON 接口'),
              subtitle: const Text('接口返回结构化数据，直接就着字段取'),
              onTap: () => Navigator.of(ctx).pop(_ScriptTemplate.json),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.code),
              title: const Text('空白脚本'),
              subtitle: const Text('只给骨架，自己从零写'),
              onTap: () => Navigator.of(ctx).pop(_ScriptTemplate.blank),
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

  final existing = ref.read(pluginsProvider).map((e) => e.id).toSet();
  var id = 'custom.${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  var n = 2;
  while (existing.contains(id)) {
    id = 'custom.${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_$n';
    n++;
  }

  final template = switch (kind) {
    _ScriptTemplate.html => _templateHtml,
    _ScriptTemplate.json => _templateJson,
    _ScriptTemplate.blank => _templateBlank,
  };
  // 模板里的占位 id 换成真实的，脚本是唯一事实源，必须一致。
  final script = template.replaceFirst("id: 'custom.mysite'", "id: '$id'");

  PluginManifest manifest;
  try {
    manifest = PluginScript.compile(script, fallbackId: id);
  } catch (e) {
    manifest = PluginManifest(
      id: id,
      name: '未命名插件',
      version: '1.0.0',
      engine: PluginEngine.js,
      source: PluginSource.script,
      script: script,
    );
  }

  await ref.read(pluginsProvider.notifier).save(manifest, message: '新建插件');
  if (!context.mounted) return;
  await context.push('/plugin/${manifest.id}/edit');
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
