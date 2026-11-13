import 'package:flutter/material.dart';

import '../design/pq_theme.dart';

enum PqFormFactor { compact, medium, expanded }

/// 响应式断点：手机 < 700，平板 700–1180，桌面 > 1180。
class PqAdaptive {
  const PqAdaptive._();

  static PqFormFactor of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 700) return PqFormFactor.compact;
    if (w < 1180) return PqFormFactor.medium;
    return PqFormFactor.expanded;
  }

  static bool isCompact(BuildContext context) =>
      of(context) == PqFormFactor.compact;
  static bool isExpanded(BuildContext context) =>
      of(context) == PqFormFactor.expanded;

  /// 主内容两侧留白随屏宽增长。
  static double gutter(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 480) return 16;
    if (w < 700) return 20;
    if (w < 1180) return 32;
    return 48;
  }

  /// 宫格列数：按可用宽度与目标卡片宽度拟合。
  static int columnsFor(double width, {double target = 148, int min = 2, int max = 9}) {
    final n = (width / target).floor();
    return n.clamp(min, max);
  }
}

/// 限定最大宽度并水平居中的内容容器。
class PqContent extends StatelessWidget {
  const PqContent({
    super.key,
    required this.child,
    this.maxWidth = PqTokens.maxContent,
    this.padding = true,
  });

  final Widget child;
  final double maxWidth;
  final bool padding;

  @override
  Widget build(BuildContext context) {
    final g = PqAdaptive.gutter(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding ? g : 0),
          child: child,
        ),
      ),
    );
  }
}

/// 页面根背景：极轻的径向光晕，避免大面积纯色平板感。
class PqBackdrop extends StatelessWidget {
  const PqBackdrop({super.key, required this.child, this.glow = true});

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: p.canvas),
      child: Stack(
        children: [
          if (glow)
            Positioned(
              top: -220,
              left: -120,
              right: -120,
              height: 520,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.1, -0.6),
                      radius: 0.9,
                      colors: [
                        p.accent.withOpacity(p.isDark ? 0.10 : 0.09),
                        p.canvas.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
