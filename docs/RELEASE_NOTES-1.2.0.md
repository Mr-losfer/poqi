# Poqi 1.2.0

> 插件系统重做：**一个 `.js` 文件就是一个插件**。

## 这次到底改了什么

1.1.0 的插件是「JSON 清单 + 里面塞一段 JS 做响应转换」。你要在 JSON 里声明 `endpoints`、
`request.path`、`parse.fields`，JS 只能改改返回值 —— 本质还是填表格。

1.2.0 把中间那层拿掉了：

```js
var plugin = {
  id: 'demo.mysite',
  name: '演示站点',
  version: '1.0.0',
  base: 'https://example.com',
  config: [ { key: 'api', label: '接口地址', required: true } ]
};

function home(p) {
  var html = pq.http.get(p.base + '/page/' + p.page);
  return { list: pq.selectAll(html, '.item').map(function (n) {
    return { id: pq.attr(pq.select(n, 'a'), 'href'), title: pq.text(n) };
  }) };
}
```

* 元信息、请求、解析、输出结构，全在一个文件里。
* 没有 `endpoints`、没有 `parse`、没有模板语法要背。
* 请求想发几次发几次，顺序、条件、循环随便写。

## 同步写法的网络请求

QuickJS 是同步求值的，网络是异步的。宿主用「重放」把两者接起来：

```
脚本执行 → pq.http.get 没缓存 → 记下请求并中断
        → 宿主真发请求 → 写入缓存
        → 脚本从头再跑一遍 → 这次命中缓存，拿到真数据
```

所以插件里就是 `var html = pq.http.get(url);`，不用 `await`、不用回调。
同一 URL 只请求一次，列表 → 详情之间也会复用（90 秒）。

## 新增能力

| 能力 | 用法 |
| --- | --- |
| 同步 HTTP | `pq.http.get / json / post / put / del / request` |
| HTML 解析 | `pq.selectAll / select / text / attr / css / cssAttr / abs` |
| 工具 | `pq.clean / num / first / matchAll / query / json / log` |

选择器支持 `tag` `.class` `#id` `[attr=v]` `[attr*=v]` `[attr^=v]` `[attr$=v]`、后代、子代、逗号分组。

## 内置插件

两个内置插件都重写成完整脚本，可以直接打开看、复制、改：

* **苹果CMS v10** —— 自己拼接口地址、发请求、解析多线路剧集串。
* **TVBox 接口** —— 先读接口 JSON，挑一个 `type=1` 的站点，再复用 CMS 协议。

## 界面

* 新建插件：HTML 站点 / JSON 接口 / 空白脚本 三个模板，选完直接进编辑器写代码。
* 脚本插件的编辑器显示的就是脚本本身，不再是转义后的 JSON 字符串。
* 校验结果会指出缺哪个函数、哪项配置重复。

## MCP

* `poqi_save_plugin` 支持直接传 `script`：一个文件写完就落库。
* `poqi_apply_patch` 对脚本插件的补丁直接打在源码上，不是打在 JSON 上。
* `initialize` 的 `instructions` 里内置了一份精简规范，AI 连上就知道怎么写。

## 兼容

旧版 JSON 清单插件（`engine: http`）仍然能读、能跑、能编辑，代码没有删除。
新建插件不再提供这个入口。

## 验证

* `flutter analyze`：0 error / 0 warning
* `flutter test`：69 个用例全通过（新增重放调度 8 个）
* `node tool/js_runtime_test.js`：22 个用例全通过（含多步请求联调）
