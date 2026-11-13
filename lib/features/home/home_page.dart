import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../domain/models/library.dart';
import '../../domain/models/media.dart';
import '../../domain/models/site.dart';
import '../../state/home_search.dart';
import '../../state/player.dart';
import '../../state/providers.dart';
import '../media/nav.dart';
import '../media/widgets.dart';

/// 首页：主视觉 + 类型快捷入口 + 继续观看 + 分区轨道。
///
/// 外壳已经提供 AppBar，页面自身不再画 header，直接从第一个区块开始。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final feed = ref.watch(homeProvider);
    final history = ref.watch(historyProvider);

    return PqBackdrop(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerHigh,
          onRefresh: () async {
            ref.invalidate(homeProvider);
            await ref.read(homeProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ...feed.when(
                loading: () => [_skeleton()],
                error: (e, _) => [
                  SliverToBoxAdapter(
                    child: PqContent(
                      child: PqErrorState(
                        message: '$e',
                        onRetry: () => ref.invalidate(homeProvider),
                      ),
                    ),
                  ),
                ],
                data: (data) => _content(context, ref, data, history),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(child: PqContent(child: _Footer(stats: feed.valueOrNull))),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    HomeData data,
    List<HistoryEntry> history,
  ) {
    final slivers = <Widget>[];

    if (data.featured.isEmpty && data.rails.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: PqEmptyState(
            icon: Icons.movie_filter_outlined,
            title: '还没有可用的片源',
            message: '去「插件」页挑一个插件，再为它添加站点；\n也可以先看看内置的演示源。',
            action: FilledButton(
              onPressed: () => context.go('/plugins'),
              child: const Text('前往插件工坊'),
            ),
          ),
        ),
      );
      return slivers;
    }

    if (data.featured.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: PqContent(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: HeroStage(
                items: data.featured,
                onPlay: (item) => openPlay(context, ref, item),
                onDetail: (item) => openDetail(context, item),
              ),
            ),
          ),
        ),
      );
    }

    // 站点切换：只有一个站点时没有切换的意义，直接不占位。
    final sites = ref.watch(enabledSitesProvider);
    if (sites.length > 1) {
      slivers.add(
        SliverToBoxAdapter(
          child: PqContent(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _SiteBar(sites: sites),
            ),
          ),
        ),
      );
    }

    // 类型快捷入口：Material 3 的 ChoiceChip 横向滚动。
    slivers.add(
      SliverToBoxAdapter(
        child: PqContent(
          child: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final kind in const ['电影', '剧集', '动漫', '综艺', '纪录片'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(kind),
                        selected: false,
                        onSelected: (_) => context.go(
                          '/discover?kind=${Uri.encodeComponent(kind)}',
                        ),
                      ),
                    ),
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: false,
                    onSelected: (_) => context.go('/discover'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (history.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: PqContent(
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              child: PqSectionHeader(
                title: '继续观看',
                subtitle: '${history.length} 条记录',
                action: TextButton(
                  onPressed: () => context.go('/settings'),
                  child: const Text('管理'),
                ),
              ),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 216,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: PqAdaptive.gutter(context)),
              itemCount: history.length.clamp(0, 8),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final h = history[i];
                return PqStagger(
                  index: i,
                  child: ContinueCard(
                    title: h.title,
                    subtitle: '${h.siteName} · ${h.episodeName} · ${(h.progress * 100).round()}%',
                    progress: h.progress == 0 ? 0.02 : h.progress,
                    posterUrl: h.poster,
                    onTap: () {
                      final site = ref
                          .read(sitesProvider)
                          .where((s) => s.id == h.siteId)
                          .firstOrNull;
                      if (site == null) return;
                      ref.read(playerProvider.notifier).open(
                            site: site,
                            item: MediaItem(id: h.itemId, title: h.title, poster: h.poster),
                            lineIndex: h.lineIndex,
                            episodeIndex: h.episodeIndex,
                          );
                      context.push('/play');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    final rails = data.rails.entries.toList();
    for (var r = 0; r < rails.length; r++) {
      final entry = rails[r];
      slivers.add(
        SliverToBoxAdapter(
          child: PqContent(
            child: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 12),
              child: PqSectionHeader(
                title: entry.key,
                subtitle: '${entry.value.length} 部',
                action: TextButton(
                  onPressed: () => context.go(
                    '/discover?kind=${Uri.encodeComponent(entry.key)}',
                  ),
                  child: const Text('查看全部'),
                ),
              ),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: MediaRail(
            items: entry.value,
            onTap: (item) => openDetail(context, item),
          ),
        ),
      );
    }

    if (data.failedSites.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: PqContent(
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text('${data.failedSites.join('、')} 本次未响应'),
                  subtitle: const Text('已跳过这些站点'),
                  trailing: TextButton(
                    onPressed: () => ref.invalidate(homeProvider),
                    child: const Text('重试'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _skeleton() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          const PqContent(
            child: PqSkeleton(height: 420, radius: 12),
          ),
          const PqContent(
            child: Padding(
              padding: EdgeInsets.only(top: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PqSkeleton(width: 120, height: 16),
                  SizedBox(height: 16),
                  PqPosterGridSkeleton(count: 6, columns: 3, gap: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({this.stats});

  final HomeData? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = stats?.loadedSites ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'Poqi 聚合了 $loaded 个站点 · 局域网 MCP · 插件工坊',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 首页的站点切换条：与顶栏共用 `selectedSiteProvider`。
///
/// 顶栏适合"切到某个站"，这里适合"扫一眼有哪些站、顺手切过去"，
/// 所以在首页用一排 ChoiceChip 呈现，而不是再放一个下拉。
class _SiteBar extends ConsumerWidget {
  const _SiteBar({required this.sites});

  final List<SiteBinding> sites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedSiteProvider);

    void pick(String? id) =>
        ref.read(selectedSiteProvider.notifier).state = id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              '站点',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: selected == null,
                onSelected: (_) => pick(null),
              ),
              for (final s in sites)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(s.name),
                    selected: selected == s.id,
                    onSelected: (_) => pick(s.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
