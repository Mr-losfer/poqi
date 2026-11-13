import 'package:flutter_test/flutter_test.dart';
import 'package:poqi/domain/models/plugin.dart';
import 'package:poqi/domain/models/site.dart';
import 'package:poqi/domain/plugin/builtin.dart';
import 'package:poqi/domain/plugin/demo_catalog.dart';
import 'package:poqi/domain/plugin/expr.dart';
import 'package:poqi/domain/plugin/parse.dart';
import 'package:poqi/domain/plugin/runner.dart';
import 'package:poqi/domain/plugin/validator.dart';

void main() {
  group('插件清单', () {
    test('内置插件本身通过校验', () {
      const validator = PluginValidator();
      for (final plugin in builtinPlugins()) {
        final issues = validator.validate(plugin);
        final errors = issues.where((e) => e.isError).toList();
        expect(errors, isEmpty, reason: '${plugin.id} 存在错误：$errors');
      }
    });

    test('JSON 往返保持一致', () {
      final plugin = builtinPlugins().first;
      final again = PluginManifest.fromJsonString(plugin.toJsonString());
      expect(again.id, plugin.id);
      expect(again.endpoints.length, plugin.endpoints.length);
      expect(again.config.length, plugin.config.length);
      expect(again.vars.keys, plugin.vars.keys);
    });

    test('非法 id / 缺 baseUrl / 缺 title 会被判错', () {
      final bad = PluginManifest.fromJson({
        'id': 'Bad Id',
        'name': '',
        'version': 'x',
        'engine': 'http',
        'baseUrl': '',
        'endpoints': {
          'home': {
            'request': {'path': '', 'method': 'GET'},
            'parse': {
              'format': 'json',
              'root': 'data',
              'fields': {'id': 'item.id'}
            }
          }
        }
      });
      final issues = const PluginValidator().validate(bad);
      expect(issues.where((e) => e.isError).length, greaterThanOrEqualTo(3));
    });
  });

  group('声明式解析', () {
    test('JSON 列表解析', () async {
      const body = '''
      {"data":{"list":[
        {"vod_id":"1","vod_name":"长夜将尽","vod_year":"2026","vod_score":"8.9"},
        {"vod_id":"2","vod_name":"雾中灯塔","vod_year":"2025","vod_score":"8.4"}
      ]}}''';
      const spec = ParseSpec(
        format: ParseFormat.json,
        root: 'data.list',
        fields: {
          'id': 'item.vod_id',
          'title': 'item.vod_name',
          'year': 'item.vod_year',
          'score': 'item.vod_score',
        },
      );
      final result = await const DeclarativeParser().records(
        spec: spec,
        body: body,
        url: 'https://demo.poqi.local/api',
        base: ExprContextStub.base,
      );
      expect(result.value.length, 2);
      expect(result.value.first['title'], '长夜将尽');
      expect(result.warnings, isEmpty);
    });

    test('HTML 选择器解析', () async {
      const body = '''
      <ul class="grid">
        <li class="card"><a href="/d/1"><h3>长夜将尽</h3></a><img data-src="/p/1.jpg"></li>
        <li class="card"><a href="/d/2"><h3>雾中灯塔</h3></a></li>
      </ul>''';
      const spec = ParseSpec(
        format: ParseFormat.html,
        root: '.card',
        fields: {
          'id': "attr(sel(item, 'a'), 'href')",
          'title': "text(sel(item, 'h3'))",
          'poster': "attr(sel(item, 'img'), 'data-src')",
        },
      );
      final result = await const DeclarativeParser().records(
        spec: spec,
        body: body,
        url: 'https://demo.poqi.local/',
        base: ExprContextStub.base,
      );
      expect(result.value.length, 2);
      expect(result.value[1]['title'], '雾中灯塔');
      expect(result.value.first['id'], '/d/1');
    });

    test('剧集记录按线路分组', () {
      final lines = linesFromRecords(
        [
          {'name': '第 1 集', 'url': '/p/1', 'line': '高清'},
          {'name': '第 2 集', 'url': '/p/2', 'line': '高清'},
          {'name': '第 1 集', 'url': '/s/1', 'line': '备用'},
        ],
        baseUrl: 'https://demo.poqi.local/detail/1',
        defaultLineName: '默认',
      );
      expect(lines.length, 2);
      expect(lines.first.name, '高清');
      expect(lines.first.episodes.length, 2);
      expect(lines.first.episodes.first.url, 'https://demo.poqi.local/p/1');
    });
  });

  group('演示引擎', () {
    test('首页与详情可运行', () async {
      final site = seedSites().first;
      final runner = DemoRunner(plugin: _demoPlugin, site: site);

      final home = await runner.home();
      expect(home.items, isNotEmpty);
      expect(home.items.length, lessThanOrEqualTo(24));
      expect(home.items.first.sourceId, site.id);

      final detail = await runner.detail(home.items.first.id);
      expect(detail.lines.length, 2);
      expect(detail.episodeCount, greaterThan(4));

      final source = await runner.play(detail.lines.first.episodes.first.url);
      expect(source.url, startsWith('demo://'));
    });

    test('搜索命中演示片库', () async {
      final runner = DemoRunner(plugin: _demoPlugin, site: seedSites().first);
      final page = await runner.search('长夜');
      expect(page.items, isNotEmpty);
      expect(page.items.first.title.contains('长夜'), isTrue);
    });
  });

  group('站点模型', () {
    test('健康状态推导', () {
      final base = seedSites().first;
      expect(healthOf(base.copyWith(lastCheckOk: null)), SiteHealth.unknown);
      expect(
        healthOf(base.copyWith(lastCheckOk: true, latencyMs: 120)),
        SiteHealth.ok,
      );
      expect(
        healthOf(base.copyWith(lastCheckOk: true, latencyMs: 4200)),
        SiteHealth.degraded,
      );
      expect(
        healthOf(base.copyWith(lastCheckOk: false)),
        SiteHealth.failed,
      );
      expect(healthOf(base.copyWith(enabled: false)), SiteHealth.unknown);
    });
  });

  test('演示片库字段完整', () {
    expect(DemoCatalog.items.length, greaterThan(20));
    for (final t in DemoCatalog.items) {
      expect(t.title.isNotEmpty, isTrue);
      expect(t.year, greaterThan(1990));
      expect(t.kind, isNotEmpty);
      expect(t.score, greaterThan(0));
    }
  });
}

/// 解析器测试用的最小上下文。
class ExprContextStub {
  static final base = ExprContext(vars: const {});
}


/// 演示引擎仍保留在 lib 中，但不再作为内置插件分发；测试用最小夹具驱动它。
const _demoPlugin = PluginManifest(
  id: 'poqi.demo.fixture',
  name: '演示夹具',
  version: '1.0.0',
  engine: PluginEngine.demo,
  baseUrl: 'https://demo.poqi.local',
);
