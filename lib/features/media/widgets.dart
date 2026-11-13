import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../domain/models/media.dart';

/// 竖版海报卡：Material 3 卡片 + 2:3 海报 + 两行文字。
///
/// 交互全部交给 [Card] / [InkWell]：水波纹、hover 状态层、焦点环都由框架提供。
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    this.onTap,
    this.showSource = true,
    this.aspect = 2 / 3,
    this.rank,
  });

  final MediaItem item;
  final VoidCallback? onTap;
  final bool showSource;
  final double aspect;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth.isFinite ? c.maxWidth : 160.0;
            final posterHeight = width / aspect;
            // 空间不足时（如工具页的紧凑缩略图）只显示海报，避免溢出。
            final showText = !c.maxHeight.isFinite || c.maxHeight >= posterHeight + 56;
            final meta = _metaLine();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: aspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SmartImage(
                        url: item.poster,
                        title: item.title,
                        seed: '${item.sourceId}-${item.title}',
                        radius: 0,
                      ),
                      if (rank != null)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: PqTag('$rank'),
                        ),
                      if (item.score != null && item.score!.isNotEmpty)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: PqTag(item.score!),
                        ),
                    ],
                  ),
                ),
                if (showText)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _metaLine() {
    final parts = <String>[
      if (item.year != null && item.year!.isNotEmpty) item.year!,
      if (item.remarks != null && item.remarks!.isNotEmpty) item.remarks!,
      if (showSource && (item.sourceName ?? '').isNotEmpty) item.sourceName!,
    ];
    return parts.join(' · ');
  }
}

