import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poqi/app.dart';
import 'package:poqi/core/ui/adaptive.dart';
import 'package:poqi/data/backend.dart';
import 'package:poqi/data/net/pq_http.dart';
import 'package:poqi/data/repositories.dart';
import 'package:poqi/data/store.dart';
import 'package:poqi/domain/models/plugin.dart';
import 'package:poqi/domain/models/site.dart';
import 'package:poqi/domain/plugin/runner.dart';
import 'package:poqi/state/providers.dart';

/// 端到端冒烟测试：真实拉起整个应用外壳，在三种断点下逐个切换 5 个 tab。
///
/// 刻意关闭网络与局域网服务，只验证「组件树建得起来、provider 接得上、
/// 布局不溢出、页面切换不抛异常」——这些是静态分析查不出来的盲区。
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
        'themeMode': 'dark',
      }),
    });
    final store = await JsonStore.open();
    final settingsRepo = SettingsRepository(store);
    final siteRepo = SiteRepository(store);
    final pluginRepo = PluginRepository(store);
    await siteRepo.seedIfEmpty();
    // 内置源已换成真实 HTTP 插件，测试环境无网络；
    // 额外挂一个演示引擎站点，保证首屏数据路径仍被覆盖。
    await pluginRepo.save(PluginManifest.fromJsonString(_demoPluginJson));
    await siteRepo.save(SiteBinding(
      id: 'site_smoke_demo',
      pluginId: 'poqi.demo.smoke',
      name: '冒烟演示源',
      baseUrl: 'https://demo.poqi.local',
      order: -1,
      config: const {},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
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

  /// 首页轮播是 7 秒周期定时器，pumpAndSettle 永远不会停，只能按帧推进。
  Future<void> settle(
    WidgetTester tester, [
    Duration total = const Duration(milliseconds: 900),
  ]) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(total ~/ 6);
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  }

  /// 依次点过 5 个 tab。导航项未选中时渲染描边图标、选中后换成实心图标，
  /// 而每次点击前目标 tab 必然处于未选中态，所以按描边图标定位最稳。
  Future<void> walkAllTabs(WidgetTester tester) async {
    const tabs = <(IconData, String, String?)>[
      (Icons.grid_view_outlined, '分类', '跨站点浏览，一处筛选，全部源生效'),
      (Icons.extension_outlined, '插件', '插件工坊'),
      (Icons.wifi_tethering_outlined, '连接', '同一 Wi-Fi 下，MCP 与数据同步都在本机完成'),
      (Icons.tune_outlined, '设置', '改动即时生效，并保存在本机'),
      (Icons.home_outlined, '首页', null),
    ];
    for (final (icon, label, marker) in tabs) {
      await tester.tap(find.byIcon(icon).first);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '切到「$label」时抛出异常');
      if (marker != null) {
        expect(
          find.text(marker).evaluate().isNotEmpty,
          isTrue,
          reason: '「$label」页没有渲染出预期内容（$marker）',
        );
      }
    }
  }

  group('应用外壳', () {
    testWidgets('手机断点 390×844：底部导航，五个 tab 可切换', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await settle(tester);
      expect(tester.takeException(), isNull);

      final ctx = tester.element(find.byType(Scaffold).first);
      expect(PqAdaptive.of(ctx), PqFormFactor.compact);

      await walkAllTabs(tester);
      await unmount(tester);
    });

    testWidgets('平板断点 700×1000：图标窄栏，五个 tab 可切换', (tester) async {
      tester.view.physicalSize = const Size(700 * 2, 1000 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await settle(tester);
      expect(tester.takeException(), isNull);

      final ctx = tester.element(find.byType(Scaffold).first);
      expect(PqAdaptive.of(ctx), PqFormFactor.medium);

      await walkAllTabs(tester);
      await unmount(tester);
    });

    testWidgets('桌面断点 1440×900：常驻抽屉，五个 tab 可切换', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await settle(tester);
      expect(tester.takeException(), isNull);

      final ctx = tester.element(find.byType(Scaffold).first);
      expect(PqAdaptive.of(ctx), PqFormFactor.expanded);

      await walkAllTabs(tester);
      await unmount(tester);
    });
  });

  group('首屏数据', () {
    testWidgets('演示插件能出片：首页渲染出多张可点击海报', (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await settle(tester, const Duration(seconds: 2));
      expect(tester.takeException(), isNull);

      // 演示目录 32 部片，首页 hero + 若干轨道，可点击元素必然不止几个。
      final tappable = find.byType(GestureDetector).evaluate().length;
      expect(tappable, greaterThan(5));

      await unmount(tester);
    });
  });
}

/// 冒烟测试专用演示插件：仅提供 home 端点，数据由 DemoRunner 生成。
const _demoPluginJson = '''
{
  "spec": 1,
  "id": "poqi.demo.smoke",
  "name": "冒烟演示源",
  "version": "1.0.0",
  "engine": "demo",
  "baseUrl": "https://demo.poqi.local",
  "endpoints": {
    "home": {
      "request": { "path": "/" },
      "parse": {
        "format": "json",
        "root": "list",
        "fields": { "id": "item.id", "title": "item.title" }
      }
    }
  }
}
''';
