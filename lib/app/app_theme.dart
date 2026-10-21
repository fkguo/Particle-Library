import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Quiet academic palette from the design (§7). Colour is never the sole
/// carrier of meaning: summaries, limits and inclusion states always have a
/// text label.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.warning,
    required this.error,
    required this.divider,
    required this.controlBorder,
    required this.measurementSurface,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color warning;
  final Color error;
  final Color divider;
  final Color controlBorder;
  final Color measurementSurface;

  static const light = AppPalette(
    background: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF2F7),
    textPrimary: Color(0xFF172B4D),
    textSecondary: Color(0xFF526079),
    primary: Color(0xFF175CD3),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFF067A75),
    warning: Color(0xFF9A5B00),
    error: Color(0xFFB42318),
    divider: Color(0xFFD7DEE8),
    controlBorder: Color(0xFF758399),
    measurementSurface: Color(0xFFF9FBFD),
  );

  static const dark = AppPalette(
    background: Color(0xFF101820),
    surface: Color(0xFF182431),
    surfaceAlt: Color(0xFF223244),
    textPrimary: Color(0xFFEDF3FA),
    textSecondary: Color(0xFFB4C0D0),
    primary: Color(0xFF90B4FF),
    onPrimary: Color(0xFF101820),
    accent: Color(0xFF74D7CA),
    warning: Color(0xFFF3C66A),
    error: Color(0xFFFFA69E),
    divider: Color(0xFF36495E),
    controlBorder: Color(0xFF7D91AB),
    measurementSurface: Color(0xFF1C2A3A),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? warning,
    Color? error,
    Color? divider,
    Color? controlBorder,
    Color? measurementSurface,
  }) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    accent: accent ?? this.accent,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    divider: divider ?? this.divider,
    controlBorder: controlBorder ?? this.controlBorder,
    measurementSurface: measurementSurface ?? this.measurementSurface,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      accent: mix(accent, other.accent),
      warning: mix(warning, other.warning),
      error: mix(error, other.error),
      divider: mix(divider, other.divider),
      controlBorder: mix(controlBorder, other.controlBorder),
      measurementSurface: mix(measurementSurface, other.measurementSurface),
    );
  }
}

class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      secondary: palette.accent,
      onSecondary: palette.onPrimary,
      secondaryContainer: isDark
          ? const Color(0xFF243C58)
          : const Color(0xFFE3EDFF),
      onSecondaryContainer: palette.textPrimary,
      primaryContainer: isDark
          ? const Color(0xFF1F3A5C)
          : const Color(0xFFDCE9FF),
      onPrimaryContainer: palette.textPrimary,
      tertiary: palette.accent,
      onTertiary: palette.onPrimary,
      error: palette.error,
      onError: isDark ? palette.background : Colors.white,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerHighest: palette.surfaceAlt,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.controlBorder,
      outlineVariant: palette.divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: palette.textPrimary,
      onInverseSurface: palette.surface,
      inversePrimary: palette.primary,
    );

    final baseText = Typography.material2021(platform: defaultTargetPlatform)
        .black
        .apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
        );
    final textTheme = baseText.copyWith(
      displaySmall: baseText.displaySmall?.copyWith(fontSize: 32, height: 1.15),
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontSize: 28,
        height: 1.18,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 24,
        height: 1.2,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: 20,
        height: 1.25,
      ),
      titleLarge: baseText.titleLarge?.copyWith(fontSize: 19, height: 1.3),
      titleMedium: baseText.titleMedium?.copyWith(fontSize: 16, height: 1.35),
      titleSmall: baseText.titleSmall?.copyWith(fontSize: 14, height: 1.35),
      bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 14.5, height: 1.5),
      bodySmall: baseText.bodySmall?.copyWith(fontSize: 13, height: 1.45),
      labelLarge: baseText.labelLarge?.copyWith(fontSize: 14, height: 1.3),
      labelMedium: baseText.labelMedium?.copyWith(fontSize: 12.5, height: 1.3),
      labelSmall: baseText.labelSmall?.copyWith(fontSize: 11.5, height: 1.25),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      dividerColor: palette.divider,
      fontFamily: null,
      textTheme: textTheme,
      extensions: [palette],
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: palette.primary.withValues(alpha: 0.32),
        selectionHandleColor: palette.primary,
        cursorColor: palette.primary,
      ),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
        shape: Border(bottom: BorderSide(color: palette.divider)),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.divider),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.controlBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.controlBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.error, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: isDark
            ? palette.primary.withValues(alpha: 0.22)
            : const Color(0xFFE3EDFF),
        disabledColor: palette.surfaceAlt,
        side: BorderSide(color: palette.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.labelMedium?.copyWith(color: palette.textPrimary),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: palette.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        showCheckmark: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primary,
          side: BorderSide(color: palette.controlBorder),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size(44, 44),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.textSecondary,
          minimumSize: const Size(44, 44),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: palette.surface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: isDark
            ? palette.primary.withValues(alpha: 0.18)
            : const Color(0xFFE3EDFF),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: palette.divider),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.surface,
        ),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(
          palette.textSecondary.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  static TextStyle numeric(
    TextStyle? base, {
    double? size,
    FontWeight? weight,
  }) => (base ?? const TextStyle()).copyWith(
    fontSize: size ?? base?.fontSize,
    fontWeight: weight ?? FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
    letterSpacing: 0.1,
  );
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

abstract final class Insets {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
