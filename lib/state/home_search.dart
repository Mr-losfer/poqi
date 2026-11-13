import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models/media.dart';
import 'providers.dart';

class HomeData {
  const HomeData({
    required this.featured,
    required this.fresh,
    required this.rails,
    required this.failedSites,
    required this.loadedSites,
  });

  final List<MediaItem> featured;
  final List<MediaItem> fresh;

  /// 分区名 → 条目（电影 / 剧集 / 动漫 / 综艺 / 纪录片）。
  final Map<String, List<MediaItem>> rails;
  final List<String> failedSites;
  final int loadedSites;

  static const empty = HomeData(
    featured: [],
    fresh: [],
    rails: {},
    failedSites: [],
    loadedSites: 0,
  );
}

final homeProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(sitesProvider);
  ref.watch(pluginsProvider);
  final backend = ref.watch(backendProvider);

  final sites = backend.enabledSites();
  final failures = <String>[];
  final all = <MediaItem>[];

  final perSite = await Future.wait(sites.map((s) async {
    final runner = backend.runnerOf(s);
    final plugin = backend.pluginOf(s);
    if (runner == null || plugin == null || !plugin.endpoints.containsKey('home')) {
      return <MediaItem>[];
    }
    try {
      final page = await runner.home();
      return page.items;
    } catch (_) {
      failures.add(s.name);
      return <MediaItem>[];
    }
  }));

  for (final list in perSite) {
    all.addAll(list);
  }

  final deduped = PoqiBackend.dedupe(all);

  final featured = [...deduped]..sort((a, b) {
      final sa = double.tryParse(a.score ?? '') ?? 0;
      final sb = double.tryParse(b.score ?? '') ?? 0;
      return sb.compareTo(sa);
    });

  final rails = <String, List<MediaItem>>{};
  for (final kind in const ['电影', '剧集', '动漫', '综艺', '纪录片']) {
    final list = deduped.where((e) => e.kind == kind).toList();
    if (list.isNotEmpty) rails[kind] = list;
  }
  // 没有 kind 字段的站点，按来源兜底成一条"来自 xx"。
  final unknown = deduped.where((e) => e.kind == null || e.kind!.isEmpty).toList();
  if (unknown.isNotEmpty) {
    rails['新近入库'] = unknown;
  }

  return HomeData(
    featured: featured.take(6).toList(),
    fresh: deduped.take(18).toList(),
    rails: rails,
    failedSites: failures,
    loadedSites: sites.length - failures.length,
  );
});

class SiteSearchStatus {
  const SiteSearchStatus({
    required this.siteId,
    required this.siteName,
    this.state = SiteQueryState.pending,
    this.count = 0,
    this.message,
    this.ms = 0,
  });

  final String siteId;
  final String siteName;
  final SiteQueryState state;
  final int count;
  final String? message;
  final int ms;

  SiteSearchStatus copyWith({
    SiteQueryState? state,
    int? count,
    String? message,
    int? ms,
  }) =>
      SiteSearchStatus(
        siteId: siteId,
        siteName: siteName,
        state: state ?? this.state,
        count: count ?? this.count,
        message: message ?? this.message,
        ms: ms ?? this.ms,
      );
}

enum SiteQueryState { pending, running, done, failed }

class SearchState {
  const SearchState({
    this.keyword = '',
    this.running = false,
    this.results = const [],
    this.sites = const [],
    this.elapsedMs = 0,
    this.round = 0,
  });

  final String keyword;
  final bool running;
  final List<MediaItem> results;
  final List<SiteSearchStatus> sites;
  final int elapsedMs;
  final int round;

  bool get isEmpty => results.isEmpty;

  SearchState copyWith({
    String? keyword,
    bool? running,
    List<MediaItem>? results,
    List<SiteSearchStatus>? sites,
    int? elapsedMs,
    int? round,
  }) =>
      SearchState(
        keyword: keyword ?? this.keyword,
        running: running ?? this.running,
        results: results ?? this.results,
        sites: sites ?? this.sites,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        round: round ?? this.round,
      );
}

