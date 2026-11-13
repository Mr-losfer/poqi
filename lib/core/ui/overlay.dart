import 'dart:async';

import 'package:flutter/material.dart';

import '../design/pq_theme.dart';
import 'adaptive.dart';
import 'primitives.dart';

enum PqToastKind { info, success, error }

/// 轻量吐司：从底部浮入，自动消失，不打断操作。
void showPqToast(
  BuildContext context,
  String message, {
  PqToastKind kind = PqToastKind.info,
  Duration duration = const Duration(milliseconds: 2400),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final palette = PqPalette.of(context);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastHost(
      message: message,
      kind: kind,
      palette: palette,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({
    required this.message,
    required this.kind,
    required this.palette,
    required this.duration,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final PqToastKind kind;
  final PqPalette palette;
  final Duration duration;
  final VoidCallback onDismissed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final color = switch (widget.kind) {
      PqToastKind.info => p.textMuted,
      PqToastKind.success => p.sage,
      PqToastKind.error => p.danger,
    };
    final icon = switch (widget.kind) {
      PqToastKind.info => Icons.info_outline_rounded,
      PqToastKind.success => Icons.check_circle_outline_rounded,
      PqToastKind.error => Icons.error_outline_rounded,
    };
    return Positioned(
      left: 0,
      right: 0,
      bottom: 28 + MediaQuery.of(context).padding.bottom,
      child: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: p.surfaceHigher.withOpacity(0.98),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.line),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: PqType.bodySmall.copyWith(color: p.text, fontSize: 12.5),
                      ),
                    ),
                    if (widget.actionLabel != null) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: widget.onAction,
                        child: Text(
                          widget.actionLabel!,
                          style: PqType.label.copyWith(color: p.accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 响应式弹层：手机从底部升起，平板/桌面居中弹出。
Future<T?> showPqSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool dismissible = true,
  double maxWidth = 560,
}) {
  if (PqAdaptive.isCompact(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _SheetFrame(title: title, child: builder(ctx)),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: _SheetFrame(title: title, child: builder(ctx), dialog: true),
      ),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.title, this.dialog = false});

  final Widget child;
  final String? title;
  final bool dialog;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(title!, style: PqType.h2.copyWith(fontSize: 16))),
                PqIconButton(
                  icon: Icons.close_rounded,
                  iconSize: 18,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          )
        else if (!dialog)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        Flexible(child: child),
      ],
    );
  }
}
