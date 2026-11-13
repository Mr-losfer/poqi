import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../domain/models/plugin.dart';
import '../../domain/plugin/diff.dart';
import '../../domain/plugin/validator.dart';
import '../backend.dart';

const _cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Mcp-Session-Id, X-Poqi-Pin',
};

Response _json(Object? data, {int status = 200}) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json; charset=utf-8', ..._cors},
    );

/// 局域网 MCP 服务端（JSON-RPC 2.0 over HTTP）。
///
/// 让任意 MCP 客户端（Claude Desktop / IDE / 自研 Agent）直接读写 Poqi 的
/// 插件、站点与媒体库，实现"用自然语言写插件、跑搜索、改代码"。
class McpServer {
  McpServer({required this.backend, required this.deviceName, this.pin = ''});

  final PoqiBackend backend;
  final String deviceName;
  String pin;

  HttpServer? _server;

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  static const protocolVersion = '2024-11-05';

  Future<int> start(int desiredPort) async {
    await stop();
    final router = Router()
      ..get('/', _info)
      ..get('/mcp', _info)
      ..post('/mcp', _handleRpc)
      ..get('/mcp/tools', _toolsIndex)
      ..get('/mcp/sse', _sse);

    final handler = const Pipeline().addMiddleware(_middleware).addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, desiredPort);
    _server!.autoCompress = true;
    debugPrint('Poqi MCP 已启动: http://0.0.0.0:${_server!.port}/mcp');
    return _server!.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware get _middleware => (inner) => (request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _cors);
        }
        if (pin.isNotEmpty && request.headers['x-poqi-pin'] != pin) {
          return _json({'error': '配对码不正确'}, status: 401);
        }
        final resp = await inner(request);
        return resp.change(headers: _cors);
      };

  Response _info(Request req) => _json({
        'name': 'poqi',
        'device': deviceName,
        'protocolVersion': protocolVersion,
        'transport': 'http-jsonrpc',
        'endpoint': '/mcp',
        'tools': _tools.length,
        'hint': 'POST /mcp 发送 JSON-RPC 2.0 请求；tools/list 查看全部工具。',
      });

  Response _toolsIndex(Request req) => _json({
        'tools': [
          for (final t in _tools)
            {'name': t.name, 'description': t.description, 'inputSchema': t.schema},
        ],
      });

  Response _sse(Request req) {
    // 兼容旧式 SSE 传输：先告知消息端点，然后保持连接。
    final controller = StreamController<List<int>>();
    controller.add(utf8.encode('event: endpoint\ndata: /mcp\n\n'));
    final timer = Timer.periodic(const Duration(seconds: 20), (_) {
      controller.add(utf8.encode(': ping\n\n'));
    });
    controller.onCancel = timer.cancel;
    return Response.ok(
      controller.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
        ..._cors,
      },
    );
  }

  Future<Response> _handleRpc(Request req) async {
    String raw;
    try {
      raw = await req.readAsString();
    } catch (e) {
      return _json(_error(null, -32700, '无法读取请求体: $e'));
    }
    if (raw.trim().isEmpty) {
      return _json(_error(null, -32600, '请求体为空'));
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      return _json(_error(null, -32700, 'JSON 解析失败'));
    }

    if (decoded is List) {
      final results = <Object?>[];
      for (final item in decoded) {
        final r = await _dispatch(item);
        if (r != null) results.add(r);
      }
      if (results.isEmpty) return Response(202, headers: _cors);
      return _json(results);
    }
    final result = await _dispatch(decoded);
    if (result == null) return Response(202, headers: _cors);
    return _json(result);
  }

  Future<Map<String, dynamic>?> _dispatch(Object? payload) async {
    if (payload is! Map) {
      return _error(null, -32600, '请求必须是 JSON-RPC 对象');
    }
    final id = payload['id'];
    final method = '${payload['method'] ?? ''}';
    final params = payload['params'] is Map
        ? (payload['params'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    if (id == null) {
      // 通知消息：不回包。
      return null;
    }

    try {
      switch (method) {
        case 'initialize':
          return _result(id, {
            'protocolVersion': protocolVersion,
            'capabilities': {
              'tools': {'listChanged': false},
              'resources': {'subscribe': false, 'listChanged': false},
              'logging': {},
            },
            'serverInfo': {
              'name': 'poqi',
              'version': '1.0.0',
              'title': 'Poqi 影视聚合与插件平台',
            },
            'instructions':
                'Poqi 是一个可编程的影视聚合器。可以用 poqi_search 跨站点搜索，'
                    'poqi_get_detail 读取剧集，poqi_save_plugin / poqi_apply_patch 编写与修改插件规则。',
          });
        case 'ping':
          return _result(id, {});
        case 'tools/list':
          return _result(id, {
            'tools': [
              for (final t in _tools)
                {
                  'name': t.name,
                  'description': t.description,
                  'inputSchema': t.schema,
                },
            ],
          });
        case 'tools/call':
          final name = '${params['name'] ?? ''}';
          final args = params['arguments'] is Map
              ? (params['arguments'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          final tool = _tools.where((t) => t.name == name).firstOrNull;
          if (tool == null) {
            return _error(id, -32602, '未知工具 $name');
          }
          try {
            final value = await tool.handler(args);
            return _result(id, {
              'content': [
                {
                  'type': 'text',
                  'text': value is String ? value : const JsonEncoder.withIndent('  ').convert(value),
                },
              ],
              'isError': false,
            });
          } catch (e) {
            return _result(id, {
              'content': [
                {'type': 'text', 'text': '执行失败：$e'},
              ],
              'isError': true,
            });
          }
        case 'resources/list':
          return _result(id, {'resources': []});
        case 'prompts/list':
          return _result(id, {'prompts': []});
        default:
          return _error(id, -32601, '不支持的方法 $method');
      }
    } catch (e, st) {
      debugPrint('MCP 处理异常: $e\n$st');
      return _error(id, -32603, '内部错误：$e');
    }
  }

  Map<String, dynamic> _result(Object? id, Object? result) =>
      {'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, dynamic> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  List<_Tool> get _tools => [
        _Tool(
          name: 'poqi_get_state',
          description: '读取 Poqi 当前状态：插件数、站点数、收藏与历史数量、本机信息。',
          schema: const {'type': 'object', 'properties': {}},
          handler: (args) async => backend.stats(),
        ),
        _Tool(
          name: 'poqi_list_plugins',
          description: '列出全部插件（含内置），返回 id/name/version/engine/端点列表。',
          schema: const {'type': 'object', 'properties': {}},
          handler: (args) async => [
            for (final p in backend.plugins())
              {
                'id': p.id,
                'name': p.name,
                'version': p.version,
                'engine': p.engine.name,
                'builtin': p.builtin,
                'endpoints': p.endpoints.keys.toList(),
                'configKeys': p.config.map((e) => e.key).toList(),
              },
          ],
        ),
        _Tool(
          name: 'poqi_get_plugin',
          description: '读取单个插件的完整 JSON 规则。',
          schema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '插件 id'},
            },
            'required': ['id'],
          },
          handler: (args) async {
            final id = '${args['id'] ?? ''}';
            final p = backend.pluginRepo.byId(id);
            if (p == null) throw StateError('插件不存在：$id');
            return p.toJsonString();
          },
        ),
        _Tool(
          name: 'poqi_validate_plugin',
          description: '校验插件 JSON 是否符合 Poqi 插件规范 v1，返回错误/警告列表。',
          schema: {
            'type': 'object',
            'properties': {
              'plugin': {
                'type': ['object', 'string'],
                'description': '插件 JSON 对象或其字符串',
              },
            },
            'required': ['plugin'],
          },
          handler: (args) async {
            final raw = args['plugin'];
            final manifest = raw is String
                ? PluginManifest.fromJsonString(raw)
                : PluginManifest.fromJson((raw as Map).cast<String, dynamic>());
            final issues = const PluginValidator().validate(manifest);
            return [
              for (final i in issues)
                {'level': i.level.name, 'message': i.message, 'path': i.path},
            ];
          },
        ),
        _Tool(
          name: 'poqi_save_plugin',
          description: '创建或覆盖插件（全量写入）。会生成一条版本记录，可用于回滚。',
          schema: {
            'type': 'object',
            'properties': {
              'plugin': {'type': ['object', 'string'], 'description': '完整插件 JSON'},
              'message': {'type': 'string', 'description': '本次修改说明'},
            },
            'required': ['plugin'],
          },
          handler: (args) async {
            final raw = args['plugin'];
            final manifest = raw is String
                ? PluginManifest.fromJsonString(raw)
                : PluginManifest.fromJson((raw as Map).cast<String, dynamic>());
            final issues = const PluginValidator().validate(manifest);
            final errors = issues.where((e) => e.isError).toList();
            if (errors.isNotEmpty) {
              return {
                'saved': false,
                'errors': [for (final e in errors) e.message],
              };
            }
            await backend.pluginRepo.save(
              manifest,
              message: '${args['message'] ?? 'MCP 写入'}',
            );
            return {'saved': true, 'id': manifest.id, 'version': manifest.version};
          },
        ),
        _Tool(
          name: 'poqi_apply_patch',
          description: '对插件应用 unified diff 补丁（差量修改），失败会返回冲突行号。',
          schema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'patch': {'type': 'string', 'description': '@@ 开头的 unified diff'},
              'message': {'type': 'string'},
            },
            'required': ['id', 'patch'],
          },
          handler: (args) async {
            final id = '${args['id']}';
            final patch = '${args['patch']}';
            final rev = await backend.pluginRepo.applyPatchToLatest(
              id,
              patch,
              message: '${args['message'] ?? 'MCP 补丁'}',
            );
            return {'applied': true, 'revision': rev.seq, 'added': rev.added, 'removed': rev.removed};
          },
        ),
        _Tool(
          name: 'poqi_list_revisions',
          description: '列出插件的历史版本（含补丁），可用于审计或回滚。',
          schema: {
            'type': 'object',
            'properties': {'id': {'type': 'string'}},
            'required': ['id'],
          },
          handler: (args) async {
            final id = '${args['id']}';
            return [
              for (final r in backend.pluginRepo.revisions(id))
                {
                  'seq': r.seq,
                  'savedAt': r.savedAt.toIso8601String(),
                  'message': r.message,
                  'added': r.added,
                  'removed': r.removed,
                  'full': r.full,
                  'patch': r.patch,
                },
            ];
          },
        ),
        _Tool(
          name: 'poqi_list_sites',
          description: '列出已绑定站点：id/名称/插件/启用状态/健康信息。',
          schema: const {'type': 'object', 'properties': {}},
          handler: (args) async => [
            for (final s in backend.sites())
              {
                'id': s.id,
                'name': s.name,
                'pluginId': s.pluginId,
                'enabled': s.enabled,
                'baseUrl': s.baseUrl,
                'lastCheckOk': s.lastCheckOk,
                'latencyMs': s.latencyMs,
              },
          ],
        ),
        _Tool(
          name: 'poqi_search',
          description: '跨所有启用站点聚合搜索，返回去重后的媒体条目。',
          schema: {
            'type': 'object',
            'properties': {
              'keyword': {'type': 'string'},
              'limit': {'type': 'integer', 'default': 20},
            },
            'required': ['keyword'],
          },
          handler: (args) async {
            final kw = '${args['keyword'] ?? ''}';
            final limit = (args['limit'] as num?)?.toInt() ?? 20;
            final items = await backend.searchAll(kw, perSite: 8);
            return [
              for (final it in items.take(limit))
                {
                  'title': it.title,
                  'year': it.year,
                  'score': it.score,
                  'site': it.sourceName,
                  'siteId': it.sourceId,
                  'id': it.id,
                  'remarks': it.remarks,
                },
            ];
          },
        ),
        _Tool(
          name: 'poqi_get_detail',
          description: '读取某站点上一条媒体的详情与剧集列表。',
          schema: {
            'type': 'object',
            'properties': {
              'siteId': {'type': 'string'},
              'itemId': {'type': 'string'},
            },
            'required': ['siteId', 'itemId'],
          },
          handler: (args) async {
            final siteId = '${args['siteId']}';
            final itemId = '${args['itemId']}';
            final site = backend.sites().where((e) => e.id == siteId).firstOrNull;
            if (site == null) throw StateError('站点不存在：$siteId');
            final detail = await backend.detailOf(site, itemId);
            if (detail == null) throw StateError('该站点的插件不可用');
            return {
              'title': detail.item.title,
              'intro': detail.intro,
              'lines': [
                for (final l in detail.lines)
                  {
                    'name': l.name,
                    'episodes': [for (final e in l.episodes) e.name],
                  },
              ],
            };
          },
        ),
        _Tool(
          name: 'poqi_export_snapshot',
          description: '导出可同步/备份的数据快照（插件、站点、收藏、历史）。',
          schema: const {'type': 'object', 'properties': {}},
          handler: (args) async => backend.snapshot().toJson(),
        ),
      ];
}

class _Tool {
  const _Tool({
    required this.name,
    required this.description,
    required this.schema,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, dynamic> schema;
  final Future<Object?> Function(Map<String, dynamic> args) handler;
}
