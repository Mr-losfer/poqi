import 'package:flutter/material.dart';

import '../design/pq_theme.dart';

/// 骨架屏：统一走 1.3s 的斜向微光。
class PqSkeleton extends StatefulWidget {
  const PqSkeleton({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.baseColor,
  });

  final double? width;
  final double height;
  final double radius;
  final Color? baseColor;

  @override
  State<PqSkeleton> createState() => _PqSkeletonState();
}

class _PqSkeletonState extends State<PqSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final base = widget.baseColor ?? p.surfaceHigh;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1.6 + _c.value * 3.2, -0.4),
                end: Alignment(-0.6 + _c.value * 3.2, 0.4),
                colors: [
                  base,
                  Color.lerp(base, p.textFaint, 0.10) ?? base,
                  base,
                ],
                stops: const [0.25, 0.5, 0.75],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 海报网格骨架。
class PqPosterGridSkeleton extends StatelessWidget {
  const PqPosterGridSkeleton({
    super.key,
    this.count = 6,
    this.columns = 3,
    this.aspect = 2 / 3,
    this.gap = 12,
  });

  final int count;
  final int columns;
  final double aspect;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap + 26,
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: aspect,
                      child: PqSkeleton(height: w / aspect, radius: 14),
                    ),
                    const SizedBox(height: 9),
                    PqSkeleton(width: w * 0.72, height: 11),
                    const SizedBox(height: 6),
                    PqSkeleton(width: w * 0.4, height: 9),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 首屏加载：品牌化的一行文字 + 细进度条，比转圈更有气质。
class PqLoadingLine extends StatelessWidget {
  const PqLoadingLine({super.key, this.label = '正在聚合…', this.expanded = true});

  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: expanded ? 40 : 16),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(minHeight: 2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: PqType.eyebrow.copyWith(color: p.textFaint, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

/// 统一错误态，强调"可继续操作"。
class PqErrorState extends StatelessWidget {
  const PqErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = '这一步没走通',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.danger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.danger.withOpacity(0.3)),
                ),
                child: Icon(Icons.offline_bolt_outlined, color: p.danger, size: 24),
              ),
              const SizedBox(height: 16),
              Text(title, style: PqType.title),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: PqType.bodySmall.copyWith(color: p.textMuted, height: 1.6),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
