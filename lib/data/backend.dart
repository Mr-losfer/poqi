import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/library.dart';
import '../domain/models/media.dart';
import '../domain/models/plugin.dart';
import '../domain/models/settings.dart';
import '../domain/models/site.dart';
import '../domain/models/sync.dart';
import '../domain/plugin/runner.dart';
import 'net/pq_http.dart';
import 'repositories.dart';
import 'store.dart';

/// 应用内核：把仓库、执行器、设置串成一个对象，
/// 供 UI、局域网同步与 MCP 三处共用同一套行为。
class PoqiBackend {
  PoqiBackend({
    required this.store,
    required this.pluginRepo,
    required this.siteRepo,
    required this.libraryRepo,
    required this.settingsRepo,
    required this.http,
    required this.varCache,
    required this.settings,
    required this.deviceId,
    required this.deviceName,
  });

  final JsonStore store;
  final PluginRepository pluginRepo;
  final SiteRepository siteRepo;
  final LibraryRepository libraryRepo;
  final SettingsRepository settingsRepo;
  final PqHttp http;
  final VarCache varCache;
  final String deviceId;
  final String deviceName;

  AppSettings settings;

  List<PluginManifest> plugins() => pluginRepo.all();

  List<SiteBinding> sites() => siteRepo.all();

  List<SiteBinding> enabledSites() => sites().where((e) => e.enabled).toList();

  PluginManifest? pluginOf(SiteBinding site) => pluginRepo.byId(site.pluginId);

  SiteRunner? runnerOf(SiteBinding site) {
    final plugin = pluginOf(site);
    if (plugin == null) return null;
    return runnerFor(
      plugin: plugin,
      site: site,
      http: http,
      varCache: varCache,
    );
  }

  /// 聚合首屏：并发拉取所有启用站点的首页。
  Future<List<MediaItem>> homeFeed({int perSite = 18}) async {
    final sites = enabledSites().where((s) {
      final p = pluginOf(s);
      return p != null && p.endpoints.containsKey('home');
    }).toList();

    final results = await Future.wait(sites.map((s) async {
      final runner = runnerOf(s);
      if (runner == null) return <MediaItem>[];
      try {
        final page = await runner.home();
        return page.items.take(perSite).toList();
      } catch (e) {
        debugPrint('首页拉取失败 ${s.name}: $e');
        return <MediaItem>[];
      }
    }));
    return dedupe(results.expand((e) => e).toList());
  }

