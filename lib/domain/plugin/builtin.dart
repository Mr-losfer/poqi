import '../models/plugin.dart';
import '../models/site.dart';

/// 随包分发的两个插件，都是「单文件脚本」形态：
/// 元信息（`var plugin = {...}`）+ 全部逻辑（home / category / search / detail / play）
/// 都在同一段 JS 里，没有任何 JSON 规则。
///
/// Dart 这边只是把它们包成 [PluginManifest] 常量，方便随包分发；
/// 用户在「插件 → 源码」里看到的、编辑的、复制的，就是下面这两段脚本本身。
const _cmsV10Script = r"""
// ===========================================================================
// 苹果CMS v10 —— Poqi 单文件插件
// 一个 .js 文件就是一个插件：元信息、请求、解析、输出结构全在这里。
// 只要站点是标准 provide/vod 接口，改配置里的「接口地址」就能直接用。
// ===========================================================================

var plugin = {
  id: 'poqi.cms.v10',
  name: '苹果CMS v10',
  version: '3.0.0',
  author: 'Poqi',
  description: '标准 provide/vod JSON 接口：列表、搜索、详情、多线路剧集。',
  base: '',
  headers: { 'Accept': 'application/json' },
  config: [
    {
      key: 'api',
      label: '接口地址',
      required: true,
      hint: 'https://example.com/api.php/provide/vod/',
      help: '填完整的 provide/vod 接口地址，末尾斜杠可留可不留'
    },
    {
      key: 'ua',
      label: 'User-Agent',
      hint: '留空使用默认浏览器 UA',
      help: '部分站点会校验 UA，遇到 403 时粘贴浏览器 UA'
    }
  ]
};

// ---------------------------------------------------------------- 请求
function apiOf(p) {
  var a = pq.trim(p.cfg.api || '');
  if (!a) throw new Error('请先到站点设置里填写「接口地址」');
  return a;
}

function call(p, query) {
  var url = apiOf(p);
  var sep = url.indexOf('?') >= 0 ? '&' : '?';
  var headers = {};
  if (pq.trim(p.cfg.ua || '')) headers['User-Agent'] = pq.trim(p.cfg.ua);
  var body = pq.http.get(url + sep + pq.query(query), { headers: headers });
  var json = pq.json(body);
  if (!json) {
    throw new Error('接口没有返回 JSON（可能被拦截或地址写错）：' + String(body).slice(0, 100));
  }
  return json;
}

// ---------------------------------------------------------------- 映射
function pick(it) {
  return {
    id: String(it.vod_id == null ? '' : it.vod_id),
    title: pq.trim(it.vod_name),
    poster: pq.trim(it.vod_pic),
    year: pq.trim(it.vod_year),
    area: pq.trim(it.vod_area),
    remarks: pq.trim(it.vod_remarks),
    score: pq.trim(it.vod_score),
    kind: pq.trim(it.type_name),
    intro: pq.clean(it.vod_blurb || '')
  };
}

function feed(p, query) {
  var json = call(p, query);
  var raw = json.list || json.data || [];
  var out = [];
  for (var i = 0; i < raw.length; i++) out.push(pick(raw[i]));
  return { list: out, hasMore: out.length >= 20 };
}

// ---------------------------------------------------------------- 端点
function home(p) {
  return feed(p, { ac: 'list', pg: p.page });
}

function category(p) {
  return feed(p, { ac: 'list', t: p.category, pg: p.page });
}

function search(p) {
  return feed(p, { ac: 'detail', wd: p.keyword, pg: p.page });
}

function detail(p) {
  var json = call(p, { ac: 'detail', ids: p.id });
  var raw = json.list || json.data || [];
  var it = raw.length ? raw[0] : {};
  var d = pick(it);
  if (!d.id) d.id = String(p.id);
  d.intro = pq.clean(it.vod_content || it.vod_blurb || '');
  d.director = pq.trim(it.vod_director);
  d.actors = pq.trim(it.vod_actor).split(/[,，\/、]/).filter(function (s) { return s; });
  d.lines = splitLines(it.vod_play_from, it.vod_play_url, p.base);
  return d;
}

// 剧集地址本身就是播放地址，不需要再请求。
function play(p) {
  return { url: p.id };
}

// ---------------------------------------------------------------- 剧集
// vod_play_from: 线路A$$$线路B
// vod_play_url : 第01集$https://a/1.m3u8#第02集$...$$$第01集$https://b/1.m3u8
function splitLines(fromRaw, urlRaw, base) {
  var lines = [];
  if (!urlRaw) return lines;
  var names = String(fromRaw || '').split('$$$');
  var groups = String(urlRaw).split('$$$');
  for (var g = 0; g < groups.length; g++) {
    var parts = groups[g].split('#');
    var eps = [];
    for (var i = 0; i < parts.length; i++) {
      var seg = pq.trim(parts[i]);
      if (!seg) continue;
      var cut = seg.indexOf('$');
      var name = cut < 0 ? '' : seg.slice(0, cut);
      var url = cut < 0 ? seg : seg.slice(cut + 1);
      url = pq.abs(base, pq.trim(url));
      if (!url) continue;
      eps.push({ name: pq.trim(name) || ('第' + (i + 1) + '集'), url: url });
    }
    if (eps.length) {
      lines.push({ name: pq.trim(names[g]) || ('线路' + (g + 1)), episodes: eps });
    }
  }
  return lines;
}
""";

