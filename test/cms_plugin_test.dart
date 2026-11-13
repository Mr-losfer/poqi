
import 'package:flutter_test/flutter_test.dart';
import 'package:poqi/domain/models/plugin.dart';
import 'package:poqi/domain/plugin/builtin.dart';
import 'package:poqi/domain/plugin/expr.dart';
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

    test('TVBox vars 能按 siteKey 或首个 type=1 选出 api', () async {
      final tvbox = builtinPlugins().firstWhere((e) => e.id == 'poqi.tvbox.api');
      final expr = tvbox.vars['api']!.expr;
      final sites = [
        {'key': 'csp_a', 'name': 'A站', 'type': 3, 'api': 'https://a/api'},
        {'key': 'csp_b', 'name': 'B站', 'type': 1, 'api': 'https://b/api'},
        {'key': 'csp_c', 'name': 'C站', 'type': 1, 'api': 'https://c/api'},
      ];

      final picked = await PExpr.eval(
        expr,
        ExprContext(vars: {
          'cfg': {'siteKey': ''},
          'vars': {'sites': sites},
        }),
      );
      expect(picked, 'https://b/api');

      final byName = await PExpr.eval(
        expr,
        ExprContext(vars: {
          'cfg': {'siteKey': 'C站'},
          'vars': {'sites': sites},
        }),
      );
      expect(byName, 'https://c/api');
    });
  });
}
