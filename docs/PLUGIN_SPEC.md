# Poqi 插件规范 v2

> 一句话：**一个 `.js` 文件就是一个插件**。元信息、请求、解析、输出结构，全在这一个文件里。
> 没有 JSON 规则要填，没有"先声明端点再写脚本"，写 JS 就是写插件。

---

## 1. 心智模型

```
┌─────────────────────────────────────────────┐
│  my-site.js                                 │
│                                             │
│  var plugin = { id, name, config, ... }     │  ← 元信息：叫什么、要用户填什么
│                                             │
│  function home(p)      { ... }              │  ← 首页要什么
│  function search(p)    { ... }              │  ← 搜索要什么
│  function detail(p)    { ... }              │  ← 详情要什么
│  function play(p)      { ... }              │  ← 播放地址
└─────────────────────────────────────────────┘
                 ↓ 存进「插件」
          站点 = 插件 + 一组配置值
```

* **插件**是可复用的逻辑（一套代码）。
* **站点**是插件的一次实例化（一份 `api` / `cookie` 配置 + 一个名字）。
* 同一个插件可以挂任意多个站点：改个接口地址就是另一个站。

---

## 2. 脚本结构

### 2.1 元信息

```js
var plugin = {
  id: 'demo.mysite',        // 唯一标识，定下来就别改（站点靠它绑定）
  name: '演示站点',
  version: '1.0.0',
  author: '你',             // 可选
  description: '一句话说明', // 可选
  base: 'https://example.com',
  headers: {                // 可选：所有请求默认带上的头
    'Referer': 'https://example.com/',
    'User-Agent': '...'
  },
  config: [ /* 见第 6 节 */ ]
};
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 建议 | 小写字母/数字/`.`/`_`/`-`；不写会按名字生成 |
| `name` | 是 | 插件列表里显示的名字 |
| `version` | 建议 | 语义化版本 |
| `base` | 否 | 站点默认地址；站点配置里填了 `baseUrl` 就以站点为准 |
| `headers` | 否 | 公共请求头，脚本里发请求时自动合并 |
| `config` | 否 | 站点级配置项，会渲染成「添加站点」的表单 |
| `notes` | 否 | 详情页展示的备注 |

### 2.2 端点函数

函数名就是端点名，写了哪个就支持哪个：

| 函数 | 何时调用 | 必须返回 |
| --- | --- | --- |
| `home(p)` | 首页 / 站点首页 | 列表 |
| `category(p)` | 分类页（不写则退回 `home`） | 列表 |
| `search(p)` | 搜索（`p.keyword`） | 列表 |
| `detail(p)` | 点开某个条目（`p.id`） | 详情 |
| `play(p)` | 点某一集（`p.id` 是剧集地址） | 播放 |

不写 `search` 的插件会被全站聚合搜索跳过；不写 `detail` 就没有详情页。

辅助函数随便定义，不会被当成端点：

```js
function pick(it) { return { id: String(it.id), title: it.name }; }
function home(p) { return { list: fetchList(p).map(pick) }; }
```

### 2.3 参数 `p`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `p.base` | string | 站点地址（站点填的 `baseUrl`，没填用 `plugin.base`） |
| `p.cfg` | object | 站点配置值，键就是 `config` 里声明的 `key` |
| `p.page` | number | 页码，从 1 开始 |
| `p.keyword` | string | 搜索词（仅 `search`） |
| `p.category` | string | 分类 id（仅 `category`） |
| `p.filters` | object | 筛选条件（仅 `category`） |
| `p.id` | string | 详情 id / 剧集地址 |
| `p.site` | object | `{ id, name }` |
| `p.now` | number | 本次执行的毫秒时间戳（重放期间保持不变） |

---

## 3. 发请求

**脚本是同步求值的**：`pq.http.get()` 直接返回字符串，不用 `await`，不用回调。
宿主在背后把异步网络接到同步脚本上（见第 9 节）。

```js
// 最常用
var html = pq.http.get(url);
var json = pq.http.json(url);
var text = pq.http.post(url, { user: 'a', pass: 'b' });   // 对象自动 JSON 序列化

// 带请求头
var html = pq.http.get(url, { headers: { 'Referer': p.base } });

