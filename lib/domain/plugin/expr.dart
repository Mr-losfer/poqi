import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;

/// 表达式求值上下文。
class ExprContext {
  ExprContext({
    this.vars = const {},
    this.baseUrl = '',
    this.onCall,
  });

  /// 顶层变量：cfg / vars / page / keyword / id / item / url …
  final Map<String, Object?> vars;
  final String baseUrl;

  /// 外部函数扩展点（http.get / http.post 等需要异步 IO 的能力）。
  final Future<Object?> Function(String name, List<Object?> args)? onCall;

  ExprContext child(Map<String, Object?> extra) => ExprContext(
        vars: {...vars, ...extra},
        baseUrl: baseUrl,
        onCall: onCall,
      );
}

class ExprException implements Exception {
  ExprException(this.message, [this.position]);

  final String message;
  final int? position;

  @override
  String toString() => position == null ? message : '$message（位置 $position）';
}

/// 轻量表达式语言：插件规则里所有"取值"都通过它完成。
///
/// 支持：字面量、四则/比较/逻辑/三元、成员与下标、函数调用、列表与对象字面量。
class PExpr {
  PExpr._();

  static final Map<String, _Node> _cache = {};

  /// 仅做语法校验，不执行。
  static void validate(String source) => _parse(source);

  /// 求值；任何异常都会抛出 [ExprException]，由引擎统一降级处理。
  static Future<Object?> eval(String source, ExprContext ctx) async {
    final node = _parse(source);
    return node.eval(ctx);
  }

  /// 求值并转为字符串（null → ''）。
  static Future<String> evalString(String source, ExprContext ctx) async {
    final v = await eval(source, ctx);
    return toStr(v);
  }

  static _Node _parse(String source) {
    final cached = _cache[source];
    if (cached != null) return cached;
    final p = _Parser(_Lexer(source).scan());
    final node = p.parseExpression();
    p.expectEof();
    if (_cache.length > 800) _cache.clear();
    _cache[source] = node;
    return node;
  }

  static String toStr(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num) {
      if (v is double && v == v.roundToDouble()) return v.toInt().toString();
      return v.toString();
    }
    if (v is bool) return v ? 'true' : 'false';
    if (v is dom.Element) return v.text.trim();
    if (v is dom.Node) return (v.text ?? '').trim();
    if (v is List) return v.map(toStr).join(',');
    return jsonEncode(v);
  }

  static num toNum(Object? v) {
    if (v is num) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is String) {
      final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(v);
      if (m != null) return num.tryParse(m.group(0)!) ?? 0;
    }
    return 0;
  }

  static bool truthy(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty && v != 'false' && v != '0';
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }
}

// ---------------------------------------------------------------------------
// 词法
// ---------------------------------------------------------------------------

enum _T { num, str, ident, op, eof }

class _Token {
  _Token(this.t, this.s, this.pos, [this.n]);
  final _T t;
  final String s;
  final int pos;
  final num? n;
}

class _Lexer {
  _Lexer(this.src);

  final String src;
  int i = 0;

  static const _ops = [
    '==', '!=', '<=', '>=', '&&', '||',
    '+', '-', '*', '/', '%', '!', '?', ':', '.', ',', '(', ')', '[', ']', '{', '}', '<', '>',
  ];

  List<_Token> scan() {
    final out = <_Token>[];
    while (true) {
      _skipWs();
      if (i >= src.length) {
        out.add(_Token(_T.eof, '', i));
        return out;
      }
      final c = src[i];
      if (c == '"' || c == "'") {
        out.add(_string(c));
        continue;
      }
      if (_isDigit(c)) {
        out.add(_number());
        continue;
      }
      if (_isIdentStart(c)) {
        final start = i;
        while (i < src.length && _isIdentPart(src[i])) {
          i++;
        }
        out.add(_Token(_T.ident, src.substring(start, i), start));
        continue;
      }
      String? matched;
      for (final op in _ops) {
        if (src.startsWith(op, i)) {
          matched = op;
          break;
        }
      }
      if (matched == null) {
        throw ExprException('无法识别的字符 "$c"', i);
      }
      out.add(_Token(_T.op, matched, i));
      i += matched.length;
    }
  }

