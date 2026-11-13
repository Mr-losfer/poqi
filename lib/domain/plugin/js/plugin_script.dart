import '../../models/plugin.dart';
import 'js_host.dart';

/// 「一个 .js 文件就是一个插件」的编译入口。
///
/// 脚本里这样声明元信息（可以省略，但强烈建议写全）：
///
/// ```js
/// var plugin = {
///   id: 'demo.mysite',        // 唯一标识，定下来就别改
///   name: '演示站点',
///   version: '1.0.0',
///   author: '你',
///   description: '',
///   base: 'https://example.com',
///   headers: { 'User-Agent': '...' },
///   config: [
///     { key: 'api', label: '接口地址', required: true }
///   ]
/// };
/// ```
///
/// 函数名就是端点名：`home` / `category` / `search` / `detail` / `play`，
/// 需要筛选器时再写 `filters`。
///
/// 元信息用内置的 JS 字面量解析器读取（纯 Dart，任何平台都能跑），
/// 只有显式要求 `precise: true` 时才真的用 QuickJS 执行一遍脚本。
class PluginScript {
  const PluginScript._();

  static const _requiredAny = ['home', 'search'];
  static const _knownFunctions = ['home', 'category', 'search', 'detail', 'play', 'filters'];
  static const _endpoints = ['home', 'category', 'search', 'detail', 'play'];

  /// 把脚本编译成运行期清单。
  ///
  /// [precise] 为 true 时用 QuickJS 真跑一遍（能发现语法错误、运行时错误），
  /// 否则走静态解析 —— 快、无依赖，适合列表渲染和测试环境。
  static PluginManifest compile(
    String script, {
    String? fallbackId,
    bool precise = false,
  }) {
    final functions = precise
        ? JsHost.parseScript(script).functions.toSet()
        : scanFunctions(script);

    if (!_requiredAny.any(functions.contains)) {
      throw JsPluginException(
        '脚本至少要定义 home(p) 或 search(p) 函数，当前只定义了：'
        '${functions.isEmpty ? '（无）' : functions.join(', ')}',
      );
    }

    final meta = lightMeta(script) ?? const <String, Object?>{};
    final name = _str(meta, ['name', 'title', 'label']);
    final id = _sanitizeId(_str(meta, ['id', 'package', 'key'])) ??
        _sanitizeId(fallbackId) ??
        _autoId(name);

    return PluginManifest(
      spec: kPluginSpecVersion,
      id: id,
      name: name.isEmpty ? id : name,
      version: _str(meta, ['version', 'ver'], '1.0.0'),
      author: _str(meta, ['author', 'by']),
      description: _str(meta, ['description', 'desc', 'intro']),
      homepage: _str(meta, ['homepage']),
      icon: _str(meta, ['icon']).isEmpty ? null : _str(meta, ['icon']),
      engine: PluginEngine.js,
      source: PluginSource.script,
      script: script,
      baseUrl: _str(meta, ['base', 'baseUrl', 'api', 'host']),
      headers: _strMap(meta['headers']),
      config: _configFields(meta['config']),
      vars: _vars(meta['vars']),
      // 占位端点：让「是否支持搜索/详情」这类判断对脚本插件同样成立。
      // 真正的逻辑在脚本里，这些 EndpointSpec 只带函数名。
      endpoints: {
        for (final f in _endpoints)
          if (functions.contains(f)) f: EndpointSpec(js: f),
      },
      notes: _str(meta, ['notes', 'note']),
      builtin: false,
    );
  }

  /// 端点名 → 是否真的有对应函数（用于编辑器提示，不阻断保存）。
  static Set<String> endpointsOf(String script) =>
      scanFunctions(script).where(_knownFunctions.contains).toSet();