// 需要看状态码 / 容错
var r = pq.http.request({ url: url, method: 'GET', timeout: 20000 });
if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + r.error);
var body = r.body;
```

`pq.http` 全部方法：

| 方法 | 返回 |
| --- | --- |
| `get(url, opts)` | 响应文本 |
| `json(url, opts)` | `JSON.parse` 后的对象，失败返回 `null` |
| `post(url, body, opts)` | 响应文本 |
| `put(url, body, opts)` | 响应文本 |
| `del(url, opts)` | 响应文本 |
| `postJson(url, obj, opts)` | 解析后的对象（自动带 `Content-Type`） |
| `request({url, method, headers, body, timeout})` | `{ ok, status, headers, body, url, error }` |

* 相对地址会按 `p.base` 补全。
* 失败（DNS / 超时 / 5xx）不会抛异常，`ok=false`、`error` 里是原因，脚本自己决定怎么办。
* 同一个 URL 在一次调用里只请求一次（含跨函数复用，缓存 90 秒）。

`opts` 支持 `headers`、`timeout`（毫秒）。

---

## 4. 解析 HTML

内置一个够用的 CSS 选择器引擎 + 文本工具，不需要 DOM：

```js
var nodes = pq.selectAll(html, '.module-item');   // 节点数组
var first = pq.select(html, 'h1');                // 第一个节点或 null
pq.text(node);            // 全部文本（含子节点，已去标签、解实体）
pq.ownText(node);         // 只取直接文本
pq.attr(node, 'href');    // 属性，取不到返回 ''
pq.html(node);            // innerHTML
pq.abs(p.base, href);     // 补全相对地址
```

选择器直接对字符串生效的快捷方法：

```js
pq.css(html, 'h1')                    // → ['长夜将尽']
pq.cssAttr(html, 'a', 'href')         // → ['/p/1', '/p/2']
pq.css(html, 'ul li a')               // 后代
pq.css(html, 'div > ul')              // 子代
pq.css(html, 'a[href^="/p/"]')        // 属性前缀
pq.css(html, '.a, .b')                // 分组
```

支持的语法：`tag` `.class` `#id` `*` `[attr]` `[attr=v]` `[attr*=v]` `[attr^=v]` `[attr$=v]`、
后代（空格）、子代（`>`）、逗号分组。

其它工具：

| 工具 | 说明 |
| --- | --- |
| `pq.clean(s)` | 去标签 + 解实体 + 压空白 |
| `pq.num('8.9分')` | → `8.9` |
| `pq.first(s, /re(.*?)/)` | 第一个匹配的分组 |
| `pq.matchAll(s, /re/g)` | 全部分组 |
| `pq.trim` / `pq.uniq` / `pq.map` / `pq.pad` | 常用小工具 |
| `pq.query({a:1,b:''})` | → `a=1`（自动跳过空值并编码） |
| `pq.json(s)` | 安全 `JSON.parse` |
| `pq.get(obj, 'a.b.0.c', def)` | 安全取值 |
| `pq.log(...)` | 写到调试面板 |

---

## 5. 输出结构

只要求结构，字段名大小写/下划线不敏感（`vod_name` / `vodName` 都认）。

### 列表

```js
{
  list: [
    {
      id: '42',              // 必填，后续 detail 会原样拿到
      title: '长夜将尽',      // 必填，空的条目会被丢弃
      poster: 'https://.../42.jpg',
      remarks: '更新至 3 集',
      year: '2026',
      area: '内地',
      score: '8.9',
      kind: '剧集',
      intro: '一句话简介'
    }
  ],
  hasMore: true              // 可选，不写就按「满 12 条」判断
}
```

也可以直接返回数组：`return [ {...}, {...} ]`。

### 详情

```js
{
  id: '42',
  title: '长夜将尽',
  poster: 'https://.../42.jpg',
  intro: '完整简介',
  director: '陈叙',
  actors: ['林恒', '周宛'],
  lines: [
    {
      name: '量子',
      episodes: [
        { name: '第01集', url: 'https://.../1.m3u8' }
      ]
    }
  ]
}
```

`lines` 不写也可以用扁平 `episodes: [{ name, url, line }]`，宿主会按 `line` 分组。

### 播放

```js
{ url: 'https://.../1.m3u8', headers: { 'Referer': '...' } }
```

返回字符串 URL 也可以；返回 `null` 表示"直接用传进来的剧集地址"。

---

## 6. 配置项 `config`