  void _skipWs() {
    while (i < src.length) {
      final c = src[i];
      if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
        i++;
      } else if (src.startsWith('//', i)) {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
      } else {
        break;
      }
    }
  }

  _Token _string(String quote) {
    final start = i;
    i++;
    final buf = StringBuffer();
    while (i < src.length) {
      final c = src[i];
      if (c == r'\') {
        i++;
        if (i >= src.length) break;
        final e = src[i];
        buf.write(switch (e) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          _ => e,
        });
        i++;
        continue;
      }
      if (c == quote) {
        i++;
        return _Token(_T.str, buf.toString(), start);
      }
      buf.write(c);
      i++;
    }
    throw ExprException('字符串未闭合', start);
  }

  _Token _number() {
    final start = i;
    while (i < src.length && (_isDigit(src[i]) || src[i] == '.')) {
      i++;
    }
    final raw = src.substring(start, i);
    return _Token(_T.num, raw, start, num.tryParse(raw) ?? 0);
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static bool _isIdentStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_' || c == r'$';
  }

  static bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);
}

// ---------------------------------------------------------------------------
// 语法树
// ---------------------------------------------------------------------------

abstract class _Node {
  Future<Object?> eval(ExprContext ctx);
}

class _Lit extends _Node {
  _Lit(this.v);
  final Object? v;

  @override
  Future<Object?> eval(ExprContext ctx) async => v;
}

class _ListLit extends _Node {
  _ListLit(this.items);
  final List<_Node> items;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    final out = <Object?>[];
    for (final it in items) {
      out.add(await it.eval(ctx));
    }
    return out;
  }
}

class _MapLit extends _Node {
  _MapLit(this.entries);
  final List<MapEntry<String, _Node>> entries;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    final out = <String, Object?>{};
    for (final e in entries) {
      out[e.key] = await e.value.eval(ctx);
    }
    return out;
  }
}

class _Ident extends _Node {
  _Ident(this.name, this.pos);
  final String name;
  final int pos;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    if (ctx.vars.containsKey(name)) return ctx.vars[name];
    // 未定义标识符视为 null，避免规则里可选字段直接报错。
    return null;
  }
}

class _Member extends _Node {
  _Member(this.target, this.name);
  final _Node target;
  final String name;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    final t = await target.eval(ctx);
    return _access(t, name);
  }
}

Object? _access(Object? t, String name) {
  if (t == null) return null;
  if (t is Map) return t[name];
  if (t is List) {
    if (name == 'length') return t.length;
    if (name == 'first') return t.isEmpty ? null : t.first;
    if (name == 'last') return t.isEmpty ? null : t.last;
    return null;
  }
  if (t is String) {
    if (name == 'length') return t.length;
    if (name == 'trim') return t.trim();
    return null;
  }
  if (t is dom.Element) {
    if (name == 'text') return t.text.trim();
    if (name == 'html') return t.innerHtml;
    if (name == 'tag') return t.localName;
    return t.attributes[name];
  }
  return null;
}

class _Index extends _Node {
  _Index(this.target, this.index);
  final _Node target;
  final _Node index;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    final t = await target.eval(ctx);
    final k = await index.eval(ctx);
    if (t is List) {
      final n = PExpr.toNum(k).toInt();
      if (n < 0) return t.length + n >= 0 && t.isNotEmpty ? t[t.length + n] : null;
      return n < t.length ? t[n] : null;
    }
    if (t is Map) return t[PExpr.toStr(k)];
    if (t is String) {
      final n = PExpr.toNum(k).toInt();
      if (n < 0 || n >= t.length) return null;
      return t[n];
    }
    return null;
  }
}

class _Call extends _Node {
  _Call(this.target, this.name, this.args, this.pos);
  final _Node? target;
  final String name;
  final List<_Node> args;
  final int pos;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    final values = <Object?>[];
    for (final a in args) {
      values.add(await a.eval(ctx));
    }
    if (target != null) {
      final recv = await target!.eval(ctx);
      final t = target;
      if (recv is Map && recv['__ns'] != null) {
        return _namespace('${recv['__ns']}.$name', values, ctx, pos);
      }
      if (recv == null && t is _Ident) {
        return _namespace('${t.name}.$name', values, ctx, pos);
      }
      // 形如 item.toUpperCase() 的方法调用
      return _method(recv, name, values);
    }
    return _namespace(name, values, ctx, pos);
  }
}

class _Unary extends _Node {
  _Unary(this.op, this.operand);
  final String op;
  final _Node operand;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    final v = await operand.eval(ctx);
    return switch (op) {
      '!' => !PExpr.truthy(v),
      '-' => -PExpr.toNum(v),
      _ => v,
    };
  }
}

