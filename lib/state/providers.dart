import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models/library.dart';
import '../domain/models/media.dart';
import '../domain/models/plugin.dart';
import '../domain/models/settings.dart';
import '../domain/models/site.dart';
import '../domain/plugin/runner.dart';

/// 在 main() 中覆盖，注入已完成初始化的内核。
final backendProvider = Provider<PoqiBackend>((ref) {
  throw UnimplementedError('backendProvider 必须在 ProviderScope 中覆盖');
});

final varCacheProvider = Provider<VarCache>((ref) => VarCache());

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(backendProvider).settings;

  Future<void> update(AppSettings next) async {
    state = next;
    ref.read(backendProvider).settings = next;
    await ref.read(backendProvider).settingsRepo.save(next);
  }

  Future<void> patch({
    ThemeMode? themeMode,
    String? deviceName,
    String? pairCode,
    bool? mcpEnabled,
    int? mcpPort,
    bool? syncEnabled,
    int? syncPort,
    bool? autoCheckUpdate,
    bool? preferProxy,
    String? repoOwner,
    String? repoName,
    int? searchConcurrency,
    bool? onboarded,
    String? skippedVersion,
  }) {
    return update(state.copyWith(
      themeMode: themeMode,
      deviceName: deviceName,
      pairCode: pairCode,
      mcpEnabled: mcpEnabled,
      mcpPort: mcpPort,
      syncEnabled: syncEnabled,
      syncPort: syncPort,
      autoCheckUpdate: autoCheckUpdate,
      preferProxy: preferProxy,
      repoOwner: repoOwner,
      repoName: repoName,
      searchConcurrency: searchConcurrency,
      onboarded: onboarded,
      skippedVersion: skippedVersion,
    ));
  }

  Future<void> toggleTheme() => patch(
        themeMode:
            state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      );
}

// ---------------------------------------------------------------------------
// 插件
// ---------------------------------------------------------------------------

final pluginsProvider = NotifierProvider<PluginsNotifier, List<PluginManifest>>(
  PluginsNotifier.new,
);

class PluginsNotifier extends Notifier<List<PluginManifest>> {
  @override
  List<PluginManifest> build() => ref.read(backendProvider).plugins();

  void reload() => state = ref.read(backendProvider).plugins();

  Future<void> save(PluginManifest plugin, {String message = ''}) async {
    await ref.read(backendProvider).pluginRepo.save(plugin, message: message);
    reload();
  }

  Future<void> delete(String id) async {
    await ref.read(backendProvider).pluginRepo.delete(id);
    reload();
    ref.read(sitesProvider.notifier).reload();
  }

  Future<void> restoreBuiltin(String id) async {
    await ref.read(backendProvider).pluginRepo.restoreBuiltin(id);
    reload();
  }

