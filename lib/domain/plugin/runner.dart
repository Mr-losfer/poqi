
import 'package:flutter/foundation.dart';

import '../../data/net/pq_http.dart';
import '../models/media.dart';
import '../models/plugin.dart';
import '../models/site.dart';
import 'demo_catalog.dart';
import 'expr.dart';
import 'js/js_bridge.dart';
import 'js/js_host.dart';
import 'js/js_normalize.dart';
import 'parse.dart';

/// 站点执行器：UI 只依赖这个接口，不关心是 HTTP 还是演示引擎。
abstract class SiteRunner {
  SiteBinding get site;
  PluginManifest get plugin;

  Future<MediaPage> home({int page = 1});
  Future<MediaPage> category({String? kind, Map<String, String> filters = const {}, int page = 1});
  Future<MediaPage> search(String keyword, {int page = 1});
  Future<MediaDetail> detail(String id);
  Future<PlaySource> play(String episodeUrl, {Map<String, String>? headers});
  Future<List<FilterGroup>> filters();
  Future<void> warmUp();
  List<HttpTraceEntry> get trace;
}

/// 变量缓存：token / cookie 这类需要定时刷新的值。
class VarCache {
  VarCache();

  final Map<String, _CachedValue> _store = {};
  final Map<String, Future<Object?>> _inflight = {};

  String _key(String siteId, String name) => '$siteId::$name';

  Object? peek(String siteId, String name) {
    final v = _store[_key(siteId, name)];
    if (v == null) return null;
    if (v.expiresAt != null && DateTime.now().isAfter(v.expiresAt!)) return null;
    return v.value;
  }

  void invalidate(String siteId, [String? name]) {
    if (name == null) {
      _store.removeWhere((k, _) => k.startsWith('$siteId::'));
    } else {
      _store.remove(_key(siteId, name));
    }
  }

  Future<Object?> resolve({
    required String siteId,
    required String name,
    required VarSpec spec,
    required Future<Object?> Function() compute,
  }) async {
    final cached = _store[_key(siteId, name)];
    if (cached != null && !cached.expired) return cached.value;

    final inflightKey = _key(siteId, name);
    final existing = _inflight[inflightKey];
    if (existing != null) return existing;

    final future = compute().then((value) {
      _store[inflightKey] = _CachedValue(
        value,
        spec.ttlSeconds > 0
            ? DateTime.now().add(Duration(seconds: spec.ttlSeconds))
            : null,
      );
      return value;
    }).whenComplete(() => _inflight.remove(inflightKey));

    _inflight[inflightKey] = future;
    return future;
  }
}

class _CachedValue {
  _CachedValue(this.value, this.expiresAt);

  final Object? value;
  final DateTime? expiresAt;

  bool get expired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// HTTP 插件执行器。
class HttpSiteRunner implements SiteRunner {
  HttpSiteRunner({
    required this.plugin,
    required this.site,
    required this.http,
    required this.varCache,
  });

  @override
  final PluginManifest plugin;
  @override
  final SiteBinding site;
  final PqHttp http;
  final VarCache varCache;

  /// JS 脚本的网络桥：`pq.http.get()` 的请求最终从这里发出。
  /// 挂在 runner 上，list → detail → play 之间就能复用同一份响应缓存。
  late final JsReplaySession jsSession = JsReplaySession(fetch: _fetchForJs);

  String get baseUrl =>
      site.baseUrl.trim().isNotEmpty ? site.baseUrl.trim() : plugin.baseUrl.trim();

  @override
  List<HttpTraceEntry> get trace => http.trace;

  @override
  Future<void> warmUp() async {
    // 预取带 TTL 的变量，减少首屏等待。
    for (final entry in plugin.vars.entries) {
      if (entry.value.ttlSeconds > 0) {
        try {
          await _vars();
          break;
        } catch (e) {
          debugPrint('warmUp 变量失败 ${entry.key}: $e');
        }
      }
    }
  }