class _Binary extends _Node {
  _Binary(this.op, this.left, this.right);
  final String op;
  final _Node left;
  final _Node right;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    if (op == '&&') {
      final l = await left.eval(ctx);
      if (!PExpr.truthy(l)) return false;
      return PExpr.truthy(await right.eval(ctx));
    }
    if (op == '||') {
      final l = await left.eval(ctx);
      if (PExpr.truthy(l)) return true;
      return PExpr.truthy(await right.eval(ctx));
    }
    final a = await left.eval(ctx);
    final b = await right.eval(ctx);
    switch (op) {
      case '+':
        if (a is num && b is num) return a + b;
        return PExpr.toStr(a) + PExpr.toStr(b);
      case '-':
        return PExpr.toNum(a) - PExpr.toNum(b);
      case '*':
        return PExpr.toNum(a) * PExpr.toNum(b);
      case '/':
        final d = PExpr.toNum(b);
        return d == 0 ? 0 : PExpr.toNum(a) / d;
      case '%':
        final d = PExpr.toNum(b);
        return d == 0 ? 0 : PExpr.toNum(a) % d;
      case '==':
        return PExpr.toStr(a) == PExpr.toStr(b);
      case '!=':
        return PExpr.toStr(a) != PExpr.toStr(b);
      case '<':
        return PExpr.toNum(a) < PExpr.toNum(b);
      case '>':
        return PExpr.toNum(a) > PExpr.toNum(b);
      case '<=':
        return PExpr.toNum(a) <= PExpr.toNum(b);
      case '>=':
        return PExpr.toNum(a) >= PExpr.toNum(b);
    }
    return null;
  }
}

class _Cond extends _Node {
  _Cond(this.cond, this.a, this.b);
  final _Node cond;
  final _Node a;
  final _Node b;

  @override
  Future<Object?> eval(ExprContext ctx) async {
    if (PExpr.truthy(await cond.eval(ctx))) return a.eval(ctx);
    return b.eval(ctx);
  }
}

// ---------------------------------------------------------------------------
// 语法分析
// ---------------------------------------------------------------------------

class _Parser {
  _Parser(this.tokens);

  final List<_Token> tokens;
  int i = 0;

  _Token get cur => tokens[i];

  bool _isOp(String s) => cur.t == _T.op && cur.s == s;

  void expectEof() {
    if (cur.t != _T.eof) {
      throw ExprException('表达式结尾有多余内容 "${cur.s}"', cur.pos);
    }
  }

  _Token _next() => tokens[i++];

  _Node parseExpression() => _conditional();

  _Node _conditional() {
    final cond = _binary(0);
    if (_isOp('?')) {
      _next();
      final a = _conditional();
      if (!_isOp(':')) throw ExprException('三元表达式缺少 ":"', cur.pos);
      _next();
      final b = _conditional();
      return _Cond(cond, a, b);
    }
    return cond;
  }

  static const _levels = [
    ['||'],
    ['&&'],
    ['==', '!='],
    ['<', '>', '<=', '>='],
    ['+', '-'],
    ['*', '/', '%'],
  ];

  _Node _binary(int level) {
    if (level >= _levels.length) return _unary();
    var left = _binary(level + 1);
    while (cur.t == _T.op && _levels[level].contains(cur.s)) {
      final op = _next().s;
      final right = _binary(level + 1);
      left = _Binary(op, left, right);
    }
    return left;
  }

  _Node _unary() {
    if (cur.t == _T.op && (cur.s == '!' || cur.s == '-')) {
      final op = _next().s;
      return _Unary(op, _unary());
    }
    return _postfix();
  }

  _Node _postfix() {
    var node = _primary();
    while (true) {
      if (_isOp('.')) {
        _next();
        if (cur.t != _T.ident) throw ExprException('"." 之后需要标识符', cur.pos);
        final name = _next().s;
        if (_isOp('(')) {
          final args = _args();
          node = _Call(node, name, args, cur.pos);
        } else {
          node = _Member(node, name);
        }
      } else if (_isOp('[')) {
        _next();
        final idx = parseExpression();
        if (!_isOp(']')) throw ExprException('缺少 "]"', cur.pos);
        _next();
        node = _Index(node, idx);
      } else {
        return node;
      }
    }
  }

