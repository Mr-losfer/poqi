import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/pq_theme.dart';

/// 由标题派生的确定性配色，用于无图时的"程序化海报"。
class PosterPalette {
  const PosterPalette(this.a, this.b, this.ink);

  final Color a;
  final Color b;
  final Color ink;

  static const _sets = <List<Color>>[
    [Color(0xFF1F3A34), Color(0xFF0B1512), Color(0xFFCBE6D4)],
    [Color(0xFF3A2418), Color(0xFF140C08), Color(0xFFF2D2AC)],
    [Color(0xFF2A2340), Color(0xFF100D1A), Color(0xFFDCD2F5)],
    [Color(0xFF123043), Color(0xFF07121A), Color(0xFFB9DCEC)],
    [Color(0xFF3B1A22), Color(0xFF15080C), Color(0xFFF0C3CA)],
    [Color(0xFF2E2A16), Color(0xFF121006), Color(0xFFE8DFAF)],
    [Color(0xFF1B2A3A), Color(0xFF090E14), Color(0xFFC6D7E6)],
    [Color(0xFF38202C), Color(0xFF150A10), Color(0xFFEFC9D9)],
  ];

  factory PosterPalette.fromSeed(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final set = _sets[h % _sets.length];
    return PosterPalette(set[0], set[1], set[2]);
  }
}

/// 程序化海报：渐变底 + 超大首字 + 胶片纹理。
///
/// 设计意图：聚合源的海报经常缺失或防盗链，与其显示灰块，
/// 不如把"缺图"变成一种稳定的视觉语言。
class PosterArt extends StatelessWidget {
  const PosterArt({
    super.key,
    required this.title,
    this.seed,
    this.radius = 14,
    this.glyphSize = 0.44,
    this.dim = 0,
    this.child,
  });

  final String title;
  final String? seed;
  final double radius;
  final double glyphSize;
  final double dim;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final pal = PosterPalette.fromSeed(seed ?? title);
    final glyph = title.trim().isEmpty ? '·' : title.trim().characters.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth.isFinite ? c.maxWidth : 160.0;
            final h = c.maxHeight.isFinite ? c.maxHeight : w * 1.5;
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [pal.a, pal.b],
                    ),
                  ),
                ),
                CustomPaint(painter: _ArtPainter(pal, w, h)),
                Center(
                  child: Transform.translate(
                    offset: Offset(-w * 0.02, h * 0.02),
                    child: Text(
                      glyph,
                      style: TextStyle(
                        fontFamily: 'Bricolage',
                        fontSize: h * glyphSize,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: pal.ink.withOpacity(0.16),
                        letterSpacing: -4,
                      ),
                    ),
                  ),
                ),
                if (dim > 0)
                  ColoredBox(color: Colors.black.withOpacity(dim.clamp(0.0, 1.0))),
                if (child != null) child!,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.pal, this.w, this.h);

  final PosterPalette pal;
  final double w;
  final double h;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 斜向细线：模拟胶片齿孔/光带。
    for (var i = 0; i < 7; i++) {
      final t = i / 7;
      paint.color = pal.ink.withOpacity(0.07 - t * 0.006);
      final path = Path()
        ..moveTo(-w * 0.1, h * (0.18 + t * 0.11))
        ..lineTo(w * 1.1, h * (0.06 + t * 0.11));
      canvas.drawPath(path, paint);
    }

    // 边角圆环。
    paint.color = pal.ink.withOpacity(0.12);
    canvas.drawCircle(Offset(w * 0.92, h * 0.9), w * 0.24, paint);
    paint.color = pal.ink.withOpacity(0.06);
    canvas.drawCircle(Offset(w * 0.92, h * 0.9), w * 0.34, paint);

    // 底部渐隐，保证叠字可读。
    final rect = Rect.fromLTWH(0, h * 0.55, w, h * 0.45);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.b.withOpacity(0), pal.b.withOpacity(0.55)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) =>
      old.pal != pal || old.w != w || old.h != h;
}

/// 网络图 + 骨架 + 失败回落，全部走程序化海报。
class SmartImage extends StatelessWidget {
  const SmartImage({
    super.key,
    required this.url,
    required this.title,
    this.fit = BoxFit.cover,
    this.radius = 14,
    this.seed,
    this.dim = 0,
    this.child,
  });

  final String? url;
  final String title;
  final BoxFit fit;
  final double radius;
  final String? seed;
  final double dim;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final fallback = PosterArt(
      title: title,
      seed: seed,
      radius: radius,
      dim: dim,
      child: child,
    );
    if (url == null || url!.trim().isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url!,
            fit: fit,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, sync) {
              if (sync || frame != null) {
                return AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: child,
                );
              }
              return fallback;
            },
            errorBuilder: (_, __, ___) => fallback,
          ),
          if (dim > 0)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black.withOpacity(dim)),
              ),
            ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// 悬停放大包装（桌面/网页），移动端自动降级。
class HoverZoom extends StatefulWidget {
  const HoverZoom({
    super.key,
    required this.child,
    this.scale = 1.035,
    this.enabled = true,
    this.borderRadius = 14,
  });

  final Widget child;
  final double scale;
  final bool enabled;
  final double borderRadius;

  @override
  State<HoverZoom> createState() => _HoverZoomState();
}

class _HoverZoomState extends State<HoverZoom> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final active = widget.enabled && _hover && !reduce;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 首字圆形徽标（插件/站点图标）。
class PqMonogram extends StatelessWidget {
  const PqMonogram({
    super.key,
    required this.text,
    this.size = 40,
    this.accent,
  });

  final String text;
  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final pal = PosterPalette.fromSeed(text);
    final color = accent ?? p.accent;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.24),
            pal.a.withOpacity(0.55),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        text.isEmpty ? '·' : text.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Bricolage',
          fontSize: size * 0.42,
          height: 1,
          fontWeight: FontWeight.w700,
          color: p.text.withOpacity(0.9),
        ),
      ),
    );
  }
}

/// 横排卡片（用于"继续观看"这类横向信息密度较高的位置）。
class PqPosterAspect {
  static const double poster = 2 / 3;
  static double wide(double w) => math.min(w, w * 1.0);
}
