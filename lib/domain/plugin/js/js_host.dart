import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

import 'js_bridge.dart';
import 'pq_runtime.dart';

class JsPluginException implements Exception {
  JsPluginException(this.message, {this.function = ''});

  final String message;
  final String function;

  @override
  String toString() =>
      function.isEmpty ? 'JS 插件错误：$message' : 'JS 插件错误（$function）：$message';
}

/// 脚本里声明的元信息（`var plugin = {...}`）+ 脚本导出的函数名。
class ScriptMeta {
  const ScriptMeta({required this.meta, required this.functions, required this.logs});

  final Map<String, Object?> meta;
  final List<String> functions;
  final List<String> logs;
}

/// 插件脚本的执行宿主。
///
/// 脚本是**同步求值**的（QuickJS），网络是异步的，两者靠 [JsReplaySession]
/// 的「重放」接起来：脚本里 `pq.http.get()` 命中缓存就返回字符串，
/// 没命中就抛 [JsNeedRequest]，宿主发真实请求后把脚本重跑一遍。
///
/// 每一轮都会重新装载脚本，因此脚本里的全局状态天然干净 ——
/// 插件作者只需要写纯函数，不用关心重放。
class JsHost {
  JsHost._();

  static JavascriptRuntime? _rt;

  static JavascriptRuntime get _runtime {
    final existing = _rt;
    if (existing != null) return existing;
    final rt = getJavascriptRuntime(xhr: false);
    rt.evaluate(pqRuntimeJs);
    _rt = rt;
    return rt;
  }

  /// 执行插件函数，返回已解码的 JSON 结构（Map / List / String / num / null）。
  static Future<Object?> call({
    required String pluginId,
    required String script,
    required String function,
    required Map<String, Object?> context,
    required JsReplaySession session,
  }) async {
    if (script.trim().isEmpty) {
      throw JsPluginException('插件没有提供脚本');
    }
    final rt = _runtime;
    final injected = <String>{};
    var primed = false;

    return session.run(() {
      final prep = rt.evaluate('__poqiPrepare(${jsonEncode(pluginId)});');
      if (prep.isError) {
        throw JsPluginException(_clean(prep.stringResult), function: function);
      }

      // 缓存只在本次调用开始时清空一次，后续重跑复用，避免重复编码大段 HTML。
      if (!primed) {
        rt.evaluate('globalThis.__poqiCache = {};');
        primed = true;
      }
      _injectCache(rt, session, injected);

      rt.evaluate('globalThis.__poqiPending = []; globalThis.__poqiLogs = [];');

      final load = rt.evaluate(script);
      if (load.isError) {
        final need = _needOf(load.stringResult);
        if (need != null) throw JsNeedRequest(need);
        throw JsPluginException(_clean(load.stringResult), function: function);
      }

      final collect = rt.evaluate('__poqiCollect(${jsonEncode(pluginId)});');
      if (collect.isError) {
        throw JsPluginException(_clean(collect.stringResult), function: function);
      }

      final setCtx = rt.evaluate(
        'globalThis.__poqiCtx = JSON.parse(${jsonEncode(jsonEncode(context))});',
      );
      if (setCtx.isError) {
        throw JsPluginException(_clean(setCtx.stringResult), function: function);
      }

      final call = rt.evaluate('''
JSON.stringify((function(){
  var bag = globalThis.__poqi[${jsonEncode(pluginId)}] || {};
  var fn = bag[${jsonEncode(function)}];
  // 兜底：极少数引擎版本里 delete 全局函数可能失败，直接读全局再试一次。
  if (typeof fn !== 'function' && typeof globalThis[${jsonEncode(function)}] === 'function') {
    fn = globalThis[${jsonEncode(function)}];
  }
  if (typeof fn !== 'function') {
    var names = [];
    for (var k in bag) { if (Object.prototype.hasOwnProperty.call(bag, k)) names.push(k); }
    throw new Error('缺少函数 ${_escapeJs(function)}()，脚本里已定义：' + (names.join(', ') || '（无）'));
  }
  var out = fn(globalThis.__poqiCtx);
  return {
    out: out === undefined ? null : out,
    pending: globalThis.__poqiPending || [],
    logs: (globalThis.__poqiLogs || []).slice(-40)
  };
})())
''');
      if (call.isError) {
        final need = _needOf(call.stringResult);
        if (need != null) throw JsNeedRequest(need);
        throw JsPluginException(_clean(call.stringResult), function: function);
      }

      final raw = call.stringResult;
      if (raw.isEmpty || raw == 'undefined' || raw == 'null') return null;
      Map<String, Object?> wrapper;
      try {
        wrapper = (jsonDecode(raw) as Map).cast<String, Object?>();
      } catch (e) {
        throw JsPluginException('返回值不是合法 JSON：$e', function: function);
      }

      final pending = wrapper['pending'];
      if (pending is List && pending.isNotEmpty) {
        // 脚本自己 try/catch 吞掉了中断信号 —— 这里补一刀，重跑一次拿真数据。
        final first = pending.first;
        if (first is Map) {
          throw JsNeedRequest(JsHttpRequest.fromJson(first.cast<String, Object?>()));
        }
      }

      _lastLogs = (wrapper['logs'] as List?)?.map((e) => '$e').toList() ?? const [];
      return wrapper['out'];
    });
  }

