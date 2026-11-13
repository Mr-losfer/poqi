# Poqi 插件规范 v1

> 一套规则，多处复用。插件描述"怎么读一个站点"，站点描述"读哪一个站点、用什么凭据"。

## 1. 心智模型

```
PluginManifest (规则)  ── 1 : N ──  SiteBinding (站点实例)
   endpoints / parse            baseUrl / config / 启用状态
```

- 同一个插件可以被多个站点复用（镜像站、不同域名、不同账号）。
- 每个站点持有自己的一份 `config`（Cookie、Token、线路偏好…）。
- 运行时变量 `vars` 由表达式计算，可按 TTL 缓存，用来处理定时轮换的签名/令牌。

## 2. 根字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `spec` | int | 是 | 规范版本，当前为 `1` |
| `id` | string | 是 | 3–64 位小写字母/数字/`.`/`_`/`-`，全局唯一 |
| `name` | string | 是 | 展示名 |
| `version` | string | 是 | 语义化版本，同步时用于比较新旧 |
| `author` / `description` / `homepage` | string | 否 | 元信息 |
| `icon` | string | 否 | 预留：URL 或字母 |
| `engine` | `http` \| `demo` | 是 | `demo` 走内置演示数据 |
| `baseUrl` | string | http 必填 | 站点基地址，站点可覆盖 |
| `headers` | map | 否 | 全局请求头，常放 UA / Referer |
| `config` | array | 否 | 站点级配置项声明 |
| `vars` | map | 否 | 运行时变量 |
| `endpoints` | map | 是 | 至少一个：home/category/search/detail/play |
| `notes` | string | 否 | 给使用者看的备注 |

## 3. config：站点级配置

```json
{
  "key": "cookie",
  "label": "Cookie",
  "type": "text",
  "required": true,
  "secret": true,
  "hint": "从浏览器复制完整 Cookie",
  "help": "失效后重新粘贴即可",
  "default": "",
  "options": ["1080P", "720P"],
  "refreshSeconds": 86400
}
```

| 字段 | 说明 |
| --- | --- |
| `key` | 合法标识符，表达式中通过 `cfg.key` 访问 |
| `type` | `text` / `password` / `number` / `boolean` / `select` |
| `required` | 添加站点时强制填写 |
| `secret` | 列表打码展示；仍存于本机存储 |
| `options` | `select` 必填 |
| `refreshSeconds` | 提示建议的刷新周期 |

## 4. vars：运行时变量

```json
"vars": {
  "sign":  { "expr": "md5(cfg.cookie + cfg.signKey + today())", "ttl": 7200 },
  "token": { "expr": "at(http.post('/auth', { body: { key: cfg.apiKey } }), 'data.token')", "ttl": 1800 }
}
```

- `expr` 在首次被引用时求值，结果按 `ttl` 缓存（秒；0 表示不缓存）。
- 表达式中可用 `http.get(path, { query, headers })` 与 `http.post(path, { body })`。
- 返回 JSON 时自动解码；否则返回字符串。
- 变量之间可以互相引用（按声明顺序）。

## 5. endpoints

```json
"search": {
  "request": {
    "method": "GET",
    "path": "/search/{{keyword}}/page/{{page}}",
    "headers": { "Referer": "{{base}}/" },
    "query": { "t": "{{category}}" },
    "body": null,
    "timeoutMs": 15000
  },
  "parse": { "format": "html", "root": ".result", "fields": { "...": "..." } },
  "filters": [
    { "key": "area", "label": "地区", "values": ["全部", "内地", "日韩"] }
  ],
  "pageStart": 1,
  "pageSize": 24
}
```

模板变量：`cfg` `vars` `page` `keyword` `category` `filters` `id` `base` `site`。

`play` 端点的 `{{id}}` 是剧集地址；会额外带 `?url=<剧集地址>` 查询参数。

若剧集地址本身就是最终播放地址（苹果CMS 等），把 `play.request.path` 留空即可：
引擎不会发起请求，只对 `parse.fields` 求值。推荐写法 `"fields": { "url": "{{id}}" }`。

