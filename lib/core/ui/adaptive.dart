import 'package:flutter/material.dart';

import '../design/pq_theme.dart';

enum PqFormFactor { compact, medium, expanded }

/// 响应式断点：对齐 Material 3 的 window size class。
///
/// - compact  < 600   手机竖屏 / 小窗
/// - medium   600–840 平板竖屏、折叠屏展开
/// - expanded ≥ 840   平板横屏、桌面
class PqAdaptive {
  const PqAdaptive._();

  static PqFormFactor of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return PqFormFactor.compact;
    if (w < 840) return PqFormFactor.medium;
    return PqFormFactor.expanded;
  }

  static bool isCompact(BuildContext context) =>
      of(context) == PqFormFactor.compact;
  static bool isExpanded(BuildContext context) =>
      of(context) == PqFormFactor.expanded;

  /// 主内容两侧留白：8dp 网格上的 16 / 24 / 32。
  static double gutter(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return 16;
    if (w < 840) return 24;
    if (w < 1240) return 24;
    return 32;
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

/// 页面根背景。
///
/// Material 3 的层级靠 surface 容器色与高度建立，不靠背景光晕，
/// 因此这里只铺一层纯 surface；`glow` 参数保留仅为兼容旧调用点。
class PqBackdrop extends StatelessWidget {
  const PqBackdrop({super.key, required this.child, this.glow = true});

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}