  static void _injectCache(
    JavascriptRuntime rt,
    JsReplaySession session,
    Set<String> injected,
  ) {
    final cache = session.snapshot();
    final delta = <String, JsHttpResult>{};
    for (final e in cache.entries) {
      if (injected.add(e.key)) delta[e.key] = e.value;
    }
    if (delta.isEmpty) return;
    final payload = jsonEncode({
      for (final e in delta.entries) e.key: e.value.toJson(),
    });
    rt.evaluate('''
(function(){
  var d = JSON.parse(${jsonEncode(payload)});
  var c = globalThis.__poqiCache;
  for (var k in d) { if (Object.prototype.hasOwnProperty.call(d, k)) c[k] = d[k]; }
})();
''');
  }

  /// 只装载脚本、读取 `var plugin = {...}`，不执行业务函数。
  ///
  /// 用于「一整个 .js 文件就是一个插件」：名称、版本、配置项、headers
  /// 全在脚本里声明，保存时解析出来缓存进清单，UI 直接读缓存。
  static ScriptMeta parseScript(String script) {
    if (script.trim().isEmpty) {
      throw JsPluginException('脚本为空');
    }
    final rt = _runtime;
    const probe = '__poqi_meta__';

    final prep = rt.evaluate('__poqiPrepare(${jsonEncode(probe)});');
    if (prep.isError) {
      throw JsPluginException(_clean(prep.stringResult));
    }

    final load = rt.evaluate(script);
    if (load.isError) {
      throw JsPluginException(_clean(load.stringResult));
    }

    final read = rt.evaluate('''
JSON.stringify((function(){
  var m = null;
  try { if (typeof plugin !== 'undefined' && plugin) m = plugin; } catch (e) {}
  if (!m) { try { if (typeof rule !== 'undefined' && rule) m = rule.meta || rule; } catch (e) {} }
  if (!m) { try { if (typeof meta !== 'undefined' && meta) m = meta; } catch (e) {} }
  var base = globalThis.__poqiBase || {};
  var fns = [];
  var keys = Object.keys(globalThis);
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i];
    if (base[k]) continue;
    if (typeof globalThis[k] === 'function') fns.push(k);
  }
  return {
    meta: m || {},
    functions: fns,
    logs: (globalThis.__poqiLogs || []).slice(-40)
  };
})())
''');
    if (read.isError) {
      throw JsPluginException(_clean(read.stringResult));
    }

    // 收尾：把脚本产物从全局清掉，避免污染下一次执行。
    rt.evaluate('__poqiCollect(${jsonEncode(probe)});');

    final raw = read.stringResult;
    Map<String, Object?> wrapper;
    try {
      wrapper = (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (e) {
      throw JsPluginException('读取插件信息失败：$e');
    }

    final meta = (wrapper['meta'] as Map?)?.cast<String, Object?>() ?? const {};
    final fns = (wrapper['functions'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    _lastLogs = (wrapper['logs'] as List?)?.map((e) => '$e').toList() ?? const [];
    return ScriptMeta(meta: meta, functions: fns, logs: const []);
  }

  /// 最近一次执行里 `pq.log(...)` 的输出，出错时展示在调试面板。
  static List<String> _lastLogs = const [];
  static List<String> get lastLogs => _lastLogs;

  static JsHttpRequest? _needOf(String raw) {
    const marker = '__POQI_NEED__';
    final idx = raw.indexOf(marker);
    if (idx < 0) return null;
    final rest = raw.substring(idx + marker.length);
    final firstLine = rest.split('\n').first.trim();
    final m = RegExp(r'^[!-~]+').firstMatch(firstLine);
    if (m == null) return null;
    try {
      return JsHttpRequest.tryParse(Uri.decodeComponent(m.group(0)!));
    } catch (_) {
      return null;
    }
  }

  /// 把 Dart 字符串安全地嵌进单引号 JS 字面量（只用于函数名）。
  static String _escapeJs(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n');

  /// QuickJS 的报错带一长串栈，界面上只留第一行可读信息。
  static String _clean(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '未知错误';
    final need = _needOf(text);
    if (need != null) return '正在获取 ${need.url}';
    final firstLine = text.split('\n').first.trim();
    return firstLine.isEmpty ? text : firstLine;
  }

  @visibleForTesting
  static void reset() {
    try {
      _rt?.dispose();
    } catch (_) {
      // 测试环境没有原生库，dispose 可能失败，忽略。
    }
    _rt = null;
    _lastLogs = const [];
  }
}
