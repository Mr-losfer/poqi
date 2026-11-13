import '../models/plugin.dart';
import '../models/site.dart';

/// 随包分发的插件。它们同时是"可运行的文档"：
/// 每一个字段都在插件页的说明书里被解释。
const _prism = '''
{
  "spec": 1,
  "id": "poqi.demo.prism",
  "name": "棱镜 · 演示源",
  "version": "1.2.0",
  "author": "Poqi Lab",
  "description": "覆盖电影、剧集、动漫、综艺与纪录片的综合演示插件，用来观察聚合、去重与排序行为。",
  "engine": "demo",
  "baseUrl": "https://demo.poqi.local",
  "headers": { "User-Agent": "Poqi/1.0" },
  "config": [
    { "key": "apiKey", "label": "接口密钥", "type": "password", "secret": true, "hint": "演示环境可留空" },
    { "key": "area", "label": "内容偏好", "type": "select", "options": ["全部", "内地", "港台", "日韩", "欧美"], "default": "全部" },
    { "key": "adFree", "label": "过滤推广位", "type": "boolean", "default": "true" }
  ],
  "vars": {
    "session": { "expr": "'demo-' + md5(cfg.apiKey + today())", "ttl": 3600 }
  },
  "endpoints": {
    "home": {
      "request": { "path": "/v1/home", "query": { "page": "{{page}}" } },
      "parse": {
        "format": "json",
        "root": "data.list",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "year": "item.vod_year",
          "score": "item.vod_score",
          "remarks": "item.vod_remarks",
          "kind": "item.type_name"
        }
      }
    },
    "category": {
      "request": { "path": "/v1/list", "query": { "t": "{{category}}", "pg": "{{page}}" } },
      "filters": [
        { "key": "area", "label": "地区", "values": ["全部", "内地", "港台", "日韩", "欧美"] },
        { "key": "year", "label": "年份", "values": ["全部", "2026", "2025", "2024"] }
      ],
      "parse": {
        "format": "json",
        "root": "data.list",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "year": "item.vod_year",
          "score": "item.vod_score",
          "remarks": "item.vod_remarks"
        }
      }
    },
    "search": {
      "request": { "path": "/v1/search", "query": { "wd": "{{keyword}}" } },
      "parse": {
        "format": "json",
        "root": "data.list",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "remarks": "item.vod_remarks"
        }
      }
    },
    "detail": {
      "request": { "path": "/v1/detail", "query": { "id": "{{id}}" }, "headers": { "X-Session": "{{vars.session}}" } },
      "parse": {
        "format": "json",
        "root": "data",
        "fields": {
          "id": "item.vod_id",
          "title": "item.vod_name",
          "poster": "item.vod_pic",
          "intro": "item.vod_content",
          "director": "item.vod_director",
          "actors": "item.vod_actor"
        },
        "episodes": {
          "format": "json",
          "root": "data.episodes",
          "fields": { "name": "item.name", "url": "item.url", "line": "item.line" }
        }
      }
    },
    "play": {
      "request": { "path": "/v1/play", "query": { "url": "{{id}}" } },
      "parse": { "format": "json", "root": "data", "fields": { "url": "item.play_url" } }
    }
  },
  "notes": "演示引擎不走网络，但规则与真实插件完全一致，可直接照抄结构改成 HTTP 插件。"
}
''';

const _tide = '''
{
  "spec": 1,
  "id": "poqi.demo.tide",
  "name": "潮汐影库",
  "version": "0.9.3",
  "author": "Poqi Lab",
  "description": "偏剧集与综艺的演示站点，用于验证多站点聚合时的排序与去重。",
  "engine": "demo",
  "baseUrl": "https://tide.poqi.local",
  "config": [
    { "key": "token", "label": "接口 Token", "type": "password", "secret": true, "required": false, "refreshSeconds": 86400 },
    { "key": "quality", "label": "清晰度偏好", "type": "select", "options": ["1080P", "720P", "自动"], "default": "自动" }
  ],
  "vars": {
    "token": { "expr": "'tk_' + substr(md5(cfg.token + ts()), 0, 16)", "ttl": 1800 }
  },
  "endpoints": {
    "home": {
      "request": { "path": "/home", "headers": { "Authorization": "Bearer {{vars.token}}" } },
      "parse": {
        "format": "html",
        "root": ".feed .card",
        "fields": {
          "id": "attr(sel(item, 'a'), 'href')",
          "title": "text(sel(item, '.card-title'))",
          "poster": "attr(sel(item, 'img'), 'data-src')",
          "remarks": "text(sel(item, '.card-badge'))"
        }
      }
    },
    "search": {
      "request": { "path": "/search", "query": { "q": "{{keyword}}" } },
      "parse": {
        "format": "html",
        "root": ".result-item",
        "fields": {
          "id": "attr(sel(item, 'a'), 'href')",
          "title": "text(sel(item, 'h3'))"
        }
      }
    },
    "detail": {
      "request": { "path": "/detail/{{id}}" },
      "parse": {
        "format": "html",
        "root": ".detail",
        "fields": {
          "id": "{{id}}",
          "title": "text(sel(item, 'h1'))",
          "intro": "text(sel(item, '.intro'))"
        },
        "episodes": {
          "format": "html",
          "root": ".episode-list a",
          "fields": { "name": "text(item)", "url": "attr(item, 'href')" }
        }
      }
    }
  },
  "notes": "这个插件演示了 HTML + CSS 选择器的写法：sel / text / attr 三个函数足够覆盖大多数站点。"
}
''';

