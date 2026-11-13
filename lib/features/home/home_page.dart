import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/logo.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../domain/models/library.dart';
import '../../domain/models/media.dart';
import '../../state/home_search.dart';
import '../../state/player.dart';
import '../../state/providers.dart';
import '../media/nav.dart';
import '../media/widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final feed = ref.watch(homeProvider);
    final history = ref.watch(historyProvider);

    return PqBackdrop(
      child: RefreshIndicator(
        color: p.accent,
        backgroundColor: p.surfaceHigh,
        onRefresh: () async {
          ref.invalidate(homeProvider);
          await ref.read(homeProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (compact)
              SliverToBoxAdapter(child: _MobileHeader())
            else
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ...feed.when(
              loading: () => [_skeleton(context, compact)],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: PqAdaptive.gutter(context)),
                    child: PqErrorState(
                      message: '$e',
                      onRetry: () => ref.invalidate(homeProvider),
                    ),
                  ),
                ),
              ],
              data: (data) => _content(context, ref, data, history, compact),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
            SliverToBoxAdapter(child: _Footer(stats: feed.valueOrNull)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    HomeData data,
    List<HistoryEntry> history,
    bool compact,
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
          child: HeroStage(
            items: data.featured,
            onPlay: (item) => openPlay(context, ref, item),
            onDetail: (item) => openDetail(context, item),
          ),
        ),
      );
    }

    // 分类快捷入口
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(PqAdaptive.gutter(context), 20, PqAdaptive.gutter(context), 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in const ['电影', '剧集', '动漫', '综艺', '纪录片'])
                _KindChip(label: kind),
              const _KindChip(label: '全部', outlined: true),
            ],
          ),
        ),
      ),
    );

    if (history.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 26),
            child: PqContent(
              child: PqSectionHeader(
                eyebrow: 'CONTINUE',
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
            height: 196,
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
              padding: EdgeInsets.only(top: r == 0 ? 30 : 34, bottom: 14),
              child: PqSectionHeader(
                eyebrow: 'RAIL ${(r + 1).toString().padLeft(2, '0')}',
                title: entry.key,
                subtitle: '${entry.value.length} 部',
                action: TextButton(
                  onPressed: () => context.go('/discover?kind=${Uri.encodeComponent(entry.key)}'),
                  child: const Text('全部'),
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
          child: Padding(
            padding: EdgeInsets.fromLTRB(PqAdaptive.gutter(context), 22, PqAdaptive.gutter(context), 0),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: PqPalette.of(context).textFaint),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${data.failedSites.join('、')} 本次未响应，已跳过',
                    style: PqType.bodySmall.copyWith(color: PqPalette.of(context).textFaint),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _skeleton(BuildContext context, bool compact) {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          SizedBox(
            height: compact ? 420 : 460,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: PqAdaptive.gutter(context)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: const PqSkeleton(height: double.infinity, radius: 18),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(PqAdaptive.gutter(context), 28, PqAdaptive.gutter(context), 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PqSkeleton(width: 120, height: 16),
                const SizedBox(height: 16),
                PqPosterGridSkeleton(
                  count: PqAdaptive.isCompact(context) ? 3 : 6,
                  columns: PqAdaptive.isCompact(context) ? 3 : 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, this.outlined = false});

  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return PqPressable(
      onTap: () {
        if (label == '全部') {
          context.go('/discover');
        } else {
          context.go('/discover?kind=${Uri.encodeComponent(label)}');
        }
      },
      borderRadius: 9,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : p.surfaceHigh,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: outlined ? p.line : p.lineSoft, width: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: PqType.label.copyWith(
                fontSize: 12,
                color: outlined ? p.textMuted : p.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.arrow_outward_rounded, size: 11, color: p.textFaint),
          ],
        ),
      ),
    );
  }
}

class _MobileHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        PqAdaptive.gutter(context),
        MediaQuery.paddingOf(context).top + 14,
        PqAdaptive.gutter(context),
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const PqLogo(size: 24),
              const Spacer(),
              PqIconButton(
                icon: ref.watch(settingsProvider).themeMode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                onTap: () => ref.read(settingsProvider.notifier).toggleTheme(),
              ),
              PqIconButton(
                icon: Icons.search_rounded,
                onTap: () => context.push('/search'),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
    final p = PqPalette.of(context);
    final loaded = stats?.loadedSites ?? 0;
    return PqContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: p.lineSoft),
          const SizedBox(height: 16),
          Row(
            children: [
              const PqLogo(size: 18, showWordmark: false),
              const SizedBox(width: 10),
              Text(
                'Poqi 聚合了 $loaded 个站点',
                style: PqType.bodySmall.copyWith(color: p.textFaint, fontSize: 11.5),
              ),
              const Spacer(),
              Text(
                '局域网 MCP · 插件工坊',
                style: PqType.eyebrow.copyWith(color: p.textFaint.withOpacity(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
