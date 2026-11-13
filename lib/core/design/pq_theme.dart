import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Poqi 设计令牌。
///
/// 视觉概念：**午夜放映厅**。墨黑为底、暖琥珀为光，
/// 用 0.5px 细描边替代投影来构造层次，避免"卡片+阴影"的通用感。
class PqTokens {
  const PqTokens._();

  // ---------- 暗色（默认） ----------
  static const canvas = Color(0xFF08090B);
  static const surface = Color(0xFF0F1216);
  static const surfaceHigh = Color(0xFF161A1F);
  static const surfaceHigher = Color(0xFF1D232A);
  static const line = Color(0xFF272F36);
  static const lineSoft = Color(0xFF1A2027);
  static const text = Color(0xFFF3F0E8);
  static const textMuted = Color(0xFF9DA7A5);
  static const textFaint = Color(0xFF6A7472);

  static const amber = Color(0xFFE8B564);
  static const amberDeep = Color(0xFFB4791F);
  static const sage = Color(0xFF92B8A5);
  static const clay = Color(0xFFD98B6F);
  static const danger = Color(0xFFE0736B);

  // ---------- 亮色 ----------
  static const lightCanvas = Color(0xFFF7F4ED);
  static const lightSurface = Color(0xFFFFFEFA);
  static const lightSurfaceHigh = Color(0xFFF0ECE2);
  static const lightSurfaceHigher = Color(0xFFE8E2D6);
  static const lightLine = Color(0xFFE0DACD);
  static const lightLineSoft = Color(0xFFECE7DC);
  static const lightText = Color(0xFF15191B);
  static const lightTextMuted = Color(0xFF5B6462);
  static const lightTextFaint = Color(0xFF8A918E);
  static const lightAmber = Color(0xFFA2631A);

  // ---------- 尺度 ----------
  static const double r4 = 4;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r28 = 28;

  static const double gutter = 20;
  static const double maxContent = 1440;
}

