import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/overlay.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../core/ui/states.dart';
import '../../domain/models/media.dart';
import '../../domain/models/site.dart';
import '../../state/player.dart';
import '../../state/providers.dart';
import '../media/nav.dart';

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
    final p = PqPalette.of(context);
    final site = ref.watch(sitesProvider).where((s) => s.id == widget.siteId).firstOrNull;

    if (site == null) {
      return Scaffold(
        body: SafeArea(
          child: PqEmptyState(
            icon: Icons.link_off_rounded,
            title: '站点不存在',
            message: '它可能已被删除，或被同步覆盖。',
            action: OutlinedButton(onPressed: () => context.pop(), child: const Text('返回')),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.canvas,
      body: _future == null
          ? _DetailSkeleton(onBack: () => context.pop())
          : FutureBuilder<MediaDetail>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _DetailSkeleton(onBack: () => context.pop());
                }
                if (snap.hasError || snap.data == null) {
                  return SafeArea(
                    child: Column(
                      children: [
                        _TopBar(onBack: () => context.pop(), title: ''),
                        Expanded(
                          child: PqErrorState(
                            message: '${snap.error ?? '未知错误'}',
                            onRetry: _load,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return _body(context, snap.data!, site);
              },
            ),
    );
  }

  Widget _body(BuildContext context, MediaDetail detail, SiteBinding site) {
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final item = detail.item;
    final line =
        detail.lines.isEmpty ? null : detail.lines[_lineIndex.clamp(0, detail.lines.length - 1)];
    final isFav = ref.watch(favoritesProvider).any(
          (e) => e.siteId == site.id && e.itemId == item.id,
        );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              SizedBox(
                height: compact ? 260 : 330,
                width: double.infinity,
                child: PosterArt(
                  title: item.title,
                  seed: '${item.sourceId}-${item.title}',
                  radius: 0,
                  glyphSize: 0.5,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        p.canvas.withOpacity(0.45),
                        p.canvas.withOpacity(0.6),
                        p.canvas,
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: _TopBar(onBack: () => context.pop(), title: item.title),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -64),
            child: PqContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: compact ? 96 : 148,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: SmartImage(
                            url: item.poster,
                            title: item.title,
                            seed: '${item.sourceId}-${item.title}',
                            radius: 16,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.10),
                                  width: 0.9,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.kind ?? '影视'} · ${item.area ?? '未知地区'}',
                              style: PqType.eyebrow.copyWith(color: p.accent),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: PqType.h1.copyWith(
                                fontSize: compact ? 24 : 32,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (item.score != null)
                                  PqTag(item.score!, color: p.accent, filled: true),
                                if (item.year != null)
                                  Text(
                                    '${item.year}',
                                    style: PqType.bodySmall.copyWith(color: p.textMuted),
                                  ),
                                if (item.remarks != null) PqTag(item.remarks!),
                                PqTag(site.name, color: p.sage),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: detail.lines.isEmpty ? null : () => _play(site, detail),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                                  label: const Text('开始播放'),
                                ),
                                const SizedBox(width: 10),
                                _RoundAction(
                                  icon: isFav
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  active: isFav,
                                  tooltip: isFav ? '取消收藏' : '收藏',
                                  onTap: () async {
                                    final added = await ref
                                        .read(favoritesProvider.notifier)
                                        .toggle(item, site.id);
                                    if (!context.mounted) return;
                                    showPqToast(
                                      context,
                                      added ? '已加入收藏' : '已取消收藏',
                                      kind: PqToastKind.success,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                _RoundAction(
                                  icon: Icons.refresh_rounded,
                                  tooltip: '重新加载',
                                  onTap: _load,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if ((detail.intro ?? '').trim().isNotEmpty)
                    PqPanel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('剧情简介', style: PqType.eyebrow.copyWith(color: p.textFaint)),
                          const SizedBox(height: 8),
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 220),
                            crossFadeState: _introOpen
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            firstChild: Text(
                              detail.intro!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: PqType.body.copyWith(color: p.textMuted, height: 1.7),
                            ),
                            secondChild: Text(
                              detail.intro!,
                              style: PqType.body.copyWith(color: p.textMuted, height: 1.7),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _introOpen = !_introOpen),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _introOpen ? '收起' : '展开',
                                style: PqType.label.copyWith(color: p.accent, fontSize: 12),
                              ),
                            ),
                          ),
                          if ((detail.director ?? '').isNotEmpty ||
                              detail.actors.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Divider(color: p.lineSoft),
                            const SizedBox(height: 6),
                            if ((detail.director ?? '').isNotEmpty)
                              PqMetaRow(label: '导演', value: detail.director!),
                            if (detail.actors.isNotEmpty)
                              PqMetaRow(label: '主演', value: detail.actors.join(' / ')),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 26),
                  if (detail.lines.isNotEmpty) ...[
                    Row(
                      children: [
                        Text('选集', style: PqType.h2.copyWith(fontSize: 17)),
                        const SizedBox(width: 10),
                        Text(
                          '${detail.lines.length} 条线路 · ${detail.episodeCount} 集',
                          style: PqType.bodySmall.copyWith(color: p.textFaint),
                        ),
                        const Spacer(),
                        if (!compact)
                          Text(
                            '播放失败会自动换源',
                            style: PqType.bodySmall.copyWith(
                              color: p.textFaint,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (detail.lines.length > 1) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < detail.lines.length; i++)
                            GestureDetector(
                              onTap: () => setState(() => _lineIndex = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _lineIndex == i
                                      ? p.accent.withOpacity(0.14)
                                      : p.surfaceHigh,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: _lineIndex == i
                                        ? p.accent.withOpacity(0.5)
                                        : p.lineSoft,
                                    width: 0.9,
                                  ),
                                ),
                                child: Text(
                                  detail.lines[i].name,
                                  style: PqType.label.copyWith(
                                    fontSize: 12,
                                    color: _lineIndex == i ? p.accent : p.textMuted,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (line != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < line.episodes.length; i++)
                            _EpisodeChip(
                              label: line.episodes[i].name,
                              onTap: () => _play(site, detail, episode: i),
                            ),
                        ],
                      ),
                  ],
                  const SizedBox(height: 30),
                  PqSectionHeader(
                    eyebrow: 'SOURCES',
                    title: '其他站点也有',
                    subtitle: _loadingOthers ? '搜索中…' : '${_otherSources.length} 个来源',
                  ),
                  const SizedBox(height: 12),
                  if (_loadingOthers && _otherSources.isEmpty)
                    const PqLoadingLine(label: '正在跨站比对…', expanded: false)
                  else if (_otherSources.isEmpty)
                    Text(
                      '暂时没有找到其他站点的同名片源',
                      style: PqType.bodySmall.copyWith(color: p.textFaint),
                    )
                  else
                    Column(
                      children: [
                        for (final other in _otherSources)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: PqPanel(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              onTap: () {
                                if (other.sourceId != null) {
                                  context.push(
                                    '/detail/${other.sourceId}/${Uri.encodeComponent(other.id)}',
                                  );
                                }
                              },
                              child: Row(
                                children: [
                                  PqMonogram(text: other.sourceName ?? '?', size: 30),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          other.sourceName ?? '未知站点',
                                          style: PqType.title.copyWith(fontSize: 13),
                                        ),
                                        Text(
                                          [
                                            if (other.year != null) other.year!,
                                            if (other.remarks != null) other.remarks!,
                                            other.title,
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: PqType.bodySmall.copyWith(
                                            fontSize: 11.5,
                                            color: p.textFaint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (other.score != null)
                                    PqTag(other.score!, color: p.accent),
                                  const SizedBox(width: 6),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 18, color: p.textFaint),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 44),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EpisodeChip extends StatefulWidget {
  const _EpisodeChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_EpisodeChip> createState() => _EpisodeChipState();
}

class _EpisodeChipState extends State<_EpisodeChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minWidth: 62, maxWidth: 132),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? p.surfaceHigher : p.surfaceHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _hover ? p.line : p.lineSoft, width: 0.9),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PqType.label.copyWith(
              fontSize: 12,
              color: _hover ? p.text : p.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final child = PqPressable(
      onTap: onTap,
      borderRadius: 11,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? p.accent.withOpacity(0.14) : p.surfaceHigh,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? p.accent.withOpacity(0.4) : p.lineSoft,
            width: 0.9,
          ),
        ),
        child: Icon(icon, size: 19, color: active ? p.accent : p.textMuted),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.title});

  final VoidCallback onBack;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          PqIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PqType.title.copyWith(color: p.text.withOpacity(0.9)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _TopBar(onBack: onBack, title: ''),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                PqSkeleton(width: 120, height: 180, radius: 16),
                SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PqSkeleton(width: 60, height: 10),
                      SizedBox(height: 12),
                      PqSkeleton(width: 200, height: 26),
                      SizedBox(height: 10),
                      PqSkeleton(width: 140, height: 12),
                      SizedBox(height: 20),
                      PqSkeleton(width: 120, height: 38, radius: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