/// 横向轨道：桌面端显示左右翻页按钮，到达两端时按钮禁用。
class MediaRail extends StatefulWidget {
  const MediaRail({
    super.key,
    required this.items,
    required this.onTap,
    this.height,
    this.itemWidth = 140,
    this.showSource = true,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onTap;

  /// 为空时按海报比例自动计算，预留两行文字的高度。
  final double? height;
  final double itemWidth;
  final bool showSource;

  @override
  State<MediaRail> createState() => _MediaRailState();
}

class _MediaRailState extends State<MediaRail> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final back = pos.pixels > 8;
    final forward = pos.pixels < pos.maxScrollExtent - 8;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _nudge(double delta) {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      (_controller.offset + delta).clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expanded = !PqAdaptive.isCompact(context);
    final height = widget.height ?? widget.itemWidth * 1.5 + 60;
    const textArea = 56.0;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: PqAdaptive.gutter(context)),
            itemCount: widget.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: widget.itemWidth,
              child: PqStagger(
                index: i,
                child: PosterCard(
                  item: widget.items[i],
                  showSource: widget.showSource,
                  onTap: () => widget.onTap(widget.items[i]),
                ),
              ),
            ),
          ),
          if (expanded)
            Positioned(
              left: 4,
              top: 0,
              bottom: textArea,
              child: Center(
                child: IconButton.filledTonal(
                  tooltip: '上一页',
                  onPressed: _canBack ? () => _nudge(-420) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
            ),
          if (expanded)
            Positioned(
              right: 4,
              top: 0,
              bottom: textArea,
              child: Center(
                child: IconButton.filledTonal(
                  tooltip: '下一页',
                  onPressed: _canForward ? () => _nudge(420) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 自适应宫格：用 [GridView] + 最大列宽约束，不再手算列数。
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.targetWidth = 150,
    this.minColumns = 2,
    this.maxColumns = 9,
    this.spacing = 12,
    this.padding = EdgeInsets.zero,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onTap;
  final double targetWidth;
  final int minColumns;
  final int maxColumns;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        final width = (c.maxWidth.isFinite ? c.maxWidth : 0) - padding.horizontal;
        if (width <= 0) return const SizedBox.shrink();

        var maxExtent = targetWidth * 1.2;
        var columns = ((width + spacing) / (maxExtent + spacing)).ceil();
        if (columns > maxColumns) {
          maxExtent = width / maxColumns;
        } else if (columns < minColumns) {
          maxExtent = width / minColumns;
        }
        columns = ((width + spacing) / (maxExtent + spacing)).ceil();
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        final tileHeight = tileWidth * 1.5 + 60;
        final height = c.maxHeight.isFinite
            ? math.min(tileHeight, c.maxHeight)
            : tileHeight;

        return GridView.builder(
          padding: padding,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            mainAxisSpacing: 12,
            crossAxisSpacing: spacing,
            mainAxisExtent: height,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => PqStagger(
            index: i,
            child: PosterCard(item: items[i], onTap: () => onTap(items[i])),
          ),
        );
      },
    );
  }
}

/// 首页主视觉：7 秒自动轮播 + 标准 Material 指示器。
class HeroStage extends StatefulWidget {
  const HeroStage({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onDetail,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onPlay;
  final void Function(MediaItem item) onDetail;

  @override
  State<HeroStage> createState() => _HeroStageState();
}

class _HeroStageState extends State<HeroStage> {
  final _controller = PageController();
  int _index = 0;
  bool _userInteracted = false;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _userInteracted || widget.items.length < 2) return;
      if (!_controller.hasClients) return;
      final next = (_index + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (!_controller.hasClients) return;
    _userInteracted = true;
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final compact = PqAdaptive.isCompact(context);
    final height = compact ? 420.0 : 460.0;
    final item = widget.items[_index.clamp(0, widget.items.length - 1)];
    final meta = <String>[
      if (item.year != null && item.year!.isNotEmpty) item.year!,
      if (item.area != null && item.area!.isNotEmpty) item.area!,
      if (item.remarks != null && item.remarks!.isNotEmpty) item.remarks!,
    ].join(' · ');

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _userInteracted = true;
              },
              itemBuilder: (context, i) =>
                  _HeroSlide(item: widget.items[i], compact: compact),
            ),
          ),
          Positioned(
            left: PqAdaptive.gutter(context),
            right: PqAdaptive.gutter(context),
            bottom: compact ? 56 : 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '本期主推 · ${item.kind ?? '精选'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  key: ValueKey('${item.id}-t'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (item.score != null && item.score!.isNotEmpty)
                            PqTag(item.score!),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => widget.onPlay(item),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('立即播放'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => widget.onDetail(item),
                            icon: const Icon(Icons.info_outline_rounded),
                            label: const Text('详情'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: PqAdaptive.gutter(context),
            bottom: 20,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () => _go(i),
                      customBorder: const StadiumBorder(),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 4,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.32),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
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

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.item, required this.compact});

  final MediaItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PosterArt(
          title: item.title,
          seed: '${item.sourceId}-${item.title}',
          radius: 0,
          glyphSize: 0.6,
        ),
        // 封面遮罩：底部压黑保证文字可读，其余保持透明。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.10),
                Colors.black.withOpacity(0.0),
                Colors.black.withOpacity(0.62),
                Colors.black.withOpacity(0.92),
              ],
              stops: const [0, 0.35, 0.75, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black.withOpacity(compact ? 0.6 : 0.7),
                Colors.black.withOpacity(0),
              ],
              stops: const [0, 0.72],
            ),
          ),
        ),
      ],
    );
  }
}

/// 继续观看卡：Material 卡片 + 16:9 封面 + 进度条。
class ContinueCard extends StatelessWidget {
  const ContinueCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.onTap,
    this.posterUrl,
    this.width = 280,
  });

  final String title;
  final String subtitle;
  final double progress;
  final VoidCallback onTap;
  final String? posterUrl;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SmartImage(
                      url: posterUrl,
                      title: title,
                      radius: 0,
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 40,
                        color: Colors.white70,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.black.withOpacity(0.32),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情页顶部信息块用到的元信息点。
class MetaDot extends StatelessWidget {
  const MetaDot({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

double clampAspect(double v) => math.max(1.2, math.min(v, 2.4));
