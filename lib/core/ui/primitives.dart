import 'package:flutter/material.dart';

import '../design/pq_theme.dart';
import 'adaptive.dart';

/// 按压回弹：移动端给出 0.97 的即时反馈。
class PqPressable extends StatefulWidget {
  const PqPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.borderRadius = 12,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final double borderRadius;
  final MouseCursor cursor;

  @override
  State<PqPressable> createState() => _PqPressableState();
}

class _PqPressableState extends State<PqPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 分区标题：一个全大写 eyebrow + 主标题 + 右侧动作。
class PqSectionHeader extends StatelessWidget {
  const PqSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.action,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: PqType.eyebrow.copyWith(color: p.accent.withOpacity(0.85)),
                  ),
                  const SizedBox(height: 7),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: PqType.h2.copyWith(fontSize: 19, letterSpacing: -0.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        subtitle!,
                        style: PqType.bodySmall.copyWith(color: p.textFaint),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class PqTag extends StatelessWidget {
  const PqTag(
    this.text, {
    super.key,
    this.color,
    this.filled = false,
    this.icon,
  });

  final String text;
  final Color? color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final c = color ?? p.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: filled ? c.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(filled ? 0.0 : 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: PqType.label.copyWith(
              fontSize: 10.5,
              color: filled ? c : c.withOpacity(0.92),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// 图标按钮：hover 时出现柔和底色，选中态统一由 [active] 控制。
class PqIconButton extends StatefulWidget {
  const PqIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onTap,
    this.active = false,
    this.size = 38,
    this.iconSize = 19,
    this.badge,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  final double iconSize;
  final Widget? badge;

  @override
  State<PqIconButton> createState() => _PqIconButtonState();
}

class _PqIconButtonState extends State<PqIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final bg = widget.active
        ? p.accent.withOpacity(0.16)
        : (_hover ? p.surfaceHigh : Colors.transparent);
    final fg = widget.active ? p.accent : p.textMuted;

    final btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.active ? p.accent.withOpacity(0.35) : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(widget.icon, size: widget.iconSize, color: fg),
              if (widget.badge != null)
                Positioned(right: -4, top: -4, child: widget.badge!),
            ],
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return btn;
    return Tooltip(message: widget.tooltip!, child: btn);
  }
}

/// 细描边面板：整个应用的"卡片"基础，不使用投影。
class PqPanel extends StatelessWidget {
  const PqPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
    this.color,
    this.border = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final bool border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: p.lineSoft, width: 0.9) : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return PqPressable(onTap: onTap, borderRadius: radius, child: content);
  }
}

/// 自定义分段控件：滑块跟随选中项移动。
class PqSegmented extends StatelessWidget {
  const PqSegmented({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.compact = false,
  });

  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.lineSoft, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14,
                  vertical: compact ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: i == index ? p.surfaceHigher : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: i == index ? p.line : Colors.transparent,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  items[i],
                  style: PqType.label.copyWith(
                    fontSize: compact ? 11.5 : 12.5,
                    color: i == index ? p.text : p.textFaint,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 搜索框：桌面显示快捷键提示，移动端为纯输入。
class PqSearchField extends StatefulWidget {
  const PqSearchField({
    super.key,
    this.hint = '搜索影片、演员、站点…',
    this.onSubmit,
    this.onChanged,
    this.autofocus = false,
    this.controller,
    this.showShortcut = true,
  });

  final String hint;
  final ValueChanged<String>? onSubmit;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextEditingController? controller;
  final bool showShortcut;

  @override
  State<PqSearchField> createState() => _PqSearchFieldState();
}

class _PqSearchFieldState extends State<PqSearchField> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  final _focus = FocusNode();
  bool _hover = false;

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final expanded = PqAdaptive.isExpanded(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: _focus.hasFocus
                ? p.accent.withOpacity(0.55)
                : (_hover ? p.line : p.lineSoft),
            width: _focus.hasFocus ? 1.2 : 0.9,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded, size: 17, color: p.textFaint),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _c,
                focusNode: _focus,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.search,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmit,
                style: PqType.body.copyWith(fontSize: 13.5),
                cursorColor: p.accent,
                cursorHeight: 16,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  hintText: widget.hint,
                  hintStyle: PqType.body.copyWith(fontSize: 13.5, color: p.textFaint),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (widget.showShortcut && expanded)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PqKeyHint(label: 'Ctrl K'),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class PqKeyHint extends StatelessWidget {  const PqKeyHint({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.surfaceHigher,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: p.line, width: 0.8),
      ),
      child: Text(
        label,
        style: PqType.mono.copyWith(fontSize: 9.5, color: p.textFaint, height: 1.4),
      ),
    );
  }
}

/// 键值行（插件/站点详情里大量使用）。
class PqMetaRow extends StatelessWidget {
  const PqMetaRow({super.key, required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: PqType.bodySmall.copyWith(color: p.textFaint)),
          ),
          Expanded(
            child: Text(
              value,
              style: PqType.bodySmall.copyWith(color: p.text, fontSize: 13),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 空状态：给出下一步动作，而不是只显示"暂无数据"。
class PqEmptyState extends StatelessWidget {
  const PqEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 28 : 56, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.surfaceHigh,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.lineSoft),
              ),
              child: Icon(icon, size: 24, color: p.textMuted),
            ),
            const SizedBox(height: 16),
            Text(title, style: PqType.title.copyWith(fontSize: 15)),
            if (message != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: PqType.bodySmall.copyWith(color: p.textMuted, height: 1.6),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 返回按钮：在桌面带文字，移动端仅图标。
class PqBackButton extends StatelessWidget {
  const PqBackButton({super.key, this.label = '返回'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = PqPalette.of(context);
    final expanded = MediaQuery.sizeOf(context).width >= 700;
    return TextButton.icon(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: Icon(Icons.arrow_back_rounded, size: 18, color: p.textMuted),
      label: expanded
          ? Text(label, style: PqType.label.copyWith(color: p.textMuted))
          : const SizedBox.shrink(),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 8, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
