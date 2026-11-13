import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' hide Response;
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../domain/models/sync.dart';
import '../backend.dart';

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Poqi-Pin, Mcp-Session-Id',
};

Response _json(Object? data, {int status = 200}) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json; charset=utf-8', ..._corsHeaders},
    );

/// 局域网同步服务端：手机、平板、PC 任一端开启，其它设备即可拉取/推送。
class SyncServer {
  SyncServer({
    required this.backend,
    required this.deviceName,
    this.pin = '',
  });

  final PoqiBackend backend;
  final String deviceName;

  /// 4 位配对码，为空表示不校验（不建议）。
  String pin;

  HttpServer? _server;

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<int> start(int desiredPort) async {
    await stop();
    final router = Router()
      ..get('/poqi/hello', _hello)
      ..post('/poqi/pull', _pull)
      ..post('/poqi/push', _push)
      ..get('/', _index);

    final handler = const Pipeline()
        .addMiddleware(_cors)
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, desiredPort);
    _server!.autoCompress = true;
    debugPrint('Poqi 同步服务已启动: ${_server!.port}');
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware get _cors => (inner) {
        return (request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: _corsHeaders);
          }
          final resp = await inner(request);
          return resp.change(headers: _corsHeaders);
        };
      };

  Response _index(Request req) => Response.ok(
        '<!doctype html><meta charset="utf-8"><title>Poqi</title>'
        '<body style="font-family:system-ui;background:#0b0d0e;color:#f3f0e8;padding:40px">'
        '<h1 style="letter-spacing:-1px">Poqi 局域网服务</h1>'
        '<p>$deviceName 正在共享数据。配对码：<b style="color:#e8b564;font-size:22px">${pin.isEmpty ? '未设置' : pin}</b></p>'
        '<p style="color:#9da7a5">在另一台设备的「连接」页选择本机即可同步插件、站点、收藏与观看进度。</p>'
        '</body>',
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

  bool _authorized(Request req) {
    if (pin.isEmpty) return true;
    return req.headers['x-poqi-pin'] == pin;
  }

  Response _hello(Request req) {
    final host = req.requestedUri.host;
    return _json({
      'svc': 'poqi',
      'id': backend.deviceId,
      'name': deviceName,
      'platform': Platform.operatingSystem,
      'version': '1.0.0',
      'host': host,
      'port': port,
      'requiresPin': pin.isNotEmpty,
      'stats': backend.stats(),
    });
  }

  Future<Response> _pull(Request req) async {
    if (!_authorized(req)) {
      return _json({'error': '配对码不正确'}, status: 401);
    }
    return _json(backend.snapshot().toJson());
  }

  Future<Response> _push(Request req) async {
    if (!_authorized(req)) {
      return _json({'error': '配对码不正确'}, status: 401);
    }
    try {
      final body = await req.readAsString();
      final data = jsonDecode(body);
      if (data is! Map) return _json({'error': '请求体必须是快照对象'}, status: 400);
      final snapshot = SyncSnapshot.fromJson(data.cast<String, dynamic>());
      final report = await backend.merge(snapshot);
      return _json({'ok': true, 'report': report.toJson()});
    } catch (e) {
      return _json({'error': '$e'}, status: 400);
    }
  }
}

/// 客户端：发现设备后拉取 / 推送。
class SyncClient {
  SyncClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;

  Future<Map<String, dynamic>> hello(SyncPeer peer, {String pin = ''}) async {
    final resp = await _dio.get<dynamic>(
      '${peer.endpoint}/poqi/hello',
      options: Options(headers: {'X-Poqi-Pin': pin}),
    );
    final data = resp.data;
    if (data is Map) return data.cast<String, dynamic>();
    throw StateError('设备返回了非预期的响应');
  }

  Future<SyncSnapshot> pull(SyncPeer peer, {required String pin}) async {
    final resp = await _dio.post<dynamic>(
      '${peer.endpoint}/poqi/pull',
      options: Options(headers: {'X-Poqi-Pin': pin}),
    );
    final data = resp.data;
    if (data is! Map) throw StateError('拉取失败：响应格式错误');
    if (data['error'] != null) throw StateError('${data['error']}');
    return SyncSnapshot.fromJson(data.cast<String, dynamic>());
  }

  Future<SyncReport> push(SyncSnapshot snapshot, SyncPeer peer, {required String pin}) async {
    final resp = await _dio.post<dynamic>(
      '${peer.endpoint}/poqi/push',
      data: snapshot.toJson(),
      options: Options(headers: {'X-Poqi-Pin': pin}),
    );
    final data = resp.data;
    if (data is! Map) throw StateError('推送失败：响应格式错误');
    if (data['error'] != null) throw StateError('${data['error']}');
    return SyncReport(
      pluginsAdded: _i(data['report']?['pluginsAdded']),
      pluginsUpdated: _i(data['report']?['pluginsUpdated']),
      sitesAdded: _i(data['report']?['sitesAdded']),
      sitesUpdated: _i(data['report']?['sitesUpdated']),
      favoritesMerged: _i(data['report']?['favoritesMerged']),
      historyMerged: _i(data['report']?['historyMerged']),
      skipped: _i(data['report']?['skipped']),
    );
  }

  int _i(Object? v) => (v as num?)?.toInt() ?? 0;
}
