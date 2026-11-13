import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/media.dart';
import '../models/plugin.dart';
import 'expr.dart';

/// 解析结果 + 诊断信息。
class ParseResult<T> {
  ParseResult(this.value, {this.warnings = const []});

  final T value;
  final List<String> warnings;
}

/// 声明式解析器：把 JSON / HTML / 正则 三种来源统一成"记录列表"。
class DeclarativeParser {
  const DeclarativeParser();

  /// 把响应体解析成一组记录（Map）。
  ///
  /// 每条记录都会被当作 `item` 注入表达式上下文，
  /// 外加 `index`（序号）与 `total`。
  Future<ParseResult<List<Map<String, Object?>>>> records({
    required ParseSpec spec,
    required String body,
    required String url,
    required ExprContext base,
  }) async {
    final warnings = <String>[];
    final out = <Map<String, Object?>>[];

    switch (spec.format) {
      case ParseFormat.json:
        Object? decoded;
        try {
          decoded = body.trim().isEmpty ? null : jsonDecode(body);
        } catch (e) {
          throw PluginParseException('响应不是合法 JSON：${_short(e.toString())}', url);
        }
        final root = _navigate(decoded, spec.root);
        final list = root is List ? root : (root == null ? const [] : [root]);
        if (list.isEmpty && root == null) {
          warnings.add('root "${spec.root ?? ''}" 未命中任何节点');
        }
        for (var i = 0; i < list.length; i++) {
          final node = list[i];
          final rec = <String, Object?>{};
          for (final e in spec.fields.entries) {
            final ctx = base.child({
              'item': node,
              'index': i,
              'total': list.length,
            });
            try {
              rec[e.key] = e.value.contains('{{')
                  ? await renderTemplate(e.value, ctx)
                  : await PExpr.eval(e.value, ctx);
            } catch (err) {
              warnings.add('字段 ${e.key}: ${_short(err.toString())}');
              rec[e.key] = null;
            }
          }
          out.add(rec);
        }
        return ParseResult(out, warnings: warnings);

      case ParseFormat.html:
        final doc = html_parser.parse(body);
        final nodes = _selectNodes(doc, spec.root);
        if (nodes.isEmpty) warnings.add('选择器 "${spec.root ?? 'body'}" 未命中任何节点');
        for (var i = 0; i < nodes.length; i++) {
          final node = nodes[i];
          final rec = <String, Object?>{};
          for (final e in spec.fields.entries) {
            final ctx = base.child({
              'item': node,
              'index': i,
              'total': nodes.length,
            });
            try {
              rec[e.key] = e.value.contains('{{')
                  ? await renderTemplate(e.value, ctx)
                  : await PExpr.eval(e.value, ctx);
            } catch (err) {
              warnings.add('字段 ${e.key}: ${_short(err.toString())}');
              rec[e.key] = null;
            }
          }
          out.add(rec);
        }
        return ParseResult(out, warnings: warnings);

      case ParseFormat.regex:
        final pattern = spec.pattern ?? '';
        if (pattern.isEmpty) {
          throw PluginParseException('regex 解析缺少 pattern', '');
        }
        final re = RegExp(pattern, dotAll: true, multiLine: true);
        for (final m in re.allMatches(body)) {
          final rec = <String, Object?>{
            'match': m.group(0) ?? '',
            'group': m.group(spec.group) ?? m.group(0) ?? '',
            'groups': List.generate(m.groupCount + 1, (i) => m.group(i) ?? ''),
          };
          if (spec.fields.isNotEmpty) {
            for (final e in spec.fields.entries) {
              final ctx = base.child({'item': rec, 'index': out.length});
              try {
                rec[e.key] = await PExpr.eval(e.value, ctx);
              } catch (err) {
                warnings.add('字段 ${e.key}: ${_short(err.toString())}');
                rec[e.key] = null;
              }
            }
          }
          out.add(rec);
        }
        return ParseResult(out, warnings: warnings);
    }
  }

  List<dom.Element> _selectNodes(dom.Document doc, String? selector) {
    final sel = (selector ?? '').trim();
    if (sel.isEmpty || sel == 'body' || sel == 'html') {
      final body = doc.body;
      return body == null ? const [] : [body];
    }
    // 支持 `selector >> nth` 这类简单管道。
    final parts = sel.split('>>').map((e) => e.trim()).toList();
    var current = doc.querySelectorAll(parts.first).toList();
    for (final p in parts.skip(1)) {
      if (p == 'all') continue;
      if (p == 'first') {
        current = current.isEmpty ? [] : [current.first];
      } else if (p == 'last') {
        current = current.isEmpty ? [] : [current.last];
      }
    }
    return current;
  }

