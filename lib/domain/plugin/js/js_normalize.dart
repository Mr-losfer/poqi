import '../../models/media.dart';
import '../expr.dart';
import '../parse.dart';

/// 把 JS 插件返回的裸结构归一成应用内的媒体模型。
///
/// 约定（与文档 docs/PLUGIN_SPEC.md 的「JS 引擎」一节一致）：
///
/// 列表端点返回数组，元素字段：
///   id / title（必填）、poster / year / area / remarks / score / kind / tags / intro
///
/// 详情端点返回对象，字段同上，外加：
///   lines:     [{ name, episodes: [{ name, url }] }]
///   episodes:  [{ name, url, line }]   （没有 lines 时按 line 分组）
///
/// 宽松处理：字段名大小写不敏感，数字/布尔会被转成字符串，
/// 缺 id 时用 title 兜底，缺 title 的条目直接丢弃（避免整页脏数据）。
class JsNormalizer {
  const JsNormalizer._();

  static String _str(Object? v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is num || v is bool) return '$v';
    return '';
  }

  static Map<String, Object?> _asMap(Object? v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry('$k', val));
    }
    return const {};
  }

  /// 大小写与下划线都不敏感的取值：`vod_name` / `vodName` / `VOD_NAME` 都能命中。
  static Object? pick(Map<String, Object?> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null) return m[k];
    }
    final lower = <String, Object?>{};
    for (final e in m.entries) {
      lower[e.key.toLowerCase().replaceAll('_', '')] = e.value;
    }
    for (final k in keys) {
      final hit = lower[k.toLowerCase().replaceAll('_', '')];
      if (hit != null) return hit;
    }
    return null;
  }

  static List<Map<String, Object?>> records(Object? raw) {
    if (raw is List) {
      return raw.whereType<Map>().map(_asMap).toList();
    }
    if (raw is Map) {
      // 允许脚本返回 { list: [...] } / { data: [...] } 这种包一层的形式
      for (final key in const ['list', 'data', 'items', 'videos']) {
        final v = raw[key];
        if (v is List) return v.whereType<Map>().map(_asMap).toList();
      }
    }
    return const [];
  }

  static List<MediaItem> items(
    Object? raw, {
    required String baseUrl,
    required String sourceId,
    required String sourceName,
  }) {
    final out = <MediaItem>[];
    for (final rec in records(raw)) {
      final item = itemFromRecord(
        rec,
        baseUrl: baseUrl,
        sourceId: sourceId,
        sourceName: sourceName,
      );
      if (item.title.isEmpty) continue;
      final id = item.id.trim().isEmpty ? item.title : item.id;
      out.add(item.copyWith(id: id));
    }
    return out;
  }

  static MediaDetail detail(
    Object? raw, {
    required String baseUrl,
    required String sourceId,
    required String sourceName,
    required String fallbackId,
  }) {
    final m = _asMap(raw is List ? (raw.isNotEmpty ? raw.first : null) : raw);
    final item = itemFromRecord(
      m,
      baseUrl: baseUrl,
      sourceId: sourceId,
      sourceName: sourceName,
    );
    final id = item.id.trim().isEmpty ? fallbackId : item.id;

    final lines = <PlayLine>[];

    // 1) 显式 lines
    final rawLines = pick(m, const ['lines', 'playLines']);
    if (rawLines is List) {
      for (final l in rawLines.whereType<Map>()) {
        final lm = _asMap(l);
        final name = _str(pick(lm, const ['name', 'line', 'from']));
        final epsRaw = pick(lm, const ['episodes', 'list', 'items']);
        final eps = <Episode>[];
        if (epsRaw is List) {
          for (final e in epsRaw.whereType<Map>()) {
            final em = _asMap(e);
            final url = resolveUrl(_str(pick(em, const ['url', 'playUrl', 'link'])), baseUrl);
            if (url.isEmpty) continue;
            eps.add(Episode(
              name: _str(pick(em, const ['name', 'title', 'episode'])),
              url: url,
            ));
          }
        }
        if (eps.isNotEmpty) {
          lines.add(PlayLine(name: name.isEmpty ? '线路${lines.length + 1}' : name, episodes: eps));
        }
      }
    }

    // 2) 扁平 episodes：[{name,url,line}]
    if (lines.isEmpty) {
      final epsRaw = pick(m, const ['episodes', 'playlist']);
      if (epsRaw is List) {
        final recs = <Map<String, Object?>>[];
        for (final e in epsRaw.whereType<Map>()) {
          final em = _asMap(e);
          final url = _str(pick(em, const ['url', 'playUrl', 'link']));
          if (url.isEmpty) continue;
          recs.add({
            'name': _str(pick(em, const ['name', 'title', 'episode'])),
            'url': url,
            'line': _str(pick(em, const ['line', 'from', 'group'])),
          });
        }
        lines.addAll(linesFromRecords(
          recs,
          baseUrl: baseUrl,
          defaultLineName: '默认线路',
        ));
      }
    }

    final actorsRaw = pick(m, const ['actors', 'vod_actor']);
    final actors = actorsRaw is List
        ? actorsRaw.map(_str).where((e) => e.isNotEmpty).toList()
        : _str(actorsRaw)
            .split(RegExp(r'[,，/、]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final intro = _str(pick(m, const ['intro', 'content', 'desc', 'description', 'vod_content']));

    return MediaDetail(
      item: item.copyWith(id: id),
      intro: intro.isEmpty ? null : intro,
      director: _str(pick(m, const ['director', 'vod_director'])).isEmpty
          ? null
          : _str(pick(m, const ['director', 'vod_director'])),
      actors: actors,
      lines: lines,
      fetchedAt: DateTime.now(),
    );
  }

  /// play 端点：脚本返回 `{url}` / 字符串 URL / null（表示直接用传入地址）。
  static String playUrl(Object? raw, {required String fallback}) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is Map) {
      final m = _asMap(raw);
      final v = _str(pick(m, const ['url', 'playUrl', 'link', 'src']));
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }
}
