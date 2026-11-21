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
    danger: Color(0xFFFF6B6B),
    info: Color(0xFF60A5FA),
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
    success: Color(0xFF15803D),
    warning: Color(0xFF92400E),
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
      Theme.of(this).extension<UmbrellaColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? UmbrellaColors.dark
          : UmbrellaColors.light);

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

/// مقیاس یکدست اندازه های رابط کاربری.
///
/// پیش از این هر صفحه و هر ویجت عدد خودش را می نوشت: فاصله های ۱۰ و ۱۲ و ۱۴،
/// گوشه های ۱۱ و ۱۴ و ۱۵، دکمه های ۴۸ و ۵۲ و ۵۴، کارت های ۲۰ و ۲۴ و ۲۸. در
/// نتیجه منوها و بخش ها «یکسان» به نظر نمی رسیدند و هر بار که صفحه ای اضافه می
/// شد یک عدد تازه می آمد. حالا همه اندازه ها از همین یک مقیاس می آیند؛ صفحه ها
/// و ویجت ها فقط درجه مقیاس را انتخاب می کنند و عدد نمی نویسند.
///
/// مقیاس فاصله پایه ۴ پیکسل است (۴، ۸، ۱۲، ۱۶، ۲۰، ۲۴، ۲۸، ۳۲، ۴۰، ۴۸) و
/// مقیاس گوشه هم ۶ تا ۳۰ پیکسل است. عددی که بین دو درجه است نباید نوشته شود؛
/// به نزدیک ترین درجه گرد می شود.
class AppMetrics {
  const AppMetrics._();

  /// ── فاصله (پایه ۴ پیکسل) ──────────────────────────────────────────
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 28;
  static const double space8 = 32;
  static const double space9 = 40;
  static const double space10 = 48;

  /// حاشیه داخلی صفحه (فاصله از لبه پنجره تا محتوا).
  static const EdgeInsets pagePadding = EdgeInsets.all(space6);

  /// حاشیه داخلی کارت ها.
  static const EdgeInsets cardPadding = EdgeInsets.all(space5);

  /// ── گردی گوشه ها ─────────────────────────────────────────────────
  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusButton = 14;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 24;
  static const double radiusHuge = 30;

  /// گوشه ی کپسول (قرص) برای چیپ و نشان های کوچک.
  static const double radiusPill = 999;

  /// ── اندازه متن ────────────────────────────────────────────────────
  ///
  /// متن های اصلی از `textTheme` می آیند؛ این مقادیر برای متن های کوچکِ
  /// اندازه اشتباه (نشان، عدد شمارنده، برچسب ریز) هستند.
  static const double fontMicro = 10;
  static const double fontCaption = 11;
  static const double fontSmall = 12;
  static const double fontBody = 14;
  static const double fontButton = 15;
  static const double fontEmphasis = 17;
  static const double fontDisplay = 28;
  static const double fontHero = 40;

  /// ── اندازه آیکون ──────────────────────────────────────────────────
  static const double iconXs = 14;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;

  /// اندازه جعبه مربعی دور آیکون (`IconSquare`).
  static const double iconBoxSm = 32;
  static const double iconBoxMd = 36;
  static const double iconBoxLg = 40;
  static const double iconBoxXl = 48;
  static const double iconBoxHero = 56;

  /// ── قد کنترل ها ───────────────────────────────────────────────────
  ///
  /// دکمه اصلی ۵۲، دکمه کوچک ۴۴ و دکمه ی بزرگ (دکمه اتصال) ۵۶ پیکسل است —
  /// روی ویندوز کمی بلندتر از حداقل لمسی ۴۴ پیکسل تا با تورفتگی ۲۰ پیکسل در
  /// کارت ها جاری باشد.
  static const double controlHeight = 52;
  static const double controlHeightSmall = 44;
  static const double controlHeightLarge = 56;