声明出来的字段会变成「添加站点」时的表单，一个插件挂多个站点就靠它。

```js
var plugin = {
  // ...
  config: [
    {
      key: 'api',                  // p.cfg.api
      label: '接口地址',
      type: 'text',                // text | password | number | boolean | select
      required: true,
      hint: 'https://example.com/api.php/provide/vod/',
      help: '填完整的 provide/vod 接口地址',
      default: ''
    },
    {
      key: 'cookie',
      label: 'Cookie',
      type: 'password',
      secret: true                 // 列表里打码
    },
    {
      key: 'quality',
      label: '清晰度',
      type: 'select',
      options: ['1080', '720']
    }
  ]
};
```

`required: true` 的项没填时，站点会标记为「未配置」，不会发请求。

可选的 `refreshSeconds` 用于"定时换 token"的场景（`vars` 里声明 `ttl` 时生效）。

---

## 7. 完整示例

### 7.1 HTML 站点

```js
var plugin = {
  id: 'demo.html',
  name: '演示影视',
  version: '1.0.0',
  base: 'https://example.com',
  config: [{ key: 'cookie', label: 'Cookie', type: 'password' }]
};

function home(p) {
  return parseList(p, p.base + '/index.php/vod/show/id/1/page/' + p.page + '.html');
}

function category(p) {
  return parseList(p, p.base + '/vod/type/id/' + p.category + '/page/' + p.page + '.html');
}

function search(p) {
  return parseList(p, p.base + '/vod/search/wd/' + encodeURIComponent(p.keyword) + '.html');
}

function parseList(p, url) {
  var html = pq.http.get(url, { headers: { 'Cookie': pq.trim(p.cfg.cookie || '') } });
  var nodes = pq.selectAll(html, '.module-item');
  var out = [];
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i];
    var a = pq.select(n, 'a');
    var href = pq.attr(a, 'href');
    if (!href) continue;
    var img = pq.select(n, 'img');
    out.push({
      id: pq.abs(p.base, href),
      title: pq.text(pq.select(n, '.title')) || pq.attr(a, 'title'),
      poster: pq.abs(p.base, pq.attr(img, 'data-src') || pq.attr(img, 'src')),
      remarks: pq.text(pq.select(n, '.module-item-note'))
    });
  }
  return { list: out, hasMore: out.length > 0 };
}

function detail(p) {
  var html = pq.http.get(p.id);
  var eps = [];
  var links = pq.selectAll(html, '.module-play-list a');
  for (var i = 0; i < links.length; i++) {
    eps.push({
      name: pq.text(links[i]) || ('第' + (i + 1) + '集'),
      url: pq.abs(p.base, pq.attr(links[i], 'href'))
    });
  }
  return {
    id: p.id,
    title: pq.css(html, 'h1')[0] || '',
    intro: pq.clean(pq.css(html, '.module-info-introduction')[0] || ''),
    lines: eps.length ? [{ name: '线路1', episodes: eps }] : []
  };
}

function play(p) {
  // 播放页还要再解析一次真实地址时：
  // var html = pq.http.get(p.id);
  // return { url: pq.first(html, /"url"\s*:\s*"([^"]+)"/) || p.id };
  return { url: p.id };
}
```

### 7.2 苹果CMS 接口

```js
var plugin = {
  id: 'demo.cms',
  name: '苹果CMS',
  version: '1.0.0',
  config: [{ key: 'api', label: '接口地址', required: true }]
};

function call(p, query) {
  var url = pq.trim(p.cfg.api);
  if (!url) throw new Error('请先填写接口地址');
  var sep = url.indexOf('?') >= 0 ? '&' : '?';
  var json = pq.json(pq.http.get(url + sep + pq.query(query)));
  if (!json) throw new Error('接口没有返回 JSON');
  return json;
}

function feed(p, query) {
  var raw = call(p, query).list || [];
  var out = [];
  for (var i = 0; i < raw.length; i++) {
    var it = raw[i];
    out.push({
      id: String(it.vod_id),
      title: pq.trim(it.vod_name),
      poster: pq.trim(it.vod_pic),
      remarks: pq.trim(it.vod_remarks)
    });
  }
  return { list: out, hasMore: out.length >= 20 };
}

function home(p) { return feed(p, { ac: 'list', pg: p.page }); }
function category(p) { return feed(p, { ac: 'list', t: p.category, pg: p.page }); }
function search(p) { return feed(p, { ac: 'detail', wd: p.keyword, pg: p.page }); }
```

