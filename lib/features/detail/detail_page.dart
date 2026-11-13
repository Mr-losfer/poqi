import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../domain/models/media.dart';
import '../../domain/models/site.dart';
import '../../state/player.dart';
import '../../state/providers.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.siteId, required this.itemId});

  final String siteId;
  final String itemId;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  Future<MediaDetail>? _future;
  int _lineIndex = 0;
  int _episodeIndex = 0;
  bool _introOpen = false;
  List<MediaItem> _otherSources = const [];
  bool _loadingOthers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final site = ref.read(sitesProvider).where((s) => s.id == widget.siteId).firstOrNull;
    if (site == null) return;
    final runner = ref.read(runnerFactoryProvider)(site);
    setState(() {
      _future = runner?.detail(widget.itemId) ?? Future.error('该站点的插件不可用');
      _lineIndex = 0;
      _episodeIndex = 0;
    });
    _future!.then((detail) {
      if (!mounted) return;
      _loadOthers(detail.item);
    }).catchError((_) {});
  }

  Future<void> _loadOthers(MediaItem item) async {
    setState(() => _loadingOthers = true);
    try {
      final list = await ref.read(backendProvider).otherSources(item);
      if (mounted) setState(() => _otherSources = list);
    } catch (_) {
      // 其它源属于增强信息，失败不影响主流程
    } finally {
      if (mounted) setState(() => _loadingOthers = false);
    }
  }

  Future<void> _play(SiteBinding site, MediaDetail detail, {int episode = 0}) async {
    await ref.read(playerProvider.notifier).open(
          site: site,
          item: detail.item,
          lineIndex: _lineIndex,
          episodeIndex: episode,
        );
    if (mounted) context.push('/play');
  }

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(sitesProvider).where((s) => s.id == widget.siteId).firstOrNull;

    if (site == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: PqEmptyState(
          icon: Icons.link_off,
          title: '站点不存在',
          message: '它可能已被删除，或被同步覆盖。',
          action: FilledButton(onPressed: () => context.pop(), child: const Text('返回')),
        ),
      );
    }

    return FutureBuilder<MediaDetail>(
      future: _future,
      builder: (context, snap) {
        if (_future == null || snap.connectionState == ConnectionState.waiting) {
          return _shell(body: const _DetailSkeleton());
        }
        if (snap.hasError || snap.data == null) {
          return _shell(
            title: '详情',
            actions: [
              IconButton(
                onPressed: _load,
                tooltip: '重新加载',
                icon: const Icon(Icons.refresh),
              ),
            ],
            body: PqEmptyState(
              icon: Icons.offline_bolt_outlined,
              title: '加载失败',
              message: '${snap.error ?? '未知错误'}',
              action: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ),
          );
        }

        final detail = snap.data!;
        return _shell(
          title: detail.item.title,
          actions: _actions(site, detail),
          body: _body(detail, site),
        );
      },
    );
  }

  Widget _shell({String title = '', List<Widget>? actions, required Widget body}) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
      ),
      body: body,
    );
  }

  List<Widget> _actions(SiteBinding site, MediaDetail detail) {
    final item = detail.item;
    final isFav = ref.watch(favoritesProvider).any(
          (e) => e.siteId == site.id && e.itemId == item.id,
        );
    return [
      IconButton(
        isSelected: isFav,
        tooltip: isFav ? '取消收藏' : '收藏',
        onPressed: () async {
          final added = await ref.read(favoritesProvider.notifier).toggle(item, site.id);
          if (!mounted) return;
          showPqToast(
            context,
            added ? '已加入收藏' : '已取消收藏',
            kind: PqToastKind.success,
          );
        },
        icon: const Icon(Icons.favorite_border),
        selectedIcon: const Icon(Icons.favorite),
      ),
      IconButton(
        onPressed: _load,
        tooltip: '刷新',
        icon: const Icon(Icons.refresh),
      ),
    ];
  }

  Widget _body(MediaDetail detail, SiteBinding site) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = PqAdaptive.isCompact(context);
    final item = detail.item;
    final line = detail.lines.isEmpty
        ? null
        : detail.lines[_lineIndex.clamp(0, detail.lines.length - 1)];
    final episodeCount = line?.episodes.length ?? 0;
    final episode = episodeCount == 0 ? 0 : _episodeIndex.clamp(0, episodeCount - 1);
    final intro = (detail.intro ?? '').trim();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: compact ? 200 : 260,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterArt(
                  title: item.title,
                  seed: '${item.sourceId}-${item.title}',
                  radius: 0,
                  glyphSize: 0.5,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black45, Colors.transparent],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: PqContent(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _header(site, detail),
                  if (intro.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '剧情简介',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 220),
                                crossFadeState: _introOpen
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                firstChild: Text(
                                  intro,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                secondChild: Text(
                                  intro,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () =>
                                      setState(() => _introOpen = !_introOpen),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  child: Text(_introOpen ? '收起' : '展开'),
                                ),
                              ),
                              if ((detail.director ?? '').isNotEmpty ||
                                  detail.actors.isNotEmpty) ...[
                                const Divider(height: 24),
                                if ((detail.director ?? '').isNotEmpty)
                                  PqMetaRow(label: '导演', value: detail.director!),
                                if (detail.actors.isNotEmpty)
                                  PqMetaRow(label: '主演', value: detail.actors.join(' / ')),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (detail.lines.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    PqSectionHeader(
                      title: '选集',
                      subtitle: '${detail.lines.length} 条线路 · ${detail.episodeCount} 集',
                    ),
                    if (detail.lines.length > 1) ...[
                      const SizedBox(height: 12),
                      _lineSelector(detail),
                    ],
                    const SizedBox(height: 12),
                    if (line != null) _episodeChips(line, detail, site, episode),
                  ],
                  const SizedBox(height: 28),
                  PqSectionHeader(
                    eyebrow: 'SOURCES',
                    title: '其他站点也有',
                    subtitle: _loadingOthers ? '搜索中…' : '${_otherSources.length} 个来源',
                  ),
                  const SizedBox(height: 12),
                  _otherSourcesSection(scheme),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(SiteBinding site, MediaDetail detail) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = detail.item;
    final line = detail.lines.isEmpty
        ? null
        : detail.lines[_lineIndex.clamp(0, detail.lines.length - 1)];
    final episodeCount = line?.episodes.length ?? 0;
    final episode = episodeCount == 0 ? 0 : _episodeIndex.clamp(0, episodeCount - 1);

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.kind ?? '影视'} · ${item.area ?? '未知地区'}',
          style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
        ),
        const SizedBox(height: 6),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (item.score != null)
              PqTag(item.score!, color: scheme.primary, filled: true),
            if (item.year != null)
              Text(
                item.year!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (item.remarks != null) PqTag(item.remarks!),
            PqTag(site.name, color: scheme.tertiary),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: detail.lines.isEmpty
              ? null
              : () => _play(site, detail, episode: episode),
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始播放'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 400;
        final posterWidth = stacked ? 124.0 : (constraints.maxWidth < 600 ? 108.0 : 148.0);
        final poster = SizedBox(
          width: posterWidth,
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: SmartImage(
                url: item.poster,
                title: item.title,
                seed: '${item.sourceId}-${item.title}',
                radius: 12,
              ),
            ),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              poster,
              const SizedBox(height: 16),
              info,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            poster,
            const SizedBox(width: 20),
            Expanded(child: info),
          ],
        );
      },
    );
  }

  Widget _lineSelector(MediaDetail detail) {
    final theme = Theme.of(context);
    if (detail.lines.length <= 3) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: PqSegmented(
          items: [for (final line in detail.lines) line.name],
          index: _lineIndex,
          compact: true,
          onChanged: (i) => setState(() {
            _lineIndex = i;
            _episodeIndex = 0;
          }),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < detail.lines.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == detail.lines.length - 1 ? 0 : 8),
              child: ChoiceChip(
                label: Text(detail.lines[i].name),
                selected: _lineIndex == i,
                onSelected: (_) => setState(() {
                  _lineIndex = i;
                  _episodeIndex = 0;
                }),
                labelStyle: theme.textTheme.labelLarge,
              ),
            ),
        ],
      ),
    );
  }

  Widget _episodeChips(PlayLine line, MediaDetail detail, SiteBinding site, int active) {
    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < line.episodes.length; i++)
          ChoiceChip(
            label: Text(line.episodes[i].name),
            selected: i == active,
            onSelected: (_) {
              setState(() => _episodeIndex = i);
              _play(site, detail, episode: i);
            },
          ),
      ],
    );
    if (line.episodes.length <= 60) return chips;
    return SizedBox(
      height: 208,
      child: Scrollbar(
        child: SingleChildScrollView(child: chips),
      ),
    );
  }

  Widget _otherSourcesSection(ColorScheme scheme) {
    if (_loadingOthers && _otherSources.isEmpty) {
      return const PqLoadingLine(label: '正在跨站比对…', expanded: false);
    }
    if (_otherSources.isEmpty) {
      return Text(
        '暂时没有找到其他站点的同名片源',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < _otherSources.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _sourceTile(_otherSources[i], scheme),
          ],
        ],
      ),
    );
  }

  Widget _sourceTile(MediaItem other, ColorScheme scheme) {
    final name = other.sourceName ?? '未知站点';
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    final meta = [
      if (other.year != null) other.year!,
      if (other.remarks != null) other.remarks!,
      other.title,
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Text(initial),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: other.sourceId == null
          ? null
          : () => context.push(
                '/detail/${other.sourceId}/${Uri.encodeComponent(other.id)}',
              ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: const [
        PqSkeleton(height: 200, radius: 0),
        SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PqSkeleton(width: 108, height: 162, radius: 12),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PqSkeleton(width: 72, height: 10),
                    SizedBox(height: 12),
                    PqSkeleton(width: 200, height: 24),
                    SizedBox(height: 12),
                    PqSkeleton(width: 140, height: 12),
                    SizedBox(height: 20),
                    PqSkeleton(width: 132, height: 40, radius: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
