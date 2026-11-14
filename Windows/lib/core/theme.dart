import 'package:flutter/material.dart';

/// رنگ های برند، برداشته شده از آیکون برنامه: قرمز آتشین، زغالی و دود.
class UmbrellaColors extends ThemeExtension<UmbrellaColors> {
  const UmbrellaColors({
    required this.background,
    required this.backgroundAlt,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.primarySoft,
    required this.primaryDeep,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.glass,
    required this.shadow,
    required this.onPrimary,
  });

  final Color background;
  final Color backgroundAlt;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color primary;
  final Color primarySoft;
  final Color primaryDeep;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color glass;
  final Color shadow;
  final Color onPrimary;

  static const UmbrellaColors dark = UmbrellaColors(
    background: Color(0xFF07080B),
    backgroundAlt: Color(0xFF0C0E13),
    surface: Color(0xFF12141B),
    surfaceHigh: Color(0xFF1A1D26),
    border: Color(0xFF272B37),
    textPrimary: Color(0xFFF3F5F9),
    textSecondary: Color(0xFF9AA2B4),
    primary: Color(0xFFE11D2E),
    primarySoft: Color(0xFF3A1017),
    primaryDeep: Color(0xFF8E0E1B),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF3B82F6),
    glass: Color(0x14FFFFFF),
    shadow: Color(0x99000000),
    onPrimary: Color(0xFFFFFFFF),
  );

  static const UmbrellaColors light = UmbrellaColors(
    background: Color(0xFFF5F6FA),
    backgroundAlt: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF0F2F8),
    border: Color(0xFFE1E5EF),
    textPrimary: Color(0xFF10131C),
    textSecondary: Color(0xFF5B6478),
    primary: Color(0xFFD21027),
    primarySoft: Color(0xFFFDE7EA),
    primaryDeep: Color(0xFF9B0C1D),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    glass: Color(0x0F000000),
    shadow: Color(0x33000000),
    onPrimary: Color(0xFFFFFFFF),
  );

  @override
  UmbrellaColors copyWith({
    Color? background,
    Color? backgroundAlt,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
    Color? primarySoft,
    Color? primaryDeep,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? glass,
    Color? shadow,
    Color? onPrimary,
  }) {
    return UmbrellaColors(
      background: background ?? this.background,
      backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      glass: glass ?? this.glass,
      shadow: shadow ?? this.shadow,
      onPrimary: onPrimary ?? this.onPrimary,
    );
  }

  @override
  UmbrellaColors lerp(ThemeExtension<UmbrellaColors>? other, double t) {
    if (other is! UmbrellaColors) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return UmbrellaColors(
      background: mix(background, other.background),
      backgroundAlt: mix(backgroundAlt, other.backgroundAlt),
      surface: mix(surface, other.surface),
      surfaceHigh: mix(surfaceHigh, other.surfaceHigh),
      border: mix(border, other.border),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      primary: mix(primary, other.primary),
      primarySoft: mix(primarySoft, other.primarySoft),
      primaryDeep: mix(primaryDeep, other.primaryDeep),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
      glass: mix(glass, other.glass),
      shadow: mix(shadow, other.shadow),
      onPrimary: mix(onPrimary, other.onPrimary),
    );
  }
}

extension UmbrellaThemeX on BuildContext {
  UmbrellaColors get colors =>
      Theme.of(this).extension<UmbrellaColors>() ?? UmbrellaColors.dark;

  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: <Color>[colors.primary, colors.primaryDeep],
      );

  LinearGradient get surfaceGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[colors.surface, colors.backgroundAlt],
      );
}

