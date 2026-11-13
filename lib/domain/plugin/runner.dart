
import 'package:flutter/foundation.dart';

import '../../data/net/pq_http.dart';
import '../models/media.dart';
import '../models/plugin.dart';
import '../models/site.dart';
import 'demo_catalog.dart';
import 'expr.dart';
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
    final ep = plugin.endpoints[endpointName];
    if (ep == null) throw PqHttpException('插件未声明 $endpointName 端点');
    final parse = ep.parse;
    if (parse == null) throw PqHttpException('$endpointName 缺少 parse 配置');

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

    final resp = await _send(ep, ctx, extraQuery: query);
    if (!resp.ok) {
      throw PqHttpException(
        'HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
        url: resp.finalUrl,
      );
    }

    final parsed = await DeclarativeParser().records(
      spec: parse,
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
    final parse = ep.parse;
    if (parse == null) throw PqHttpException('detail 缺少 parse 配置');

    final ctx = await _context(id: id);
    final resp = await _send(ep, ctx);
    if (!resp.ok) {
      throw PqHttpException('HTTP ${resp.statusCode}', statusCode: resp.statusCode, url: resp.finalUrl);
    }

    final parsed = await DeclarativeParser().records(
      spec: parse,
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
      final eps = await DeclarativeParser().records(
        spec: parse.episodes!,
        body: resp.body,
        url: resp.finalUrl,
        base: ctx,
      );
      lines.addAll(linesFromRecords(
        eps.value,
        baseUrl: resp.finalUrl,
        defaultLineName: '默认线路',
      ));
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
    final resp = await _send(ep, ctx, extraQuery: {'url': episodeUrl});
    if (!resp.ok) {
      throw PqHttpException('HTTP ${resp.statusCode}', statusCode: resp.statusCode, url: resp.finalUrl);
    }
    final parse = ep.parse;
    if (parse == null) return PlaySource(url: episodeUrl);

    final parsed = await DeclarativeParser().records(
      spec: parse,
      body: resp.body,
      url: resp.finalUrl,
      base: ctx,
    );
    if (parsed.value.isEmpty) {
      throw PluginParseException('播放地址解析为空', resp.finalUrl);
    }
    final rec = parsed.value.first;
    var playUrl = PExpr.toStr(rec['url']).trim();
    if (playUrl.isEmpty) playUrl = episodeUrl;
    if (!playUrl.startsWith('http') && !playUrl.startsWith('rtmp')) {
      playUrl = resolveUrl(playUrl, resp.finalUrl);
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
    case PluginEngine.http:
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