  _Node _primary() {
    if (cur.t == _T.num) {
      final v = _next().n;
      return _Lit(v);
    }
    if (cur.t == _T.str) {
      return _Lit(_next().s);
    }
    if (_isOp('(')) {
      _next();
      final e = parseExpression();
      if (!_isOp(')')) throw ExprException('缺少 ")"', cur.pos);
      _next();
      return e;
    }
    if (_isOp('[')) {
      _next();
      final items = <_Node>[];
      while (!_isOp(']')) {
        items.add(parseExpression());
        if (_isOp(',')) {
          _next();
        } else {
          break;
        }
      }
      if (!_isOp(']')) throw ExprException('缺少 "]"', cur.pos);
      _next();
      return _ListLit(items);
    }
    if (_isOp('{')) {
      _next();
      final entries = <MapEntry<String, _Node>>[];
      while (!_isOp('}')) {
        if (cur.t != _T.str && cur.t != _T.ident) {
          throw ExprException('对象字面量的键必须是字符串', cur.pos);
        }
        final key = _next().s;
        if (!_isOp(':')) throw ExprException('对象字面量缺少 ":"', cur.pos);
        _next();
        entries.add(MapEntry(key, parseExpression()));
        if (_isOp(',')) {
          _next();
        } else {
          break;
        }
      }
      if (!_isOp('}')) throw ExprException('缺少 "}"', cur.pos);
      _next();
      return _MapLit(entries);
    }
    if (cur.t == _T.ident) {
      final tok = _next();
      switch (tok.s) {
        case 'true':
          return _Lit(true);
        case 'false':
          return _Lit(false);
        case 'null':
          return _Lit(null);
      }
      if (_isOp('(')) {
        final args = _args();
        return _Call(null, tok.s, args, tok.pos);
      }
      return _Ident(tok.s, tok.pos);
    }
    throw ExprException('无法解析的表达式片段 "${cur.s}"', cur.pos);
  }

  List<_Node> _args() {
    if (!_isOp('(')) throw ExprException('缺少 "("', cur.pos);
    _next();
    final out = <_Node>[];
    while (!_isOp(')')) {
      out.add(parseExpression());
      if (_isOp(',')) {
        _next();
      } else {
        break;
      }
    }
    if (!_isOp(')')) throw ExprException('缺少 ")"', cur.pos);
    _next();
    return out;
  }
}

// ---------------------------------------------------------------------------
// 内置函数
// ---------------------------------------------------------------------------

