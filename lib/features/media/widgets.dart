import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/pq_theme.dart';
import '../../core/ui/adaptive.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/poster.dart';
import '../../core/ui/primitives.dart';
import '../../domain/models/media.dart';

/// 竖版海报卡：2:3，悬停浮起，右下角信息随宽度自适应。
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
    final p = PqPalette.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 160.0;
        final compact = w < 120;
        return HoverZoom(
          borderRadius: 14,
          child: PqPressable(
            onTap: onTap,
            borderRadius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: aspect,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SmartImage(
                          url: item.poster,
                          title: item.title,
                          seed: '${item.sourceId}-${item.title}',
                          radius: 14,
                        ),
                      ),
                      // 底部渐隐，压住海报上的杂色。
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.05),
                                  Colors.black.withOpacity(0.0),
                                  Colors.black.withOpacity(0.55),
                                ],
                                stops: const [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 9,
                        child: Row(
                          children: [
                            if (item.score != null && item.score!.isNotEmpty)
                              _ScorePill(score: item.score!),
                            const Spacer(),
                            if (item.remarks != null && item.remarks!.isNotEmpty)
                              Flexible(
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.45),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.14),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: Text(
                                    item.remarks!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PqType.label.copyWith(
                                      fontSize: 9.5,
                                      color: Colors.white.withOpacity(0.9),
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (rank != null)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$rank',
                              style: PqType.label.copyWith(
                                fontFamily: 'Bricolage',
                                color: p.onAccent,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PqType.title.copyWith(fontSize: compact ? 12 : 13.5, color: p.text),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (item.year != null && item.year!.isNotEmpty)
                      Text(
                        item.year!,
                        style: PqType.bodySmall.copyWith(fontSize: 11, color: p.textFaint),
                      ),
                    if (item.year != null && showSource)
                      Text(
                        ' · ',
                        style: PqType.bodySmall.copyWith(fontSize: 11, color: p.textFaint),
                      ),
                    if (showSource)
                      Expanded(
                        child: Text(
                          item.sourceName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PqType.bodySmall.copyWith(
                            fontSize: 11,
                            color: p.textFaint,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final String score;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: p.accent.withOpacity(0.92),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        score,
        style: PqType.label.copyWith(
          fontSize: 9.5,
          color: p.onAccent,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// 横向轨道：宽屏时给出左右翻页按钮。
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

  /// 为空时按海报比例自动计算，避免文字被裁切。
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
    final p = PqPalette.of(context);
    final expanded = !PqAdaptive.isCompact(context);
    final height = widget.height ?? widget.itemWidth * 1.5 + 56;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(
              left: PqAdaptive.gutter(context),
              right: PqAdaptive.gutter(context) + (expanded ? 40 : 0),
            ),
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
          if (expanded && _canBack)
            Positioned(
              left: 6,
              top: 0,
              bottom: 34,
              child: Center(child: _RailArrow(icon: Icons.chevron_left_rounded, onTap: () => _nudge(-420))),
            ),
          if (expanded && _canForward)
            Positioned(
              right: 6,
              top: 0,
              bottom: 34,
              child: Center(child: _RailArrow(icon: Icons.chevron_right_rounded, onTap: () => _nudge(420))),
            ),
          // 底部渐隐提示还有内容
          Positioned(
            right: 0,
            top: 0,
            bottom: 34,
            width: 56,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [p.canvas.withOpacity(0), p.canvas.withOpacity(0.85)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailArrow extends StatefulWidget {
  const _RailArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_RailArrow> createState() => _RailArrowState();
}

class _RailArrowState extends State<_RailArrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hover ? p.surfaceHigher : p.surface.withOpacity(0.86),
            shape: BoxShape.circle,
            border: Border.all(color: p.line),
          ),
          child: Icon(widget.icon, size: 20, color: p.text),
        ),
      ),
    );
  }
}

/// 自适应宫格：列数随宽度变化。
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.targetWidth = 150,
    this.minColumns = 2,
    this.maxColumns = 9,
    this.spacing = 14,
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
    return LayoutBuilder(
      builder: (context, c) {
        final cols = PqAdaptive.columnsFor(
          c.maxWidth,
          target: targetWidth,
          min: minColumns,
          max: maxColumns,
        );
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Padding(
          padding: padding,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing + 22,
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: w,
                  child: PqStagger(
                    index: i,
                    child: PosterCard(item: items[i], onTap: () => onTap(items[i])),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 首页主视觉：巨型标题 + 自动轮播。
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
    final p = PqPalette.of(context);
    final compact = PqAdaptive.isCompact(context);
    final height = compact ? 420.0 : 460.0;
    final item = widget.items[_index.clamp(0, widget.items.length - 1)];

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
              itemBuilder: (context, i) => _HeroSlide(item: widget.items[i], compact: compact),
            ),
          ),
          // 左侧文本层盖在遮罩上，保证可读性
          Positioned(
            left: PqAdaptive.gutter(context),
            right: PqAdaptive.gutter(context),
            bottom: compact ? 56 : 64,
            child: IgnorePointer(
              ignoring: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 1,
                        color: p.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '本期主推 · ${item.kind ?? '精选'}',
                        style: PqType.eyebrow.copyWith(color: p.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                          style: PqType.hero.copyWith(
                            fontSize: compact ? 38 : 54,
                            color: p.text,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (item.score != null) PqTag(item.score!, color: p.accent, filled: true),
                            if (item.year != null) Text('${item.year}', style: _meta(p)),
                            if (item.area != null) Text('${item.area}', style: _meta(p)),
                            if (item.remarks != null) Text('${item.remarks}', style: _meta(p)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _HeroButton(
                              label: '立即播放',
                              icon: Icons.play_arrow_rounded,
                              primary: true,
                              onTap: () => widget.onPlay(item),
                            ),
                            const SizedBox(width: 10),
                            _HeroButton(
                              label: '详情',
                              icon: Icons.info_outline_rounded,
                              onTap: () => widget.onDetail(item),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 指示器
          Positioned(
            right: PqAdaptive.gutter(context),
            bottom: 22,
            child: Row(
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  GestureDetector(
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(left: 6),
                      width: i == _index ? 22 : 7,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i == _index ? p.accent : p.textFaint.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2),
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

  TextStyle _meta(PqPalette p) => PqType.bodySmall.copyWith(
        fontSize: 12.5,
        color: p.textMuted,
        letterSpacing: 0.2,
      );
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.item, required this.compact});

  final MediaItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        PosterArt(
          title: item.title,
          seed: '${item.sourceId}-${item.title}',
          radius: 0,
          glyphSize: 0.6,
        ),
        // 垂直遮罩：底部压暗，顶部留一点光
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                p.canvas.withOpacity(0.35),
                p.canvas.withOpacity(0.15),
                p.canvas.withOpacity(0.86),
                p.canvas,
              ],
              stops: const [0, 0.38, 0.82, 1],
            ),
          ),
        ),
        // 左侧横向遮罩，给文字留出干净区域
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                p.canvas.withOpacity(compact ? 0.72 : 0.82),
                p.canvas.withOpacity(0.1),
              ],
              stops: const [0, 0.72],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroButton extends StatefulWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final bg = widget.primary
        ? p.accent
        : (_hover ? Colors.white.withOpacity(0.16) : Colors.white.withOpacity(0.08));
    final fg = widget.primary ? p.onAccent : p.text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: widget.primary ? p.accent : Colors.white.withOpacity(0.16),
              width: 0.9,
            ),
            boxShadow: widget.primary
                ? [
                    BoxShadow(
                      color: p.accent.withOpacity(_hover ? 0.35 : 0.18),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: PqType.label.copyWith(fontSize: 13, color: fg, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 继续观看卡：横版 16:9，带进度条。
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
    final p = PqPalette.of(context);
    return HoverZoom(
      borderRadius: 14,
      child: PqPressable(
        onTap: onTap,
        borderRadius: 14,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: SmartImage(
                  url: posterUrl,
                  title: title,
                  radius: 14,
                  dim: 0.12,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: Colors.white.withOpacity(0.18),
                          ),
                        ),
                      ),
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 40,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PqType.title.copyWith(fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PqType.bodySmall.copyWith(fontSize: 11.5, color: p.textFaint),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: PqPalette.of(context).textFaint,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

double clampAspect(double v) => math.max(1.2, math.min(v, 2.4));