const _nightOwl = '''
{
  "spec": 1,
  "id": "poqi.demo.nightowl",
  "name": "夜枭放映室",
  "version": "2.0.1",
  "author": "Poqi Lab",
  "description": "以电影为主的演示站点，演示如何用 vars 定时换取临时签名。",
  "engine": "demo",
  "baseUrl": "https://owl.poqi.local",
  "config": [
    { "key": "cookie", "label": "Cookie", "type": "text", "secret": true, "hint": "从浏览器复制完整 Cookie" },
    { "key": "signKey", "label": "签名密钥", "type": "password", "secret": true }
  ],
  "vars": {
    "sign": { "expr": "md5(cfg.cookie + cfg.signKey + today())", "ttl": 7200 }
  },
  "endpoints": {
    "home": {
      "request": { "path": "/api/home", "headers": { "X-Sign": "{{vars.sign}}" } },
      "parse": {
        "format": "json",
        "root": "result",
        "fields": { "id": "item.id", "title": "item.title", "poster": "item.cover" }
      }
    },
    "search": {
      "request": { "path": "/api/search", "query": { "kw": "{{keyword}}", "sign": "{{vars.sign}}" } },
      "parse": {
        "format": "json",
        "root": "result",
        "fields": { "id": "item.id", "title": "item.title", "poster": "item.cover" }
      }
    }
  },
  "notes": "签名类站点的典型写法：把签名放进 vars，设置 ttl，请求里引用 {{vars.sign}}。"
}
''';

const _atlas = '''
{
  "spec": 1,
  "id": "poqi.demo.atlas",
  "name": "图鉴资料馆",
  "version": "1.0.0",
  "author": "Poqi Lab",
  "description": "纪录片与人文类内容演示站点，用于验证'优先源'与播放回退策略。",
  "engine": "demo",
  "baseUrl": "https://atlas.poqi.local",
  "config": [
    { "key": "token", "label": "访问令牌", "type": "password", "secret": true }
  ],
  "endpoints": {
    "home": {
      "request": { "path": "/docs", "headers": { "Authorization": "{{vars.token}}" } },
      "parse": {
        "format": "html",
        "root": ".entry",
        "fields": { "id": "attr(sel(item, 'a'), 'href')", "title": "text(sel(item, 'h2'))" }
      }
    },
    "search": {
      "request": { "path": "/docs/search", "query": { "kw": "{{keyword}}" } },
      "parse": {
        "format": "html",
        "root": ".entry",
        "fields": { "id": "attr(sel(item, 'a'), 'href')", "title": "text(sel(item, 'h2'))" }
      }
    }
  }
}
''';

List<PluginManifest> builtinPlugins() => [
      PluginManifest.fromJsonString(_prism).copyWith(builtin: true),
      PluginManifest.fromJsonString(_tide).copyWith(builtin: true),
      PluginManifest.fromJsonString(_nightOwl).copyWith(builtin: true),
      PluginManifest.fromJsonString(_atlas).copyWith(builtin: true),
    ];

/// 初始站点：每个内置插件都挂一个站点实例。
List<SiteBinding> seedSites() {
  final now = DateTime.now();
  return [
    SiteBinding(
      id: 'site_prism',
      pluginId: 'poqi.demo.prism',
      name: '棱镜主站',
      baseUrl: 'https://demo.poqi.local',
      order: 0,
      config: const {'apiKey': '', 'area': '全部', 'adFree': 'true'},
      notes: '默认综合源',
      createdAt: now,
      updatedAt: now,
    ),
    SiteBinding(
      id: 'site_tide',
      pluginId: 'poqi.demo.tide',
      name: '潮汐影库',
      baseUrl: 'https://tide.poqi.local',
      order: 1,
      config: const {'token': '', 'quality': '自动'},
      createdAt: now,
      updatedAt: now,
    ),
    SiteBinding(
      id: 'site_owl',
      pluginId: 'poqi.demo.nightowl',
      name: '夜枭放映室',
      baseUrl: 'https://owl.poqi.local',
      order: 2,
      config: const {'cookie': '', 'signKey': ''},
      createdAt: now,
      updatedAt: now,
    ),
    SiteBinding(
      id: 'site_atlas',
      pluginId: 'poqi.demo.atlas',
      name: '图鉴资料馆',
      baseUrl: 'https://atlas.poqi.local',
      order: 3,
      config: const {'token': ''},
      createdAt: now,
      updatedAt: now,
    ),
  ];
}