Future<Object?> _namespace(
  String name,
  List<Object?> args,
  ExprContext ctx,
  int pos,
) async {
  if (name.startsWith('http.')) {
    final fn = ctx.onCall;
    if (fn == null) throw ExprException('当前上下文不支持 $name', pos);
    return fn(name, args);
  }

  Object? a0() => args.isNotEmpty ? args[0] : null;
  Object? a1() => args.length > 1 ? args[1] : null;
  Object? a2() => args.length > 2 ? args[2] : null;

  switch (name) {
    // --- 字符串 ---
    case 'text':
      return PExpr.toStr(a0()).trim();
    case 'html':
      final v = a0();
      return v is dom.Element ? v.innerHtml : PExpr.toStr(v);
    case 'trim':
      return PExpr.toStr(a0()).trim();
    case 'lower':
      return PExpr.toStr(a0()).toLowerCase();
    case 'upper':
      return PExpr.toStr(a0()).toUpperCase();
    case 'replace':
      return PExpr.toStr(a0()).replaceAll(PExpr.toStr(a1()), PExpr.toStr(a2()));
    case 'split':
      return PExpr.toStr(a0()).split(PExpr.toStr(a1()));
    case 'join':
      final v = a0();
      return v is List ? v.map(PExpr.toStr).join(PExpr.toStr(a1())) : PExpr.toStr(v);
    case 'substr':
      final str = PExpr.toStr(a0());
      final start = PExpr.toNum(a1()).toInt().clamp(0, str.length);
      final len = args.length > 2 ? PExpr.toNum(a2()).toInt() : str.length - start;
      final end = (start + (len < 0 ? 0 : len)).clamp(start, str.length);
      return str.substring(start, end);
    case 'startsWith':
      return PExpr.toStr(a0()).startsWith(PExpr.toStr(a1()));
    case 'contains':
      final s = a0();
      if (s is List) return s.map(PExpr.toStr).contains(PExpr.toStr(a1()));
      return PExpr.toStr(s).contains(PExpr.toStr(a1()));
    case 'regex':
      final s = PExpr.toStr(a0());
      final p = PExpr.toStr(a1());
      final g = args.length > 2 ? PExpr.toNum(a2()).toInt() : 1;
      final m = RegExp(p, dotAll: true, multiLine: true).firstMatch(s);
      if (m == null) return '';
      if (g == 0) return m.group(0) ?? '';
      return m.group(g) ?? '';

    // --- 数字 ---
    case 'int':
      return PExpr.toNum(a0()).toInt();
    case 'number':
      return PExpr.toNum(a0());
    case 'abs':
      return PExpr.toNum(a0()).abs();
    case 'min':
      return math.min(PExpr.toNum(a0()), PExpr.toNum(a1()));
    case 'max':
      return math.max(PExpr.toNum(a0()), PExpr.toNum(a1()));
    case 'round':
      return PExpr.toNum(a0()).round();

    // --- 集合 ---
    case 'len':
      final v = a0();
      if (v is List) return v.length;
      if (v is Map) return v.length;
      if (v is String) return v.length;
      return 0;
    case 'first':
      final v = a0();
      return v is List && v.isNotEmpty ? v.first : null;
    case 'last':
      final v = a0();
      return v is List && v.isNotEmpty ? v.last : null;
    case 'nth':
      final v = a0();
      final n = PExpr.toNum(a1()).toInt();
      if (v is List && n >= 0 && n < v.length) return v[n];
      return null;
    case 'slice':
      final v = a0();
      final start = PExpr.toNum(a1()).toInt();
      final end = args.length > 2 ? PExpr.toNum(a2()).toInt() : null;
      if (v is List) {
        final s = start.clamp(0, v.length);
        final e = (end ?? v.length).clamp(s, v.length);
        return v.sublist(s, e);
      }
      return null;
    case 'reverse':
      final v = a0();
      return v is List ? v.reversed.toList() : v;
    case 'uniq':
      final v = a0();
      if (v is! List) return v;
      final seen = <String>{};
      return v.where((e) => seen.add(PExpr.toStr(e))).toList();
    case 'keys':
      final v = a0();
      return v is Map ? v.keys.map((e) => '$e').toList() : <String>[];
    case 'values':
      final v = a0();
      return v is Map ? v.values.toList() : <Object?>[];
    case 'where':
      return _filterByField(a0(), a1(), a2());
    case 'find':
      final hits = _filterByField(a0(), a1(), a2());
      return hits.isEmpty ? null : hits.first;

    // --- JSON / 路径 ---
    case 'json':
      try {
        return jsonDecode(PExpr.toStr(a0()));
      } catch (_) {
        return null;
      }
    case 'at':
    case 'path':
      return _at(a0(), PExpr.toStr(a1()));
    case 'encode':
      return jsonEncode(args.length > 1 ? args[1] : a0());
    case 'urlencode':
      return Uri.encodeComponent(PExpr.toStr(a0()));

    // --- 编码/摘要 ---
    case 'md5':
      return md5.convert(utf8.encode(PExpr.toStr(a0()))).toString();
    case 'sha1':
      return sha1.convert(utf8.encode(PExpr.toStr(a0()))).toString();
    case 'b64':
      return base64Encode(utf8.encode(PExpr.toStr(a0())));
    case 'b64d':
      try {
        return utf8.decode(base64Decode(PExpr.toStr(a0())));
      } catch (_) {
        return '';
      }

    // --- HTML ---
    case 'sel':
      final node = a0();
      final css = PExpr.toStr(a1());
      if (node is dom.Element) return node.querySelector(css);
      if (node is dom.Document) return node.querySelector(css);
      return null;
    case 'selAll':
      final node = a0();
      final css = PExpr.toStr(a1());
      if (node is dom.Element) return node.querySelectorAll(css);
      if (node is dom.Document) return node.querySelectorAll(css);
      return <dom.Element>[];
    case 'attr':
      final node = a0();
      final key = PExpr.toStr(a1());
      if (node is dom.Element) return node.attributes[key] ?? '';
      if (node is Map) return PExpr.toStr(node[key]);
      return '';

    // --- 时间 / 随机 ---
    case 'now':
      return DateTime.now().toIso8601String();
    case 'ts':
      return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    case 'today':
      final n = DateTime.now();
      return '${n.year.toString().padLeft(4, '0')}-'
          '${n.month.toString().padLeft(2, '0')}-'
          '${n.day.toString().padLeft(2, '0')}';
    case 'rand':
      final max = args.isEmpty ? 1000000 : PExpr.toNum(a0()).toInt();
      return math.Random().nextInt(max <= 0 ? 1 : max);
    case 'uuid':
      final r = math.Random();
      String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
      return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';

    // --- URL ---
    case 'resolve':
    case 'absolute':
      return resolveUrl(PExpr.toStr(a0()), ctx.baseUrl);
    case 'domain':
      final u = Uri.tryParse(PExpr.toStr(a0()));
      return u?.host ?? '';

    // --- 兜底 ---
    case 'coalesce':
      for (final a in args) {
        if (a != null && PExpr.toStr(a).trim().isNotEmpty) return a;
      }
      return '';
    case 'default':
      final v = a0();
      if (v == null || PExpr.toStr(v).trim().isEmpty) return a1();
      return v;
    case 'if':
      return PExpr.truthy(a0()) ? a1() : (args.length > 2 ? args[2] : '');
    case 'not':
      return !PExpr.truthy(a0());
  }
  throw ExprException('未知函数 $name', pos);
}