const _tvboxScript = r"""
// ===========================================================================
// TVBox 接口 —— Poqi 单文件插件
// 先读 TVBox 的接口 JSON，挑一个 type=1 的站点，再复用苹果CMS 标准协议。
// ===========================================================================

var plugin = {
  id: 'poqi.tvbox.api',
  name: 'TVBox 接口',
  version: '2.0.0',
  author: 'Poqi',
  description: '读取 TVBox 单仓接口，自动挑选 type=1 的站点并复用苹果CMS 协议。',
  base: '',
  headers: { 'Accept': 'application/json' },
  config: [
    {
      key: 'interface',
      label: '接口 JSON 地址',
      required: true,
      hint: 'https://example.com/tvbox.json',
      help: '填 TVBox 接口配置的原始 JSON 地址（不是多仓仓库列表）'
    },
    {
      key: 'siteKey',
      label: '站点 key 或名称',
      hint: '留空自动取第一个 type=1 的站点',
      help: '填 sites 数组里的 key（如 csp_Xxx）或 name'
    },
    {
      key: 'ua',
      label: 'User-Agent',
      hint: '留空使用默认浏览器 UA'
    }
  ]
};

// ---------------------------------------------------------------- 接口解析
function apiOf(p) {
  var entry = pq.trim(p.cfg.interface || '');
  if (!entry) throw new Error('请先填写「接口 JSON 地址」');

  var raw = pq.http.get(entry);
  var json = pq.json(raw);
  if (!json) throw new Error('接口 JSON 解析失败：' + String(raw).slice(0, 100));

  var sites = json.sites || [];
  var key = pq.trim(p.cfg.siteKey || '');
  var hit = null;
  var i;

  if (key) {
    for (i = 0; i < sites.length; i++) {
      if (sites[i].key === key || sites[i].name === key) { hit = sites[i]; break; }
    }
    if (!hit) throw new Error('接口里找不到站点「' + key + '」');
  }
  if (!hit) {
    for (i = 0; i < sites.length; i++) {
      if (sites[i].type === 1) { hit = sites[i]; break; }
    }
  }
  if (!hit) throw new Error('接口里没有 type=1 的站点，可能填的是多仓地址');

  var api = pq.trim(hit.api || '');
  if (!api) throw new Error('站点「' + (hit.name || hit.key) + '」没有 api 字段');
  return api;
}

// ---------------------------------------------------------------- 请求
function call(p, query) {
  var url = apiOf(p);
  var sep = url.indexOf('?') >= 0 ? '&' : '?';
  var headers = {};
  if (pq.trim(p.cfg.ua || '')) headers['User-Agent'] = pq.trim(p.cfg.ua);
  var body = pq.http.get(url + sep + pq.query(query), { headers: headers });
  var json = pq.json(body);
  if (!json) {
    throw new Error('站点接口没有返回 JSON：' + String(body).slice(0, 100));
  }
  return json;
}

// ---------------------------------------------------------------- 映射
function pick(it) {
  return {
    id: String(it.vod_id == null ? '' : it.vod_id),
    title: pq.trim(it.vod_name),
    poster: pq.trim(it.vod_pic),
    year: pq.trim(it.vod_year),
    area: pq.trim(it.vod_area),
    remarks: pq.trim(it.vod_remarks),
    score: pq.trim(it.vod_score),
    kind: pq.trim(it.type_name),
    intro: pq.clean(it.vod_blurb || '')
  };
}

function feed(p, query) {
  var json = call(p, query);
  var raw = json.list || json.data || [];
  var out = [];
  for (var i = 0; i < raw.length; i++) out.push(pick(raw[i]));
  return { list: out, hasMore: out.length >= 20 };
}

// ---------------------------------------------------------------- 端点
function home(p) {
  return feed(p, { ac: 'list', pg: p.page });
}

function category(p) {
  return feed(p, { ac: 'list', t: p.category, pg: p.page });
}

function search(p) {
  return feed(p, { ac: 'detail', wd: p.keyword, pg: p.page });
}

function detail(p) {
  var json = call(p, { ac: 'detail', ids: p.id });
  var raw = json.list || json.data || [];
  var it = raw.length ? raw[0] : {};
  var d = pick(it);
  if (!d.id) d.id = String(p.id);
  d.intro = pq.clean(it.vod_content || it.vod_blurb || '');
  d.director = pq.trim(it.vod_director);
  d.actors = pq.trim(it.vod_actor).split(/[,，\/、]/).filter(function (s) { return s; });
  d.lines = splitLines(it.vod_play_from, it.vod_play_url, p.base);
  return d;
}

function play(p) {
  return { url: p.id };
}

function splitLines(fromRaw, urlRaw, base) {
  var lines = [];
  if (!urlRaw) return lines;
  var names = String(fromRaw || '').split('$$$');
  var groups = String(urlRaw).split('$$$');
  for (var g = 0; g < groups.length; g++) {
    var parts = groups[g].split('#');
    var eps = [];
    for (var i = 0; i < parts.length; i++) {
      var seg = pq.trim(parts[i]);
      if (!seg) continue;
      var cut = seg.indexOf('$');
      var name = cut < 0 ? '' : seg.slice(0, cut);
      var url = cut < 0 ? seg : seg.slice(cut + 1);
      url = pq.abs(base, pq.trim(url));
      if (!url) continue;
      eps.push({ name: pq.trim(name) || ('第' + (i + 1) + '集'), url: url });
    }
    if (eps.length) {
      lines.push({ name: pq.trim(names[g]) || ('线路' + (g + 1)), episodes: eps });
    }
  }
  return lines;
}
""";