## 6. JS 引擎（engine: js）

声明式规则擅长结构规整的接口；一旦站点把数据揉成复合字符串、要在多个字段间
做条件判断、或者需要先清洗 HTML 再取字段，JSON 规则就会变得别扭。
这时把 `engine` 换成 `js`，用脚本做「响应 → 标准结构」的映射。

### 6.1 结构

```json
{
  "spec": 1,
  "id": "poqi.cms.v10",
  "name": "苹果CMS v10",
  "version": "2.0.0",
  "engine": "js",
  "baseUrl": "https://example.com",
  "script": "function home(ctx) { ... }",
  "endpoints": {
    "home": {
      "request": { "path": "/api.php/provide/vod/", "query": { "ac": "list", "pg": "{{page}}" } },
      "js": "home"
    },
    "detail": {
      "request": { "path": "/api.php/provide/vod/", "query": { "ac": "detail", "ids": "{{id}}" } },
      "js": "detail"
    },
    "play": { "request": { "path": "" }, "js": "play" }
  }
}
```

- `script` 是完整脚本，含所有端点函数。
- 端点的 `js` 是函数名，省略时按端点名推断（`home` 端点调 `home()`）。
- `request` 的写法与声明式完全一致：模板变量、headers、query、body 都照旧。
  **请求由 Dart 发起**，脚本只处理拿到的响应。
- `engine: js` 时不需要 `parse`。

### 6.2 上下文（ctx）

| 字段 | 说明 |
| --- | --- |
| `ctx.body` | 响应原文（字符串） |
| `ctx.json` | 响应若是 JSON，这里是解析后的对象；否则为 `null` |
| `ctx.url` | 最终请求地址（跟随重定向后） |
| `ctx.status` | HTTP 状态码 |
| `ctx.headers` | 响应头 |
| `ctx.base` | 站点的 baseUrl |
| `ctx.page` | 页码 |
| `ctx.keyword` | 搜索词（search 端点） |
| `ctx.category` | 分类（category 端点） |
| `ctx.filters` | 筛选参数对象 |
| `ctx.id` | 详情 / 播放端点传入的 id（播放时就是剧集地址） |
| `ctx.cfg` | 该站点填写的配置项 |
| `ctx.vars` | 已解析的运行时变量 |
| `ctx.site` | `{ id, name }` |

### 6.3 返回值

**列表端点**（`home` / `category` / `search`）返回数组：

```js
[{ id, title, poster, year, area, remarks, score, kind, intro, tags }]
```

**详情端点** 返回对象，在上面的字段基础上加：

```js
{
  id, title, poster, year, area, remarks, score, kind, intro,
  director, actors: ['…'],
  lines: [{ name, episodes: [{ name, url }] }]
}
```

也可以返回扁平的 `episodes: [{ name, url, line }]`，引擎会按 `line` 自动分组。

**播放端点** 返回 `{ url }` 或一个字符串；返回空则由引擎回落到传入的剧集地址。

字段名大小写与下划线都不敏感（`vod_name` 与 `vodName` 等价），数字/布尔会自动转字符串。
`poster` 支持相对路径，引擎会用 `ctx.base` 补全。缺 `title` 的条目会被丢弃。

### 6.4 内置工具 pq

```js
pq.get(obj, 'data.list', [])   // 安全取深层字段
pq.select(html, 'css')         // 第一个匹配节点
pq.selectAll(html, 'css')      // 全部匹配
pq.css(html, 'css')            // 匹配到的文本数组
pq.cssAttr(html, 'css', 'href')
pq.text(node) / pq.ownText(node) / pq.attr(node, 'href')
pq.html(node) / pq.outer(node)
pq.abs('https://a.com', '/p/1.jpg')
pq.clean('<b>x</b>&nbsp;y')    // 去标签 + 解实体 → 'x y'
pq.matchAll(str, /(\d+)/g, 1)  // 全局正则，取第 1 组
pq.first(str, /id=(\d+)/)      // 首个匹配
pq.num('8.9 分')               // → 8.9
pq.trim / pq.uniq / pq.map / pq.pad
```

