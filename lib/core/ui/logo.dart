import 'package:flutter/material.dart';

import '../design/pq_theme.dart';

/// 品牌标记：一个被切开的棱镜 + 字标。
///
/// 造型来自"一束光进入棱镜，散成多路"——正好是聚合器的隐喻。
class PqLogo extends StatelessWidget {
  const PqLogo({super.key, this.size = 26, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _PrismPainter(p.accent, p.text),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 9),
          Text(
            'POQI',
            style: PqType.brand.copyWith(
              fontSize: size * 0.78,
              color: p.text,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _PrismPainter extends CustomPainter {
  _PrismPainter(this.accent, this.ink);

  final Color accent;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.96, h * 0.86)
      ..lineTo(w * 0.04, h * 0.86)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = ink.withOpacity(0.85),
    );
    // 折射出的三束光
    final beams = [
      (0.16, 0.28),
      (0.30, 0.14),
      (0.44, 0.06),
    ];
    for (var i = 0; i < beams.length; i++) {
      final paint = Paint()
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = accent.withOpacity(0.9 - i * 0.24);
      canvas.drawLine(
        Offset(w * 0.5, h * 0.5),
        Offset(w * (0.5 + beams[i].$1), h * (0.5 - beams[i].$2)),
        paint,
      );
    }
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.5),
      w * 0.045,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _PrismPainter old) =>
      old.accent != accent || old.ink != ink;
}