  /// 全站聚合搜索：受控并发 + 渐进回调。
  Future<List<MediaItem>> searchAll(
    String keyword, {
    int perSite = 12,
    void Function(SiteBinding site, List<MediaItem> items, Object? error)? onSiteDone,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    final sites = enabledSites().where((s) {
      final p = pluginOf(s);
      return p != null && p.supportsSearch;
    }).toList();

    final out = <MediaItem>[];
    final limit = settings.searchConcurrency.clamp(1, 8);
    var index = 0;

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= sites.length) return;
        final site = sites[i];
        final runner = runnerOf(site);
        if (runner == null) continue;
        try {
          final page = await runner.search(kw).timeout(
                Duration(milliseconds: settings.aggregateTimeoutMs),
                onTimeout: () => MediaPage.empty,
              );
          final items = page.items.take(perSite).toList();
          out.addAll(items);
          onSiteDone?.call(site, items, null);
        } catch (e) {
          onSiteDone?.call(site, const [], e);
        }
      }
    }

    await Future.wait(List.generate(limit, (_) => worker()));
    return dedupe(out);
  }

  Future<MediaDetail?> detailOf(SiteBinding site, String itemId) async {
    final runner = runnerOf(site);
    if (runner == null) return null;
    return runner.detail(itemId);
  }

  /// 跨站找同名片源（详情页"其他站点也有"）。
  Future<List<MediaItem>> otherSources(MediaItem item, {int limit = 6}) async {
    final results = await searchAll(item.title, perSite: 4);
    final key = normalizeTitle(item.title);
    return results
        .where((e) => normalizeTitle(e.title) == key && e.sourceId != item.sourceId)
        .take(limit)
        .toList();
  }

  static String normalizeTitle(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\[\]【】()（）\-—:：·\s]'), '')
        .replaceAll(RegExp(r'第.*?季'), '');
  }

  /// 去重：同名同年的条目保留评分更高/靠前的一个，并记录其他来源。
  static List<MediaItem> dedupe(List<MediaItem> items) {
    final seen = <String, MediaItem>{};
    final order = <String>[];
    for (final it in items) {
      final key = '${normalizeTitle(it.title)}|${it.year ?? ''}';
      final existing = seen[key];
      if (existing == null) {
        seen[key] = it;
        order.add(key);
      } else {
        final a = double.tryParse(existing.score ?? '') ?? 0;
        final b = double.tryParse(it.score ?? '') ?? 0;
        if (b > a) seen[key] = it;
      }
    }
    return order.map((k) => seen[k]!).toList();
  }

  // ---------------- 同步 ----------------

  SyncSnapshot snapshot() => SyncSnapshot(
        deviceId: deviceId,
        deviceName: deviceName,
        exportedAt: DateTime.now(),
        plugins: pluginRepo.all().where((e) => !e.builtin).toList(),
        sites: sites(),
        favorites: libraryRepo.favorites(),
        history: libraryRepo.history(),
      );

  Future<SyncReport> merge(SyncSnapshot incoming) async {
    var report = const SyncReport();

    // 插件：同 id 以版本号高者为准
    for (final p in incoming.plugins) {
      final existing = pluginRepo.byId(p.id);
      if (existing == null) {
        await pluginRepo.save(p, message: '来自 ${incoming.deviceName} 的同步');
        report = report + const SyncReport(pluginsAdded: 1);
      } else if (comparePluginVersion(p.version, existing.version) > 0 && !existing.builtin) {
        await pluginRepo.save(p, message: '与 ${incoming.deviceName} 同步更新');
        report = report + const SyncReport(pluginsUpdated: 1);
      } else {
        report = report + const SyncReport(skipped: 1);
      }
    }

    // 站点：同 id 以 updatedAt 新者为准
    final localSites = {for (final s in sites()) s.id: s};
    for (final s in incoming.sites) {
      final existing = localSites[s.id];
      if (existing == null) {
        await siteRepo.save(s);
        report = report + const SyncReport(sitesAdded: 1);
      } else {
        final a = existing.updatedAt ?? DateTime(2000);
        final b = s.updatedAt ?? DateTime(2000);
        if (b.isAfter(a)) {
          await siteRepo.save(s);
          report = report + const SyncReport(sitesUpdated: 1);
        } else {
          report = report + const SyncReport(skipped: 1);
        }
      }
    }

    // 收藏：按 key 合并
    final favKeys = {for (final f in libraryRepo.favorites()) f.key};
    var favAdded = 0;
    for (final f in incoming.favorites) {
      if (!favKeys.contains(f.key)) {
        await libraryRepo.toggleFavorite(f);
        favAdded++;
      }
    }
    if (favAdded > 0) report = report + SyncReport(favoritesMerged: favAdded);

    // 历史：同 key 取更新的一条
    final localHistory = {for (final h in libraryRepo.history()) h.key: h};
    var historyMerged = 0;
    for (final h in incoming.history) {
      final existing = localHistory[h.key];
      if (existing == null || h.updatedAt.isAfter(existing.updatedAt)) {
        await libraryRepo.upsertHistory(h);
        historyMerged++;
      }
    }
    if (historyMerged > 0) report = report + SyncReport(historyMerged: historyMerged);

    return report;
  }

  int comparePluginVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  Map<String, dynamic> stats() {
    final sites = this.sites();
    return {
      'plugins': plugins().length,
      'sites': sites.length,
      'enabledSites': sites.where((e) => e.enabled).length,
      'favorites': libraryRepo.favorites().length,
      'history': libraryRepo.history().length,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'kinds': _kindCounts(),
    };
  }

  List<Map<String, dynamic>> _kindCounts() {
    final counts = <String, int>{};
    for (final s in sites()) {
      final p = pluginOf(s);
      if (p == null) continue;
      counts[p.name] = (counts[p.name] ?? 0) + 1;
    }
    return counts.entries.map((e) => {'name': e.key, 'count': e.value}).toList();
  }

  Future<void> recordPlay({
    required SiteBinding site,
    required MediaItem item,
    required PlayLine line,
    required Episode episode,
    required int lineIndex,
    int positionSec = 0,
    int durationSec = 0,
  }) async {
    await libraryRepo.upsertHistory(HistoryEntry(
      siteId: site.id,
      siteName: site.name,
      itemId: item.id,
      title: item.title,
      poster: item.poster,
      lineIndex: lineIndex,
      episodeIndex: episode.index,
      episodeName: episode.name,
      lineName: line.name,
      positionSec: positionSec,
      durationSec: durationSec,
      updatedAt: DateTime.now(),
    ));
  }
}