  PluginManifest? byId(String id) {
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// 站点
// ---------------------------------------------------------------------------

final sitesProvider = NotifierProvider<SitesNotifier, List<SiteBinding>>(
  SitesNotifier.new,
);

class SitesNotifier extends Notifier<List<SiteBinding>> {
  @override
  List<SiteBinding> build() => ref.read(backendProvider).sites();

  void reload() => state = ref.read(backendProvider).sites();

  Future<void> save(SiteBinding site) async {
    await ref.read(backendProvider).siteRepo.save(site);
    reload();
  }

  Future<void> delete(String id) async {
    await ref.read(backendProvider).siteRepo.delete(id);
    reload();
  }

  Future<void> toggle(String id) async {
    final site = state.firstWhere((e) => e.id == id);
    await save(site.copyWith(enabled: !site.enabled));
  }

  Future<void> reorder(List<String> ids) async {
    await ref.read(backendProvider).siteRepo.reorder(ids);
    reload();
  }

  SiteBinding? byId(String id) {
    for (final s in state) {
      if (s.id == id) return s;
    }
    return null;
  }
}

final enabledSitesProvider = Provider<List<SiteBinding>>((ref) {
  return ref.watch(sitesProvider).where((e) => e.enabled).toList();
});

/// 当前锁定的站点，null 表示「全部站点」聚合模式。
///
/// 顶栏的站点切换器写它；首页、分类、搜索都读它，
/// 这样"我只看这一个站"的意图在全应用一致。
final selectedSiteProvider = StateProvider<String?>((ref) => null);

/// 实际参与聚合的站点：受 [selectedSiteProvider] 约束，但站点被禁用或删除时自动回落。
final activeSitesProvider = Provider<List<SiteBinding>>((ref) {
  final sites = ref.watch(enabledSitesProvider);
  final id = ref.watch(selectedSiteProvider);
  if (id == null) return sites;
  final hit = sites.where((s) => s.id == id).toList();
  if (hit.isNotEmpty) return hit;

  // 选中的站点已不可用：延后一帧清空选择，避免在 build 期间改状态。
  final notifier = ref.read(selectedSiteProvider.notifier);
  Future.microtask(() => notifier.state = null);
  return sites;
});

/// 当前选中的站点对象（null 表示全部）。
final selectedSiteNameProvider = Provider<SiteBinding?>((ref) {
  final id = ref.watch(selectedSiteProvider);
  if (id == null) return null;
  for (final s in ref.watch(enabledSitesProvider)) {
    if (s.id == id) return s;
  }
  return null;
});

/// 站点 → 执行器（随插件与站点变化自动重建）。插件缺失时返回 null。
final runnerFactoryProvider = Provider<SiteRunner? Function(SiteBinding)>((ref) {
  ref.watch(pluginsProvider);
  ref.watch(sitesProvider);
  final backend = ref.watch(backendProvider);
  return backend.runnerOf;
});

// ---------------------------------------------------------------------------
// 媒体库
// ---------------------------------------------------------------------------

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, List<FavoriteEntry>>(FavoritesNotifier.new);

class FavoritesNotifier extends Notifier<List<FavoriteEntry>> {
  @override
  List<FavoriteEntry> build() => ref.read(backendProvider).libraryRepo.favorites();

  bool contains(String siteId, String itemId) =>
      state.any((e) => e.siteId == siteId && e.itemId == itemId);

  Future<bool> toggle(MediaItem item, String siteId) async {
    final added = await ref.read(backendProvider).libraryRepo.toggleFavorite(
          FavoriteEntry(
            siteId: siteId,
            itemId: item.id,
            title: item.title,
            poster: item.poster,
            year: item.year,
            remarks: item.remarks,
            addedAt: DateTime.now(),
          ),
        );
    state = ref.read(backendProvider).libraryRepo.favorites();
    return added;
  }

  Future<void> remove(String siteId, String itemId) async {
    await ref.read(backendProvider).libraryRepo.removeFavorite(siteId, itemId);
    state = ref.read(backendProvider).libraryRepo.favorites();
  }

  void reload() => state = ref.read(backendProvider).libraryRepo.favorites();
}

final historyProvider =
    NotifierProvider<HistoryNotifier, List<HistoryEntry>>(HistoryNotifier.new);

class HistoryNotifier extends Notifier<List<HistoryEntry>> {
  @override
  List<HistoryEntry> build() => ref.read(backendProvider).libraryRepo.history();

  Future<void> record(HistoryEntry entry) async {
    await ref.read(backendProvider).libraryRepo.upsertHistory(entry);
    state = ref.read(backendProvider).libraryRepo.history();
  }

  Future<void> remove(String siteId, String itemId) async {
    await ref.read(backendProvider).libraryRepo.removeHistory(siteId, itemId);
    state = ref.read(backendProvider).libraryRepo.history();
  }

  Future<void> clear() async {
    await ref.read(backendProvider).libraryRepo.clearHistory();
    state = const [];
  }

  void reload() => state = ref.read(backendProvider).libraryRepo.history();
}

/// 播放进度记忆：给"继续观看"用。
HistoryEntry? lastPlayed(List<HistoryEntry> list) => list.isEmpty ? null : list.first;
