import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:poqi/domain/plugin/expr.dart';

void main() {
  group('表达式', () {
    test('成员访问与函数', () async {
      final ctx = ExprContext(vars: {
        'item': {'name': '  长夜将尽  ', 'year': 2026, 'score': '8.9'},
        'cfg': {'area': '内地'},
      });
      expect(await PExpr.eval('trim(item.name)', ctx), '长夜将尽');
      expect(await PExpr.eval('item.year', ctx), 2026);
      expect(await PExpr.eval('upper(item.name.trim())', ctx), '长夜将尽');
      expect(await PExpr.eval('cfg.area == "内地"', ctx), isTrue);
      expect(await PExpr.eval('item.score > 8 ? "推荐" : "普通"', ctx), '推荐');
    });

    test('字符串、编码与摘要', () async {
      final ctx = ExprContext();
      expect(await PExpr.eval("substr('abcdef', 1, 3)", ctx), 'bcd');
      expect(await PExpr.eval("replace('a-b-c', '-', '_')", ctx), 'a_b_c');
      final md5ish = await PExpr.eval("md5('poqi')", ctx) as String;
      expect(md5ish.length, 32);
      expect(await PExpr.eval("md5('poqi')", ctx), md5ish);
      expect((await PExpr.eval("sha1('poqi')", ctx) as String).length, 40);
      expect(await PExpr.eval("b64d(b64('中文'))", ctx), '中文');
      expect(await PExpr.eval("urlencode('a b')", ctx), 'a%20b');
    });

    test('集合与 JSON 路径', () async {
      final ctx = ExprContext(vars: {
        'data': {
          'list': [
            {'name': 'a', 'score': 1},
            {'name': 'b', 'score': 2},
          ]
        }
      });
      expect(await PExpr.eval('len(data.list)', ctx), 2);
      expect(await PExpr.eval('at(data, "list[1].name")', ctx), 'b');
      expect(await PExpr.eval('data.list[0].name', ctx), 'a');
      expect(await PExpr.eval("json('{\"x\": 3}').x", ctx), 3);
      expect(await PExpr.eval('coalesce("", null, "fallback")', ctx), 'fallback');
    });

    test('HTML 选择器', () async {
      final doc = html_parser.parse('''
        <div class="list">
          <div class="item"><a href="/detail/1"><h3>长夜将尽</h3></a><img data-src="/p/1.jpg"/></div>
          <div class="item"><a href="/detail/2"><h3>雾中灯塔</h3></a></div>
        </div>
      ''');
      final items = doc.querySelectorAll('.item');
      expect(items.length, 2);

      final ctx = ExprContext(vars: {'item': items.first});
      expect(await PExpr.eval("text(sel(item, 'h3'))", ctx), '长夜将尽');
      expect(await PExpr.eval("attr(sel(item, 'a'), 'href')", ctx), '/detail/1');
      expect(await PExpr.eval("attr(sel(item, 'img'), 'data-src')", ctx), '/p/1.jpg');
      expect(await PExpr.eval("selAll(item, 'a').length", ctx), 1);
    });

    test('相对地址补全', () async {
      final ctx = ExprContext(baseUrl: 'https://demo.poqi.local/list?p=2');
      expect(
        await PExpr.eval("resolve('/detail/1')", ctx),
        'https://demo.poqi.local/detail/1',
      );
      expect(
        await PExpr.eval("resolve('//cdn.poqi.local/a.jpg')", ctx),
        'https://cdn.poqi.local/a.jpg',
      );
    });

    test('模板渲染', () async {
      final ctx = ExprContext(vars: {
        'page': 3,
        'keyword': '长夜',
      });
      expect(
        await renderTemplate('/search?wd={{keyword}}&p={{page}}', ctx),
        '/search?wd=长夜&p=3',
      );
      expect(await renderTemplate('no template', ctx), 'no template');
    });

    test('语法错误会抛出 ExprException', () {
      expect(() => PExpr.validate('item.'), throwsA(isA<ExprException>()));
      expect(() => PExpr.validate("trim('a'"), throwsA(isA<ExprException>()));
    });

    test('未定义标识符返回 null 而不是崩溃', () async {
      expect(await PExpr.eval('missing.value', ExprContext()), isNull);
      expect(await PExpr.evalString('missing.value', ExprContext()), '');
    });
  });

  group('HTML 节点访问', () {
    test('属性与文本', () {
      final el = dom.Element.tag('a')
        ..attributes['href'] = '/x'
        ..text = ' 标题 ';
      final ctx = ExprContext(vars: {'item': el});
      expect(PExpr.toStr(el.text).trim(), '标题');
      expect(el.attributes['href'], '/x');
      expect(ctx.vars['item'], isNotNull);
    });
  });
}
