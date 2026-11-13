import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/primitives.dart';

/// 插件规范 v1：写给插件作者与 Agent 的完整说明书。
class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  final _scroll = ScrollController();
  late final List<GlobalKey> _keys =
      List.generate(_chapters.length, (_) => GlobalKey());
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncActive);
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncActive);
    _scroll.dispose();
    super.dispose();
  }

  void _syncActive() {
    var active = 0;
    final root = context.findRenderObject();
    for (var i = 0; i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || root is! RenderBox) continue;
      final y = box.localToGlobal(Offset.zero, ancestor: root).dy;
      if (y <= 150) active = i;
    }
    if (active != _active && mounted) setState(() => _active = active);
  }

  void _jump(int index) {
    final ctx = _keys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  Future<void> _copyMarkdown() async {
    await Clipboard.setData(const ClipboardData(text: _summaryMarkdown));
    if (!mounted) return;
    showPqToast(context, '规范 Markdown 已复制', kind: PqToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final wide = MediaQuery.sizeOf(context).width >= 1080;

    final sections = <Widget>[
      _DocSection(
        key: _keys[0],
        number: '01',
        title: '模型：规则与配置分家',
        subtitle: '为什么插件不是"一个站点一套代码"',
        children: [
          _lead(
            context,
            '插件 = 声明式规则（请求 + 解析 + 变量）；站点 = 插件 + 一份配置。',
          ),
          const SizedBox(height: 14),
          const _ModelFlow(),
          const SizedBox(height: 16),
          _rich(
            context,
            '插件本身不含任何用户数据，也不绑定域名之外的环境。它只描述"怎么发请求、怎么把响应变成条目、'
            '哪些值需要在运行时换取"。同一个插件可以被任意多个站点引用，各自填写自己的域名、Cookie 或密钥。',
          ),
          const SizedBox(height: 10),
          _bullets(context, const [
            '站点只覆盖 `baseUrl` 与 `config`；解析规则始终以插件为准，插件更新后所有站点同步生效。',
            '聚合层按标准字段（`id`/`title`/`poster`…）归一化、去重与排序；详情与播放仍回到站点自己的规则。',
            '规则是纯 JSON 数据，因此可以被编辑器结构化修改，也可以由 MCP / AI 以 unified diff 的方式修改。',
            '内置插件随包分发，不可删除；复制一份即可得到可编辑的自定义版本。',
          ]),
          const SizedBox(height: 12),
          _note(
            context,
            '判断一段逻辑该放哪里：与"域名、账号、地区"有关 → 站点配置；与"页面结构、字段位置"有关 → 插件规则。',
          ),
        ],
      ),
      _DocSection(
        key: _keys[1],
        number: '02',
        title: '清单字段',
        subtitle: 'PluginManifest 的 15 个字段',
        children: [
          _rich(
            context,
            '一个插件就是一个 JSON 对象。加载器会先补齐缺省值，再交给校验器检查；'
            '校验器报错时插件无法保存（MCP 写入同样会被拒绝）。',
          ),
          const SizedBox(height: 12),
          const _Table(
            headers: ['字段', '类型', '必填', '说明'],
            widths: [112, 92, 56, 430],
            monoColumns: {0},
            rows: [
              ['spec', 'int', '否', '规范版本，当前固定为 `1`；缺省按 1 处理。'],
              ['id', 'string', '是', '3–64 位小写字母、数字、`.`、`_`、`-`，全局唯一。'],
              ['name', 'string', '是', '展示名称，可中文。'],
              ['version', 'string', '是', '语义化版本，如 `1.0.0`；非语义化只告警。'],
              ['author', 'string', '否', '作者或维护者署名。'],
              ['description', 'string', '否', '一两句话说明覆盖的内容范围。'],
              ['homepage', 'string', '否', '项目主页或规则仓库地址。'],
              ['icon', 'string', '否', '图标 URL；留空时使用首字徽标。'],
              ['engine', 'string', '是', '`http` 或 `demo`。演示引擎随包运行，不需要网络。'],
              ['baseUrl', 'string', '是*', 'HTTP 插件的根地址；站点可覆盖。'],
              ['headers', 'object', '否', '默认请求头，值支持 `{{ }}` 模板。'],
              ['config', 'array', '否', '站点配置声明，见第 03 节。'],
              ['vars', 'object', '否', '运行时变量，见第 04 节。'],
              [
                'endpoints',
                'object',
                '是',
                '至少一个；键名只能是 home/category/search/detail/play。'
              ],
              ['notes', 'string', '否', '给使用者看的补充说明（限制、已知问题）。'],
            ],
          ),
          const SizedBox(height: 14),
          _h3(context, '最小可用骨架'),
          const _Code(
            label: 'PLUGIN.JSON',
            code: _minimalPlugin,
          ),
          const SizedBox(height: 12),
          _bullets(context, const [
            '`spec` 目前只有 1；未来新增字段会保持向后兼容。',
            '`id` 一旦发布就不要改，站点通过它绑定插件；改名等于换插件。',
            '没有 `home` 只会告警（首页不展示该站点）；没有 `search` 则是建议（聚合搜索跳过）。',
            '`detail` 建议声明 `episodes`，否则播放页可能没有剧集可选。',
          ]),
        ],
      ),
      _DocSection(
        key: _keys[2],
        number: '03',
        title: '配置项 config',
        subtitle: '声明"用户需要填什么"，而不是替用户填',
        children: [
          _rich(
            context,
            '`config` 是一个数组。添加站点时，编辑器会按声明的顺序渲染表单；'
            '**每个站点单独填写自己的值**，插件只负责声明字段。',
          ),
          const SizedBox(height: 12),
          const _Table(
            headers: ['字段', '类型', '必填', '说明'],
            widths: [130, 92, 56, 412],
            monoColumns: {0},
            rows: [
              ['key', 'string', '是', '标识符（字母或下划线开头），模板中用 `{{cfg.key}}` 引用。'],
              ['label', 'string', '是', '表单里显示的中文名。'],
              [
                'type',
                'string',
                '否',
                '`text` / `password` / `number` / `boolean` / `select`，默认 text。'
              ],
              ['required', 'bool', '否', '必填；缺失时站点健康检查会提示。'],
              ['secret', 'bool', '否', '敏感值，列表与日志中打码展示。'],
              ['hint', 'string', '否', '输入框占位提示。'],
              ['help', 'string', '否', '字段下方的补充说明。'],
              ['default', 'string', '否', '默认值（统一存为字符串）。'],
              ['options', 'array', 'select 必填', '下拉候选值。'],
              ['refreshSeconds', 'int', '否', '建议的刷新周期，提示用户凭证会过期。'],
            ],
          ),
          const SizedBox(height: 14),
          const _Code(label: 'CONFIG 示例', code: _configSample),
          const SizedBox(height: 12),
          _bullets(context, const [
            '`type: number` 仍然以字符串存储，表达式里用 `int(cfg.limit)` 转数值。',
            '`boolean` 的值为 `"true"` / `"false"`，表达式里用 `cfg.adFree == "true"` 比较。',
            '`select` 必须给出非空 `options`，否则校验报错。',
            '`required` 且没有 `default` 时只产生一条建议，提醒作者用户首次添加需要填写。',
            '敏感项不要写进 `default`，也不要在 `notes` 里透露真实值。',
          ]),
        ],
      ),
      _DocSection(
        key: _keys[3],
        number: '04',
        title: '运行时变量 vars',
        subtitle: '签名、token、Cookie 的换取与缓存',
        children: [
          _rich(
            context,
            '`vars` 是"运行时才算出来的值"。每个变量由 `expr` 与 `ttl` 组成：'
            '`expr` 是表达式，`ttl` 是缓存秒数（0 表示永久缓存，直到手动失效）。'
            '变量按声明顺序求值，后面的变量可以通过 `vars.前面名字` 引用前面结果。',
          ),
          const SizedBox(height: 12),
          const _Table(
            headers: ['字段', '类型', '必填', '说明'],
            widths: [120, 80, 56, 434],
            monoColumns: {0},
            rows: [
              ['expr', 'string', '是', '表达式；支持 `http.get` / `http.post` 等异步调用。'],
              ['ttl', 'int', '否', '缓存秒数；建议 ≥ 30，避免频繁刷新。'],
            ],
          ),
          const SizedBox(height: 14),
          const _Code(label: 'VARS 示例', code: _varsSample),
          const SizedBox(height: 12),
          _bullets(context, const [
            '引用方式：请求模板里写 `{{vars.token}}`，请求头里同样可用。',
            '在变量表达式里发请求：`http.get(path, {query: {...}, headers: {...}})`，返回 JSON 会自动解码。',
            '`http.*` 失败会抛出异常，该变量记为 `""` 并写入日志；不要让关键请求依赖可能为空的变量。',
            '鉴权失败（401/403）说明缓存里的凭证已过期：应让该变量失效后重取（`VarCache.invalidate`），'
                '或把 `ttl` 设得比服务端有效期更短。否则过期值会一直用到 TTL 结束。',
            '`ttl` 小于 30 秒只告警，但真实场景里通常意味着设计有问题。',
          ]),
        ],
      ),
      _DocSection(
        key: _keys[4],
        number: '05',
        title: '端点 endpoints',
        subtitle: 'home / category / search / detail / play',
        children: [
          _rich(
            context,
            '端点把"页面动作"映射到一次请求与一次解析。`request` 描述怎么取，`parse` 描述怎么读。'
            '未知端点名只告警，但不会被执行。',
          ),
          const SizedBox(height: 12),
          const _Table(
            headers: ['端点', '用途', '解析要求'],
            widths: [110, 300, 280],
            monoColumns: {0},
            rows: [
              [
                'home',
                '首页信息流；首页聚合与"为你推荐"使用它。',
                '必须有 `parse`，至少包含 `id` 与 `title`。'
              ],
              [
                'category',
                '分类浏览；可附带 `filters` 定义筛选项。',
                '与 home 相同，通常多一个 `kind` 字段。'
              ],
              [
                'search',
                '关键词搜索；聚合搜索会并发调用。',
                '必须有 `parse`；关键词通过 `{{keyword}}` 传入。'
              ],
              [
                'detail',
                '详情与剧集；`episodes` 声明剧集解析。',
                '必须有 `parse`；建议声明 `episodes`。'
              ],
              ['play', '把剧集地址换成可播放地址（可选）。', '可省略；省略时直接播放剧集地址。'],
            ],
          ),
          const SizedBox(height: 14),
          _h3(context, 'request'),
          const _Table(
            headers: ['字段', '类型', '说明'],
            widths: [110, 90, 490],
            monoColumns: {0},
            rows: [
              ['method', 'string', 'HTTP 方法，默认 `GET`。'],
              ['path', 'string', '相对 `baseUrl` 的路径，也可写完整 URL；支持模板。'],
              ['headers', 'object', '端点级请求头，会覆盖插件级同名头。'],
              ['query', 'object', '查询参数，值为模板字符串；渲染后为空的参数会被省略。'],
              ['body', 'object', '请求体；对象/数组会递归渲染模板后序列化为 JSON。'],
              ['timeoutMs', 'int', '超时毫秒数，默认 `15000`。'],
            ],
          ),
          const SizedBox(height: 12),
          _note(
            context,
            '分页不会自动注入：需要在 `query` 里显式写 `"page": "{{page}}"`。'
            '`search` 的 `wd`、分类的 `t` 与筛选值会作为额外查询参数附加。',
          ),
          const SizedBox(height: 14),
          _h3(context, '模板变量'),
          const _Table(
            headers: ['变量', '含义', '示例'],
            widths: [110, 250, 330],
            monoColumns: {0, 2},
            rows: [
              ['cfg', '当前站点的配置项。', '{{cfg.apiKey}}'],
              ['vars', '运行时变量结果。', '{{vars.token}}'],
              ['page', '页码，从 `pageStart` 开始。', '{{page}}'],
              ['keyword', '搜索关键词（仅 search）。', '{{keyword}}'],
              ['category', '分类名（仅 category）。', '{{category}}'],
              ['id', '条目 id；play 端点为剧集地址。', '{{id}}'],
              ['base', '当前站点的 baseUrl。', '{{base}}/static'],
            ],
          ),
          const SizedBox(height: 12),
          const _Code(label: 'ENDPOINTS 示例', code: _endpointsSample),
        ],
      ),
      _DocSection(
        key: _keys[5],
        number: '06',
        title: '解析 parse',
        subtitle: 'json / html / regex 三种格式',
        children: [
          _rich(
            context,
            '`parse` 负责把响应变成"记录列表"。无论哪种格式，每条记录都会以 `item` 注入表达式上下文，'
            '并额外提供 `index` 与 `total`。因此字段表达式里通常从 `item` 开始写。',
          ),
          const SizedBox(height: 14),
          _h3(context, 'json：root 路径'),
          _rich(
            context,
            '`root` 用点号路径定位列表，支持下标：`data.list`、`data.list[0].items`、`a.b[0].c`。'
            '根节点不是数组时会当成单条记录；未命中则返回空列表并记录一条警告。',
          ),
          const _Code(label: 'JSON', code: _jsonParse),
          const _Code(label: '响应', code: _jsonResponse),
          const SizedBox(height: 14),
          _h3(context, 'html：CSS 选择器'),
          _rich(
            context,
            '`root` 是选择器，选中多个节点时会逐条解析。支持 `选择器 >> first` / `last` 管道。'
            "字段里用 `sel(item, '.x')` 取子节点、`text(...)` 取文本、`attr(node, 'href')` 取属性。",
          ),
          const _Code(label: 'HTML', code: _htmlParse),
          const SizedBox(height: 14),
          _h3(context, 'regex：pattern + group'),
          _rich(
            context,
            '对响应文本做全局匹配，每条匹配生成一条记录，自动提供 `match`、`group`（指定分组）与 `groups`（全部分组）。'
            '`group` 默认为 1。',
          ),
          const _Code(label: 'REGEX', code: _regexParse),
          const SizedBox(height: 12),
          _bullets(context, const [
            '所有字段表达式都会在保存前做语法检查，写错函数名或括号会直接报错。',
            'HTML 解析必须提供 `root`；`body` 或空值表示从整个文档开始。',
            '`episodes` 是一个嵌套的 `parse`，`root` 指向剧集节点集合，字段常用 `name` / `url` / `line`。',
          ]),
        ],
      ),
      _DocSection(
        key: _keys[6],
        number: '07',
        title: '标准字段映射',
        subtitle: '解析结果如何变成一条媒体',
        children: [
          _rich(
            context,
            '解析出的记录会映射到统一的媒体模型。`id` 与 `title` 是硬性要求，空值的条目会被丢弃；'
            '其余字段缺失时保持为空，不影响展示。',
          ),
          const SizedBox(height: 12),
          const _Table(
            headers: ['字段', '类型', '必填', '说明'],
            widths: [110, 82, 56, 442],
            monoColumns: {0},
            rows: [
              ['id', 'string', '是', '站点内唯一；参与详情跳转与去重。'],
              ['title', 'string', '是', '标题；为空时整条记录被跳过。'],
              ['poster', 'string', '否', '竖版海报；相对地址会自动补全为绝对地址。'],
              ['year', 'string', '否', '年份，展示用。'],
              ['score', 'string', '否', '评分，展示用；不做数值换算。'],
              ['remarks', 'string', '否', '更新信息，如"全 24 集"。'],
              ['area', 'string', '否', '地区。'],
              ['kind', 'string', '否', '类型/频道，用于分类栏。'],
              ['tags', 'array/string', '否', '数组，或用 `,` `|` `/` 分隔的字符串。'],
              ['intro', 'string', '否', '简介，详情页展示。'],
              ['director', 'string', '否', '导演。'],
              ['actors', 'string', '否', '主演。'],
              ['url', 'string', '否', '剧集地址（仅 episodes）；相对地址自动补全。'],
              ['name', 'string', '否', '剧集名（仅 episodes）；缺省为"第 N 集"。'],
              ['line', 'string', '否', '线路名（仅 episodes）；同名的归为一条线路。'],
            ],
          ),
          const SizedBox(height: 12),
          _bullets(context, const [
            '`poster` 与剧集 `url` 以 `http://` / `https://` 开头时原样保留，否则用站点 baseUrl 补全。',
            '未列出的字段不会丢弃，会进入 `extra`，详情页可以按需读取。',
            '`tags` 为空字符串时得到空数组，不会产生一个空标签。',
            '同一个 `id` 在多个站点出现时由聚合层去重，优先保留来源顺序靠前的条目。',
          ]),
        ],
      ),
      _DocSection(
        key: _keys[7],
        number: '08',
        title: '表达式函数速查',
        subtitle: '字段与变量共用的求值语言',
        children: [
          _rich(
            context,
            '表达式支持字面量、`+ - * / %`、比较与逻辑运算、三元 `a ? b : c`，以及方法调用（如 `item.title.trim()`）。'
            '下面是内置函数，按用途分组。',
          ),
          const SizedBox(height: 8),
          const _FnGroup(title: '字符串', items: [
            ('text(v)', '转字符串并去掉首尾空白。`text(item.vod_name)`'),
            ('html(v)', '取节点的 innerHTML。`html(item)`'),
            ('trim(v)', '去首尾空白。`trim(cfg.cookie)`'),
            ('lower(v) / upper(v)', '转小写 / 大写。`upper(item.type)`'),
            ('replace(s, a, b)', '全部替换。`replace(item.url, "http:", "https:")`'),
            ('split(s, sep)', '切分为数组。`split(item.remarks, ",")`'),
            ('join(list, sep)', '拼接数组。`join(item.tags, " / ")`'),
            ('substr(s, start, end)', '截取子串（不含 end）。`substr(item.year, 0, 4)`'),
            ('contains(s, sub)', '是否包含；数组时判断元素。`contains(item.title, "预告")`'),
            (
              'regex(s, pattern, group)',
              '正则取分组，默认第 1 组。`regex(item.url, "id=(\\d+)")`'
            ),
          ]),
          const _FnGroup(title: '数字', items: [
            ('int(v)', '转整数。`int(cfg.limit)`'),
            ('number(v)', '转浮点数。`number(item.score)`'),
            ('abs(v) / round(v)', '绝对值 / 四舍五入。`round(number(item.score))`'),
            ('min(a, b) / max(a, b)', '取较小 / 较大值。`max(int(cfg.pageSize), 10)`'),
          ]),
          const _FnGroup(title: '集合', items: [
            ('len(v)', '长度：字符串 / 数组 / 对象。`len(item.tags)`'),
            ('first(list) / last(list)', '首项 / 末项。`first(item.tags)`'),
            ('nth(list, i)', '第 i 项（从 0 开始）。`nth(item.tags, 1)`'),
            ('slice(list, start, end)', '切片。`slice(item.tags, 0, 3)`'),
            ('uniq(list)', '按字符串值去重。`uniq(item.tags)`'),
            ('reverse(list)', '反转数组。`reverse(item.tags)`'),
            ('keys(obj) / values(obj)', '对象的键 / 值数组。`keys(item)`'),
          ]),
          const _FnGroup(title: 'JSON 与路径', items: [
            ('json(s)', '解析 JSON 字符串。`json(item.raw).data`'),
            (
              'at(v, path) / path(v, path)',
              '按 `a.b[0].c` 取值。`at(item, "vod.tag")`'
            ),
            ('encode(v, opts?)', '序列化为 JSON 字符串。`encode(item.tags)`'),
          ]),
          const _FnGroup(title: '编码与摘要', items: [
            ('urlencode(s)', 'URL 查询参数编码。`urlencode(item.title)`'),
            ('md5(s) / sha1(s)', '十六进制摘要。`md5(cfg.apiKey + ts())`'),
            ('b64(s) / b64d(s)', 'Base64 编码 / 解码。`b64("user:" + cfg.token)`'),
          ]),
          const _FnGroup(title: 'HTML', items: [
            ('sel(node, css)', '取第一个匹配子节点。`sel(item, ".title")`'),
            ('selAll(node, css)', '取全部匹配节点，返回数组。`selAll(item, "a")`'),
            ('attr(node, name)', '取属性；对象时取同名字段。`attr(sel(item, "a"), "href")`'),
          ]),
          const _FnGroup(title: '时间与随机', items: [
            ('now()', 'ISO 8601 当前时间。`now()`'),
            ('ts()', '当前 Unix 秒级时间戳。`ts()`'),
            ('today()', '`YYYY-MM-DD`。`today()`'),
            ('rand(max)', '0 ≤ n < max 的随机整数。`rand(100000)`'),
            ('uuid()', '随机 UUID v4 形态字符串。`uuid()`'),
          ]),
          const _FnGroup(title: 'URL 与逻辑', items: [
            (
              'resolve(url, base?)',
              '补全相对地址；缺省用站点 baseUrl。`resolve(item.poster)`'
            ),
            ('domain(url)', '取 host。`domain(base)`'),
            (
              'coalesce(a, b, …)',
              '返回第一个非空值。`coalesce(item.poster, cfg.fallbackPoster)`'
            ),
            ('default(v, fallback)', '空值时取默认。`default(item.area, "未知")`'),
            ('if(cond, a, b)', '条件取值。`if(item.score != "", item.score, "—")`'),
            ('not(v)', '逻辑取反。`not(contains(item.title, "预告"))`'),
          ]),
          const SizedBox(height: 10),
          _note(
            context,
            '表达式里不要写副作用逻辑；需要请求时只用 `http.get` / `http.post`，且放在 vars 里。'
            '字段表达式越短越好，复杂判断拆成多个字段或变量。',
          ),
        ],
      ),
      _DocSection(
        key: _keys[8],
        number: '09',
        title: '差量修改工作流',
        subtitle: 'diff → patch → 应用 → 回滚',
        children: [
          _rich(
            context,
            '编辑器每次保存都会对比上一版，自动生成 unified diff 并写入版本历史；'
            '首版没有前置版本，因此记为全量快照（`full: true`）。历史里可以查看补丁、复制补丁、回滚到任意版本。',
          ),
          const SizedBox(height: 12),
          _h3(context, '补丁格式'),
          const _Code(label: 'UNIFIED DIFF', code: _patchSample),
          const SizedBox(height: 10),
          _bullets(context, const [
            '`@@ -旧起始,旧行数 +新起始,新行数 @@` 是 hunk 头，例如 `@@ -1,3 +1,4 @@` 表示旧文件从第 1 行起 3 行、新文件从第 1 行起 4 行。',
            '行首 `-` 删除、`+` 新增、空格为上下文。',
            '上下文不匹配时会抛错并给出行号，不会"部分应用"；因此补丁要基于最新快照生成。',
            '`applyPatchToLatest` 只接受针对当前版本的补丁；版本落后时先生成新补丁，或直接全量保存。',
            '回滚不是反向应用补丁，而是用历史快照生成新版本，历史保持只增不减。',
          ]),
          const SizedBox(height: 12),
          _h3(context, 'MCP 工具'),
          const _Table(
            headers: ['工具', '用途', '输入'],
            widths: [190, 300, 250],
            monoColumns: {0},
            rows: [
              ['poqi_apply_patch', '应用差量补丁，适合小改动。', '`id`、`patch`、`message`'],
              ['poqi_save_plugin', '全量写入插件，适合首版或大改。', '`plugin`、`message`'],
            ],
          ),
          const SizedBox(height: 12),
          _rich(
            context,
            '推荐流程：先 `poqi_get_plugin` 取当前 JSON → 让模型只输出补丁 → `poqi_apply_patch`；'
            '若补丁冲突，退回 `poqi_save_plugin` 全量写入。每次写入都会生成版本记录，出错可回滚。',
          ),
        ],
      ),
      _DocSection(
        key: _keys[9],
        number: '10',
        title: '局域网 MCP 接入',
        subtitle: '让桌面 Agent 直接读写规则',
        children: [
          _rich(
            context,
            'Poqi 在设备上监听一个 HTTP 端点，实现 MCP 的 JSON-RPC 2.0 传输。'
            '默认地址为 `http://<设备IP>:8765/mcp`，端口可在「连接」页修改；'
            '开启配对码后需附带 `X-Poqi-Pin` 请求头。',
          ),
          const SizedBox(height: 12),
          const _Table(
            headers: ['方法', '路径', '说明'],
            widths: [100, 170, 470],
            monoColumns: {0, 1},
            rows: [
              ['GET', '/', '服务信息：名称、设备、协议版本。'],
              ['GET', '/mcp', '与 `/` 相同，便于探测。'],
              ['POST', '/mcp', 'JSON-RPC 入口。'],
              ['GET', '/mcp/tools', '工具索引与入参 schema。'],
              ['GET', '/mcp/sse', '事件流（部分客户端使用）。'],
            ],
          ),
          const SizedBox(height: 14),
          _h3(context, 'initialize'),
          const _Code(label: 'JSON-RPC', code: _mcpInit),
          const SizedBox(height: 14),
          _h3(context, 'tools/call'),
          const _Code(label: 'JSON-RPC', code: _mcpCall),
          const SizedBox(height: 14),
          _h3(context, '工具清单'),
          const _Table(
            headers: ['工具', '作用'],
            widths: [210, 530],
            monoColumns: {0},
            rows: [
              ['poqi_search', '跨所有启用站点聚合搜索，返回去重后的条目。'],
              ['poqi_get_detail', '读取某站点某条目的详情与线路/剧集。'],
              ['poqi_save_plugin', '全量写入插件；校验有 error 时拒绝保存。'],
              ['poqi_apply_patch', '对最新版本应用 unified diff，失败返回冲突行号。'],
              ['poqi_list_revisions', '列出版本历史（序号、时间、说明、增删行数）。'],
              ['poqi_list_sites', '列出站点：插件、启用状态、健康信息。'],
              ['poqi_export_snapshot', '导出插件、站点、收藏、历史的快照。'],
            ],
          ),
          const SizedBox(height: 10),
          _rich(
            context,
            '另有 `poqi_get_state`、`poqi_list_plugins`、`poqi_get_plugin`、`poqi_validate_plugin` 四个读取/校验工具，'
            '适合在写入前先了解现状。',
          ),
        ],
      ),
      _DocSection(
        key: _keys[10],
        number: '11',
        title: '调试建议',
        subtitle: '从 home 到 play，一步一步验证',
        children: [
          _rich(
            context,
            '不要一次写完五个端点。按"列表 → 详情 → 剧集 → 播放"的顺序推进，每一步都能单独验证。',
          ),
          const SizedBox(height: 12),
          _numbered(context, const [
            '先只写 `home`：确认 `baseUrl`、`root` 与 `id`/`title` 能取到值。',
            '再写 `detail`：确认详情字段与 `episodes.root` 命中，剧集名与地址不为空。',
            '最后补 `play`：若剧集地址本身可播放，可以不声明 play 端点。',
            '每加一个端点就保存一次，让版本历史保留可回滚的节点。',
            '用「连接」页的健康检查观察状态码与延迟；失败时先看请求 URL 是否正确。',
          ]),
          const SizedBox(height: 14),
          _h3(context, '常见错误'),
          const _Table(
            headers: ['现象', '可能原因', '处理'],
            widths: [190, 250, 300],
            rows: [
              [
                '列表为空，但接口有数据',
                '`root` 未命中；接口把数据包在 `data.list` 里。',
                '在调试里逐层试 `data`、`data.list`；注意数组下标写法。'
              ],
              [
                '字段全是空',
                '表达式写的是 `item.xxx`，但 root 已经指向了单条记录。',
                '确认 root 是"列表"还是"单条"，相应调整 `item` 前缀。'
              ],
              [
                '保存时提示表达式语法错误',
                '括号/引号不配对，或函数名拼错。',
                '按校验结果里的 `path` 定位到具体字段，从最短表达式开始试。'
              ],
              [
                '403 / 401',
                '缺少 UA、Referer、Cookie 或签名。',
                '补 `headers`；把签名逻辑放进 vars，并检查 `ttl` 是否过长。'
              ],
              [
                '海报或剧集地址打不开',
                '接口返回相对地址。',
                '交给 `resolve` / 自动补全；确认站点 baseUrl 带协议。'
              ],
              [
                '详情页没有剧集',
                '`detail.parse.episodes` 未声明或 root 不匹配。',
                '补 `episodes`，字段至少包含 `name` 与 `url`。'
              ],
              ['首页一直转圈', '某站点超时拖慢聚合。', '检查 `timeoutMs`；必要时先停用该站点。'],
            ],
          ),
          const SizedBox(height: 14),
          _note(
            context,
            '改动越小越容易回滚：优先改一个字段、一个端点，保存后再继续。'
            '遇到不确定的响应结构，先把原始响应存到 notes 里，再慢慢收窄 root。',
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: p.canvas,
      body: PqBackdrop(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.only(
            top: compact ? MediaQuery.paddingOf(context).top + 8 : 18,
            bottom: 72,
          ),
          child: PqContent(
            maxWidth: 1240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(context),
                const SizedBox(height: 18),
                _titleBlock(context),
                const SizedBox(height: 18),
                PqPanel(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 2,
                        height: 34,
                        margin: const EdgeInsets.only(right: 12, top: 2),
                        decoration: BoxDecoration(
                          color: p.accent.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: _rich(
                          context,
                          '本规范描述 Poqi 插件清单（manifest）的结构、求值方式与调试方法。'
                          '适用于插件作者、二次开发者，以及通过 MCP 修改规则的外部 Agent。'
                          '当前版本 `spec: 1`，字段只增不改。',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 214, child: _toc(context)),
                      const SizedBox(width: 34),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: sections,
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tocCompact(context),
                      const SizedBox(height: 22),
                      ...sections,
                    ],
                  ),
                const SizedBox(height: 36),
                _footer(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _copyMarkdown,
          icon: const Icon(Icons.content_copy_rounded, size: 15),
          label: Text(compact ? '复制 Markdown' : '复制规范 Markdown'),
        ),
        FilledButton.icon(
          onPressed: () => context.go('/connect'),
          icon: const Icon(Icons.wifi_tethering_rounded, size: 15),
          label: const Text('打开 MCP 页'),
        ),
      ],
    );

    final back = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PqIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: '返回',
          size: 34,
          iconSize: 18,
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/plugins');
            }
          },
        ),
        const SizedBox(width: 8),
        Text('DOCS', style: PqType.eyebrow.copyWith(color: p.textFaint)),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          back,
          const SizedBox(height: 12),
          buttons,
        ],
      );
    }
    return Row(
      children: [
        back,
        const Spacer(),
        buttons,
      ],
    );
  }

  Widget _titleBlock(BuildContext context) {
    final p = PqPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SPECIFICATION',
          style: PqType.eyebrow.copyWith(color: p.accent.withOpacity(0.9)),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                'Poqi 插件规范',
                style: PqType.hero.copyWith(
                  fontSize: MediaQuery.sizeOf(context).width < 480 ? 32 : 40,
                  color: p.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            PqTag('v1', color: p.accent, filled: true),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '一份 JSON，描述请求、解析与变量；站点只负责填配置。',
          style: PqType.bodySmall.copyWith(fontSize: 12.5, color: p.textMuted),
        ),
      ],
    );
  }

  Widget _toc(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(PqTokens.r16),
        border: Border.all(color: p.lineSoft, width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 9),
            child: Text(
              'CONTENTS',
              style: PqType.eyebrow.copyWith(fontSize: 9.5, color: p.textFaint),
            ),
          ),
          for (var i = 0; i < _chapters.length; i++)
            _TocItem(
              number: _chapters[i].$1,
              title: _chapters[i].$2,
              active: i == _active,
              onTap: () => _jump(i),
            ),
        ],
      ),
    );
  }

  Widget _tocCompact(BuildContext context) {
    final p = PqPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONTENTS',
          style: PqType.eyebrow.copyWith(fontSize: 9.5, color: p.textFaint),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (var i = 0; i < _chapters.length; i++)
              GestureDetector(
                onTap: () => _jump(i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color:
                        i == _active ? p.accent.withOpacity(0.14) : p.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: i == _active
                          ? p.accent.withOpacity(0.32)
                          : p.lineSoft,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _chapters[i].$1,
                        style: PqType.mono.copyWith(
                          fontSize: 9.5,
                          color: i == _active ? p.accent : p.textFaint,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _chapters[i].$2,
                        style: PqType.label.copyWith(
                          fontSize: 11.5,
                          color: i == _active ? p.text : p.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final p = PqPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: p.lineSoft),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Poqi 插件规范 v1 · 2026',
              style:
                  PqType.bodySmall.copyWith(fontSize: 11.5, color: p.textFaint),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/connect'),
              child: Text(
                '连接 MCP →',
                style: PqType.label.copyWith(
                  fontSize: 11.5,
                  color: p.accent.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 章节与排版
// ---------------------------------------------------------------------------

const _chapters = <(String, String)>[
  ('01', '模型'),
  ('02', '清单字段'),
  ('03', '配置项'),
  ('04', '运行时变量'),
  ('05', '端点'),
  ('06', '解析'),
  ('07', '标准字段'),
  ('08', '表达式函数'),
  ('09', '差量工作流'),
  ('10', '局域网 MCP'),
  ('11', '调试建议'),
];

class _DocSection extends StatelessWidget {
  const _DocSection({
    super.key,
    required this.number,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String number;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.lineSoft, width: 0.9)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 12),
                  child: Text(
                    number,
                    style: PqType.mono.copyWith(
                      fontSize: 11,
                      color: p.accent.withOpacity(0.8),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: PqType.h2.copyWith(fontSize: 19)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: PqType.bodySmall.copyWith(
                            fontSize: 11.5,
                            color: p.textFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _TocItem extends StatelessWidget {
  const _TocItem({
    required this.number,
    required this.title,
    required this.active,
    required this.onTap,
  });

  final String number;
  final String title;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: active ? p.accent.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                number,
                style: PqType.mono.copyWith(
                  fontSize: 9.5,
                  color: active ? p.accent : p.textFaint,
                ),
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PqType.bodySmall.copyWith(
                  fontSize: 12,
                  color: active ? p.text : p.textMuted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _lead(BuildContext context, String text) {
  final p = PqPalette.of(context);
  return Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
    decoration: BoxDecoration(
      color: p.surfaceHigh,
      borderRadius: BorderRadius.circular(PqTokens.r12),
      border: Border.all(color: p.lineSoft, width: 0.9),
    ),
    child: Text(
      text,
      style: PqType.body.copyWith(
        fontSize: 14.5,
        height: 1.6,
        fontWeight: FontWeight.w600,
        color: p.text,
      ),
    ),
  );
}

Widget _h3(BuildContext context, String text) {
  final p = PqPalette.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 1.5,
          margin: const EdgeInsets.only(right: 8),
          color: p.accent.withOpacity(0.7),
        ),
        Flexible(
          child: Text(
            text,
            style: PqType.title.copyWith(fontSize: 13.5),
          ),
        ),
      ],
    ),
  );
}

Widget _rich(BuildContext context, String text, {double size = 13}) {
  final p = PqPalette.of(context);
  final base = PqType.bodySmall.copyWith(
    fontSize: size,
    height: 1.75,
    color: p.textMuted,
  );
  return RichText(
    text: TextSpan(children: _inline(text, p, base)),
  );
}

List<InlineSpan> _inline(String text, PqPalette p, TextStyle base) {
  final parts = text.split('`');
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        TextSpan(
          text: parts[i],
          style: i.isOdd
              ? base.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const [
                    'Menlo',
                    'Consolas',
                    'Courier New'
                  ],
                  fontSize: (base.fontSize ?? 13) - 1.4,
                  height: 1.6,
                  backgroundColor: p.surfaceHigh,
                  color: p.text,
                )
              : base,
        ),
  ];
}

Widget _bullets(BuildContext context, List<String> items) {
  final p = PqPalette.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 9, right: 9),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.accent.withOpacity(0.65),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: _rich(context, item)),
            ],
          ),
        ),
    ],
  );
}

