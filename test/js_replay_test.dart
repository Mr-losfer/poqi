import 'package:flutter_test/flutter_test.dart';
import 'package:poqi/domain/plugin/js/js_bridge.dart';

/// 「同步脚本 × 异步网络」的重放调度。
///
/// 这段逻辑决定了一次插件调用会不会卡死、会不会无限重试、会不会把
/// 过期数据当成新数据，值得单独测。QuickJS 在 Dart VM 里加载不了，
/// 所以这里只测调度器本身，脚本层的行为由 tool/js_runtime_test.js 覆盖。
void main() {
  JsHttpRequest req(String url, {String method = 'GET', String? body}) =>
      JsHttpRequest(url: url, method: method, body: body);

  test('第一次抛需求 → 补数据 → 重跑拿到结果', () async {
    var fetches = 0;
    var rounds = 0;
    final session = JsReplaySession(fetch: (r) async {
      fetches++;
      return JsHttpResult(status: 200, body: 'hello', finalUrl: r.url);
    });

    final out = await session.run(() {
      rounds++;
      final cache = session.snapshot();
      final key = req('https://a/1').key;
      if (!cache.containsKey(key)) throw JsNeedRequest(req('https://a/1'));
      return cache[key]!.body;
    });

    expect(out, 'hello');
    expect(fetches, 1);
    expect(rounds, 2, reason: '一轮发现缺数据，一轮拿结果');
  });

  test('两个请求串起来：第二个依赖第一个的地址', () async {
    final calls = <String>[];
    final session = JsReplaySession(fetch: (r) async {
      calls.add(r.url);
      return JsHttpResult(
        status: 200,
        body: r.url.endsWith('/1') ? 'next:/2' : 'done',
        finalUrl: r.url,
      );
    });

    final out = await session.run(() {
      final cache = session.snapshot();
      final first = cache[req('https://a/1').key];
      if (first == null) throw JsNeedRequest(req('https://a/1'));
      final second = cache[req('https://a/2').key];
      if (second == null) throw JsNeedRequest(req('https://a/2'));
      return '${first.body}|${second.body}';
    });

    expect(out, 'next:/2|done');
    expect(calls, ['https://a/1', 'https://a/2']);
  });

  test('失败也会写进缓存，不会无限重试', () async {
    var fetches = 0;
    final session = JsReplaySession(fetch: (r) async {
      fetches++;
      return JsHttpResult.failure('连接被重置');
    });

    final out = await session.run(() {
      final cache = session.snapshot();
      final key = req('https://a/1').key;
      if (!cache.containsKey(key)) throw JsNeedRequest(req('https://a/1'));
      return cache[key]!.ok;
    });

    expect(out, false);
    expect(fetches, 1);
  });

  test('缓存里明明有却还在要 → 报错而不是死循环', () async {
    final session = JsReplaySession(
      fetch: (r) async => JsHttpResult(status: 200, body: 'x', finalUrl: r.url),
    );

    // 第一次正常补数据
    var asked = false;
    await session.run(() {
      if (!asked) {
        asked = true;
        throw JsNeedRequest(req('https://a/1'));
      }
      return null;
    });

    // 然后模拟「键对不上」：脚本反复要同一个已经缓存的地址
    await expectLater(
      session.run(() {
        final cache = session.snapshot();
        if (cache.isEmpty) throw JsNeedRequest(req('https://a/1'));
        // 故意抛一个已缓存的请求
        throw JsNeedRequest(req('https://a/1'));
      }),
      throwsA(isA<JsPluginRuntimeException>()),
    );
  });

  test('轮数上限兜底', () async {
    var n = 0;
    final session = JsReplaySession(
      maxRounds: 3,
      fetch: (r) async => JsHttpResult(status: 200, body: 'x', finalUrl: r.url),
    );

    await expectLater(
      session.run(() => throw JsNeedRequest(req('https://a/${n++}'))),
      throwsA(isA<JsPluginRuntimeException>()),
    );
    expect(n, 3);
  });

  test('TTL 过期后会重新请求', () async {
    var fetches = 0;
    final session = JsReplaySession(
      cacheTtl: const Duration(milliseconds: 1),
      fetch: (r) async {
        fetches++;
        return JsHttpResult(status: 200, body: 'v$fetches', finalUrl: r.url);
      },
    );

    Future<String> once() => session.run(() {
          final cache = session.snapshot();
          final key = req('https://a/1').key;
          if (!cache.containsKey(key)) throw JsNeedRequest(req('https://a/1'));
          return cache[key]!.body;
        });

    expect(await once(), 'v1');
    await Future<void>.delayed(const Duration(milliseconds: 3));
    expect(await once(), 'v2', reason: '超过 TTL 要重新请求');
    expect(fetches, 2);
  });

  test('缓存条数有上限，超出按先进先出淘汰', () async {
    final session = JsReplaySession(
      maxCache: 2,
      fetch: (r) async => JsHttpResult(status: 200, body: r.url, finalUrl: r.url),
    );

    for (var i = 0; i < 3; i++) {
      var asked = false;
      await session.run(() {
        if (!asked) {
          asked = true;
          throw JsNeedRequest(req('https://a/$i'));
        }
        return null;
      });
    }

    final cache = session.snapshot();
    expect(cache.length, 2);
    expect(cache.containsKey(req('https://a/0').key), isFalse, reason: '最早的被淘汰');
    expect(cache.containsKey(req('https://a/2').key), isTrue);
  });

  test('缓存键区分 method 与 body', () {
    expect(req('https://a/1').key, 'GET https://a/1 ');
    expect(req('https://a/1', method: 'post').key, 'POST https://a/1 ');
    expect(req('https://a/1', method: 'POST', body: 'x').key, isNot(req('https://a/1').key));
  });
}