  /// دکمه آیکونی مربعی (نسخه ۴۰ در ۴۰ پیکسل).
  static const double iconButton = 40;

  /// بیشینه پهنای دکمه ها تا در پنجره پهن بی اندازه کشیده نشوند.
  static const double buttonMaxWidth = 240;
  static const double controlMaxWidth = 420;

  /// خانه منو در نوار کناری.
  static const double navItemHeight = 44;

  /// ── نوار بالای پنجره ──────────────────────────────────────────────
  static const double titleBarHeight = 54;
  static const double windowButtonWidth = 48;

  /// ── نوار کناری ───────────────────────────────────────────────────
  ///
  /// عرض نوار از عرض منطقی پنجره تعیین می شود؛ روی لپ تاپ کوچک
  /// و DPI بالا حالت فشرده فضای بیشتری برای محتوای صفحه باقی می گذارد.
  static const double navWidthCompact = 72;
  static const double navWidthMedium = 188;
  static const double navWidthWide = 236;

  /// مرزهای نوار کناری، بر حسب **عرض پنجره**.
  static const double breakpointNav = 1200;
  static const double breakpointNavWide = 1440;

  /// ── مرزهای ریسپانسیو (عرض محتوا) ──────────────────────────────────
  static const double breakpointCompact = 560;
  static const double breakpointGrid = 720;
  static const double breakpointColumns = 820;

  /// حداکثر پهنای محتوا تا در پنجره های بسیار پهن خط متن بی اندازه بلند
  /// نشود و چیدمان منو ها در وسط بماند.
  static const double maxContentWidth = 1180;

  /// حداکثر پهنای گفت و گو ها.
  static const double dialogMaxWidth = 560;
  static const double dialogMaxHeight = 620;
  static const double qrDialogWidth = 372;
  static const double qrCodeSize = 200;

  /// ابعاد گفت و گوی عضویت در کانال تلگرام.
  static const double telegramDialogWidth = 360;
  static const double telegramHeaderHeight = 188;
  static const double telegramAvatarSize = 84;

  /// کمینه پهنای نشان عددی (شمارنده اعلان ها).
  static const double badgeMinWidth = 14;

  /// اندازه لوگوی برنامه در صفحه های معرفی، ورود و درباره.
  static const double logoMd = 64;
  static const double logoLg = 80;

  /// اندازه پرچم کشورها.
  static const double flagWidth = 32;
  static const double flagWidthSmall = 28;
}