CSS 选择器支持：`tag`、`.class`、`#id`、`*`、`[attr]`、`[attr=v]`、`[attr*=v]`、
`[attr^=v]`、`[attr$=v]`，组合器支持后代（空格）与子代（`>`），逗号分组。
不支持伪类与 `+` / `~` 相邻选择器——够用，且实现只有几百行，行为可预期。

### 6.5 示例：多线路剧集

苹果CMS 的 `vod_play_url` 是 `线路$$$线路`、`集#集`、`集名$地址` 三层嵌套的字符串，
用脚本表达比声明式清晰得多：

```js
function cmsLines(fromRaw, urlRaw, base) {
  var lines = [];
  var names = String(fromRaw || '').split('$$$');
  var groups = String(urlRaw || '').split('$$$');
  for (var g = 0; g < groups.length; g++) {
    var parts = groups[g].split('#');
    var eps = [];
    for (var i = 0; i < parts.length; i++) {
      var seg = parts[i];
      if (!seg) continue;
      var cut = seg.indexOf('$');
      var name = cut < 0 ? '' : seg.slice(0, cut);
      var url = cut < 0 ? seg : seg.slice(cut + 1);
      if (!url) continue;
      eps.push({ name: name || ('第' + (i + 1) + '集'), url: pq.abs(base, url) });
    }
    if (eps.length) lines.push({ name: names[g] || ('线路' + (g + 1)), episodes: eps });
  }
  return lines;
}
```

### 6.6 限制（有意为之）

- **脚本不能自己发请求**。需要多步请求的场景（先取 token 再查列表）请用 `vars`：
  每个变量是一次独立请求，表达式或脚本负责提取，结果会带进 `ctx.vars`。
  这样做的原因是同步 HTTP 会卡死 UI，异步回调又会让插件行为不可预测。
- **同步执行**。单次脚本求值应控制在几十毫秒内；不要在脚本里写大循环处理整站数据。
- **没有 `require` / 网络 / 文件系统**。ES5 + JSON + 正则 + 内置 `pq`，仅此而已。
- 脚本报错会带函数名返回给「试跑端点」，据此定位即可。

### 6.7 调试

插件编辑器右上角的终端图标打开脚本编辑器；保存后用「试跑端点」选择 `home` / `category` /
`search` / `detail` / `play`，填入关键词或 id，直接看解析出的条目数与首条标题。
脚本改动不需要重新打包。

## 7. parse

### JSON

```json
{
  "format": "json",
  "root": "data.list",
  "fields": {
    "id": "item.vod_id",
    "title": "item.vod_name",
    "poster": "item.vod_pic",
    "score": "item.vod_score"
  }
}
```

`root` 支持 `a.b[0].c`；为空表示根节点。字段值会作为 `item` 注入表达式。

### HTML

```json
{
  "format": "html",
  "root": ".module-item",
  "fields": {
    "id": "attr(sel(item, 'a'), 'href')",
    "title": "text(sel(item, '.title'))",
    "poster": "attr(sel(item, 'img'), 'data-src')"
  },
  "episodes": {
    "format": "html",
    "root": ".play-list a",
    "fields": { "name": "text(item)", "url": "attr(item, 'href')" }
  }
}
```

`root` 额外支持 `selector >> first` / `selector >> last` 管道。

### regex

```json
{ "format": "regex", "pattern": "\"url\":\"(.*?)\"", "group": 1 }
```

### split（剧集串）

苹果CMS 的 `vod_play_url` 把线路、剧集、集名/地址压在一个字符串里：

```
第01集$https://x/1.m3u8#第02集$https://x/2.m3u8$$$第01集$https://y/1.m3u8
```

用 `split` 格式声明，`from` / `lineNames` 针对**详情记录**求值：

```json
"episodes": {
  "format": "split",
  "from": "item.vod_play_url",
  "lineNames": "item.vod_play_from",
  "lineSep": "$$$",
  "itemSep": "#",
  "pairSep": "$"
}
```

