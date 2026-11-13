import 'dart:convert';

/// JS 脚本发起的一次网络请求。
class JsHttpRequest {
  const JsHttpRequest({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.timeoutMs = 20000,
  });

  final String url;
  final String method;
  final Map<String, String> headers;
  final String? body;
  final int timeoutMs;

  /// 缓存键：和 JS 侧 `__poqiHttpKey()` 必须逐字一致。
  String get key => '${method.toUpperCase()} $url ${body ?? ''}';

  Map<String, Object?> toJson() => {
        'url': url,
        'method': method.toUpperCase(),
        'headers': headers,
        'body': body,
        'timeoutMs': timeoutMs,
      };

  factory JsHttpRequest.fromJson(Map<String, Object?> j) => JsHttpRequest(
        url: '${j['url'] ?? ''}',
        method: '${j['method'] ?? 'GET'}',
        headers: (j['headers'] as Map?)
                ?.map((k, v) => MapEntry('$k', '$v'))
                .cast<String, String>() ??
            const {},
        body: j['body'] == null ? null : '${j['body']}',
        timeoutMs: (j['timeoutMs'] as num?)?.toInt() ?? 20000,
      );

  static JsHttpRequest? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return JsHttpRequest.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      // 解析失败按「没有待办请求」处理，交给上层报原始错误。
    }
    return null;
  }
}

/// 一次请求的结果。失败也正常返回，让脚本自己决定怎么办。
class JsHttpResult {
  const JsHttpResult({
    required this.status,
    required this.body,
    this.headers = const {},
    this.finalUrl = '',
    this.error,
  });

  final int status;
  final String body;
  final Map<String, String> headers;
  final String finalUrl;
  final String? error;

  bool get ok => error == null && status >= 200 && status < 400;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'status': status,
        'body': body,
        'headers': headers,
        'url': finalUrl,
        'error': error ?? '',
      };

  static JsHttpResult failure(String message) =>
      JsHttpResult(status: 0, body: '', finalUrl: '', error: message);
}

/// 脚本在「拿不到数据」时抛出的信号，携带它想要的请求。
class JsNeedRequest implements Exception {
  JsNeedRequest(this.request);

  final JsHttpRequest request;

  @override
  String toString() => '需要请求 ${request.method} ${request.url}';
}

/// 同步脚本 × 异步网络的桥。
///
/// 做法是「重放」：脚本每次从头执行，`pq.http.*` 命中缓存就返回，
/// 没命中就抛出 [JsNeedRequest]。宿主执行真实请求、写进缓存，
/// 再把脚本重跑一遍，直到不再产生新请求。
///
/// 为什么不用回调/协程：QuickJS 是同步求值的，跨语言回调会把事件循环
/// 卡死；重放虽然多跑几遍脚本，但每次都是纯计算（毫秒级），
/// 换来的是「插件里可以直接写同步代码」这种最好用的形态。
class JsReplaySession {
  JsReplaySession({
    required this.fetch,
    this.maxRounds = 16,
    this.cacheTtl = const Duration(seconds: 90),
    this.maxCache = 60,
  });

  /// 真正的网络执行器，由 runner 注入（带站点 UA / 超时 / 代理）。
  final Future<JsHttpResult> Function(JsHttpRequest request) fetch;

  /// 最多重放多少轮，防止脚本写出死循环。
  final int maxRounds;

  /// 单条响应的复用时间。列表 → 详情通常是连续点击，这个窗口够用。
  final Duration cacheTtl;

  /// 缓存条数上限，避免整季剧集把内存吃满。
  final int maxCache;

  final Map<String, _Entry> _entries = {};
  final List<String> _order = [];

  /// 调试信息：本次执行实际发了几次网络请求。
  int lastFetchCount = 0;

  Map<String, JsHttpResult> snapshot() {
    _purge();
    return {for (final e in _entries.entries) e.key: e.value.result};
  }

  /// 执行一轮脚本；遇到 [JsNeedRequest] 就补数据后重来。
  Future<T> run<T>(T Function() round) async {
    lastFetchCount = 0;
    for (var i = 0; i < maxRounds; i++) {
      try {
        return round();
      } on JsNeedRequest catch (need) {
        final req = need.request;
        if (_entries.containsKey(req.key) && !_expired(_entries[req.key]!)) {
          // 缓存里明明有，脚本却还在要 —— 说明键对不上，直接报错比死循环好。
          throw JsPluginRuntimeException(
            '脚本重复请求同一个地址（缓存键未命中）：${req.method} ${req.url}',
          );
        }
        final result = await fetch(req);
        lastFetchCount++;
        _put(req.key, result);
        // 请求完必须重跑：JS 侧这一轮已经在抛异常处中断了。
      }
    }
    throw JsPluginRuntimeException('请求链过长（超过 $maxRounds 轮），检查脚本是否在循环里发请求');
  }

  void _put(String key, JsHttpResult result) {
    _entries[key] = _Entry(result, DateTime.now());
    _order.remove(key);
    _order.add(key);
    while (_order.length > maxCache) {
      final drop = _order.removeAt(0);
      _entries.remove(drop);
    }
  }

  bool _expired(_Entry e) => DateTime.now().difference(e.at) > cacheTtl;

  void _purge() {
    final dead = <String>[];
    for (final e in _entries.entries) {
      if (_expired(e.value)) dead.add(e.key);
    }
    for (final k in dead) {
      _entries.remove(k);
      _order.remove(k);
    }
  }

  void clear() {
    _entries.clear();
    _order.clear();
  }
}

class _Entry {
  _Entry(this.result, this.at);

  final JsHttpResult result;
  final DateTime at;
}

class JsPluginRuntimeException implements Exception {
  JsPluginRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}
