import 'dart:convert';

import '../models/plugin.dart';
import '../models/site.dart';

/// 随包分发的真实插件：苹果CMS v10 与 TVBox 接口。
///
/// 两者共享 CMS JSON 协议的字段映射；TVBox 额外从接口 JSON 里
/// 解析出目标站点的 api 地址。
/// 苹果CMS v10 的 JS 脚本。
///
/// 选择 JS 而不是声明式：这个站点的剧集是 `$$$` 分线路、`#` 分集、
/// `$` 分「集名/地址」的复合字符串，声明式需要额外约定 split 格式，
/// 而脚本里三行 split 就能表达清楚，也更容易按站点微调。
const _cmsV10Script = r"""
// 苹果CMS v10 —— Poqi JS 插件
// ctx 可用字段：body / json / url / base / page / keyword / category / id / cfg / vars
function cmsList(ctx) {
  var j = ctx.json || {};
  var list = j.list || j.data || [];
  var out = [];
  for (var i = 0; i < list.length; i++) out.push(cmsItem(list[i], ctx.base));
  return out;
}

function cmsItem(it, base) {
  return {
    id: String(it.vod_id == null ? '' : it.vod_id),
    title: pq.trim(it.vod_name),
    poster: pq.abs(base, pq.trim(it.vod_pic)),
    year: pq.trim(it.vod_year),
    area: pq.trim(it.vod_area),
    remarks: pq.trim(it.vod_remarks),
    score: pq.trim(it.vod_score),
    kind: pq.trim(it.type_name),
    intro: pq.clean(it.vod_blurb || '')
  };
}

function home(ctx) { return cmsList(ctx); }
function category(ctx) { return cmsList(ctx); }
function search(ctx) { return cmsList(ctx); }

function detail(ctx) {
  var j = ctx.json || {};
  var list = j.list || j.data || [];
  var it = list.length ? list[0] : {};
  var d = cmsItem(it, ctx.base);
  if (!d.id) d.id = String(ctx.id == null ? '' : ctx.id);
  d.intro = pq.clean(it.vod_content || it.vod_blurb || '');
  d.director = pq.trim(it.vod_director);
  d.actors = pq.trim(it.vod_actor).split(/[,，\\/、]/).filter(function (s) { return s; });
  d.lines = cmsLines(it.vod_play_from, it.vod_play_url, ctx.base);
  return d;
}

// vod_play_url 形如：第01集$https://a/1.m3u8#第02集$...$$$第01集$https://b/1.m3u8
// vod_play_from 用 $$$ 分隔线路名，数量通常与上面一致。
function cmsLines(fromRaw, urlRaw, base) {
  var lines = [];
  if (!urlRaw) return lines;
  var names = String(fromRaw || '').split('$$$');
  var groups = String(urlRaw).split('$$$');
  for (var g = 0; g < groups.length; g++) {
    var lineName = pq.trim(names[g]) || ('线路' + (g + 1));
    var parts = groups[g].split('#');
    var eps = [];
    for (var i = 0; i < parts.length; i++) {
      var seg = pq.trim(parts[i]);
      if (!seg) continue;
      var cut = seg.indexOf('$');
      var epName = cut < 0 ? '' : seg.slice(0, cut);
      var epUrl = cut < 0 ? seg : seg.slice(cut + 1);
      epUrl = pq.abs(base, pq.trim(epUrl));
      if (!epUrl) continue;
      eps.push({ name: pq.trim(epName) || ('第' + (i + 1) + '集'), url: epUrl });
    }
    if (eps.length) lines.push({ name: lineName, episodes: eps });
  }
  return lines;
}

// 剧集地址本身就是播放地址，不需要再请求。
function play(ctx) { return { url: String(ctx.id == null ? '' : ctx.id) }; }
""";