| 字段 | 缺省 | 说明 |
| --- | --- | --- |
| `from` | 必填 | 剧集串表达式 |
| `lineNames` | 可省略 | 线路名串；省略或数量不足时用「线路1/线路2…」 |
| `lineSep` | `$$$` | 线路分隔符 |
| `itemSep` | `#` | 剧集分隔符 |
| `pairSep` | `$` | 集名与地址的分隔符 |

拆分规则：空线路、空片段、空地址会被跳过；片段中没有 `pairSep` 时整段当地址，
集名按「第 N 集」自动编号；线路数与线路名数量不一致时按索引尽量匹配，不会报错。
拆分结果会转成 `{name, url, line}` 记录，交给标准的剧集分组逻辑。

## 8. 标准字段

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 站内唯一，常取详情页路径 |
| `title` | 是 | 片名 |
| `poster` | 否 | 海报；相对地址自动补全 |
| `year` `score` `remarks` `area` `kind` | 否 | 元信息 |
| `tags` | 否 | 数组，或用 `,`/`|` 分隔的字符串 |
| `intro` `director` `actors` | 详情页 | 简介/导演/演员（演员用 `,` 分隔） |
| `name` `url` `line` | 剧集 | 集名、播放页地址、线路名（缺省为"默认线路"） |

## 9. 表达式函数

| 分组 | 函数 |
| --- | --- |
| 字符串 | `text` `html` `trim` `lower` `upper` `replace` `split` `join` `substr(s,start,len)` `startsWith` `contains` `regex(s,p,g)` |
| 数字 | `int` `number` `abs` `min` `max` `round` |
| 集合 | `len` `first` `last` `nth` `slice` `reverse` `uniq` `keys` `values` |
| 筛选 | `where(list,key,value)` `find(list,key,value)`；`key` 为 Map 字段名，值按宽松相等比较（`1` 与 `"1"` 相同），入参非法时返回空数组 / `null` |
| JSON | `json` `at(v,'a.b[0]')` `path` `encode` |
| HTML | `sel(node,css)` `selAll(node,css)` `attr(node,key)` |
| 编码 | `md5` `sha1` `b64` `b64d` `urlencode` |
| 时间 | `now()` `ts()` `today()` |
| 随机 | `rand(n)` `uuid()` |
| URL | `resolve(v)` `domain(v)` |
| 逻辑 | `coalesce` `default` `if(cond,a,b)` `not` |

运算符：`+ - * / %`、`== != < <= > >=`、`&& || !`、三元 `? :`、成员 `.`、下标 `[]`。

## 10. 差量修改（补丁）

编辑器每次保存都会生成一条版本记录，包含相对于上一版的 unified diff：

```
--- a/plugin.json
+++ b/plugin.json
@@ -7,7 +8,8 @@
 {
-  "name": "棱镜",
+  "name": "棱镜 · 演示源",
   "endpoints": {
```

应用方式：

1. 应用内「插件编辑器 → 应用补丁」，粘贴后即时校验并应用。
2. MCP 工具 `poqi_apply_patch`，参数 `{ id, patch, message }`。
3. 冲突时返回补丁中的具体行号，原文本不会被改动。
4. 需要回滚时，在「版本」面板选择任意版本载入，或 `poqi_list_revisions` 取历史快照。

## 11. 调试节奏

1. 先跑 `home`：确认列表 selector 与必填字段。
2. 再跑 `detail`：确认 `episodes` 能拆出线路与集数。
3. 最后跑 `play`：确认直链可解析；HLS/MP4 会交给播放器。
4. 常见问题：`root` 未命中（页面结构变了）、403（Cookie/Referer 缺失）、
   表达式语法错误（编辑器会直接标红）、相对地址未补全（用 `resolve()`）。

## 12. 局域网 MCP

```bash
curl -X POST http://192.168.1.8:8765/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
        "name":"poqi_search","arguments":{"keyword":"长夜"}}}'
```

MCP 端点不校验配对码：只要设备在同一个局域网内、能在「连接」页看到端口，
就能直接读写。真正的边界是"同一个 Wi-Fi"，而不是一个所有人都懒得填的 4 位数字。

工具清单见 README。所有工具返回 MCP `content[0].text`，内容为 JSON 字符串。