  Map<String, Object?> _cfgMap() => Map<String, Object?>.from(site.config);

  /// 脚本发起的请求：加上插件的公共 headers，失败也返回结果（让脚本自己兜底）。
  Future<JsHttpResult> _fetchForJs(JsHttpRequest req) async {
    try {
      final resp = await http.request(
        url: req.url,
        method: req.method,
        headers: {...plugin.headers, ...req.headers},
        body: req.body,
        timeoutMs: req.timeoutMs,
      );
      return JsHttpResult(
        status: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
        finalUrl: resp.finalUrl,
      );
    } catch (e) {
      return JsHttpResult.failure('$e');
    }
  }

  /// 解析全部 vars（按需计算）。返回 name → value。
  Future<Map<String, Object?>> _vars() async {
    final out = <String, Object?>{};
    if (plugin.vars.isEmpty) return out;

    final cfg = _cfgMap();
    for (final entry in plugin.vars.entries) {
      final spec = entry.value;
      try {
        final value = await varCache.resolve(
          siteId: site.id,
          name: entry.key,
          spec: spec,
          compute: () async {
            final ctx = ExprContext(
              vars: {
                'cfg': cfg,
                'vars': out,
                'base': baseUrl,
                'site': site.name,
                'now': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              },
              baseUrl: baseUrl,
              onCall: _httpCall,
            );
            return PExpr.eval(spec.expr, ctx);
          },
        );
        out[entry.key] = value;
      } catch (e) {
        debugPrint('变量 ${entry.key} 解析失败: $e');
        out[entry.key] = '';
      }
    }
    return out;
  }

  /// 供表达式调用的异步能力：`http.get('/path', {query: {...}})`
  Future<Object?> _httpCall(String name, List<Object?> args) async {
    final path = args.isNotEmpty ? PExpr.toStr(args[0]) : '';
    final opts = args.length > 1 && args[1] is Map ? (args[1] as Map) : const {};
    final headers = <String, String>{};
    final query = <String, String>{};

    final h = opts['headers'];
    if (h is Map) {
      h.forEach((k, v) => headers['$k'] = PExpr.toStr(v));
    }
    final q = opts['query'];
    if (q is Map) {
      q.forEach((k, v) => query['$k'] = PExpr.toStr(v));
    }

    final url = path.startsWith('http') ? path : resolveUrl(path, baseUrl);
    final method = name.split('.').last.toUpperCase();
    final resp = await http.request(
      url: url,
      method: method,
      headers: {...plugin.headers, ...headers},
      query: query.isEmpty ? null : query,
      body: opts['body'],
    );
    if (!resp.ok) {
      throw PqHttpException('HTTP ${resp.statusCode}', statusCode: resp.statusCode, url: url);
    }
    final ct = resp.headers['content-type'] ?? '';
    if (ct.contains('json')) return resp.json;
    final decoded = resp.json;
    return decoded ?? resp.body;
  }

  Future<ExprContext> _context({
    int page = 1,
    String? keyword,
    String? category,
    String? id,
    Map<String, String> filters = const {},
  }) async {
    final vars = await _vars();
    return ExprContext(
      vars: {
        'cfg': _cfgMap(),
        'vars': vars,
        'page': page,
        'keyword': keyword ?? '',
        'category': category ?? '',
        'filters': filters,
        'id': id ?? '',
        'base': baseUrl,
        'site': site.name,
      },
      baseUrl: baseUrl,
      onCall: _httpCall,
    );
  }

