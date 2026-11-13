import 'package:flutter/material.dart';

import '../design/pq_theme.dart';
import 'adaptive.dart';

/// 可点击区域。
///
/// 标准 Material 交互：水波纹（InkWell）+ 鼠标指针 + 焦点高亮，
/// 不再用自定义缩放回弹——那属于品牌化微交互，不是 Material 规范。
class PqPressable extends StatelessWidget {
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

  /// 保留参数以兼容旧调用点；Material 标准交互不使用缩放反馈。
  final double scale;
  final double borderRadius;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(borderRadius),
        mouseCursor: onTap == null ? MouseCursor.defer : cursor,
        child: child,
      ),
    );
  }
}

/// 分区标题：eyebrow + 标题 + 右侧动作。
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// 小标签：Material 3 的 tonal label chip 视觉，但不受 Chip 固定高度约束，
/// 可以安全地贴在海报角标、表格行这类紧凑位置。
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? c.withOpacity(0.16) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(PqTokens.r8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: filled ? c : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 图标按钮：Material 3 的 IconButton，选中态用 tonal 底色。
class PqIconButton extends StatelessWidget {
  const PqIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onTap,
    this.active = false,
    this.size = 40,
    this.iconSize = 20,
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = IconButton(
      onPressed: onTap,
      iconSize: iconSize,
      tooltip: tooltip,
      isSelected: active,
      style: IconButton.styleFrom(
        minimumSize: Size(size, size),
        maximumSize: Size(size, size),
        padding: EdgeInsets.zero,
        foregroundColor: active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        backgroundColor: active ? scheme.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PqTokens.r8 * 2),
        ),
      ),
      icon: Icon(icon),
    );
    if (badge == null) return button;
    return Badge(label: badge, child: button);
  }
}

/// 面板：Material 3 的 Card（filled 风格 + 细描边）。
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
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border
          ? BorderSide(color: scheme.outlineVariant)
          : BorderSide.none,
    );

    return Card(
      elevation: 0,
      color: color ?? scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 分段控件：直接使用 Material 3 的 [SegmentedButton]。
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
    return SegmentedButton<int>(
      segments: [
        for (var i = 0; i < items.length; i++)
          ButtonSegment<int>(value: i, label: Text(items[i])),
      ],
      selected: {index},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
      showSelectedIcon: false,
      style: compact
          ? const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            )
          : null,
    );
  }
}

/// 搜索框：Material 3 的全圆角 outlined 输入框。
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

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expanded = PqAdaptive.isExpanded(context);

    return SizedBox(
      height: 48,
      child: TextField(
        controller: _c,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmit,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          prefixIcon: Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: widget.showShortcut && expanded
              ? const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Center(widthFactor: 1, child: PqKeyHint(label: 'Ctrl K')),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
        ),
      ),
    );
  }
}

class PqKeyHint extends StatelessWidget {
  const PqKeyHint({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(PqTokens.r4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 10,
          color: scheme.onSurfaceVariant,
        ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 空状态：图标 + 标题 + 说明 + 主操作。
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 32 : 64, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 返回按钮：桌面带文字，移动端仅图标。
class PqBackButton extends StatelessWidget {
  const PqBackButton({super.key, this.label = '返回'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final expanded = MediaQuery.sizeOf(context).width >= 600;
    return TextButton.icon(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back, size: 20),
      label: expanded ? Text(label) : const SizedBox.shrink(),
    );
  }
}