/// 随明暗切换的语义色板，通过 ThemeExtension 下发。
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

  final Color canvas;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceHigher;
  final Color line;
  final Color lineSoft;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color onAccent;
  final Color sage;
  final Color clay;
  final Color danger;
  final bool isDark;

  static const dark = PqPalette(
    canvas: PqTokens.canvas,
    surface: PqTokens.surface,
    surfaceHigh: PqTokens.surfaceHigh,
    surfaceHigher: PqTokens.surfaceHigher,
    line: PqTokens.line,
    lineSoft: PqTokens.lineSoft,
    text: PqTokens.text,
    textMuted: PqTokens.textMuted,
    textFaint: PqTokens.textFaint,
    accent: PqTokens.amber,
    onAccent: Color(0xFF231804),
    sage: PqTokens.sage,
    clay: PqTokens.clay,
    danger: PqTokens.danger,
    isDark: true,
  );

  static const light = PqPalette(
    canvas: PqTokens.lightCanvas,
    surface: PqTokens.lightSurface,
    surfaceHigh: PqTokens.lightSurfaceHigh,
    surfaceHigher: PqTokens.lightSurfaceHigher,
    line: PqTokens.lightLine,
    lineSoft: PqTokens.lightLineSoft,
    text: PqTokens.lightText,
    textMuted: PqTokens.lightTextMuted,
    textFaint: PqTokens.lightTextFaint,
    accent: PqTokens.lightAmber,
    onAccent: Color(0xFFFFFBF2),
    sage: Color(0xFF3F6B58),
    clay: Color(0xFF9C5334),
    danger: Color(0xFFB4453D),
    isDark: false,
  );

  static PqPalette of(BuildContext context) =>
      Theme.of(context).extension<PqPalette>() ?? dark;

  @override
  PqPalette copyWith({Color? accent, Color? text, bool? isDark}) => PqPalette(
        canvas: canvas,
        surface: surface,
        surfaceHigh: surfaceHigh,
        surfaceHigher: surfaceHigher,
        line: line,
        lineSoft: lineSoft,
        text: text ?? this.text,
        textMuted: textMuted,
        textFaint: textFaint,
        accent: accent ?? this.accent,
        onAccent: onAccent,
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

/// 排版：展示级用 Bricolage（拉丁/数字），中文回落到系统字重层次。
class PqType {
  const PqType._();

  static const String display = 'Bricolage';

  static const TextStyle brand = TextStyle(
    fontFamily: display,
    fontSize: 22,
    height: 1.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  static const TextStyle hero = TextStyle(
    fontFamily: display,
    fontSize: 40,
    height: 1.02,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const TextStyle title = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.55,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Consolas', 'Courier New'],
    fontSize: 12.5,
    height: 1.6,
    fontWeight: FontWeight.w400,
  );

  /// 小号全大写标签，用于分区标识（如 "CONTINUE"）。
  static const TextStyle eyebrow = TextStyle(
    fontFamily: display,
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
  );
}

class PqTheme {
  const PqTheme._();

  static ThemeData build({required bool dark}) {
    final p = dark ? PqPalette.dark : PqPalette.light;
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.sage,
      onSecondary: dark ? const Color(0xFF0A1512) : Colors.white,
      tertiary: p.clay,
      onTertiary: dark ? const Color(0xFF1A0C07) : Colors.white,
      error: p.danger,
      onError: dark ? const Color(0xFF1A0908) : Colors.white,
      surface: p.surface,
      onSurface: p.text,
      surfaceContainerHighest: p.surfaceHigher,
      outline: p.line,
      outlineVariant: p.lineSoft,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      fontFamilyFallback: const ['Noto Sans CJK SC', 'Source Han Sans SC', 'PingFang SC', 'Microsoft YaHei', 'sans-serif'],
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: p.text, displayColor: p.text)
          .copyWith(
            displayLarge: PqType.hero.copyWith(color: p.text),
            headlineMedium: PqType.h1.copyWith(color: p.text),
            titleLarge: PqType.h2.copyWith(color: p.text),
            titleMedium: PqType.title.copyWith(color: p.text),
            bodyMedium: PqType.body.copyWith(color: p.text),
            bodySmall: PqType.bodySmall.copyWith(color: p.textMuted),
            labelLarge: PqType.label.copyWith(color: p.text),
          ),
      extensions: [p],
      dividerTheme: DividerThemeData(color: p.lineSoft, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textMuted, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: PqType.title.copyWith(color: p.text, fontSize: 16),
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardTheme(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PqTokens.r16),
          side: BorderSide(color: p.lineSoft),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PqTokens.r20),
          side: BorderSide(color: p.line),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surfaceHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceHigh,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: PqType.body.copyWith(color: p.textFaint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PqTokens.r12),
          borderSide: BorderSide(color: p.lineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PqTokens.r12),
          borderSide: BorderSide(color: p.lineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PqTokens.r12),
          borderSide: BorderSide(color: p.accent.withOpacity(0.9), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PqTokens.r12),
          borderSide: BorderSide(color: p.danger),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceHigh,
        selectedColor: p.accent,
        side: BorderSide(color: p.lineSoft),
        labelStyle: PqType.label.copyWith(color: p.textMuted),
        secondaryLabelStyle: PqType.label.copyWith(color: p.onAccent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          textStyle: PqType.label.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PqTokens.r12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.text,
          textStyle: PqType.label.copyWith(fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PqTokens.r8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          side: BorderSide(color: p.line),
          textStyle: PqType.label.copyWith(fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PqTokens.r12)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceHigher,
        contentTextStyle: PqType.bodySmall.copyWith(color: p.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PqTokens.r12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accent.withOpacity(0.16),
        height: 64,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => PqType.eyebrow.copyWith(
            fontSize: 10,
            letterSpacing: 0.8,
            color: s.contains(WidgetState.selected) ? p.accent : p.textFaint,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 21,
            color: s.contains(WidgetState.selected) ? p.accent : p.textMuted,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceHigher,
        circularTrackColor: p.surfaceHigher,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceHigher,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.line),
        ),
        textStyle: PqType.bodySmall.copyWith(color: p.text, fontSize: 11.5),
        waitDuration: const Duration(milliseconds: 420),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.textFaint.withOpacity(0.35)),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
      ),
    );
  }
}