  /// 把 Dart 侧的上下文交给 JS 函数，返回脚本产出的裸结构。
  Future<Object?> _callJs(
    EndpointSpec ep,
    String endpoint,
    ExprContext ctx,
    PqHttpResponse resp,
  ) {
    return JsHost.call(
      session: jsSession,
      pluginId: plugin.id,
      script: plugin.script,
      function: ep.jsFunctionFor(endpoint),
      context: {
        'endpoint': endpoint,
        'body': resp.body,
        'json': resp.json,
        'url': resp.finalUrl,
        'status': resp.statusCode,
        'headers': resp.headers,
        'base': baseUrl,
        'cfg': _cfgMap(),
        'vars': ctx.vars['vars'] ?? const <String, Object?>{},
        'page': ctx.vars['page'] ?? 1,
        'keyword': ctx.vars['keyword'] ?? '',
        'category': ctx.vars['category'] ?? '',
        'filters': ctx.vars['filters'] ?? const <String, String>{},
        'id': ctx.vars['id'] ?? '',
        'site': {'id': site.id, 'name': site.name},
        'now': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<Object?> _callJsPlay(
    EndpointSpec ep,
    ExprContext ctx,
    PqHttpResponse? resp,
    String episodeUrl,
  ) {
    return JsHost.call(
      session: jsSession,
      pluginId: plugin.id,
      script: plugin.script,
      function: ep.jsFunctionFor('play'),
      context: {
        'endpoint': 'play',
        'body': resp?.body ?? '',
        'json': resp?.json,
        'url': resp?.finalUrl ?? episodeUrl,
        'status': resp?.statusCode ?? 0,
        'headers': resp?.headers ?? const <String, String>{},
        'base': baseUrl,
        'cfg': _cfgMap(),
        'vars': ctx.vars['vars'] ?? const <String, Object?>{},
        'page': 1,
        'keyword': '',
        'category': '',
        'filters': const <String, String>{},
        // 播放端点里 id 就是剧集地址，脚本可直接返回它。
        'id': episodeUrl,
        'site': {'id': site.id, 'name': site.name},
        'now': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  Future<PqHttpResponse> _send(
    EndpointSpec ep,
    ExprContext ctx, {
    Map<String, String> extraQuery = const {},
  }) async {
    final path = await renderTemplate(ep.request.path, ctx);
    final url = path.startsWith('http') ? path : resolveUrl(path, baseUrl);

    final query = <String, String>{};
    for (final e in ep.request.query.entries) {
      final v = await renderTemplate(e.value, ctx);
      if (v.isNotEmpty) query[e.key] = v;
    }
    query.addAll(extraQuery);

    final headers = <String, String>{...plugin.headers};
    for (final e in ep.request.headers.entries) {
      headers[e.key] = await renderTemplate(e.value, ctx);
    }

    Object? body;
    if (ep.request.body != null) {
      body = await renderDeep(ep.request.body, ctx);
    }

    return http.request(
      url: url,
      method: ep.request.method,
      headers: headers,
      query: query.isEmpty ? null : query,
      body: body,
      timeoutMs: ep.request.timeoutMs,
    );
  }

  Future<MediaPage> _list(
    String endpointName, {
    int page = 1,
    String? keyword,
    String? category,
    Map<String, String> filters = const {},
  }) async {
    // 脚本插件不一定写了 category()，这时退回 home()：分类只是多传一个参数。
    final ep = plugin.endpoints[endpointName] ??
        (endpointName == 'category' ? plugin.endpoints['home'] : null);
    if (ep == null) throw PqHttpException('插件未声明 $endpointName 端点');
    final useJs = plugin.engine == PluginEngine.js;
    final parse = ep.parse;
    if (parse == null && !useJs) {
      throw PqHttpException('$endpointName 缺少 parse 配置（JS 插件则应提供 script）');
    }

    final ctx = await _context(
      page: page,
      keyword: keyword,
      category: category,
      filters: filters,
    );
    final query = <String, String>{
      if (keyword != null && keyword.isNotEmpty) 'wd': keyword,
      if (category != null && category.isNotEmpty) 't': category,
      ...filters,
    };

    // 脚本插件（request.path 为空）自己发请求，Dart 不再预取。
    final PqHttpResponse resp;
    if (useJs && ep.request.path.trim().isEmpty) {
      resp = PqHttpResponse(
        statusCode: 200,
        body: '',
        headers: const {},
        finalUrl: baseUrl,
      );
    } else {
      resp = await _send(ep, ctx, extraQuery: query);
      if (!resp.ok) {
        throw PqHttpException(
          'HTTP ${resp.statusCode}',
          statusCode: resp.statusCode,
          url: resp.finalUrl,
        );
      }
    }

    if (useJs) {
      final raw = await _callJs(ep, endpointName, ctx, resp);
      final items = JsNormalizer.items(
        raw,
        baseUrl: resp.finalUrl,
        sourceId: site.id,
        sourceName: site.name,
      );
      final scripted = raw is Map && raw['hasMore'] is bool ? raw['hasMore'] as bool : null;
      final hasMore = scripted ??
          (ep.pageSize != null ? items.length >= ep.pageSize! : items.length >= 12);
      return MediaPage(items: items, page: page, hasMore: hasMore);
    }

    final parsed = await DeclarativeParser().records(
      spec: parse!,
      body: resp.body,
      url: resp.finalUrl,
      base: ctx,
    );

    final items = <MediaItem>[];
    for (final rec in parsed.value) {
      final item = itemFromRecord(
        rec,
        baseUrl: resp.finalUrl,
        sourceId: site.id,
        sourceName: site.name,
      );
      if (item.title.isEmpty || item.id.isEmpty) continue;
      items.add(item);
    }

    final hasMore = ep.pageSize != null ? items.length >= ep.pageSize! : items.length >= 12;
    return MediaPage(items: items, page: page, hasMore: hasMore);
  }

  @override
  Future<MediaPage> home({int page = 1}) => _list('home', page: page);

  @override
  Future<MediaPage> category({
    String? kind,
    Map<String, String> filters = const {},
    int page = 1,
  }) =>
      _list('category', page: page, category: kind, filters: filters);

  @override
  Future<MediaPage> search(String keyword, {int page = 1}) =>
      _list('search', page: page, keyword: keyword);

  @override
  Future<List<FilterGroup>> filters() async {
    final ep = plugin.endpoints['category'];
    if (ep == null || ep.filters.isEmpty) return const [];
    final ctx = await _context();
    final out = <FilterGroup>[];
    for (final g in ep.filters) {
      out.add(FilterGroup(
        key: g.key,
        label: g.label,
        values: [for (final v in g.values) await renderTemplate(v, ctx)],
      ));
    }
    return out;
  }

  @override
  Future<MediaDetail> detail(String id) async {
    final ep = plugin.endpoints['detail'];
    if (ep == null) throw PqHttpException('插件未声明 detail 端点');
    final useJs = plugin.engine == PluginEngine.js;
    final parse = ep.parse;
    if (parse == null && !useJs) throw PqHttpException('detail 缺少 parse 配置');

    final ctx = await _context(id: id);
    final PqHttpResponse resp;
    if (useJs && ep.request.path.trim().isEmpty) {
      resp = PqHttpResponse(
        statusCode: 200,
        body: '',
        headers: const {},
        finalUrl: baseUrl,
      );
    } else {
      resp = await _send(ep, ctx);
      if (!resp.ok) {
        throw PqHttpException('HTTP ${resp.statusCode}', statusCode: resp.statusCode, url: resp.finalUrl);
      }
    }

    if (useJs) {
      final raw = await _callJs(ep, 'detail', ctx, resp);
      final detail = JsNormalizer.detail(
        raw,
        baseUrl: resp.finalUrl,
        sourceId: site.id,
        sourceName: site.name,
        fallbackId: id,
      );
      if (detail.item.title.isEmpty) {
        throw PluginParseException('JS 详情返回为空，检查 detail() 的返回值', resp.finalUrl);
      }
      return detail;
    }

    final parsed = await DeclarativeParser().records(
      spec: parse!,
      body: resp.body,
      url: resp.finalUrl,
      base: ctx,
    );
    if (parsed.value.isEmpty) {
      throw PluginParseException('详情解析为空，请检查 detail.parse 选择器', resp.finalUrl);
    }
    final rec = parsed.value.first;
    final item = itemFromRecord(
      rec,
      baseUrl: resp.finalUrl,
      sourceId: site.id,
      sourceName: site.name,
    ).copyWith(
      id: PExpr.toStr(rec['id']).trim().isEmpty ? id : PExpr.toStr(rec['id']).trim(),
    );

    final lines = <PlayLine>[];
    if (parse.episodes != null) {
      final epSpec = parse.episodes!;
      if (epSpec.format == ParseFormat.split) {
        // split 分支不针对响应体，而是对详情记录（rec）求值后再拆分。
        final epCtx = ctx.child({'item': rec, 'index': 0, 'total': 1});
        var rawPlay = '';
        var rawNames = '';
        try {
          rawPlay = await PExpr.evalString(epSpec.from ?? '', epCtx);
          if ((epSpec.lineNames ?? '').trim().isNotEmpty) {
            rawNames = await PExpr.evalString(epSpec.lineNames!, epCtx);
          }
        } catch (e) {
          debugPrint('split 剧集表达式失败：$e');
        }
        final episodes = splitEpisodes(
          rawPlay,
          lineNames: rawNames,
          lineSep: epSpec.lineSep,
          itemSep: epSpec.itemSep,
          pairSep: epSpec.pairSep,
        );
        lines.addAll(linesFromRecords(
          episodes,
          baseUrl: resp.finalUrl,
          defaultLineName: '默认线路',
        ));
      } else {
        final eps = await DeclarativeParser().records(
          spec: epSpec,
          body: resp.body,
          url: resp.finalUrl,
          base: ctx,
        );
        lines.addAll(linesFromRecords(
          eps.value,
          baseUrl: resp.finalUrl,
          defaultLineName: '默认线路',
        ));
      }
    } else if (rec['episodes'] is List) {
      final raw = rec['episodes'] as List;
      final eps = <Map<String, Object?>>[];
      for (final e in raw) {
        if (e is Map) {
          eps.add({
            'name': '${e['name'] ?? e['title'] ?? ''}',
            'url': '${e['url'] ?? e['link'] ?? ''}',
          });
        } else {
          eps.add({'name': '', 'url': '$e'});
        }
      }
      lines.addAll(linesFromRecords(
        eps,
        baseUrl: resp.finalUrl,
        defaultLineName: '默认线路',
      ));
    }

    final actors = [PExpr.toStr(rec['actors'])]
        .expand((e) => e.split(RegExp(r'[,，/|]')))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return MediaDetail(
      item: item,
      intro: PExpr.toStr(rec['intro']).trim().isEmpty ? null : PExpr.toStr(rec['intro']).trim(),
      director: PExpr.toStr(rec['director']).trim().isEmpty ? null : PExpr.toStr(rec['director']).trim(),
      actors: actors,
      lines: lines,
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Future<PlaySource> play(String episodeUrl, {Map<String, String>? headers}) async {
    final ep = plugin.endpoints['play'];
    if (ep == null) {
      return PlaySource(url: episodeUrl, headers: {...plugin.headers, ...?headers});
    }
    final ctx = await _context(id: episodeUrl);

    // 约定：play.request.path 为空表示"不需要再请求"，
    // 直接对空响应体求值 parse.fields（常见于剧集地址即播放地址的 CMS）。
    final skipRequest = ep.request.path.trim().isEmpty;
    PqHttpResponse? resp;
    if (!skipRequest) {
      resp = await _send(ep, ctx, extraQuery: {'url': episodeUrl});
      if (!resp.ok) {
        throw PqHttpException('HTTP ${resp.statusCode}', statusCode: resp.statusCode, url: resp.finalUrl);
      }
    }
    if (plugin.engine == PluginEngine.js) {
      final raw = await _callJsPlay(ep, ctx, resp, episodeUrl);
      var playUrl = JsNormalizer.playUrl(raw, fallback: episodeUrl).trim();
      if (playUrl.isEmpty) playUrl = episodeUrl;
      if (!playUrl.startsWith('http') && !playUrl.startsWith('rtmp')) {
        playUrl = resolveUrl(playUrl, episodeUrl);
      }
      return PlaySource(
        url: playUrl,
        headers: {...plugin.headers, ...?headers},
        kind: _kindOf(playUrl),
      );
    }

    final parse = ep.parse;
    if (parse == null) return PlaySource(url: episodeUrl);

    if (skipRequest) {
      // 无请求模式：只对 parse.fields 求值，典型写法是 `"url": "{{id}}"`。
      final field = parse.fields['url'];
      var playUrl = '';
      if (field != null) {
        playUrl = field.contains('{{')
            ? await renderTemplate(field, ctx)
            : PExpr.toStr(await PExpr.eval(field, ctx));
        playUrl = playUrl.trim();
      }
      if (playUrl.isEmpty) playUrl = episodeUrl;
      if (!playUrl.startsWith('http') && !playUrl.startsWith('rtmp')) {
        playUrl = resolveUrl(playUrl, episodeUrl);
      }
      return PlaySource(
        url: playUrl,
        headers: {...plugin.headers, ...?headers},
        kind: _kindOf(playUrl),
      );
    }

    final parsed = await DeclarativeParser().records(
      spec: parse,
      body: resp?.body ?? '',
      url: resp?.finalUrl ?? episodeUrl,
      base: ctx,
    );
    if (parsed.value.isEmpty) {
      throw PluginParseException('播放地址解析为空', resp?.finalUrl ?? episodeUrl);
    }
    final rec = parsed.value.first;
    var playUrl = PExpr.toStr(rec['url']).trim();
    if (playUrl.isEmpty) playUrl = episodeUrl;
    if (!playUrl.startsWith('http') && !playUrl.startsWith('rtmp')) {
      playUrl = resolveUrl(playUrl, resp?.finalUrl ?? episodeUrl);
    }
    final headerMap = <String, String>{...plugin.headers};
    if (rec['headers'] is Map) {
      (rec['headers'] as Map).forEach((k, v) => headerMap['$k'] = PExpr.toStr(v));
    }
    return PlaySource(
      url: playUrl,
      headers: headerMap,
      kind: _kindOf(playUrl),
    );
  }

  PlayKind _kindOf(String url) {
    final u = url.toLowerCase();
    if (u.contains('.m3u8')) return PlayKind.hls;
    if (u.contains('.mp4')) return PlayKind.mp4;
    if (u.contains('.flv')) return PlayKind.flv;
    return PlayKind.auto;
  }
}

SiteRunner runnerFor({
  required PluginManifest plugin,
  required SiteBinding site,
  required PqHttp http,
  required VarCache varCache,
}) {
  switch (plugin.engine) {
    case PluginEngine.demo:
      return DemoRunner(plugin: plugin, site: site);
    // JS 引擎复用 HTTP 引擎的请求管线（模板渲染、headers、vars、超时、trace），
    // 只在"响应 → 标准结构"这一步换成脚本求值，所以是同一个 runner。
    case PluginEngine.http:
    case PluginEngine.js:
      return HttpSiteRunner(
        plugin: plugin,
        site: site,
        http: http,
        varCache: varCache,
      );
  }
}

/// 演示引擎：随包分发的可运行样例，用来验证 UI 与聚合逻辑。
class DemoRunner implements SiteRunner {
  DemoRunner({required this.plugin, required this.site});

  @override
  final PluginManifest plugin;
  @override
  final SiteBinding site;

  @override
  List<HttpTraceEntry> get trace {
    final now = DateTime.now();
    return [
      HttpTraceEntry(
        method: 'DEMO',
        url: 'demo://${plugin.id}',
        startedAt: now,
        status: 200,
        durationMs: 12,
        bytes: 0,
        preview: '内置演示数据',
      ),
    ];
  }

  int get _offset {
    var h = 0;
    for (final c in site.id.codeUnits) {
      h = (h * 17 + c) & 0xff;
    }
    return h;
  }

  @override
  Future<void> warmUp() async {}

  @override
  Future<List<FilterGroup>> filters() async => const [
        FilterGroup(key: 'area', label: '地区', values: ['全部', '内地', '港台', '日韩', '欧美']),
        FilterGroup(key: 'year', label: '年份', values: ['全部', '2026', '2025', '2024', '2023', '更早']),
        FilterGroup(key: 'sort', label: '排序', values: ['最新', '最热', '评分']),
      ];

  @override
  Future<MediaPage> home({int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    final all = DemoCatalog.items;
    final rotated = [
      for (var i = 0; i < all.length; i++) all[(i + _offset + (page - 1) * 6) % all.length],
    ];
    return MediaPage(items: rotated.take(24).map(_decorate).toList(), page: page, hasMore: page < 3);
  }

  @override
  Future<MediaPage> category({
    String? kind,
    Map<String, String> filters = const {},
    int page = 1,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    var items = DemoCatalog.items.where((e) {
      if (kind == null || kind.isEmpty || kind == '全部') return true;
      return e.kind == kind;
    }).toList();
    final area = filters['area'];
    if (area != null && area != '全部') {
      items = items.where((e) => e.area == area).toList();
    }
    if (items.isEmpty) items = DemoCatalog.items.take(8).toList();
    return MediaPage(items: items.map(_decorate).toList(), page: page, hasMore: false);
  }

  @override
  Future<MediaPage> search(String keyword, {int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 420));
    final k = keyword.trim().toLowerCase();
    final hits = DemoCatalog.items.where((e) {
      return e.title.toLowerCase().contains(k) ||
          (e.actors ?? '').toLowerCase().contains(k) ||
          e.kind.toLowerCase().contains(k);
    }).toList();
    return MediaPage(items: hits.map(_decorate).toList(), page: page, hasMore: false);
  }

  @override
  Future<MediaDetail> detail(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final base = DemoCatalog.items.firstWhere(
      (e) => e.title == id || '${e.title.hashCode}' == id,
      orElse: () => DemoCatalog.items.first,
    );
    final count = 12 + (base.title.length % 12);
    final lines = <PlayLine>[
      PlayLine(
        name: '高清线路',
        episodes: [
          for (var i = 1; i <= count; i++)
            Episode(
              name: '第 $i 集',
              url: 'demo://${base.title}/hd/$i',
              index: i - 1,
            ),
        ],
      ),
      PlayLine(
        name: '备用线路',
        episodes: [
          for (var i = 1; i <= count; i++)
            Episode(
              name: '第 $i 集',
              url: 'demo://${base.title}/sd/$i',
              index: i - 1,
            ),
        ],
      ),
    ];
    return MediaDetail(
      item: _decorate(base),
      intro: base.intro,
      director: base.director,
      actors: (base.actors ?? '').split(',').where((e) => e.isNotEmpty).toList(),
      lines: lines,
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Future<PlaySource> play(String episodeUrl, {Map<String, String>? headers}) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return PlaySource(
      url: episodeUrl,
      headers: headers ?? const {},
      kind: PlayKind.auto,
      title: episodeUrl.split('/').last,
    );
  }

  MediaItem _decorate(DemoTitle t) => MediaItem(
        id: t.title,
        title: t.title,
        poster: null,
        year: '${t.year}',
        score: t.score.toStringAsFixed(1),
        remarks: t.remarks,
        area: t.area,
        kind: t.kind,
        tags: t.tags,
        sourceId: site.id,
        sourceName: site.name,
      );
}
