import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

import 'pq_runtime.dart';

class JsPluginException implements Exception {
  JsPluginException(this.message, {this.function = ''});

  final String message;
  final String function;

  @override
  String toString() =>
      function.isEmpty ? 'JS 插件错误：$message' : 'JS 插件错误（$function）：$message';
}

/// 插件脚本的执行宿主。
///
/// 设计取舍：只用 **同步求值**，不碰 flutter_js 的消息通道。
/// 网络请求、变量刷新这些异步动作全部由 Dart 侧完成，JS 只负责
/// 「把一份响应变成标准结构」这件纯计算的事。好处是：
///   * 没有跨语言回调，不会卡住事件循环；
///   * 插件行为可预测，出错能拿到行号；
///   * 同一个 runtime 能服务所有站点。
///
/// 代价是插件不能自己发请求 —— 需要多步请求的站点用 `vars` 声明，
/// Dart 会按顺序取好再一次性交给脚本。
class JsHost {
  JsHost._();

  static JavascriptRuntime? _rt;
  static final Set<String> _loaded = {};

  static JavascriptRuntime get _runtime {
    final existing = _rt;
    if (existing != null) return existing;
    final rt = getJavascriptRuntime(xhr: false);
    rt.evaluate(pqRuntimeJs);
    _rt = rt;
    return rt;
  }

  /// 让脚本在独立闭包里注册函数，避免不同插件的同名函数互相覆盖。
  static void _ensureLoaded(String pluginId, String script) {
    final key = '$pluginId@${script.length}:${script.hashCode}';
    if (_loaded.contains(key)) return;

    final wrapper = '''
globalThis.__poqi = globalThis.__poqi || {};
(function(){
$script

  var picked = {};
  var names = ['home','category','search','detail','play','filters'];
  for (var i = 0; i < names.length; i++) {
    var n = names[i];
    if (typeof globalThis[n] === 'function') { picked[n] = globalThis[n]; delete globalThis[n]; }
  }
  globalThis.__poqi[${jsonEncode(pluginId)}] = picked;
})();
''';

    final result = _runtime.evaluate(wrapper);
    if (result.isError) {
      throw JsPluginException(_cleanError(result.stringResult));
    }
    _loaded.add(key);
  }

  /// 执行插件函数，返回已解码的 JSON 结构（Map / List / String / num / null）。
  static Object? call({
    required String pluginId,
    required String script,
    required String function,
    required Map<String, Object?> context,
  }) {
    if (script.trim().isEmpty) {
      throw JsPluginException('插件没有提供 script');
    }
    _ensureLoaded(pluginId, script);

    final rt = _runtime;
    // 用 JSON 往返传参：不依赖 FFI 的值映射规则，也天然支持嵌套结构。
    final payload = jsonEncode(jsonEncode(context));
    final assign = rt.evaluate('globalThis.__poqiCtx = JSON.parse($payload);');
    if (assign.isError) {
      throw JsPluginException(_cleanError(assign.stringResult), function: function);
    }

    final call = rt.evaluate('''
JSON.stringify((function(){
  var bag = globalThis.__poqi[${jsonEncode(pluginId)}] || {};
  var fn = bag[${jsonEncode(function)}];
  if (typeof fn !== 'function') {
    throw new Error('插件脚本缺少函数 ' + ${jsonEncode(function)} + '()');
  }
  var out = fn(globalThis.__poqiCtx);
  return out === undefined ? null : out;
})())
''');
    if (call.isError) {
      throw JsPluginException(_cleanError(call.stringResult), function: function);
    }

    final raw = call.stringResult;
    if (raw.isEmpty || raw == 'undefined' || raw == 'null') return null;
    try {
      return jsonDecode(raw);
    } catch (e) {
      throw JsPluginException('返回值不是合法 JSON：$e', function: function);
    }
  }

  /// QuickJS 的报错带一长串栈，界面上只留第一行可读信息。
  static String _cleanError(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '未知错误';
    final firstLine = text.split('\n').first.trim();
    return firstLine.isEmpty ? text : firstLine;
  }

  @visibleForTesting
  static void reset() {
    _loaded.clear();
    try {
      _rt?.dispose();
    } catch (_) {
      // 测试环境没有原生库，dispose 可能失败，忽略。
    }
    _rt = null;
  }
}