  /// 扫描 `function name(...)` 与 `name = function(...)` 两种写法。
  static Set<String> scanFunctions(String script) {
    final out = <String>{};
    for (final m in RegExp(r'function\s+([A-Za-z_$][\w$]*)\s*\(').allMatches(script)) {
      out.add(m.group(1)!);
    }
    for (final m in RegExp(r'(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?function')
        .allMatches(script)) {
      out.add(m.group(1)!);
    }
    for (final m in RegExp(r'([A-Za-z_$][\w$]*)\s*:\s*(?:async\s*)?function\s*\(')
        .allMatches(script)) {
      out.add(m.group(1)!);
    }
    return out;
  }

  /// 静态读取 `var plugin = {...}` / `var rule = {...}` / `var meta = {...}`。
  static Map<String, Object?>? lightMeta(String script) {
    for (final name in const ['plugin', 'rule', 'meta']) {
      final obj = _extractObject(script, name);
      if (obj == null) continue;
      final inner = obj['meta'];
      if (inner is Map) return inner.cast<String, Object?>();
      return obj;
    }
    return null;
  }

  // ------------------------------------------------------------ 内部

  static Map<String, Object?>? _extractObject(String src, String varName) {
    final re = RegExp(
      '(?:var|let|const)\\s+${RegExp.escape(varName)}\\s*=\\s*\\{',
    );
    final m = re.firstMatch(src);
    if (m == null) return null;
    final start = src.indexOf('{', m.start);
    if (start < 0) return null;

    var depth = 0;
    var i = start;
    String? quote;
    while (i < src.length) {
      final c = src[i];
      if (quote != null) {
        if (c == r'\') {
          i += 2;
          continue;
        }
        if (c == quote) quote = null;
        i++;
        continue;
      }
      if (c == "'" || c == '"' || c == '`') {
        quote = c;
        i++;
        continue;
      }
      if (c == '/' && i + 1 < src.length) {
        if (src[i + 1] == '/') {
          final e = src.indexOf('\n', i);
          i = e < 0 ? src.length : e + 1;
          continue;
        }
        if (src[i + 1] == '*') {
          final e = src.indexOf('*/', i);
          i = e < 0 ? src.length : e + 2;
          continue;
        }
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          try {
            final parsed = _Literal(src.substring(start, i + 1)).parse();
            return parsed is Map ? parsed.cast<String, Object?>() : null;
          } catch (_) {
            return null;
          }
        }
      }
      i++;
    }
    return null;
  }

  static String _str(Map<String, Object?> m, List<String> keys, [String def = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = '$v'.trim();
      if (s.isNotEmpty) return s;
    }
    return def;
  }

  static String? _sanitizeId(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    final cleaned = s.replaceAll(RegExp(r'[^a-z0-9._-]'), '-');
    if (cleaned.isEmpty) return null;
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }

  /// 没写 id 时按名字生成一个稳定 id，保证「改脚本不换站点绑定」。
  static String _autoId(String name) {
    var sum = 0;
    for (final c in (name.isEmpty ? 'plugin' : name).codeUnits) {
      sum = (sum * 31 + c) & 0x7fffffff;
    }
    return 'custom.${sum.toRadixString(36)}';
  }

  static Map<String, String> _strMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v == null) return;
      out['$k'] = '$v';
    });
    return out;
  }

  static Map<String, VarSpec> _vars(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, VarSpec>{};
    raw.forEach((k, v) {
      if (v is Map) {
        out['$k'] = VarSpec.fromJson(v.cast<String, dynamic>());
      } else if (v is String) {
        out['$k'] = VarSpec(expr: v);
      }
    });
    return out;
  }

  static List<ConfigField> _configFields(Object? raw) {
    if (raw is! List) return const [];
    final out = <ConfigField>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = e.cast<String, Object?>();
      final key = '${m['key'] ?? m['name'] ?? ''}'.trim();
      if (key.isEmpty) continue;
      out.add(ConfigField(
        key: key,
        label: '${m['label'] ?? m['title'] ?? key}',
        type: ConfigFieldType.parse(m['type'] as String?),
        required: m['required'] == true,
        secret: m['secret'] == true || '${m['type'] ?? ''}' == 'password',
        hint: m['hint'] == null ? null : '${m['hint']}',
        help: m['help'] == null ? null : '${m['help']}',
        defaultValue: m['default']?.toString(),
        options: (m['options'] as List?)?.map((e) => '$e').toList() ?? const [],
        refreshSeconds: (m['refreshSeconds'] as num?)?.toInt(),
      ));
    }
    return out;
  }
}