final _cmsV10 = const JsonEncoder.withIndent('  ').convert({
  'spec': 1,
  'id': 'poqi.cms.v10',
  'name': '苹果CMS v10',
  'version': '2.0.0',
  'author': 'Poqi',
  'description': '适配苹果CMS v10 标准 JSON 接口（/api.php/provide/vod/），'
      '用 JS 脚本完成列表、搜索、详情与多线路剧集映射。',
  'engine': 'js',
  'script': _cmsV10Script,
  'baseUrl': 'https://example.com',
  'headers': {'Accept': 'application/json'},
  'config': [
    {
      'key': 'api',
      'label': '接口地址',
      'required': true,
      'hint': 'https://example.com/api.php/provide/vod/',
      'help': '填完整的 provide/vod 接口地址，末尾斜杠可保留',
    },
    {
      'key': 'ua',
      'label': 'User-Agent',
      'hint': '留空使用默认浏览器 UA',
      'help': '部分站点会校验 UA，遇到 403 时可粘贴浏览器 UA',
    },
  ],
  'endpoints': {
    'home': {
      'request': {
        'path': r'{{coalesce(cfg.api, base + "/api.php/provide/vod/")}}',
        'query': {'ac': 'list', 'pg': '{{page}}'},
        'headers': {
          'User-Agent': r"{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}",
        },
      },
      'js': 'home',
    },
    'category': {
      'request': {
        'path': r'{{coalesce(cfg.api, base + "/api.php/provide/vod/")}}',
        'query': {'ac': 'list', 't': '{{category}}', 'pg': '{{page}}'},
        'headers': {
          'User-Agent': r"{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}",
        },
      },
      'js': 'category',
    },
    'search': {
      'request': {
        'path': r'{{coalesce(cfg.api, base + "/api.php/provide/vod/")}}',
        'query': {'ac': 'detail', 'wd': '{{keyword}}', 'pg': '{{page}}'},
        'headers': {
          'User-Agent': r"{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}",
        },
      },
      'js': 'search',
    },
    'detail': {
      'request': {
        'path': r'{{coalesce(cfg.api, base + "/api.php/provide/vod/")}}',
        'query': {'ac': 'detail', 'ids': '{{id}}'},
        'headers': {
          'User-Agent': r"{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}",
        },
      },
      'js': 'detail',
    },
    'play': {
      'request': {'path': ''},
      'js': 'play',
    },
  },
  'notes': '适用：苹果CMS v10 及其衍生站点的标准 JSON 接口。\n'
      '配置：只需填「接口地址」，形如 https://example.com/api.php/provide/vod/。\n'
      r'为什么用 JS：剧集字段 vod_play_url 是「线路$$$线路、集#集、集名$地址」的复合字符串，'
      '脚本里直接 split 比声明式规则更直观，也方便按站点微调。\n'
      '想改字段映射：打开本插件的源码，改 cmsItem / cmsLines 两个函数即可，'
      '保存后用「试跑端点」验证，无需重新打包。\n'
      '已知限制：分类筛选依赖站点的分类 id（t 参数），不同的站 id 不同，'
      '所以没有内置分类表；播放地址即剧集地址，不做二次解析。',
});