class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'Vazirmatn';

  static Color gradientForeground(Color start, Color end) {
    double contrast(Color a, Color b) {
      final double x = a.computeLuminance();
      final double y = b.computeLuminance();
      return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
    }
    double worst(Color foreground) {
      final double a = contrast(foreground, start);
      final double b = contrast(foreground, end);
      return a < b ? a : b;
    }
    return worst(Colors.white) >= worst(Colors.black) ? Colors.white : Colors.black;
  }

  static final ThemeData _darkCache = _base(
    palette: UmbrellaColors.dark,
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

  static final ThemeData _lightCache = _base(
    palette: UmbrellaColors.light,
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

  static ThemeData dark() => _darkCache;

  static ThemeData light() => _lightCache;

  static ThemeData _base({
    required UmbrellaColors palette,
    required Brightness brightness,
    required ColorScheme scheme,
  }) {
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
      // فونت وزیرمتن نمادهای یونیکد (مثل نشانگرها و علامت های ریاضی) را
      // ندارد؛ بدون فونت جانشین، ویندوز آن ها را مربع یا خط تیره نشان می
      // داد. Segoe UI Symbol همیشه روی ویندوز هست.
      fontFamilyFallback: const <String>[
        'Segoe UI',
        'Segoe UI Symbol',
        'Tahoma',
      ],
      colorScheme: scheme.copyWith(
        primaryContainer: palette.primarySoft,
        onPrimaryContainer: palette.textPrimary,
        secondaryContainer: palette.surfaceHigh,
        onSecondaryContainer: palette.textPrimary,
        surfaceContainerLowest: palette.background,
        surfaceContainerLow: palette.surface,
        surfaceContainer: palette.surface,
        surfaceContainerHigh: palette.surfaceHigh,
        surfaceContainerHighest: palette.surfaceHigh,
        onSurfaceVariant: palette.textSecondary,
        outline: palette.textSecondary,
        outlineVariant: palette.border,
        surfaceTint: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
          side: BorderSide(color: palette.border),
        ),
        titleTextStyle: text.titleLarge?.copyWith(fontFamily: fontFamily, fontSize: 20),
        contentTextStyle: text.bodyMedium?.copyWith(fontFamily: fontFamily, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppMetrics.radiusXxl),
          ),
          side: BorderSide(color: palette.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: palette.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          side: BorderSide(color: palette.border),
        ),
        textStyle: TextStyle(fontFamily: fontFamily, color: palette.textPrimary),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(palette.surface),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          shadowColor: WidgetStatePropertyAll<Color>(palette.shadow),
          elevation: const WidgetStatePropertyAll<double>(12),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.all(AppMetrics.space2),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
              side: BorderSide(color: palette.border),
            ),
          ),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: palette.surfaceHigh.withValues(alpha: 0.55),
        collapsedBackgroundColor: palette.surfaceHigh.withValues(alpha: 0.4),
        iconColor: palette.textSecondary,
        collapsedIconColor: palette.textSecondary,
        textColor: palette.textPrimary,
        collapsedTextColor: palette.textPrimary,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space4,
          vertical: AppMetrics.space1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          side: BorderSide(color: palette.border),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          side: BorderSide(color: palette.border),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.primary,
        selectionColor: palette.primary.withValues(alpha: 0.25),
        selectionHandleColor: palette.primary,
      ),
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: text,
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: palette.textSecondary, size: AppMetrics.iconMd),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          border: Border.all(color: palette.border),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: AppMetrics.fontSmall,
          color: palette.textPrimary,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(palette.border),
        radius: const Radius.circular(AppMetrics.radiusSm),
        thickness: const WidgetStatePropertyAll<double>(6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceHigh,
        isDense: true,
        hintStyle: TextStyle(color: palette.textSecondary, fontFamily: fontFamily),
        labelStyle: TextStyle(
          color: palette.textSecondary,
          fontFamily: fontFamily,
          fontSize: AppMetrics.fontBody,
        ),
        helperStyle: TextStyle(
          color: palette.textSecondary,
          fontFamily: fontFamily,
          fontSize: AppMetrics.fontCaption,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space4,
          vertical: AppMetrics.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
        errorStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.danger,
          fontSize: AppMetrics.fontSmall,
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
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
          side: BorderSide(color: palette.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll<Color>(palette.onPrimary),
        side: BorderSide(color: palette.border, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.space1),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.textSecondary,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceHigh,
        selectedColor: palette.primarySoft,
        disabledColor: palette.surfaceHigh.withValues(alpha: 0.5),
        side: BorderSide(color: palette.border),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.textPrimary,
          fontSize: AppMetrics.fontSmall,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.primary,
          fontSize: AppMetrics.fontSmall,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.textPrimary,
          fontSize: AppMetrics.fontBody,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(palette.surface),
          surfaceTintColor:
              const WidgetStatePropertyAll<Color>(Colors.transparent),
          shadowColor: WidgetStatePropertyAll<Color>(palette.shadow),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: palette.border),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            ),
          ),
        ),
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, AppMetrics.controlHeightSmall),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: AppMetrics.fontBody,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, AppMetrics.controlHeight),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w800,
            fontSize: AppMetrics.fontButton,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.border),
          minimumSize: const Size(0, AppMetrics.controlHeightSmall),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: AppMetrics.fontBody,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
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
