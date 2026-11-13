import 'dart:async';

import 'package:flutter/material.dart';

/// 入场动画：淡入 + 上移，带轻微延迟形成节奏。
class PqEnter extends StatefulWidget {
  const PqEnter({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 380),
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<PqEnter> createState() => _PqEnterState();
}

class _PqEnterState extends State<PqEnter> {
  bool _show = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _show = true;
    } else {
      _t = Timer(widget.delay, () {
        if (mounted) setState(() => _show = true);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return widget.child;
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _show ? Offset.zero : Offset(0, widget.offset / 100),
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// 按索引错峰入场（列表使用，最多累计 240ms 避免长列表末尾等待）。
class PqStagger extends StatelessWidget {
  const PqStagger({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 26),
    this.maxDelay = 12,
  });

  final int index;
  final Widget child;
  final Duration step;
  final int maxDelay;

  @override
  Widget build(BuildContext context) {
    final i = index.clamp(0, maxDelay);
    return PqEnter(delay: step * i, child: child);
  }
}

/// 页面转场：淡入 + 4% 上移 + 轻微缩放，替代平台默认的横向推入。
class PqPageTransitions extends PageTransitionsBuilder {
  const PqPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.992, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

/// 内容切换时的交叉淡化（筛选结果、Tab 内容）。
class PqAnimatedSwap extends StatelessWidget {
  const PqAnimatedSwap({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.01),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 呼吸光点：表示"服务在线/正在扫描"。
class PqPulseDot extends StatefulWidget {
  const PqPulseDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  State<PqPulseDot> createState() => _PqPulseDotState();
}

class _PqPulseDotState extends State<PqPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.6,
      height: widget.size * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - _c.value) * 0.45,
                child: Container(
                  width: widget.size + widget.size * 1.6 * _c.value,
                  height: widget.size + widget.size * 1.6 * _c.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 进度条：1.5px 细线，带高光。
class PqProgressLine extends StatelessWidget {
  const PqProgressLine({
    super.key,
    required this.value,
    this.height = 3,
    this.color,
  });

  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: Colors.white.withOpacity(0.08)),
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
