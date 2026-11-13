
import 'package:flutter_test/flutter_test.dart';
import 'package:poqi/domain/models/plugin.dart';
import 'package:poqi/domain/plugin/builtin.dart';
import 'package:poqi/domain/plugin/expr.dart';
import 'package:poqi/domain/plugin/js/plugin_script.dart';
import 'package:poqi/domain/plugin/parse.dart';
import 'package:poqi/domain/plugin/validator.dart';

void main() {
  group('split 剧集拆分', () {
    test('多线路 + 空段 + 缺失 \$ + 线路名不足', () {
      const raw = '第01集\$https://x/1.m3u8#第02集\$https://x/2.m3u8#'
          '\$\$\$'
          '第01集\$https://y/1.m3u8#第02集\$https://y/2.m3u8#https://y/3.m3u8';

      final eps = splitEpisodes(raw, lineNames: '量子');
      expect(eps.length, 5);

      expect(eps[0]['line'], '量子');
      expect(eps[0]['name'], '第01集');
      expect(eps[0]['url'], 'https://x/1.m3u8');

      // 线路名少于线路数：第二条回退为「线路2」。
      expect(eps[2]['line'], '线路2');
      expect(eps[2]['name'], '第01集');
      expect(eps[2]['url'], 'https://y/1.m3u8');

      // 没有 pairSep 的片段：整段当 url，集名自动编号。
      expect(eps[4]['name'], '第 3 集');
      expect(eps[4]['url'], 'https://y/3.m3u8');
      expect(eps[4]['line'], '线路2');
    });

    test('空串与空地址被跳过，线路名全缺省', () {
      const raw = '#第1集\$https://a/1.m3u8##\$https://a/2.m3u8#第3集\$';

      final eps = splitEpisodes(raw);
      expect(eps.length, 2);
      expect(eps[0]['line'], '线路1');
      expect(eps[0]['name'], '第1集');
      expect(eps[1]['name'], '第 2 集');
      expect(eps[1]['url'], 'https://a/2.m3u8');
    });

    test('线路数与剧集组数不一致时不崩', () {
      const raw = 'a\$https://a/1\$\$\$b\$https://b/1\$\$\$c\$https://c/1';
      final eps = splitEpisodes(raw, lineNames: 'L1\$\$\$L2\$\$\$L3\$\$\$L4');
      expect(eps.map((e) => e['line']).toList(), ['L1', 'L2', 'L3']);
    });

    test('ParseSpec JSON 往返保留 split 字段', () {
      const spec = ParseSpec(
        format: ParseFormat.split,
        from: 'item.play_url',
        lineNames: 'item.play_from',
        lineSep: '||',
        itemSep: ';',
        pairSep: '@',
      );
      final again = ParseSpec.fromJson(spec.toJson());
      expect(again.format, ParseFormat.split);
      expect(again.from, 'item.play_url');
      expect(again.lineNames, 'item.play_from');
      expect(again.lineSep, '||');
      expect(again.itemSep, ';');
      expect(again.pairSep, '@');
    });

    test('自定义分隔符', () {
      final eps = splitEpisodes(
        '第1集|https://a/1||第2集|https://a/2@@第1集|https://b/1',
        lineSep: '@@',
        itemSep: '||',
        pairSep: '|',
      );
      expect(eps.length, 3);
      expect(eps[2]['line'], '线路2');
    });
  });

  group('where / find', () {
    final ctx = ExprContext(vars: {
      'sites': [
        {'key': 'csp_a', 'name': 'A', 'type': 1},
        {'key': 'csp_b', 'name': 'B', 'type': '1'},
        {'key': 'csp_c', 'name': 'C', 'type': 3},
        {'key': 'csp_d'},
      ],
    });

    test('数字与字符串宽松比较', () async {
      expect(await PExpr.eval("len(where(sites, 'type', 1))", ctx), 2);
      final first = await PExpr.eval("first(where(sites, 'type', '1'))", ctx);
      expect((first as Map)['key'], 'csp_a');
    });

    test('find 命中与未命中', () async {
      final hit = await PExpr.eval("find(sites, 'key', 'csp_b')", ctx);
      expect((hit as Map)['name'], 'B');
      expect(await PExpr.eval("find(sites, 'key', 'missing')", ctx), isNull);
    });

    test('异常入参安全返回', () async {
      expect(await PExpr.eval("where('not-a-list', 'type', 1)", ctx), isEmpty);
      expect(await PExpr.eval("find(null, 'type', 1)", ctx), isNull);
      expect(await PExpr.eval("len(where([1, 'x', 2], 'type', 1))", ctx), 0);
    });
  });

  group('内置真实插件', () {
    test('只有两个内置插件且都通过校验', () {
      final plugins = builtinPlugins();
      expect(plugins.length, 2);
      expect(plugins.map((e) => e.id).toSet(), {'poqi.cms.v10', 'poqi.tvbox.api'});

      const validator = PluginValidator();
      for (final plugin in plugins) {
        final errors = validator.validate(plugin).where((e) => e.isError).toList();
        expect(errors, isEmpty, reason: '${plugin.id} 存在错误：$errors');
      }
    });

    test('seedSites 为两个插件各生成一个站点', () {
      final sites = seedSites();
      expect(sites.length, 2);
      expect(sites.map((e) => e.pluginId).toSet(), {'poqi.cms.v10', 'poqi.tvbox.api'});
      expect(sites.every((e) => e.enabled), isTrue);
      expect(sites.first.config['api'], '');
      expect(sites[1].config['interface'], '');
    });

    test('split episodes 缺少 from 会被判错', () {
      final bad = PluginManifest.fromJson({
        'id': 'poqi.test.badsplit',
        'name': '坏插件',
        'version': '1.0.0',
        'engine': 'http',
        'baseUrl': 'https://example.com',
        'endpoints': {
          'detail': {
            'request': {'path': '/api'},
            'parse': {
              'format': 'json',
              'root': 'list',
              'fields': {'id': 'item.id', 'title': 'item.name'},
              'episodes': {'format': 'split'},
            },
          },
        },
      });
      final errors = const PluginValidator()
          .validate(bad)
          .where((e) => e.isError)
          .map((e) => e.message)
          .toList();
      expect(errors.any((e) => e.contains('from')), isTrue);
    });

    test('CMS 插件走 JS 引擎，脚本覆盖五个端点', () {
      final cms = builtinPlugins().firstWhere((e) => e.id == 'poqi.cms.v10');
      expect(cms.engine, PluginEngine.js);
      expect(cms.script, isNotEmpty);
      for (final fn in const ['home', 'category', 'search', 'detail', 'play']) {
        expect(
          RegExp('function\\s+$fn\\s*\\(').hasMatch(cms.script),
          isTrue,
          reason: '脚本缺少 $fn()',
        );
      }
      expect(cms.endpoints.length, 5);
      expect(cms.endpoints['detail']!.parse, isNull);
      expect(cms.endpoints['play']!.request.path, isEmpty);
    });

    test('CMS 插件的 JS 脚本能被校验器接受', () {
      final cms = builtinPlugins().firstWhere((e) => e.id == 'poqi.cms.v10');
      final issues = const PluginValidator().validate(cms);
      expect(
        issues.where((e) => e.isError),
        isEmpty,
        reason: issues.map((e) => '${e.path}: ${e.message}').join('\n'),
      );
    });

    test('JS 插件缺 script 会被判错', () {
      final broken = builtinPlugins()
          .firstWhere((e) => e.id == 'poqi.cms.v10')
          .copyWith(script: '');
      final issues = const PluginValidator().validate(broken);
      expect(issues.any((e) => e.isError && e.path == 'script'), isTrue);
    });

    test('JS 插件声明的函数在脚本里找不到时给出警告', () {
      final broken = builtinPlugins().firstWhere((e) => e.id == 'poqi.cms.v10').copyWith(
            script: 'function home(ctx) { return []; }',
          );
      final issues = const PluginValidator().validate(broken);
      final warns = issues.where((e) => e.level == IssueLevel.warning).toList();
      expect(warns.any((e) => e.message.contains('detail')), isTrue);
    });

    test('TVBox 改成了单文件脚本，选站逻辑写在脚本里', () {
      final tvbox = builtinPlugins().firstWhere((e) => e.id == 'poqi.tvbox.api');
      expect(tvbox.engine, PluginEngine.js);
      expect(tvbox.source, PluginSource.script);
      expect(tvbox.vars, isEmpty, reason: '不再依赖表达式变量，改成脚本里请求');
      expect(tvbox.config.map((e) => e.key), containsAll(['interface', 'siteKey', 'ua']));
      // 选中站点：先按 key/name 精确匹配，再退回第一个 type=1。
      expect(tvbox.script, contains('type === 1'));
      expect(tvbox.script, contains('sites[i].key === key'));
      expect(tvbox.script, contains('pq.http.get'));
    });


  group('脚本元信息静态解析', () {
    test('内置脚本能被静态解析出名字与配置', () {
      for (final p in builtinPlugins()) {
        final meta = PluginScript.lightMeta(p.script);
        expect(meta, isNotNull, reason: '${p.id} 的 var plugin 没解析出来');
        expect(meta!['name'], p.name);
        expect(meta['config'], isA<List>());
        final fns = PluginScript.scanFunctions(p.script);
        expect(fns, containsAll(['home', 'search', 'detail', 'play']));
      }
    });

    test('用户脚本：字段、headers、配置类型都能读出来', () {
      const script = r"""
var plugin = {
  id: 'x.y',
  name: '测试 站',
  version: '2.0.0',
  base: 'https://a.com',
  headers: { 'User-Agent': 'UA', 'Referer': 'https://a.com/' },
  config: [
    { key: 'cookie', label: 'Cookie', type: 'password' },
    { key: 'q', label: '清晰度', type: 'select', options: ['1080', '720'] }
  ]
};
function home(p) { return { list: [] }; }
function search(p) { return { list: [] }; }
""";
      final m = PluginScript.compile(script);
      expect(m.id, 'x.y');
      expect(m.name, '测试 站');
      expect(m.version, '2.0.0');
      expect(m.baseUrl, 'https://a.com');
      expect(m.headers['User-Agent'], 'UA');
      expect(m.config.length, 2);
      expect(m.config[0].secret, isTrue, reason: 'password 类型自动打码');
      expect(m.config[1].options, ['1080', '720']);
      expect(m.endpoints.keys, containsAll(['home', 'search']));
      expect(m.endpoints.containsKey('detail'), isFalse);
      expect(m.source, PluginSource.script);
    });

    test('缺 home / search 时明确报错', () {
      const script = r"""
var plugin = { id: 'x', name: 'x' };
function detail(p) { return {}; }
""";
      expect(
        () => PluginScript.compile(script),
        throwsA(isA<Exception>()),
      );
    });

    test('没写 id 时按名字生成稳定 id', () {
      const a = 'var plugin = { name: "同一个名字" }; function home(p) { return []; }';
      const b = 'var plugin = { name: "同一个名字" }; function home(p) { return []; }';
      final id1 = PluginScript.compile(a).id;
      final id2 = PluginScript.compile(b).id;
      expect(id1, id2);
      expect(id1, startsWith('custom.'));
    });

    test('注释和尾逗号不影响解析', () {
      const script = r"""
// 头部注释
var plugin = {
  id: 'c.d',        // 行内注释
  name: 'C',
  /* 块注释
     跨行 */
  config: [
    { key: 'a', label: 'A' },
  ],
};
function home(p) { return { list: [] }; }
""";
      final m = PluginScript.compile(script);
      expect(m.id, 'c.d');
      expect(m.config.single.key, 'a');
    });
  });
  });
}
