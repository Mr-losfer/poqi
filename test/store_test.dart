import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:poqi/data/repositories.dart';
import 'package:poqi/data/store.dart';
import 'package:poqi/domain/models/library.dart';
import 'package:poqi/domain/models/plugin.dart';
import 'package:poqi/domain/models/site.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：`JsonStore.getList` 曾经在 key 不存在时返回 `const []`，
/// 而所有仓库都是「取出 → add/insert/removeWhere → 写回」，
/// 于是首次保存必定抛 `Unsupported operation: Cannot add to an unmodifiable list`。
///
/// 这个 bug 让「新建插件」「修改插件」「添加站点」「MCP 写入」「收藏」
/// 在全新安装的设备上全部静默失效（异常在 async 里被吞，界面毫无反应）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('空库 getList 返回可变列表', () async {
    final store = await JsonStore.open();
    final list = store.getList('anything');
    expect(list, isEmpty);
    list.add({'id': 'x'});
    expect(list, hasLength(1));
  });

  test('全新安装：插件首次保存不抛异常且能读回', () async {
    final store = await JsonStore.open();
    final repo = PluginRepository(store);

    const manifest = PluginManifest(
      id: 'custom.1',
      name: '测试插件',
      version: '1.0.0',
      engine: PluginEngine.http,
      baseUrl: 'https://example.com',
    );

    await repo.save(manifest, message: '首次保存');

    final all = repo.all();
    expect(all.map((e) => e.id), contains('custom.1'));
    expect(repo.byId('custom.1')?.name, '测试插件');
    // 首次保存应生成一条全量版本记录
    expect(repo.revisions('custom.1'), hasLength(1));
    expect(repo.revisions('custom.1').first.full, isTrue);
  });

  test('全新安装：站点首次保存不抛异常且能读回', () async {
    final store = await JsonStore.open();
    final repo = SiteRepository(store);

    await repo.save(
      const SiteBinding(
        id: 'site_1',
        pluginId: 'custom.1',
        name: '我的站点',
        baseUrl: 'https://a.example.com',
      ),
    );

    expect(repo.all().map((e) => e.id), contains('site_1'));
  });

  test('全新安装：收藏与历史首次写入可用', () async {
    final store = await JsonStore.open();
    final repo = LibraryRepository(store);

    await repo.toggleFavorite(
      FavoriteEntry(
        siteId: 's1',
        itemId: 'i1',
        title: '某片',
        addedAt: DateTime(2026, 1, 1),
      ),
    );
    expect(repo.favorites(), hasLength(1));

    await repo.upsertHistory(
      HistoryEntry(
        siteId: 's1',
        siteName: '源一',
        itemId: 'i1',
        title: '某片',
        lineIndex: 0,
        episodeIndex: 1,
        episodeName: '第 2 集',
        positionSec: 12,
        durationSec: 24,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    expect(repo.history(), hasLength(1));
  });

  test('损坏的 JSON 不会让列表退化成不可变值', () async {
    SharedPreferences.setMockInitialValues({
      StoreKeys.plugins: '{ not json',
      StoreKeys.sites: '{"a":1}',
    });
    final store = await JsonStore.open();
    final list = store.getList(StoreKeys.plugins);
    expect(list, isEmpty);
    list.add({'id': 'x'}); // 不应抛
    expect(jsonEncode(list), isNotEmpty);
    expect(store.getList(StoreKeys.sites), isEmpty);
  });
}
