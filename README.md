# Poqi

> 把散落的影像，收进一只盒子。

Poqi 是一个可编程的影视聚合器：**插件 = 一套声明式规则，站点 = 插件 + 一份配置**。
它把任意站点的页面结构翻译成统一的媒体 API，再用一套精致的 Material 3 界面放映出来。
同时内置**局域网 MCP 服务**，让任意 AI 客户端直接读写插件、跑搜索、改代码。

包名 `cn.losfer.Poqi` · 目标平台 Android / Windows / Linux（平板与桌面自适应） · 无需 iOS。

**[下载最新版 APK](https://github.com/Mr-losfer/poqi/releases/latest)** · Android 7.0+ · 56 MB 通用包（arm64 / armv7 / x86_64）

---

## 功能地图

| 模块 | 能力 |
| --- | --- |
| 首页 | 主视觉轮播、继续观看、按类型分区轨道、跨站聚合去重 |
| 分类 | 类型/地区/年份筛选，一站式聚合全部启用站点 |
| 搜索 | 全站并发搜索，结果边到边显示，逐站点状态可观测 |
| 详情 | 线路/剧集选择、跨站同名片源、收藏 |
| 播放 | 自定义控制层、倍速、全屏、播放诊断；失败自动换源 |
| 插件工坊 | 新建/编辑/复制/删除插件，JSON 编辑器、即时校验、端点试跑、版本历史 |
| 差量修改 | 自动生成 unified diff，支持复制补丁、粘贴应用、回滚到任意版本 |
| 站点管理 | 一插件多站点，每个站点独立配置（Cookie/Token/线路…） |
| 局域网 | UDP 广播发现、配对码校验、插件/站点/收藏/进度双向同步 |
| MCP | HTTP JSON-RPC 2.0，11 个工具，供 AI 客户端调用 |
| 更新 | 从 GitHub Releases 检查版本，gh-proxy 主代理下载，直连兜底 |

## 快速开始

```bash
flutter pub get
flutter run -d <device>
flutter test          # 29 个测试：表达式 / 解析 / 补丁 / 演示引擎 / 端到端冒烟
```

构建安装包：

```bash
flutter build apk --release           # Android
flutter build windows --release       # Windows
flutter build linux --release         # Linux
```

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
`poqi_get_detail` · `poqi_export_snapshot`

开启配对码后，请求需带 `X-Poqi-Pin` 头。

## 更新与发布

- 版本检查：`GET https://api.github.com/repos/<owner>/<repo>/releases/latest`
- 备用清单：`https://gh-proxy.com/https://raw.githubusercontent.com/<owner>/<repo>/main/version.json`
- 下载：`https://gh-proxy.com/https://github.com/.../releases/download/...`，失败自动回退直连

发布流程（本地）：

```bash
./tool/release.sh 1.1.0 "支持弹幕" --push   # 构建 → 写 version.json → 提交 → 打 tag → 推送 → 发 Release
```

CI 见 `.github/workflows/android-release.yml`：推送 `v*` tag 自动构建并创建 Release。

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
