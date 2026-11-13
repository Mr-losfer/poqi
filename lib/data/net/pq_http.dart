import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// 一次请求的调试记录（插件测试台会展示它）。
class HttpTraceEntry {
  HttpTraceEntry({
    required this.method,
    required this.url,
    required this.startedAt,
    this.status,
    this.durationMs,
    this.bytes = 0,
    this.error,
    this.preview,
  });

  final String method;
  final String url;
  final DateTime startedAt;
  final int? status;
  final int? durationMs;
  final int bytes;
  final String? error;
  final String? preview;

  bool get ok => error == null && (status ?? 0) >= 200 && (status ?? 0) < 400;

  Map<String, dynamic> toJson() => {
        'method': method,
        'url': url,
        'status': status,
        'durationMs': durationMs,
        'bytes': bytes,
        if (error != null) 'error': error,
      };
}

class PqHttpResponse {
  const PqHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.finalUrl,
    this.durationMs = 0,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final String finalUrl;
  final int durationMs;

  bool get ok => statusCode >= 200 && statusCode < 400;

  Object? get json {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

class PqHttpException implements Exception {
  PqHttpException(this.message, {this.statusCode, this.url});

  final String message;
  final int? statusCode;
  final String? url;

  @override
  String toString() => message;
}

/// 统一 HTTP 出口：带超时、UA、请求追踪。
class PqHttp {
  PqHttp({Map<String, String>? defaultHeaders, int timeoutMs = 15000})
      : _timeoutMs = timeoutMs,
        _defaultHeaders = {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/json,application/xhtml+xml,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
          ...?defaultHeaders,
        };

  final int _timeoutMs;
  final Map<String, String> _defaultHeaders;
  final List<HttpTraceEntry> trace = [];
  final Dio _dio = Dio(BaseOptions(
    followRedirects: true,
    maxRedirects: 5,
    responseType: ResponseType.plain,
    validateStatus: (s) => s != null && s < 500,
  ));

  void _push(HttpTraceEntry e) {
    trace.insert(0, e);
    if (trace.length > 60) trace.removeLast();
  }

  Future<PqHttpResponse> request({
    required String url,
    String method = 'GET',
    Map<String, String>? headers,
    Map<String, String>? query,
    Object? body,
    int? timeoutMs,
    Map<String, String>? cookies,
  }) async {
    final started = DateTime.now();
    final mergedHeaders = {..._defaultHeaders, ...?headers};
    if (cookies != null && cookies.isNotEmpty) {
      mergedHeaders['Cookie'] = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    try {
      final resp = await _dio
          .request<String>(
            url,
            data: body,
            queryParameters: query,
            options: Options(
              method: method.toUpperCase(),
              headers: mergedHeaders,
              sendTimeout: Duration(milliseconds: timeoutMs ?? _timeoutMs),
              receiveTimeout: Duration(milliseconds: timeoutMs ?? _timeoutMs),
            ),
          )
          .timeout(Duration(milliseconds: (timeoutMs ?? _timeoutMs) + 2000));

      final text = resp.data ?? '';
      final ms = DateTime.now().difference(started).inMilliseconds;
      _push(HttpTraceEntry(
        method: method,
        url: resp.realUri.toString(),
        startedAt: started,
        status: resp.statusCode,
        durationMs: ms,
        bytes: text.length,
        preview: text.length > 240 ? text.substring(0, 240) : text,
      ));
      return PqHttpResponse(
        statusCode: resp.statusCode ?? 0,
        body: text,
        headers: resp.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
        finalUrl: resp.realUri.toString(),
        durationMs: ms,
      );
    } on DioException catch (e) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      final msg = _humanize(e);
      _push(HttpTraceEntry(
        method: method,
        url: url,
        startedAt: started,
        status: e.response?.statusCode,
        durationMs: ms,
        error: msg,
      ));
      throw PqHttpException(msg, statusCode: e.response?.statusCode, url: url);
    } catch (e) {
      _push(HttpTraceEntry(
        method: method,
        url: url,
        startedAt: started,
        error: '$e',
      ));
      throw PqHttpException('$e', url: url);
    }
  }

  String _humanize(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，站点可能无法直连';
      case DioExceptionType.receiveTimeout:
        return '响应超时';
      case DioExceptionType.sendTimeout:
        return '请求超时';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.connectionError:
        return '网络不可达或站点拒绝连接';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        final s = e.response?.statusCode;
        if (s == 401 || s == 403) return 'HTTP $s：鉴权失败，请检查 Cookie / Token 配置';
        if (s == 404) return 'HTTP 404：接口路径不存在';
        if (s != null) return 'HTTP $s';
        return e.message ?? '请求失败';
    }
  }

  void clearTrace() => trace.clear();
}
