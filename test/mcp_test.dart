import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poqi/data/backend.dart';
import 'package:poqi/data/mcp/mcp_server.dart';
import 'package:poqi/data/net/pq_http.dart';
import 'package:poqi/data/repositories.dart';
import 'package:poqi/data/store.dart';
import 'package:poqi/domain/plugin/runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MCP 端到端：起一个真实的 HTTP 服务，用真实 socket 调 JSON-RPC。
///
/// 覆盖三件事：
///   1. 端点不再要求配对码（曾经这里 401，AI 客户端一律写不进去）；
///   2. `poqi_save_plugin` / `poqi_save_site` 能把数据真正落库；
///   3. 写入后 onMutated 会被触发，界面才有机会刷新。
void main() {
  late PoqiBackend backend;
  late McpServer server;
  late int port;
  late int mutations;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      StoreKeys.settings: jsonEncode({'onboarded': true, 'autoCheckUpdate': false}),
    });
    final store = await JsonStore.open();
    final settingsRepo = SettingsRepository(store);
    final siteRepo = SiteRepository(store);
    final pluginRepo = PluginRepository(store);

    backend = PoqiBackend(
      store: store,
      pluginRepo: pluginRepo,
      siteRepo: siteRepo,
      libraryRepo: LibraryRepository(store),
      settingsRepo: settingsRepo,
      http: PqHttp(),
      varCache: VarCache(),
      settings: settingsRepo.load(),
      deviceId: 'test-device',
      deviceName: '测试机',
    );

    mutations = 0;
    server = McpServer(
      backend: backend,
      deviceName: '测试机',
      onMutated: () => mutations++,
    );
    port = await server.start(0);
  });

  tearDown(() async {
    await server.stop();
  });

  Future<Map<String, dynamic>> rpc(
    String method, {
    Map<String, dynamic>? params,
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
      req.headers.contentType = ContentType.json;
      headers?.forEach(req.headers.set);
      req.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        if (params != null) 'params': params,
      }));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      expect(resp.statusCode, 200, reason: 'HTTP ${resp.statusCode}: $body');
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> call(String tool, Map<String, dynamic> args) async {
    final res = await rpc('tools/call', params: {'name': tool, 'arguments': args});
    final result = res['result'] as Map<String, dynamic>?;
    expect(result, isNotNull, reason: '缺少 result: $res');
    final content = (result!['content'] as List).first as Map;
    return jsonDecode(content['text'] as String) as Map<String, dynamic>;
  }

  test('不带配对码也能握手', () async {
    final res = await rpc('initialize', params: {});
    expect(res['error'], isNull);
    final result = res['result'] as Map<String, dynamic>;
    expect(result['protocolVersion'], isNotEmpty);
    expect(result['serverInfo']['name'], 'poqi');
  });

  test('tools/list 暴露 12 个工具', () async {
    final res = await rpc('tools/list');
    final tools = (res['result'] as Map)['tools'] as List;
    expect(tools, hasLength(12));
    final names = tools.map((e) => (e as Map)['name']).toList();
    expect(names, contains('poqi_save_plugin'));
    expect(names, contains('poqi_save_site'));
  });

  test('poqi_save_plugin 真正落库并触发刷新', () async {
    final before = backend.plugins().length;
    final out = await call('poqi_save_plugin', {
      'plugin': {
        'spec': 1,
        'id': 'mcp.test',
        'name': 'MCP 写入的插件',
        'version': '1.0.0',
        'engine': 'js',
        'script': 'function home(ctx) { return []; }',
        'baseUrl': 'https://example.com',
        'endpoints': {
          'home': {
            'request': {'path': '/'},
            'js': 'home',
          },
        },
      },
      'message': '测试写入',
    });

    expect(out['saved'], isTrue, reason: '$out');
    expect(out['id'], 'mcp.test');
    expect(backend.plugins().length, before + 1);
    expect(backend.pluginRepo.byId('mcp.test')?.name, 'MCP 写入的插件');
    expect(backend.pluginRepo.revisions('mcp.test'), isNotEmpty);
    expect(mutations, greaterThan(0), reason: '写入后没有通知界面刷新');
  });

  test('poqi_save_site 建站点并回报缺失配置', () async {
    await call('poqi_save_plugin', {
      'plugin': {
        'spec': 1,
        'id': 'mcp.site.plugin',
        'name': '带配置的插件',
        'version': '1.0.0',
        'engine': 'js',
        'script': 'function home(ctx) { return []; }',
        'baseUrl': 'https://example.com',
        'config': [
          {'key': 'token', 'label': '令牌', 'required': true},
        ],
        'endpoints': {
          'home': {
            'request': {'path': '/'},
            'js': 'home',
          },
        },
      },
    });

    final out = await call('poqi_save_site', {
      'pluginId': 'mcp.site.plugin',
      'name': '我的站点',
      'baseUrl': 'https://a.example.com',
      'config': {'token': ''},
    });

    expect(out['saved'], isTrue, reason: '$out');
    expect(out['missingConfig'], contains('token（令牌）'));
    expect(
      backend.sites().any((s) => s.name == '我的站点'),
      isTrue,
      reason: '站点没有落库',
    );
  });

  test('引用不存在的插件时给出可读错误', () async {
    final out = await call('poqi_save_site', {
      'pluginId': 'nope.nope',
      'name': 'x',
    });
    expect(out['saved'], isFalse);
    expect('${out['error']}', contains('不存在'));
  });

  test('poqi_apply_patch 能改已有插件', () async {
    await call('poqi_save_plugin', {
      'plugin': {
        'spec': 1,
        'id': 'mcp.patch',
        'name': '待打补丁',
        'version': '1.0.0',
        'engine': 'js',
        'script': 'function home(ctx) { return []; }',
        'baseUrl': 'https://example.com',
        'endpoints': {
          'home': {
            'request': {'path': '/'},
            'js': 'home',
          },
        },
      },
    });

    final current = backend.pluginRepo.byId('mcp.patch')!.toJsonString();
    final next = current.replaceFirst('"name": "待打补丁"', '"name": "补丁后"');
    final patch = _unifiedDiff(current, next);

    final out = await call('poqi_apply_patch', {'id': 'mcp.patch', 'patch': patch});
    expect(out['applied'], isTrue, reason: '$out');
    expect(backend.pluginRepo.byId('mcp.patch')?.name, '补丁后');
  });
}

/// 只用于构造测试补丁：把整段当作一次替换。
String _unifiedDiff(String before, String after) {
  final a = before.split('\n');
  final b = after.split('\n');
  final buf = StringBuffer()
    ..writeln('--- a/plugin.json')
    ..writeln('+++ b/plugin.json')
    ..writeln('@@ -1,${a.length} +1,${b.length} @@');
  for (final line in a) {
    buf.writeln('-$line');
  }
  for (final line in b) {
    buf.writeln('+$line');
  }
  return buf.toString();
}
