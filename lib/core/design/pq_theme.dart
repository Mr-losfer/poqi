import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Poqi 设计令牌 —— **Material 3 标准体系**。
///
/// 主题由 `ColorScheme.fromSeed` 生成，配色、层级、形状全部走 Material 3
/// 的 tonal palette 与 shape scale；不再自定义品牌色与投影规则。
/// 这里只保留两样东西：
///   1. 8dp 网格常量（间距节奏）
///   2. 一层语义别名 [PqPalette]，把 ColorScheme 的角色翻译成业务可读的名字，
///      避免每个页面都写 `Theme.of(context).colorScheme.onSurfaceVariant`。
class PqTokens {
  const PqTokens._();

  /// Material 3 形状尺度：extra-small / small / medium / large / extra-large。
  static const double r4 = 4;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r28 = 28;

  /// 8dp 网格：页面边距 16、区块间距 24、大区块 32。
  static const double gutter = 16;
  static const double maxContent = 1440;

  /// 断点，与 Material 3 window size class 对齐。
  static const double compactMax = 600;
  static const double mediumMax = 840;
}

/// 语义色板：不是新的配色系统，只是 [ColorScheme] 的业务别名。
///
/// 每个字段都直接来自 Material 3 的角色（surface / surfaceContainer /
/// onSurfaceVariant / outlineVariant / primary …），因此亮暗切换、
/// 动态取色都会自动跟随，页面里不需要判断明暗。
@immutable
class PqPalette extends ThemeExtension<PqPalette> {
  const PqPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceHigher,
    required this.line,
    required this.lineSoft,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.sage,
    required this.clay,
    required this.danger,
    required this.isDark,
  });

  /// 页面底色 → `surface`
  final Color canvas;

  /// 一级容器 → `surfaceContainerLow`
  final Color surface;

  /// 二级容器（输入框、hover）→ `surfaceContainerHigh`
  final Color surfaceHigh;

  /// 三级容器（选中态、tooltip）→ `surfaceContainerHighest`
  final Color surfaceHigher;

  /// 分隔线与描边 → `outlineVariant`
  final Color line;

  /// 更轻的描边 → `outlineVariant` 降透明度
  final Color lineSoft;

  /// 主文字 → `onSurface`
  final Color text;

  /// 次要文字 → `onSurfaceVariant`
  final Color textMuted;

  /// 极弱文字（占位、计数）→ `onSurfaceVariant` 降透明度
  final Color textFaint;

  /// 强调色 → `primary`
  final Color accent;

  /// 强调色上的文字 → `onPrimary`
  final Color onAccent;

  /// 辅助强调 → `tertiary`
  final Color sage;

  /// 次强调 → `secondary`
  final Color clay;

  /// 错误 → `error`
  final Color danger;

  final bool isDark;

  /// 从 Material 3 色彩方案派生，不做任何额外加工。
  factory PqPalette.fromScheme(ColorScheme s) => PqPalette(
        canvas: s.surface,
        surface: s.surfaceContainerLow,
        surfaceHigh: s.surfaceContainerHigh,
        surfaceHigher: s.surfaceContainerHighest,
        line: s.outlineVariant,
        lineSoft: s.outlineVariant.withOpacity(0.55),
        text: s.onSurface,
        textMuted: s.onSurfaceVariant,
        textFaint: s.onSurfaceVariant.withOpacity(0.72),
        accent: s.primary,
        onAccent: s.onPrimary,
        sage: s.tertiary,
        clay: s.secondary,
        danger: s.error,
        isDark: s.brightness == Brightness.dark,
      );

  static PqPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<PqPalette>() ?? PqPalette.fromScheme(theme.colorScheme);
  }

  @override
  PqPalette copyWith({
    Color? accent,
    Color? onAccent,
    Color? text,
    Color? canvas,
    Color? surface,
    bool? isDark,
  }) =>
      PqPalette(
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh,
        surfaceHigher: surfaceHigher,
        line: line,
        lineSoft: lineSoft,
        text: text ?? this.text,
        textMuted: textMuted,
        textFaint: textFaint,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        sage: sage,
        clay: clay,
        danger: danger,
        isDark: isDark ?? this.isDark,
      );

  @override
  PqPalette lerp(ThemeExtension<PqPalette>? other, double t) {
    if (other is! PqPalette) return this;
    return PqPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      surfaceHigher: Color.lerp(surfaceHigher, other.surfaceHigher, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineSoft: Color.lerp(lineSoft, other.lineSoft, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      clay: Color.lerp(clay, other.clay, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// 排版：严格对齐 Material 3 type scale（2021）。
///
/// 字号/行高/字重都取自规范，字体交给主题默认的 Roboto（中文自动回落系统字体），
/// 不再引入第三方展示字体。
class PqType {
  const PqType._();

  /// 品牌字：22 / 28，对应 titleLarge 的度量。
  static const TextStyle brand = TextStyle(
    fontSize: 22,
    height: 1.27,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  /// 主视觉标题：32 / 40，对应 headlineLarge。
  static const TextStyle hero = TextStyle(
    fontSize: 32,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  /// 页面标题：24 / 32，对应 headlineSmall。
  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    height: 1.33,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// 区块标题：22 / 28，对应 titleLarge。
  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    height: 1.27,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// 卡片标题：16 / 24，对应 titleMedium。
  static const TextStyle title = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );

  /// 正文：14 / 20，对应 bodyMedium。
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.43,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
  );

  /// 辅助正文：12 / 16，对应 bodySmall。
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    height: 1.33,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
  );

  /// 标签/按钮：14 / 20，对应 labelLarge。
  static const TextStyle label = TextStyle(
    fontSize: 14,
    height: 1.43,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// 等宽：代码与 JSON 预览。
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Roboto Mono', 'Menlo', 'Consolas', 'Courier New'],
    fontSize: 12.5,
    height: 1.6,
    fontWeight: FontWeight.w400,
  );

  /// 分区小标签：11 / 16，对应 labelSmall。
  static const TextStyle eyebrow = TextStyle(
    fontSize: 11,
    height: 1.45,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );
}

/// 主题构建：先取 Material 3 默认值，再只覆盖"必须覆盖"的几项。
///
/// 刻意保持克制——组件的形状、高度、动效都走 Flutter 的 Material 3 默认实现，
/// 这样才是"标准格式"，而不是把 Material 组件重新化妆一遍。
class PqTheme {
  const PqTheme._();

  /// Material 3 基线种子色（Flutter `ColorScheme.fromSeed` 的默认值）。
  static const Color seed = Color(0xFF6750A4);

  static ThemeData build({required bool dark}) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      // 中文回落链：Roboto → 系统中文字体
      textTheme: base.textTheme.apply(
        fontFamilyFallback: const [
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'Source Han Sans SC',
          'PingFang SC',
          'Microsoft YaHei',
        ],
      ),
      extensions: [PqPalette.fromScheme(scheme)],

      // 卡片默认无外边距：布局由页面控制间距，避免出现"双份 padding"。
      cardTheme: const CardTheme(margin: EdgeInsets.zero),

      // 状态栏图标跟随明暗
      appBarTheme: AppBarTheme(
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      // 桌面端滚动条细化，移动端不受影响
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(scheme.onSurfaceVariant.withOpacity(0.4)),
      ),
    );
  }
}
