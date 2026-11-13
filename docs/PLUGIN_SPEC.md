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

## 6. parse

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

## 7. 标准字段

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 站内唯一，常取详情页路径 |
| `title` | 是 | 片名 |
| `poster` | 否 | 海报；相对地址自动补全 |
| `year` `score` `remarks` `area` `kind` | 否 | 元信息 |
| `tags` | 否 | 数组，或用 `,`/`|` 分隔的字符串 |
| `intro` `director` `actors` | 详情页 | 简介/导演/演员（演员用 `,` 分隔） |
| `name` `url` `line` | 剧集 | 集名、播放页地址、线路名（缺省为"默认线路"） |

## 8. 表达式函数

| 分组 | 函数 |
| --- | --- |
| 字符串 | `text` `html` `trim` `lower` `upper` `replace` `split` `join` `substr(s,start,len)` `startsWith` `contains` `regex(s,p,g)` |
| 数字 | `int` `number` `abs` `min` `max` `round` |
| 集合 | `len` `first` `last` `nth` `slice` `reverse` `uniq` `keys` `values` |
| JSON | `json` `at(v,'a.b[0]')` `path` `encode` |
| HTML | `sel(node,css)` `selAll(node,css)` `attr(node,key)` |
| 编码 | `md5` `sha1` `b64` `b64d` `urlencode` |
| 时间 | `now()` `ts()` `today()` |
| 随机 | `rand(n)` `uuid()` |
| URL | `resolve(v)` `domain(v)` |
| 逻辑 | `coalesce` `default` `if(cond,a,b)` `not` |

运算符：`+ - * / %`、`== != < <= > >=`、`&& || !`、三元 `? :`、成员 `.`、下标 `[]`。

## 9. 差量修改（补丁）

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

## 10. 调试节奏

1. 先跑 `home`：确认列表 selector 与必填字段。
2. 再跑 `detail`：确认 `episodes` 能拆出线路与集数。
3. 最后跑 `play`：确认直链可解析；HLS/MP4 会交给播放器。
4. 常见问题：`root` 未命中（页面结构变了）、403（Cookie/Referer 缺失）、
   表达式语法错误（编辑器会直接标红）、相对地址未补全（用 `resolve()`）。

## 11. 局域网 MCP

```bash
curl -X POST http://192.168.1.8:8765/mcp \
  -H 'Content-Type: application/json' \
  -H 'X-Poqi-Pin: 1234' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
        "name":"poqi_search","arguments":{"keyword":"长夜"}}}'
```

工具清单见 README。所有工具返回 MCP `content[0].text`，内容为 JSON 字符串。