const _tvboxApi = r'''
{
  "spec": 1,
  "id": "poqi.tvbox.api",
  "name": "TVBox 接口",
  "version": "1.0.0",
  "author": "Poqi",
  "description": "读取 TVBox 接口 JSON，自动挑选 type=1 的站点并复用苹果CMS 标准协议解析列表、搜索、详情与播放。",
  "engine": "http",
  "baseUrl": "https://example.com",
  "headers": { "Accept": "application/json" },
  "config": [
    {
      "key": "interface",
      "label": "接口 JSON 地址",
      "required": true,
      "hint": "https://example.com/tvbox.json",
      "help": "填 TVBox 接口配置的原始 JSON 地址（不是多仓仓库地址）"
    },
    {
      "key": "siteKey",
      "label": "站点 key 或名称",
      "hint": "留空自动取第一个 type=1 的站点",
      "help": "填 TVBox sites 数组里的 key（如 csp_Xxx）或 name；留空则自动选择"
    },
    {
      "key": "ua",
      "label": "User-Agent",
      "hint": "留空使用默认浏览器 UA",
      "help": "接口与站点请求共用该 UA，遇到 403 时可粘贴浏览器 UA"
    }
  ],
  "vars": {
    "sites": {
      "expr": "coalesce(path(http.get(cfg.interface), 'sites'), [])",
      "ttl": 3600
    },
    "api": {
      "expr": "coalesce(if(coalesce(cfg.siteKey, '') == '', path(first(where(vars.sites, 'type', 1)), 'api'), coalesce(path(first(where(vars.sites, 'key', cfg.siteKey)), 'api'), path(first(where(vars.sites, 'name', cfg.siteKey)), 'api'))), '')",
      "ttl": 3600
    }
  },
  "endpoints": {
    "home": {
      "request": {
        "path": "{{vars.api}}",
        "query": { "ac": "list", "pg": "{{page}}" },
        "headers": { "User-Agent": "{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}" }
      },
      "pageSize": 20,
      "parse": {
        "format": "json",
        "root": "list",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "year": "item.vod_year",
          "score": "item.vod_score",
          "remarks": "item.vod_remarks",
          "area": "item.vod_area",
          "kind": "item.type_name"
        }
      }
    },
    "category": {
      "request": {
        "path": "{{vars.api}}",
        "query": { "ac": "list", "t": "{{category}}", "pg": "{{page}}" },
        "headers": { "User-Agent": "{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}" }
      },
      "pageSize": 20,
      "parse": {
        "format": "json",
        "root": "list",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "year": "item.vod_year",
          "score": "item.vod_score",
          "remarks": "item.vod_remarks",
          "area": "item.vod_area",
          "kind": "item.type_name"
        }
      }
    },
    "search": {
      "request": {
        "path": "{{vars.api}}",
        "query": { "ac": "detail", "wd": "{{keyword}}", "pg": "{{page}}" },
        "headers": { "User-Agent": "{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}" }
      },
      "pageSize": 20,
      "parse": {
        "format": "json",
        "root": "list",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "year": "item.vod_year",
          "score": "item.vod_score",
          "remarks": "item.vod_remarks",
          "area": "item.vod_area",
          "kind": "item.type_name"
        }
      }
    },
    "detail": {
      "request": {
        "path": "{{vars.api}}",
        "query": { "ac": "detail", "ids": "{{id}}" },
        "headers": { "User-Agent": "{{coalesce(cfg.ua, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')}}" }
      },
      "parse": {
        "format": "json",
        "root": "list",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "intro": "item.vod_content",
          "director": "item.vod_director",
          "actors": "item.vod_actor",
          "year": "item.vod_year",
          "score": "item.vod_score",
          "remarks": "item.vod_remarks",
          "area": "item.vod_area",
          "kind": "item.type_name",
          "tags": "item.vod_class"
        },
        "episodes": {
          "format": "split",
          "from": "item.vod_play_url",
          "lineNames": "item.vod_play_from"
        }
      }
    },
    "play": {
      "request": { "path": "" },
      "parse": { "format": "json", "fields": { "url": "{{id}}" } }
    }
  },
  "notes": "适用：TVBox 单仓接口（根节点含 sites 数组）。配置：填写「接口 JSON 地址」；siteKey 留空时自动选择第一个 type=1 的站点，也可以填 sites 里的 key 或 name 精确指定。\n接口 JSON 会缓存 1 小时（vars.ttl=3600），选中站点的 api 通常是 /api.php/provide/vod/，因此列表、搜索、详情、剧集拆分与苹果CMS 插件完全一致。\n已知限制：仅支持单仓结构；如果接口根节点只有 urls（多仓/仓库列表），请打开具体仓库的 JSON 地址再填入，本插件不会自动展开多仓。type 不是 1 的站点（如 jar/csp 扩展、直播源）不受支持。"
}
''';

List<PluginManifest> builtinPlugins() => [
      PluginManifest.fromJsonString(_cmsV10).copyWith(builtin: true),
      PluginManifest.fromJsonString(_tvboxApi).copyWith(builtin: true),
    ];

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