Widget _numbered(BuildContext context, List<String> items) {
  final p = PqPalette.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${i + 1}'.padLeft(2, '0'),
                  style: PqType.mono.copyWith(
                    fontSize: 10.5,
                    color: p.accent.withOpacity(0.75),
                  ),
                ),
              ),
              Expanded(child: _rich(context, items[i])),
            ],
          ),
        ),
    ],
  );
}

Widget _note(BuildContext context, String text) {
  final p = PqPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: p.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.lineSoft, width: 0.9),
      ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 8),
          child: Icon(Icons.info_outline_rounded,
              size: 14, color: p.accent.withOpacity(0.85)),
        ),
        Expanded(child: _rich(context, text, size: 12.5)),
      ],
    ),
  );
}

class _Code extends StatelessWidget {
  const _Code({required this.code, this.label = 'CODE'});

  final String code;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 9, bottom: 10),
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: BorderRadius.circular(PqTokens.r12),
        border: Border.all(color: p.lineSoft, width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
            child: Row(
              children: [
                Text(
                  label,
                  style: PqType.eyebrow.copyWith(
                    fontSize: 9,
                    letterSpacing: 1.1,
                    color: p.textFaint,
                  ),
                ),
                const Spacer(),
                PqIconButton(
                  icon: Icons.content_copy_rounded,
                  tooltip: '复制代码',
                  size: 26,
                  iconSize: 13,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    showPqToast(context, '已复制', kind: PqToastKind.success);
                  },
                ),
              ],
            ),
          ),
          Divider(color: p.lineSoft, height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(
                code,
                style: PqType.mono.copyWith(
                  fontSize: 11.5,
                  height: 1.7,
                  color: p.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.headers,
    required this.widths,
    required this.rows,
    this.monoColumns = const {},
  });

  final List<String> headers;
  final List<double> widths;
  final List<List<String>> rows;
  final Set<int> monoColumns;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final minWidth = widths.fold<double>(0, (a, b) => a + b);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth > minWidth ? c.maxWidth : minWidth;
        final scale = width / minWidth;
        final actual = [for (final w in widths) w * scale];
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(PqTokens.r12),
            border: Border.all(color: p.lineSoft, width: 0.9),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: p.surfaceHigh,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        for (var i = 0; i < headers.length; i++)
                          SizedBox(
                            width: actual[i],
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                headers[i].toUpperCase(),
                                style: PqType.eyebrow.copyWith(
                                  fontSize: 9,
                                  letterSpacing: 0.8,
                                  color: p.textFaint,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var r = 0; r < rows.length; r++) ...[
                    if (r > 0)
                      Divider(color: p.lineSoft, height: 1, thickness: 0.8),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < rows[r].length; i++)
                            SizedBox(
                              width: actual[i],
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                child: _cell(
                                  context,
                                  rows[r][i],
                                  mono: monoColumns.contains(i),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cell(BuildContext context, String text, {required bool mono}) {
    final p = PqPalette.of(context);
    final base = mono
        ? PqType.mono.copyWith(fontSize: 10.5, height: 1.6, color: p.text)
        : PqType.bodySmall
            .copyWith(fontSize: 11.5, height: 1.65, color: p.textMuted);
    return RichText(text: TextSpan(children: _inline(text, p, base)));
  }
}

class _FnGroup extends StatelessWidget {
  const _FnGroup({required this.title, required this.items});

  final String title;
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(PqTokens.r12),
        border: Border.all(color: p.lineSoft, width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
            child: Text(
              title,
              style: PqType.eyebrow.copyWith(
                fontSize: 9.5,
                letterSpacing: 1.0,
                color: p.accent.withOpacity(0.85),
              ),
            ),
          ),
          Divider(color: p.lineSoft, height: 1),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(color: p.lineSoft, height: 1, thickness: 0.7),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: LayoutBuilder(
                builder: (context, c) {
                  final fnWidth = c.maxWidth < 420 ? 130.0 : 176.0;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: fnWidth,
                        child: Text(
                          items[i].$1,
                          style: PqType.mono.copyWith(
                            fontSize: 10.5,
                            height: 1.5,
                            color: p.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _rich(context, items[i].$2, size: 12),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelFlow extends StatelessWidget {
  const _ModelFlow();

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 620;
        final boxes = [
          _flowBox(
            context,
            eyebrow: 'PLUGIN',
            title: '插件',
            lines: const ['请求 · 解析 · 变量', '纯 JSON，不含用户数据'],
            color: p.accent,
          ),
          _flowBox(
            context,
            eyebrow: 'SITE',
            title: '站点',
            lines: const ['pluginId + 配置', '域名 / 凭证各填各的'],
            color: p.sage,
          ),
          _flowBox(
            context,
            eyebrow: 'FEED',
            title: '聚合',
            lines: const ['标准化 · 去重 · 排序', '统一进入首页与搜索'],
            color: p.clay,
          ),
        ];

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < boxes.length; i++) ...[
                boxes[i],
                if (i < boxes.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Icon(Icons.arrow_downward_rounded,
                        size: 15, color: p.textFaint),
                  ),
              ],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: boxes[0]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 16, color: p.textFaint),
            ),
            Expanded(child: boxes[1]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 16, color: p.textFaint),
            ),
            Expanded(child: boxes[2]),
          ],
        );
      },
    );
  }

  Widget _flowBox(
    BuildContext context, {
    required String eyebrow,
    required String title,
    required List<String> lines,
    required Color color,
  }) {
    final p = PqPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(PqTokens.r12),
        border: Border.all(color: color.withOpacity(0.28), width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            style: PqType.eyebrow.copyWith(
              fontSize: 8.5,
              letterSpacing: 1.2,
              color: color.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: PqType.title.copyWith(fontSize: 14)),
          const SizedBox(height: 4),
          for (final l in lines)
            Text(
              l,
              style: PqType.bodySmall.copyWith(
                fontSize: 11,
                height: 1.55,
                color: p.textFaint,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 代码示例
// ---------------------------------------------------------------------------

const _minimalPlugin = r'''{
  "spec": 1,
  "id": "custom.example",
  "name": "示例插件",
  "version": "1.0.0",
  "author": "you",
  "engine": "http",
  "baseUrl": "https://example.com",
  "headers": { "User-Agent": "Poqi/1.0" },
  "config": [],
  "endpoints": {
    "home": {
      "request": { "path": "/list", "query": { "page": "{{page}}" } },
      "parse": {
        "format": "json",
        "root": "data.list",
        "fields": {
          "id": "item.id",
          "title": "item.title",
          "poster": "item.poster"
        }
      }
    }
  }
}''';

const _configSample = r'''"config": [
  {
    "key": "apiKey",
    "label": "接口密钥",
    "type": "password",
    "required": true,
    "secret": true,
    "hint": "在站点「个人中心」获取",
    "help": "保存后会打码显示，仅用于签名。",
    "refreshSeconds": 86400
  },
  {
    "key": "region",
    "label": "地区",
    "type": "select",
    "options": ["全部", "内地", "港台", "日韩", "欧美"],
    "default": "全部"
  },
  {
    "key": "adFree",
    "label": "过滤推广位",
    "type": "boolean",
    "default": "true"
  },
  {
    "key": "pageSize",
    "label": "每页条数",
    "type": "number",
    "default": "24"
  }
]''';

const _varsSample = r'''"vars": {
  "sign": {
    "expr": "md5(cfg.apiKey + ts())",
    "ttl": 60
  },
  "token": {
    "expr": "http.get('/api/auth', {query: {key: cfg.apiKey}}).data.token",
    "ttl": 1800
  }
}''';

const _endpointsSample = r'''"endpoints": {
  "home": {
    "request": {
      "method": "GET",
      "path": "/v1/home",
      "query": { "page": "{{page}}" },
      "timeoutMs": 12000
    },
    "parse": {
      "format": "json",
      "root": "data.list",
      "fields": {
        "id": "item.vod_id",
        "title": "item.vod_name",
        "poster": "item.vod_pic"
      }
    }
  },
  "search": {
    "request": {
      "path": "/v1/search",
      "query": { "wd": "{{keyword}}", "pg": "{{page}}" },
      "headers": { "X-Sign": "{{vars.sign}}" }
    },
    "parse": { "format": "json", "root": "data.list", "fields": {
      "id": "item.vod_id", "title": "item.vod_name"
    } }
  },
  "detail": {
    "request": { "path": "/v1/detail", "query": { "id": "{{id}}" } },
    "parse": {
      "format": "json",
      "root": "data",
      "fields": {
        "id": "item.vod_id",
        "title": "item.vod_name",
        "intro": "item.vod_content"
      },
      "episodes": {
        "format": "json",
        "root": "data.episodes",
        "fields": { "name": "item.name", "url": "item.play_url", "line": "item.line" }
      }
    }
  }
}''';

const _jsonParse = r'''{
  "format": "json",
  "root": "data.list",
  "fields": {
    "id": "item.vod_id",
    "title": "item.vod_name",
    "poster": "item.vod_pic",
    "year": "item.vod_year",
    "score": "default(item.vod_score, '—')",
    "remarks": "item.vod_remarks",
    "tags": "split(item.vod_class, ',')"
  }
}''';

const _jsonResponse = r'''{
  "data": {
    "list": [
      {
        "vod_id": 1024,
        "vod_name": "沙丘",
        "vod_pic": "/img/dune.jpg",
        "vod_year": "2021",
        "vod_class": "科幻,冒险"
      }
    ]
  }
}''';

const _htmlParse = r'''{
  "format": "html",
  "root": ".module-list .module-item",
  "fields": {
    "id": "regex(attr(sel(item, 'a'), 'href'), '/detail/(\\d+)')",
    "title": "text(sel(item, '.module-item-title'))",
    "poster": "attr(sel(item, 'img'), 'data-original')",
    "remarks": "text(sel(item, '.module-item-text'))"
  }
}''';

const _regexParse = r'''{
  "format": "regex",
  "pattern": "<a href=\"(/play/(\\d+))\">([^<]+)</a>",
  "group": 2,
  "fields": {
    "id": "item.group",
    "title": "item.groups[3]",
    "url": "resolve(item.groups[1])"
  }
}''';

const _patchSample = r'''--- a/plugin.json
+++ b/plugin.json
@@ -12,3 +12,4 @@
   "engine": "http",
-  "baseUrl": "https://old.example.com",
+  "baseUrl": "https://new.example.com",
+  "author": "Poqi Lab",
   "config": [],''';

const _mcpInit = r'''POST http://192.168.1.20:8765/mcp
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "clientInfo": { "name": "claude-desktop", "version": "0.7.0" },
    "capabilities": {}
  }
}''';

const _mcpCall = r'''{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "poqi_search",
    "arguments": { "keyword": "沙丘", "limit": 20 }
  }
}''';

// ---------------------------------------------------------------------------
// 精简 Markdown（供复制给外部模型/同事）
// ---------------------------------------------------------------------------

const _summaryMarkdown = r'''# Poqi 插件规范 v1

插件 = 声明式规则（请求 + 解析 + 变量）；站点 = 插件 + 一份配置。
规则是纯 JSON，站点只覆盖 `baseUrl` 与 `config`。

## 清单字段
spec(int,1) id(name) version author description homepage icon engine(http|demo)
baseUrl headers config vars endpoints notes

- id：3–64 位小写字母/数字/./_/-，全局唯一。
- endpoints：至少一个，键名限 home/category/search/detail/play。
- 每个 parse 的 fields 至少含 id 与 title。

## config（站点级，每个站点单独填写）
key label type(text|password|number|boolean|select) required secret hint help
default options refreshSeconds

## vars（运行时变量）
{ "token": { "expr": "http.get('/api/auth').data.token", "ttl": 1800 } }
- 引用：{{vars.token}}、{{cfg.apiKey}}。
- 鉴权 401/403 时应让变量失效重取，TTL 不要过长（建议 ≥30 秒）。

## request
method path headers query body timeoutMs
模板变量：cfg vars page keyword category id base

## parse
- json：root 路径（data.list，支持 a.b[0].c），字段从 item 开始。
- html：root 为 CSS 选择器；sel()/text()/attr()。
- regex：pattern + group；记录提供 match/group/groups。
- detail 建议声明 episodes，字段 name/url/line。

## 标准字段
id(必填) title(必填) poster year score remarks area kind tags intro director actors
episodes: url name line
相对地址自动按 baseUrl 补全。

## 差量修改
编辑器保存自动生成 unified diff；@@ -旧,数 +新,数 @@。
applyPatchToLatest 只对最新版本生效，冲突报行号。
MCP：poqi_apply_patch（补丁）、poqi_save_plugin（全量）。

## 局域网 MCP
POST http://<设备IP>:8765/mcp（JSON-RPC 2.0）
initialize / tools/call
工具：poqi_search poqi_get_detail poqi_save_plugin poqi_apply_patch
poqi_list_revisions poqi_list_sites poqi_export_snapshot

## 调试顺序
home → detail(episodes) → play。
常见问题：root 未命中、表达式语法、鉴权 403、相对地址、episodes 缺失。
''';