/// 极简 JS 字面量解析器：只认对象、数组、字符串、数字、布尔、null。
///
/// 存在的意义是「不启动 QuickJS 也能读到插件元信息」——
/// 列表页、测试环境、以及脚本顶层有副作用时都能正常工作。
class _Literal {
  _Literal(this.s);

  final String s;
  int i = 0;

  Object? parse() {
    final v = _value();
    return v;
  }

  bool get _eof => i >= s.length;

  void _skip() {
    while (!_eof) {
      final c = s[i];
      if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
        i++;
        continue;
      }
      if (c == '/' && i + 1 < s.length) {
        if (s[i + 1] == '/') {
          final e = s.indexOf('\n', i);
          i = e < 0 ? s.length : e + 1;
          continue;
        }
        if (s[i + 1] == '*') {
          final e = s.indexOf('*/', i);
          i = e < 0 ? s.length : e + 2;
          continue;
        }
      }
      break;
    }
  }

  Object? _value() {
    _skip();
    if (_eof) return null;
    final c = s[i];
    if (c == '{') return _object();
    if (c == '[') return _array();
    if (c == '"' || c == "'" || c == '`') return _string(c);
    if (c == '-' || c == '+' || _isDigit(c)) return _number();
    return _ident();
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  Map<String, Object?> _object() {
    final out = <String, Object?>{};
    i++; // {
    while (true) {
      _skip();
      if (_eof) break;
      if (s[i] == '}') {
        i++;
        break;
      }
      if (s[i] == ',') {
        i++;
        continue;
      }
      String key;
      if (s[i] == '"' || s[i] == "'" || s[i] == '`') {
        key = _string(s[i]);
      } else {
        final start = i;
        while (!_eof && s[i] != ':' && s[i] != ',' && s[i] != '}') {
          i++;
        }
        key = s.substring(start, i).trim();
      }
      _skip();
      if (!_eof && s[i] == ':') i++;
      out[key] = _value();
    }
    return out;
  }

  List<Object?> _array() {
    final out = <Object?>[];
    i++; // [
    while (true) {
      _skip();
      if (_eof) break;
      if (s[i] == ']') {
        i++;
        break;
      }
      if (s[i] == ',') {
        i++;
        continue;
      }
      out.add(_value());
    }
    return out;
  }

  String _string(String quote) {
    i++; // opening quote
    final buf = StringBuffer();
    while (!_eof) {
      final c = s[i];
      if (c == r'\') {
        i++;
        if (_eof) break;
        final e = s[i];
        switch (e) {
          case 'n':
            buf.write('\n');
          case 't':
            buf.write('\t');
          case 'r':
            buf.write('\r');
          case 'b':
            buf.write('\b');
          case 'f':
            buf.write('\f');
          case 'u':
            if (i + 4 < s.length) {
              final hex = s.substring(i + 1, i + 5);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) buf.writeCharCode(code);
              i += 4;
            }
          default:
            buf.write(e);
        }
        i++;
        continue;
      }
      if (c == quote) {
        i++;
        break;
      }
      buf.write(c);
      i++;
    }
    return buf.toString();
  }

  Object? _number() {
    final start = i;
    while (!_eof && (RegExp(r'[0-9eE+\-.]').hasMatch(s[i]))) {
      i++;
    }
    final text = s.substring(start, i);
    return num.tryParse(text) ?? 0;
  }

  Object? _ident() {
    final start = i;
    while (!_eof && RegExp(r'[A-Za-z0-9_$.]').hasMatch(s[i])) {
      i++;
    }
    final text = s.substring(start, i);
    switch (text) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
      case 'undefined':
        return null;
      default:
        return text;
    }
  }
}
