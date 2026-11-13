# Poqi

> 把散落的影像，收进一只盒子。

Poqi 是一个可编程的影视聚合器：**插件 = 一个 .js 文件，站点 = 插件 + 一份配置**。
元信息、请求、解析、输出结构全写在脚本里，不填 JSON 规则。
它把任意站点的页面结构翻译成统一的媒体 API，再用一套标准的 Material 3 界面放映出来。
同时内置**局域网 MCP 服务**，让任意 AI 客户端直接读写插件、跑搜索、改代码。

包名 `cn.losfer.Poqi` · 目标平台 **Android / Windows**（平板与桌面自适应） · 不提供 iOS / Linux 版本。

**[下载最新版](https://github.com/Mr-losfer/poqi/releases/latest)** · Android 7.0+ · 56 MB 通用 APK（arm64 / armv7 / x86_64） · Windows x64 压缩包

---

## 功能地图

| 模块 | 能力 |
| --- | --- |
| 首页 | 主视觉轮播、站点切换、继续观看、按类型分区轨道、跨站聚合去重 |
| 分类 | 类型/地区/年份筛选，一站式聚合全部启用站点 |
| 搜索 | 全站并发搜索，结果边到边显示，逐站点状态可观测 |
| 详情 | 线路/剧集选择、跨站同名片源、收藏 |
| 播放 | 自定义控制层、倍速、全屏、播放诊断；失败自动换源 |
| 插件工坊 | 新建/编辑/复制/删除插件，HTML / JSON 接口 / 空白三套脚本模板、即时校验、端点试跑、版本历史 |
| 插件脚本 | 内嵌 QuickJS。`pq.http.get(url)` 同步发请求，`pq.css/select/attr` 解 HTML，返回值就是标准结构 |
| 差量修改 | 自动生成 unified diff，支持复制补丁、粘贴应用、回滚到任意版本 |
| 站点管理 | 一插件多站点，每个站点独立配置（Cookie/Token/线路…） |
| 局域网 | UDP 广播发现、插件/站点/收藏/进度双向同步；MCP 端点免配对码直接读写 |
| MCP | HTTP JSON-RPC 2.0，12 个工具（含写插件 / 写站点），供 AI 客户端调用 |
| 更新 | 从 GitHub Releases 检查版本，gh-proxy 主代理下载，直连兜底 |

## 快速开始

```bash
flutter pub get
flutter run -d <device>
flutter test          # 74 个测试：表达式 / 解析 / 补丁 / 存储 / 重放调度 / 脚本解析 / MCP / 冒烟
node tool/js_runtime_test.js   # JS 运行时与内置脚本的离线验证（9 组断言）
```

构建安装包（只支持 Android 与 Windows 两个平台）：

```bash
flutter build apk --release           # Android 通用包
flutter build windows --release       # Windows x64（只能在 Windows 上构建）
```

Windows 产物位于 `build/windows/x64/runner/Release/`，整个目录一起分发即可运行；
发布时会被压成 `poqi-<version>-windows-x64.zip`（zip 内置同名顶层目录，解压即用）。

## 目录结构

```
lib/
  core/
    design/      设计令牌与主题（午夜放映厅：墨黑底 + 琥珀光）
    ui/          自适应容器、动效、海报、骨架、弹层等原语
  domain/
    models/      Media / Plugin / Site / Library / Sync / Release
    plugin/      expr 表达式引擎、parse 声明式解析、runner 执行器、
                 diff 补丁、validator 校验、builtin 内置插件、demo 片库
  data/
    net/         Dio 封装与请求追踪
    sync/        设备发现、同步服务端与客户端
    mcp/         MCP JSON-RPC 服务端与工具集
    update/      版本检查与下载安装
  state/         Riverpod providers、搜索控制器、播放控制器
  features/      home / discover / search / detail / player / plugins /
                 sites / connect / settings / docs / shell
```

## 插件规则

插件是一份 JSON（Spec v1）。最小示例：

```json
{
  "spec": 1,
  "id": "demo.site",
  "name": "示例站点",
  "version": "1.0.0",
  "engine": "http",
  "baseUrl": "https://example.com",
  "config": [
    { "key": "cookie", "label": "Cookie", "type": "text", "secret": true }
  ],
  "vars": {
    "sign": { "expr": "md5(cfg.cookie + today())", "ttl": 3600 }
  },
  "endpoints": {
    "home": {
      "request": { "path": "/list", "query": { "page": "{{page}}" } },
      "parse": {
        "format": "html",
        "root": ".item",
        "fields": {
          "id": "attr(sel(item, 'a'), 'href')",
          "title": "text(sel(item, '.title'))",
          "poster": "attr(sel(item, 'img'), 'data-src')"
        }
      }
    }
  }
}
```

完整规范见 [docs/PLUGIN_SPEC.md](docs/PLUGIN_SPEC.md)，应用内「插件 → 规范」页也可离线阅读。

三种解析格式：

- `json`：`root` 用路径（支持 `data.list[0].name`），字段用表达式取 `item.xxx`
- `html`：`root` 用 CSS 选择器，字段用 `sel/text/attr`
- `regex`：`pattern` + `group`，适合从脚本里抠直链

表达式语言覆盖字符串、数字、集合、JSON、HTML、编码、时间、URL 共 50+ 函数，
`{{ }}` 模板用于 URL / Header / Body 插值。

## 局域网 MCP

在「连接」页开启 MCP 服务后，同一局域网内即可访问：

```
POST http://<设备IP>:8765/mcp
Content-Type: application/json

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
```

工具：`poqi_get_state` · `poqi_list_plugins` · `poqi_get_plugin` ·
`poqi_validate_plugin` · `poqi_save_plugin` · `poqi_apply_patch` ·
`poqi_list_revisions` · `poqi_list_sites` · `poqi_search` ·
`poqi_get_detail` · `poqi_save_site` · `poqi_export_snapshot`

MCP 端点不做鉴权：同一局域网内即可读写，省掉配对码这一层摩擦。

## 更新与发布

- 版本检查：`GET https://api.github.com/repos/<owner>/<repo>/releases/latest`
- 备用清单：`https://gh-proxy.com/https://raw.githubusercontent.com/<owner>/<repo>/main/version.json`
- 下载：`https://gh-proxy.com/https://github.com/.../releases/download/...`，失败自动回退直连

发布流程（本地）：

```bash
./tool/release.sh 1.1.0 "支持弹幕"                     # 只构建 APK
./tool/release.sh 1.1.0 "支持弹幕" --desktop           # 追加 Windows zip（需在 Windows 宿主上执行）
./tool/release.sh 1.1.0 "支持弹幕" --desktop --push    # 构建 → 写 version.json → 提交 → 打 tag → 推送 → 发 Release
./tool/release.sh 1.1.0 "支持弹幕" --no-build --push   # 复用已有产物，只做清单与发布
```

- Linux / macOS 上 `--desktop` 会自动跳过 Windows 包并打印提示，不会让脚本失败；
  这类机器请只发 APK，Windows 包交给 CI（推送 tag 后由 windows job 产出）。
- Release 附带的产物：`poqi-<version>.apk`、`poqi-<version>-windows-x64.zip`（CI 必产出）、
  `SHA256SUMS.txt`、`version.json`；`version.json` 的 `assets` 同时列出 apk 与 zip，各自带 size / sha256。

CI 见 `.github/workflows/release.yml`：推送 `v*` tag 自动构建 Android + Windows 并一次性创建 Release
（`android` job 跑 `flutter test`，`windows` job 只构建，因 Windows 上测试易因路径差异误报）。

> **签名说明**：`android/app/poqi-release.jks` 与 `android/key.properties` 故意纳入版本库，
> 以保证本地构建与 CI 产出的 APK 使用同一签名 —— 否则换构建环境后，用户无法覆盖安装更新。
> 若你 fork 并自行分发，请替换为你自己的密钥。

## 设计说明

- **色彩**：墨黑 `#08090B` 为底，暖琥珀 `#E8B564` 作为唯一的"光"；亮色主题是纸感米白。
- **层次**：不用投影堆叠，靠 0.5–0.9px 细描边与背景色差；仅在海报悬停时给一层柔和外发光。
- **字体**：Bricolage Grotesque 承担拉丁字与数字，中文回落到系统 CJK 字重层次。
- **海报**：缺图时生成"程序化海报"（渐变 + 超大首字 + 胶片纹理），避免灰块破坏版面。
- **动效**：180–260ms，`easeOutCubic`；入场错峰 26ms；列表/筛选用交叉淡化。

## 许可

私有项目，仅供学习与自用。请遵守目标站点的服务条款与当地法律。