剧集串（`vod_play_url`）的拆法见内置「苹果CMS v10」插件源码，直接复制改就行。

---

## 8. 调试

* 插件详情 →「试跑」：选端点、填参数，看请求轨迹和解析结果。
* 编辑器下方是校验结果：缺函数、配置项重复、脚本语法问题都会列出来。
* `pq.log(...)` 的输出会出现在「试跑」面板里。
* MCP 连上后可以直接让 AI 试跑、改脚本、看错误。

---

## 9. 同步脚本是怎么跑网络的

QuickJS 是同步求值的，网络是异步的。宿主用「重放」把两者接起来：

1. 脚本执行，`pq.http.get(url)` 发现缓存里没有 → 记录请求并抛出中断信号；
2. 宿主真正发请求，把响应写进缓存；
3. 宿主把脚本**从头再跑一遍**，这次命中缓存，返回值就是真的了；
4. 重复直到没有新请求（最多 16 轮）。

所以：

* ✅ 脚本里写同步代码，`var html = pq.http.get(url);` 就是能用。
* ❌ 不要写 `await` / `Promise` / `setTimeout`。
* ❌ 不要用 `try/catch` 包住 `pq.http` 调用 —— 中断信号被吞掉后宿主拿不到请求。宿主有兜底（会检测未完成的请求并重跑），但白跑一轮。
* ✅ 请求按顺序发生（第二个请求可以依赖第一个的结果）。
* ✅ 同一 URL 只请求一次，列表 → 详情之间也复用（90 秒）。

---

## 10. 兼容：JSON 清单（旧格式）

v1 的声明式格式仍然能被读取和执行（`engine: http` + `endpoints[].parse`），
用于早期创建的插件。新建插件不再提供这个入口。

如果你有一个旧插件想迁到脚本：复制它的 `config`，把 `endpoints` 里的请求和选择器
翻译成 `home` / `search` / `detail` / `play` 四个函数即可，见第 7 节。

<details>
<summary>旧格式参考（点击展开）</summary>

```json
{
  "spec": 1,
  "id": "demo.json",
  "name": "声明式插件",
  "version": "1.0.0",
  "engine": "http",
  "baseUrl": "https://example.com",
  "config": [{ "key": "api", "label": "接口地址", "required": true }],
  "endpoints": {
    "home": {
      "request": { "path": "{{cfg.api}}", "query": { "ac": "list", "pg": "{{page}}" } },
      "parse": {
        "format": "json",
        "root": "list",
        "fields": { "id": "item.vod_id", "title": "item.vod_name" }
      }
    }
  }
}
```

`parse.format` 支持 `json`（路径表达式）、`html`（CSS 选择器）、`regex`、`split`（剧集串）。
`request.path` / `query` / `headers` 支持 `{{ }}` 模板，可用 `cfg` / `vars` / `page` / `keyword` / `category` / `id`。

</details>

---

## 11. 差量修改（补丁）

* 每次保存在本地留一条版本记录（最近 40 条），首版是全量快照，之后是 unified diff。
* 脚本插件的补丁**直接打在脚本源码上**，不是打在 JSON 上。
* MCP 的 `poqi_apply_patch` 接受 `@@` 开头的 unified diff；冲突会返回行号，不会改坏文件。

---

## 12. 局域网 MCP

App 里打开「连接」页 → 启动 MCP 服务，同一局域网内的 AI 客户端用
`http://<手机IP>:<端口>/mcp` 接入（JSON-RPC 2.0，无鉴权，仅限内网）。

可用工具：

| 工具 | 用途 |
| --- | --- |
| `poqi_list_plugins` / `poqi_get_plugin` | 读插件（含脚本源码） |
| `poqi_save_plugin` | **传 `script` 直接写入一个插件** |
| `poqi_apply_patch` | 对脚本做差量修改 |
| `poqi_test_endpoint` | 试跑端点，返回真实响应与解析结果 |
| `poqi_list_sites` / `poqi_save_site` | 站点管理 |
| `poqi_search` / `poqi_get_detail` | 跨站点搜索与详情 |

接上后 `initialize` 的 `instructions` 里带着一份精简规范，AI 不需要额外提示就知道怎么写。