class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'Vazirmatn';

  static ThemeData dark() {
    const UmbrellaColors palette = UmbrellaColors.dark;
    return _base(
      palette: palette,
      brightness: Brightness.dark,
      scheme: const ColorScheme.dark(
        primary: Color(0xFFE11D2E),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFFFF5566),
        onSecondary: Color(0xFF1A0306),
        surface: Color(0xFF12141B),
        onSurface: Color(0xFFF3F5F9),
        error: Color(0xFFEF4444),
        onError: Color(0xFFFFFFFF),
      ),
    );
  }

  static ThemeData light() {
    const UmbrellaColors palette = UmbrellaColors.light;
    return _base(
      palette: palette,
      brightness: Brightness.light,
      scheme: const ColorScheme.light(
        primary: Color(0xFFD21027),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFFB00F22),
        onSecondary: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF10131C),
        error: Color(0xFFDC2626),
        onError: Color(0xFFFFFFFF),
      ),
    );
  }

  static ThemeData _base({
    required UmbrellaColors palette,
    required Brightness brightness,
    required ColorScheme scheme,
  }) {
    final bool isDark = brightness == Brightness.dark;
    final TextTheme text = TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w900, color: palette.textPrimary, height: 1.25),
      displayMedium: TextStyle(fontWeight: FontWeight.w900, color: palette.textPrimary, height: 1.25),
      displaySmall: TextStyle(fontWeight: FontWeight.w800, color: palette.textPrimary, height: 1.3),
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, color: palette.textPrimary, height: 1.3),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: palette.textPrimary, height: 1.35),
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: palette.textPrimary, height: 1.4),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: palette.textPrimary, height: 1.4),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: palette.textPrimary, height: 1.5),
      titleSmall: TextStyle(fontWeight: FontWeight.w600, color: palette.textSecondary, height: 1.5),
      bodyLarge: TextStyle(fontWeight: FontWeight.w500, color: palette.textPrimary, height: 1.7),
      bodyMedium: TextStyle(fontWeight: FontWeight.w400, color: palette.textPrimary, height: 1.75),
      bodySmall: TextStyle(fontWeight: FontWeight.w400, color: palette.textSecondary, height: 1.7),
      labelLarge: TextStyle(fontWeight: FontWeight.w700, color: palette.textPrimary, height: 1.4),
      labelMedium: TextStyle(fontWeight: FontWeight.w600, color: palette.textSecondary, height: 1.4),
      labelSmall: TextStyle(fontWeight: FontWeight.w500, color: palette.textSecondary, height: 1.4),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: text,
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: palette.textSecondary, size: 20),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          color: palette.textPrimary,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(palette.border),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll<double>(6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? palette.surfaceHigh : palette.surfaceHigh,
        hintStyle: TextStyle(color: palette.textSecondary, fontFamily: fontFamily),
        labelStyle: TextStyle(color: palette.textSecondary, fontFamily: fontFamily),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.danger),
        ),
        errorStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.danger,
          fontSize: 12,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.onPrimary
              : palette.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.surfaceHigh,
        ),
        trackOutlineColor: WidgetStatePropertyAll<Color>(palette.border),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        inactiveTrackColor: palette.surfaceHigh,
        thumbColor: palette.primary,
        overlayColor: palette.primary.withValues(alpha: 0.16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.surfaceHigh,
        circularTrackColor: palette.surfaceHigh,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHigh,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 52),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.border),
          minimumSize: const Size(0, 48),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// تصاویر وضعیت اتصال، همان لوگوهای پوشه Image.
class BrandAssets {
  const BrandAssets._();

  static const String logo = 'assets/images/logo.png';
  static const String iconRound = 'assets/icons/icon_round.png';

  static const String connected = 'assets/images/Connected.png';
  static const String connecting = 'assets/images/Connecting.png';
  static const String disconnected = 'assets/images/Disconnected.png';
  static const String failed = 'assets/images/Failed.png';
  static const String paused = 'assets/images/Paused.png';
  static const String reconnecting = 'assets/images/Reconnecting.png';
  static const String switching = 'assets/images/Switching-Server.png';
  static const String killSwitch = 'assets/images/Kill-Switch.png';
  static const String maxProtection = 'assets/images/Max-Protection.png';
  static const String noInternet = 'assets/images/No-Internet.png';
  static const String turbo = 'assets/images/Turbo-Speed.png';
  static const String weakSignal = 'assets/images/Weak-Signal.png';

  static const List<String> all = <String>[
    connected,
    connecting,
    disconnected,
    failed,
    paused,
    reconnecting,
    switching,
    killSwitch,
    maxProtection,
    noInternet,
    turbo,
    weakSignal,
  ];
}