/// `where/find` 共用的字段筛选；非 List 或元素非 Map 时安全返回空列表。
List<Object?> _filterByField(Object? list, Object? key, Object? value) {
  if (list is! List) return const [];
  final field = PExpr.toStr(key);
  final out = <Object?>[];
  for (final item in list) {
    if (item is! Map) continue;
    if (_looseEquals(item[field], value)) out.add(item);
  }
  return out;
}

/// 宽松相等：数字 1 与字符串 "1" 视为相同，便于 `where(sites, 'type', 1)`。
bool _looseEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is num && b is num) return a == b;
  return PExpr.toStr(a) == PExpr.toStr(b);
}

Future<Object?> _method(Object? recv, String name, List<Object?> args) async {
  switch (name) {
    case 'toString':
      return PExpr.toStr(recv);
    case 'toUpperCase':
      return PExpr.toStr(recv).toUpperCase();
    case 'toLowerCase':
      return PExpr.toStr(recv).toLowerCase();
    case 'trim':
      return PExpr.toStr(recv).trim();
    case 'replace':
      return PExpr.toStr(recv).replaceAll(PExpr.toStr(args[0]), PExpr.toStr(args[1]));
    case 'contains':
      return PExpr.toStr(recv).contains(PExpr.toStr(args[0]));
    case 'split':
      return PExpr.toStr(recv).split(PExpr.toStr(args[0]));
    case 'at':
      return _at(recv, PExpr.toStr(args[0]));
  }
  return null;
}

/// `a.b[0].c` 形式的路径取值。
Object? _at(Object? root, String path) {
  if (path.isEmpty) return root;
  var cur = root;
  for (final raw in path.split('.')) {
    if (cur == null) return null;
    var seg = raw.trim();
    if (seg.isEmpty) continue;
    String? indexPart;
    final bracket = seg.indexOf('[');
    if (bracket >= 0) {
      indexPart = seg.substring(bracket);
      seg = seg.substring(0, bracket);
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
    if (indexPart != null) {
      final inner = indexPart.replaceAll('[', '').replaceAll(']', '');
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

/// 相对地址补全。
String resolveUrl(String raw, String baseUrl) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  if (v.startsWith('//')) return 'https:$v';
  final u = Uri.tryParse(v);
  if (u != null && u.hasScheme) return v;
  final b = Uri.tryParse(baseUrl);
  if (b == null) return v;
  try {
    return b.resolve(v).toString();
  } catch (_) {
    return v;
  }
}

/// `{{ expr }}` 模板渲染。
Future<String> renderTemplate(String template, ExprContext ctx) async {
  if (!template.contains('{{')) return template;
  final re = RegExp(r'\{\{([\s\S]*?)\}\}');
  final matches = re.allMatches(template).toList();
  if (matches.isEmpty) return template;
  final buf = StringBuffer();
  var last = 0;
  for (final m in matches) {
    buf.write(template.substring(last, m.start));
    final expr = m.group(1)!.trim();
    Object? v;
    try {
      v = await PExpr.eval(expr, ctx);
    } catch (_) {
      v = '';
    }
    buf.write(PExpr.toStr(v));
    last = m.end;
  }
  buf.write(template.substring(last));
  return buf.toString();
}

/// 递归渲染对象中的所有字符串值。
Future<Object?> renderDeep(Object? value, ExprContext ctx) async {
  if (value is String) return renderTemplate(value, ctx);
  if (value is List) {
    final out = <Object?>[];
    for (final v in value) {
      out.add(await renderDeep(v, ctx));
    }
    return out;
  }
  if (value is Map) {
    final out = <String, Object?>{};
    for (final e in value.entries) {
      out['${e.key}'] = await renderDeep(e.value, ctx);
    }
    return out;
  }
  return value;
}