final searchProvider = NotifierProvider<SearchController, SearchState>(
  SearchController.new,
);

/// 全站循环搜索：结果边到边显示，不等待最慢的站点。
class SearchController extends Notifier<SearchState> {
  int _token = 0;
  Timer? _ticker;
  DateTime? _startedAt;

  @override
  SearchState build() => const SearchState();

  Future<void> search(String keyword) async {
    final kw = keyword.trim();
    final token = ++_token;
    _ticker?.cancel();

    if (kw.isEmpty) {
      state = const SearchState();
      return;
    }

    final backend = ref.read(backendProvider);
    final sites = backend.enabledSites().where((s) {
      final p = backend.pluginOf(s);
      return p != null && p.supportsSearch;
    }).toList();

    _startedAt = DateTime.now();
    state = SearchState(
      keyword: kw,
      running: true,
      sites: [
        for (final s in sites) SiteSearchStatus(siteId: s.id, siteName: s.name),
      ],
    );

    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final elapsed = DateTime.now().difference(_startedAt!).inMilliseconds;
      state = state.copyWith(elapsedMs: elapsed);
    });

    final collected = <MediaItem>[];
    final statuses = {
      for (final s in sites) s.id: SiteSearchStatus(siteId: s.id, siteName: s.name),
    };

    final limit = ref.read(settingsProvider).searchConcurrency.clamp(1, 8);
    var cursor = 0;
    final timeoutMs = ref.read(settingsProvider).aggregateTimeoutMs;

    Future<void> worker() async {
      while (true) {
        final i = cursor++;
        if (i >= sites.length) return;
        if (token != _token) return;
        final site = sites[i];
        final runner = backend.runnerOf(site);
        final started = DateTime.now();
        statuses[site.id] = statuses[site.id]!.copyWith(state: SiteQueryState.running);
        _publish(token, collected, statuses);

        if (runner == null) {
          statuses[site.id] = statuses[site.id]!
              .copyWith(state: SiteQueryState.failed, message: '插件缺失');
          continue;
        }
        try {
          final page = await runner.search(kw).timeout(
                Duration(milliseconds: timeoutMs),
                onTimeout: () => MediaPage.empty,
              );
          if (token != _token) return;
          collected.addAll(page.items);
          statuses[site.id] = statuses[site.id]!.copyWith(
            state: SiteQueryState.done,
            count: page.items.length,
            ms: DateTime.now().difference(started).inMilliseconds,
            message: page.items.isEmpty ? '无结果' : null,
          );
        } catch (e) {
          statuses[site.id] = statuses[site.id]!.copyWith(
            state: SiteQueryState.failed,
            ms: DateTime.now().difference(started).inMilliseconds,
            message: '$e',
          );
        }
        _publish(token, collected, statuses);
      }
    }

    await Future.wait(List.generate(limit, (_) => worker()));
    _ticker?.cancel();
    if (token != _token) return;
    state = state.copyWith(
      running: false,
      results: PoqiBackend.dedupe(collected),
      sites: _ordered(statuses),
      elapsedMs: DateTime.now().difference(_startedAt!).inMilliseconds,
    );
  }

  void _publish(int token, List<MediaItem> collected, Map<String, SiteSearchStatus> map) {
    if (token != _token) return;
    state = state.copyWith(
      results: PoqiBackend.dedupe(List<MediaItem>.from(collected)),
      sites: _ordered(map),
    );
  }

  List<SiteSearchStatus> _ordered(Map<String, SiteSearchStatus> map) {
    final order = {for (var i = 0; i < state.sites.length; i++) state.sites[i].siteId: i};
    final list = map.values.toList()
      ..sort((a, b) => (order[a.siteId] ?? 99).compareTo(order[b.siteId] ?? 99));
    return list;
  }

  void clear() {
    _token++;
    _ticker?.cancel();
    state = const SearchState();
  }
}
