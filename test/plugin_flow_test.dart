import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poqi/app.dart';
import 'package:poqi/data/backend.dart';
import 'package:poqi/data/net/pq_http.dart';
import 'package:poqi/data/repositories.dart';
import 'package:poqi/data/store.dart';
import 'package:poqi/domain/models/plugin.dart';
import 'package:poqi/domain/plugin/runner.dart';
import 'package:poqi/routes.dart';
import 'package:poqi/state/providers.dart';

/// 插件工坊的关键交互回归。
///
/// 起因是一个真实故障：`JsonStore.getList` 在 key 不存在时返回 `const []`，
/// 而 `PluginRepository.save` 直接对它 `add()`，于是在全新安装的设备上
/// 「新建插件」一点反应都没有（异常在 async 里被吞掉，界面毫无提示）。
/// MCP 的写入走同一条路径，也同样静默失败。
///
/// 这些用例从按钮点起，覆盖到数据真正落库，避免同类问题再次溜过去。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PoqiBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      StoreKeys.settings: jsonEncode({
        'autoCheckUpdate': false,
        'mcpEnabled': false,
        'syncEnabled': false,
        'onboarded': true,
        'themeMode': 'light',
      }),
    });
    final store = await JsonStore.open();
    final settingsRepo = SettingsRepository(store);
    final siteRepo = SiteRepository(store);
    final pluginRepo = PluginRepository(store);
    await siteRepo.seedIfEmpty();

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
  });

  Widget app() => ProviderScope(
        overrides: [backendProvider.overrideWithValue(backend)],
        child: const PoqiApp(),
      );

  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// appRouter 是全局单例，上一个用例停留的位置会带到下一个，
  /// 所以每次都显式导航，而不是点图标（选中态的图标会换成实心）。
  Future<void> openPluginsTab(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    appRouter.go('/home');
    await settle(tester, 6);
    appRouter.go('/plugins');
    await settle(tester);
  }

  testWidgets('插件页能打开，内置插件已列出', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await openPluginsTab(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('插件工坊'), findsWidgets);
    expect(find.text('苹果CMS v10'), findsWidgets);
    expect(find.text('TVBox 接口'), findsWidgets);
    // 列表里应该出现新建入口
    expect(find.text('新建插件'), findsWidgets);
  });

  testWidgets('新建插件 → 选 HTML 模板 → 真正落库并进入编辑器', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await openPluginsTab(tester);
    final before = backend.plugins().length;

    await tester.tap(find.text('新建插件').first);
    await settle(tester);

    // 模板选择对话框：三种脚本模板，不再出现 JSON 规则
    expect(find.text('HTML 站点'), findsOneWidget);
    expect(find.text('JSON 接口'), findsOneWidget);
    expect(find.text('空白脚本'), findsOneWidget);

    await tester.tap(find.text('HTML 站点'));
    await settle(tester, 16);

    expect(tester.takeException(), isNull);

    // 1. 数据落库
    final plugins = backend.plugins();
    expect(plugins.length, before + 1, reason: '新插件没有写进仓库');
    final created = plugins.where((p) => !p.builtin).toList();
    expect(created, hasLength(1), reason: '新建的插件没有被识别为自定义插件');
    expect(created.single.source, PluginSource.script, reason: '应该是单文件脚本形态');
    expect(created.single.engine, PluginEngine.js);
    expect(created.single.script, contains('function home'));
    expect(created.single.script, contains('var plugin'));
    expect(created.single.name, '我的站点', reason: '元信息应从脚本里读出来');
    expect(created.single.endpoints.containsKey('detail'), isTrue);

    // 2. 版本记录也写进去了（曾经这里会因为空 before 崩掉）
    expect(backend.pluginRepo.revisions(created.single.id), isNotEmpty);

    // 3. 页面确实跳到了编辑器
    expect(find.text('保存'), findsWidgets);
  });

  testWidgets('新建插件 → 选 JSON 接口模板 → config 被解析成表单字段', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await openPluginsTab(tester);
    await tester.tap(find.text('新建插件').first);
    await settle(tester);
    await tester.tap(find.text('JSON 接口'));
    await settle(tester, 16);

    expect(tester.takeException(), isNull);
    final created = backend.plugins().where((p) => !p.builtin).toList();
    expect(created, hasLength(1));
    expect(created.single.config.map((e) => e.key), contains('api'));
    expect(created.single.config.first.required, isTrue);
    expect(created.single.source, PluginSource.script);
  });

  testWidgets('点击插件卡片能进入详情页', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await openPluginsTab(tester);
    await tester.tap(find.text('苹果CMS v10').first);
    await settle(tester, 16);

    expect(tester.takeException(), isNull);
    // 详情页会展示端点与校验结果
    expect(find.textContaining('端点'), findsWidgets);
  });

  testWidgets('站点页签能添加站点', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await openPluginsTab(tester);
    await tester.tap(find.text('站点'));
    await settle(tester);

    final before = backend.sites().length;
    await tester.tap(find.text('添加站点').first);
    await settle(tester, 14);
    expect(tester.takeException(), isNull);
    // 只验证跳转成功（页面里有「保存」）
    expect(find.text('保存'), findsWidgets);
    expect(backend.sites().length, before, reason: '未保存前不应写入');
  });
}