const _endpoints = <String, EndpointSpec>{
  'home': EndpointSpec(js: 'home'),
  'category': EndpointSpec(js: 'category'),
  'search': EndpointSpec(js: 'search'),
  'detail': EndpointSpec(js: 'detail'),
  'play': EndpointSpec(js: 'play'),
};

final PluginManifest _cmsV10 = PluginManifest(
  id: 'poqi.cms.v10',
  name: '苹果CMS v10',
  version: '3.0.0',
  author: 'Poqi',
  description: '标准 provide/vod JSON 接口：列表、搜索、详情、多线路剧集。',
  engine: PluginEngine.js,
  source: PluginSource.script,
  script: _cmsV10Script,
  headers: const {'Accept': 'application/json'},
  config: const [
    ConfigField(
      key: 'api',
      label: '接口地址',
      required: true,
      hint: 'https://example.com/api.php/provide/vod/',
      help: '填完整的 provide/vod 接口地址，末尾斜杠可留可不留',
    ),
    ConfigField(
      key: 'ua',
      label: 'User-Agent',
      hint: '留空使用默认浏览器 UA',
      help: '部分站点会校验 UA，遇到 403 时粘贴浏览器 UA',
    ),
  ],
  endpoints: _endpoints,
  notes: '适用：苹果CMS v10 及衍生站点的标准 JSON 接口。\n'
      '配置：只需填「接口地址」，形如 https://example.com/api.php/provide/vod/。\n'
      '源码就是插件：点「编辑脚本」可以看到全部逻辑，改完保存立即生效，不需要重新打包。'
      '想适配非标准站点，复制这个插件改几行就行。',
  builtin: true,
);

final PluginManifest _tvboxApi = PluginManifest(
  id: 'poqi.tvbox.api',
  name: 'TVBox 接口',
  version: '2.0.0',
  author: 'Poqi',
  description: '读取 TVBox 单仓接口，自动挑选 type=1 的站点并复用苹果CMS 协议。',
  engine: PluginEngine.js,
  source: PluginSource.script,
  script: _tvboxScript,
  headers: const {'Accept': 'application/json'},
  config: const [
    ConfigField(
      key: 'interface',
      label: '接口 JSON 地址',
      required: true,
      hint: 'https://example.com/tvbox.json',
      help: '填 TVBox 接口配置的原始 JSON 地址（不是多仓仓库地址）',
    ),
    ConfigField(
      key: 'siteKey',
      label: '站点 key 或名称',
      hint: '留空自动取第一个 type=1 的站点',
      help: '填 TVBox sites 数组里的 key（如 csp_Xxx）或 name；留空则自动选择',
    ),
    ConfigField(
      key: 'ua',
      label: 'User-Agent',
      hint: '留空使用默认浏览器 UA',
    ),
  ],
  endpoints: _endpoints,
  notes: '适用：TVBox 单仓接口（根节点含 sites 数组）。\n'
      '配置：填「接口 JSON 地址」；siteKey 留空时自动选第一个 type=1 的站点。\n'
      '接口 JSON 与站点接口都由脚本自己请求，逻辑全在这一个文件里。\n'
      '已知限制：不支持多仓（根节点只有 urls 的地址）、type 不是 1 的站点（jar/csp 扩展、直播源）。',
  builtin: true,
);

List<PluginManifest> builtinPlugins() => [_cmsV10, _tvboxApi];

/// 初始站点：两个内置插件各挂一个占位站点；必填配置留空，避免首次启动误请求。
List<SiteBinding> seedSites() {
  final now = DateTime.now();
  return [
    SiteBinding(
      id: 'site_cms_v10',
      pluginId: 'poqi.cms.v10',
      name: '苹果CMS 示例',
      baseUrl: 'https://example.com',
      order: 0,
      config: const {'api': '', 'ua': ''},
      notes: '填写接口地址后启用',
      createdAt: now,
      updatedAt: now,
    ),
    SiteBinding(
      id: 'site_tvbox_api',
      pluginId: 'poqi.tvbox.api',
      name: 'TVBox 示例',
      baseUrl: 'https://example.com',
      order: 1,
      config: const {'interface': '', 'siteKey': '', 'ua': ''},
      notes: '填写接口 JSON 地址后启用',
      createdAt: now,
      updatedAt: now,
    ),
  ];
}