  Object? _navigate(Object? value, String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty || p == r'$' || p == 'body') return value;
    final clean = p.startsWith(r'$.') ? p.substring(2) : (p.startsWith(r'$') ? p.substring(1) : p);
    return _at(value, clean);
  }

  Object? _at(Object? root, String path) {
    var cur = root;
    for (final raw in path.split('.')) {
      if (cur == null) return null;
      var seg = raw.trim();
      if (seg.isEmpty) continue;
      String? index;
      final b = seg.indexOf('[');
      if (b >= 0) {
        index = seg.substring(b);
        seg = seg.substring(0, b);
      }
      if (seg.isNotEmpty) {
        if (cur is Map) {
          cur = cur[seg];
        } else if (cur is List) {
          final n = int.tryParse(seg);
          cur = (n != null && n >= 0 && n < cur.length) ? cur[n] : null;
        } else {
          return null;
        }
      }
      if (index != null) {
        final inner = index.replaceAll('[', '').replaceAll(']', '');
        if (cur is List) {
          final n = int.tryParse(inner) ?? 0;
          cur = (n >= 0 && n < cur.length) ? cur[n] : null;
        } else if (cur is Map) {
          cur = cur[inner];
        } else {
          return null;
        }
      }
    }
    return cur;
  }

  static String _short(String s) => s.length > 120 ? '${s.substring(0, 120)}…' : s;
}

class PluginParseException implements Exception {
  PluginParseException(this.message, this.url);

  final String message;
  final String url;

  @override
  String toString() => message;
}

/// 字段 → MediaItem 映射（键名约定见插件文档）。
MediaItem itemFromRecord(
  Map<String, Object?> rec, {
  required String baseUrl,
  String? sourceId,
  String? sourceName,
}) {
  String pick(String k) => PExpr.toStr(rec[k]).trim();

  final id = pick('id');
  final poster = _absUrl(pick('poster'), baseUrl);
  final tagsRaw = rec['tags'];
  final tags = tagsRaw is List
      ? tagsRaw.map(PExpr.toStr).where((e) => e.isNotEmpty).toList()
      : pick('tags')
          .split(_sep)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

  return MediaItem(
    id: id,
    title: pick('title'),
    poster: poster.isEmpty ? null : poster,
    year: _emptyToNull(pick('year')),
    score: _emptyToNull(pick('score')),
    remarks: _emptyToNull(pick('remarks')),
    area: _emptyToNull(pick('area')),
    kind: _emptyToNull(pick('kind')),
    tags: tags,
    sourceId: sourceId,
    sourceName: sourceName,
    extra: {
      for (final e in rec.entries)
        if (!const {'id', 'title', 'poster', 'year', 'score', 'remarks', 'area', 'kind', 'tags'}
            .contains(e.key))
          e.key: e.value,
    },
  );
}

final _sep = RegExp(r'[,|/]');

String _absUrl(String v, String baseUrl) {
  if (v.isEmpty) return '';
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  return resolveUrl(v, baseUrl);
}

String? _emptyToNull(String v) => v.trim().isEmpty ? null : v.trim();

/// 详情页剧集解析：把 records 转成线路列表。
List<PlayLine> linesFromRecords(
  List<Map<String, Object?>> recs, {
  required String baseUrl,
  required String defaultLineName,
}) {
  if (recs.isEmpty) return const [];
  final grouped = <String, List<Episode>>{};
  for (var i = 0; i < recs.length; i++) {
    final r = recs[i];
    final name = PExpr.toStr(r['name']).trim().isEmpty
        ? '第 ${i + 1} 集'
        : PExpr.toStr(r['name']).trim();
    final url = _absUrl(PExpr.toStr(r['url']).trim(), baseUrl);
    if (url.isEmpty) continue;
    final lineName = PExpr.toStr(r['line']).trim().isEmpty
        ? defaultLineName
        : PExpr.toStr(r['line']).trim();
    grouped.putIfAbsent(lineName, () => []).add(Episode(name: name, url: url, index: i));
  }
  return grouped.entries
      .map((e) => PlayLine(
            name: e.key,
            episodes: [
              for (var i = 0; i < e.value.length; i++)
                Episode(name: e.value[i].name, url: e.value[i].url, index: i),
            ],
          ))
      .toList();
}
