import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/safe_url_launcher.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import 'common.dart';

/// مدیریت زمان بندی و نمایش گفت و گوی دعوت به کانال رسمی تلگرام آمبرلا.
///
/// در نخستین اجرای برنامه نمایش داده می شود و پس از آن دقیقاً هر ۷ روز یک بار
/// یادآوری می کند تا کاربر از اخبار، نسخه های جدید و ترفندهای اتصال مطلع بماند.
class TelegramChannelPrompt {
  const TelegramChannelPrompt._();

  /// فاصله بین هر دو نمایش پیاپی اعلان عضویت در کانال تلگرام.
  static const Duration repeatInterval = Duration(days: 7);

  /// زمان آخرین نمایش ذخیره شده در انبار محلی (یا `null` اگر هنوز نمایش نشده).
  static DateTime? readLastShown({LocalStore? store}) {
    final LocalStore target = store ?? LocalStore.instance;
    final String? raw = target.read(StoreKeys.telegramChannelPromptAt)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final int? epochMs = int.tryParse(raw);
    if (epochMs == null || epochMs <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
  }

  /// ثبت زمان نمایش اعلان در انبار محلی (رشته ۶۴ بیتی بر پایه ساعت جهانی).
  static Future<void> markShown({
    DateTime? at,
    LocalStore? store,
    int? announcementVersion,
  }) async {
    final LocalStore target = store ?? LocalStore.instance;
    final int epochMs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await target.write(StoreKeys.telegramChannelPromptAt, epochMs.toString());
    if (announcementVersion != null) {
      final Map<String, dynamic> state =
          Map<String, dynamic>.from(target.readJson(StoreKeys.appAnnouncementState));
      state['shown_version'] = announcementVersion;
      state['shown_at_ms'] = epochMs;
      await target.writeJson(StoreKeys.appAnnouncementState, state);
    }
  }

  /// بررسی موعد نمایش بر پایه تنظیمات پویای اعلان دریافت شده از ربات تلگرام.
  static Future<bool> isAnnouncementDue(
    AppAnnouncement announcement, {
    DateTime? now,
    LocalStore? store,
  }) async {
    if (!announcement.enabled) {
      return false;
    }
    final DateTime current = (now ?? DateTime.now()).toUtc();
    if (announcement.startsAt > 0 &&
        current.millisecondsSinceEpoch < announcement.startsAt * 1000) {
      return false;
    }
    final LocalStore target = store ?? LocalStore.instance;
    final Map<String, dynamic> state =
        Map<String, dynamic>.from(target.readJson(StoreKeys.appAnnouncementState));
    int shownVersion = JsonX.integer(state['shown_version']);
    int shownAtMs = JsonX.integer(state['shown_at_ms']);

    if (shownAtMs <= 0 && announcement.version == 1) {
      final DateTime? legacy = await normalizeClockSkewIfNeeded(
        now: current,
        store: target,
      );
      if (legacy != null) {
        shownVersion = 1;
        shownAtMs = legacy.millisecondsSinceEpoch;
      }
    }

    if (shownAtMs <= 0 || shownVersion != announcement.version) {
      return true;
    }
    if (shownAtMs > current.millisecondsSinceEpoch) {
      state['shown_at_ms'] = current.millisecondsSinceEpoch;
      await target.writeJson(StoreKeys.appAnnouncementState, state);
      return false;
    }
    if (announcement.intervalHours <= 0) {
      return false;
    }
    final int requiredMs = announcement.intervalHours * 3600 * 1000;
    return (current.millisecondsSinceEpoch - shownAtMs) >= requiredMs;
  }

  /// باز کردن نشانی دکمه اعلان پویا (تلگرام مستقیم یا مرورگر پیش فرض).
  static Future<bool> openActionUrl(
    String rawUrl, {
    Future<bool> Function(Uri uri)? canLaunch,
    Future<bool> Function(Uri uri, LaunchMode mode)? launch,
  }) async {
    final String clean = rawUrl.trim();
    if (clean.isEmpty ||
        clean.toLowerCase() == AppConfig.channelUrl.toLowerCase()) {
      return openChannel(canLaunch: canLaunch, launch: launch);
    }
    final Future<bool> Function(Uri) check = canLaunch ?? canLaunchUrl;
    final Future<bool> Function(Uri, LaunchMode) opener =
        launch ?? ((Uri uri, LaunchMode mode) => SafeUrlLauncher.open(uri, mode: mode));

    final Uri? webUri = Uri.tryParse(clean);
    if (webUri == null || !webUri.hasScheme) {
      return openChannel(canLaunch: canLaunch, launch: launch);
    }
    if ((webUri.host == 't.me' || webUri.host == 'telegram.me') &&
        webUri.pathSegments.isNotEmpty) {
      final String first = webUri.pathSegments.first;
      if (first.isNotEmpty &&
          !first.startsWith('+') &&
          first.toLowerCase() != 'joinchat') {
        final Uri tgUri = Uri.parse('tg://resolve?domain=$first');
        try {
          if (await check(tgUri) &&
              await opener(tgUri, LaunchMode.externalNonBrowserApplication)) {
            return true;
          }
        } catch (_) {}
      }
    }
    try {
      return await opener(webUri, LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// اگر ساعت سیستم به عقب برگشته باشد، مبدا ذخیره شده را به زمان جاری اصلاح
  /// می کند تا چرخه هفت روزه هرگز قفل نشود.
  static Future<DateTime?> normalizeClockSkewIfNeeded({
    DateTime? now,
    LocalStore? store,
  }) async {
    final DateTime? lastShown = readLastShown(store: store);
    if (lastShown == null) {
      return null;
    }
    final DateTime current = (now ?? DateTime.now()).toUtc();
    if (lastShown.isAfter(current)) {
      await markShown(at: current, store: store);
      return current;
    }
    return lastShown;
  }

  /// آیا اکنون زمان نمایش اعلان عضویت در کانال فرارسیده است؟
  ///
  /// - اگر تاکنون نمایش داده نشده باشد (`lastShownAt == null`): `true`
  /// - اگر دست کم ۷ روز کامل از آخرین نمایش گذشته باشد: `true`
  /// - در غیر این صورت: `false`
  static bool isDue({required DateTime? lastShownAt, DateTime? now}) {
    if (lastShownAt == null) {
      return true;
    }
    final DateTime current = (now ?? DateTime.now()).toUtc();
    final DateTime baseline = lastShownAt.toUtc();
    if (baseline.isAfter(current)) {
      return false;
    }
    return current.difference(baseline) >= repeatInterval;
  }

  /// باز کردن کانال رسمی تلگرام: ابتدا در نرم افزار تلگرام دسکتاپ (در صورت نصب
  /// بودن روی ویندوز) و در غیر این صورت در مرورگر پیش فرض سیستم.
  static Future<bool> openChannel({
    Future<bool> Function(Uri uri)? canLaunch,
    Future<bool> Function(Uri uri, LaunchMode mode)? launch,
  }) async {
    final Future<bool> Function(Uri) check = canLaunch ?? canLaunchUrl;
    final Future<bool> Function(Uri, LaunchMode) opener =
        launch ?? ((Uri uri, LaunchMode mode) => SafeUrlLauncher.open(uri, mode: mode));

    final Uri appUri = Uri.parse(AppConfig.channelAppUrl);
    final Uri webUri = Uri.parse(AppConfig.channelUrl);

    try {
      if (await check(appUri)) {
        if (await opener(appUri, LaunchMode.externalNonBrowserApplication)) {
          return true;
        }
      }
    } catch (_) {
      // اگر باز کردن مستقیم اپلیکیشن تلگرام ممکن نبود، از لینک وب باز می شود.
    }

    try {
      return await opener(webUri, LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// نمایش گفت و گوی عضویت در کانال و ثبت هم زمان تاریخ نمایش برای چرخه ۷ روزه.
  /// خروجی `true` است اگر کاربر روی عضویت در کانال کلیک کرده باشد.
  static Future<bool> show(
    BuildContext context, {
    DateTime? now,
    LocalStore? store,
    AppAnnouncement? announcement,
    Future<bool> Function()? onJoinLaunch,
    bool animate = true,
  }) async {
    await markShown(
      at: now,
      store: store,
      announcementVersion: announcement?.version,
    );
    if (!context.mounted) {
      return false;
    }
    final Color barrier = Theme.of(context).brightness == Brightness.dark
        ? context.colors.shadow
        : context.colors.textPrimary.withValues(alpha: 0.44);
    final bool? joined = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'بستن',
      barrierColor: barrier,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return SafeArea(
          child: Center(
            child: TelegramChannelDialog(
              announcement: announcement,
              onJoinLaunch: onJoinLaunch,
              animate: animate,
            ),
          ),
        );
      },
      transitionBuilder: (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
    return joined ?? false;
  }

  /// بررسی موعد نمایش بر پایه اعلان پویای دریافتی از سرور (مدیریت شده در ربات).
  static Future<bool> showAnnouncementIfDue(
    BuildContext context, {
    required AppAnnouncement announcement,
    DateTime? now,
    LocalStore? store,
    Future<bool> Function()? onJoinLaunch,
    bool animate = true,
  }) async {
    return showIfDue(
      context,
      now: now,
      store: store,
      announcement: announcement,
      onJoinLaunch: onJoinLaunch,
      animate: animate,
    );
  }

  /// بررسی موعد ۷ روزه یا زمان بندی اعلان پویای ربات و نمایش خودکار گفت و گو.
  static Future<bool> showIfDue(
    BuildContext context, {
    DateTime? now,
    LocalStore? store,
    AppAnnouncement? announcement,
    Future<bool> Function()? onJoinLaunch,
    bool animate = true,
  }) async {
    if (announcement != null) {
      final bool due = await isAnnouncementDue(
        announcement,
        now: now,
        store: store,
      );
      if (!due) {
        return false;
      }
    } else {
      final DateTime? lastShown = await normalizeClockSkewIfNeeded(
        now: now,
        store: store,
      );
      if (!isDue(lastShownAt: lastShown, now: now)) {
        return false;
      }
    }
    if (!context.mounted) {
      return false;
    }
    await show(
      context,
      now: now,
      store: store,
      announcement: announcement,
      onJoinLaunch: onJoinLaunch,
      animate: animate,
    );
    return true;
  }
}

/// گفت و گوی دعوت به کانال رسمی تلگرام آمبرلا با پالت رنگی اختصاصی آمبرلا
/// (سازگار با هر دو حالت روشن و تاریک)، حلقه های تنفسی نرم، ستاره های درخشان،
/// نشان شناور تلگرام و آیدی رسمی کانال.
class TelegramChannelDialog extends StatefulWidget {
  const TelegramChannelDialog({
    super.key,
    this.channelHandle = AppConfig.channelHandle,
    this.announcement,
    this.onJoinLaunch,
    this.animate = true,
  });

  /// گرادیان سربرگ کارت بر پایه پالت فعال آمبرلا (روشن یا تاریک).
  static List<Color> headerGradientFor(
    UmbrellaColors colors,
    Brightness brightness,
  ) {
    final double highlight = brightness == Brightness.dark ? 0.14 : 0.16;
    return <Color>[
      Color.lerp(colors.primary, colors.onPrimary, highlight)!,
      colors.primary,
      colors.primaryDeep,
    ];
  }

  final String channelHandle;
  final AppAnnouncement? announcement;
  final Future<bool> Function()? onJoinLaunch;
  final bool animate;

  @override
  State<TelegramChannelDialog> createState() => _TelegramChannelDialogState();
}

class _TelegramChannelDialogState extends State<TelegramChannelDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animate) {
      _floatController.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bool shouldRun = widget.animate && !reduceMotion;
    if (shouldRun && !_floatController.isAnimating) {
      _floatController.repeat();
    } else if (!shouldRun && _floatController.isAnimating) {
      _floatController.stop();
    }
  }

  @override
  void didUpdateWidget(covariant TelegramChannelDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (widget.animate && !reduceMotion) {
        _floatController.repeat();
      } else {
        _floatController.stop();
      }
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  void _handleJoin() {
    playUiClick(context);
    final Future<bool> Function() launcher = widget.onJoinLaunch ??
        () {
          final AppAnnouncement? ann = widget.announcement;
          if (ann != null) {
            return TelegramChannelPrompt.openActionUrl(ann.buttonUrl);
          }
          return TelegramChannelPrompt.openChannel();
        };
    Navigator.of(context).pop(true);
    unawaited(launcher());
  }

  void _handleLater() {
    playUiClick(context);
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UmbrellaColors colors = context.colors;
    final AppAnnouncement? ann = widget.announcement;
    final String effectiveHandle =
        ann != null ? ann.displaySubtitleHandle : widget.channelHandle;
    final String titleText = ann?.title ?? 'به کانال رسمی آمبرلا بپیوندید';
    final String bodyText = Fa.num(
      ann?.body ??
          '☂️ فیلترشکن آمبرلا؛ برای دریافت به روز رسانی ها و اخبار، عضو کانال رسمی تلگرام شوید.',
    );
    final String buttonText = ann?.buttonText ?? 'عضویت در کانال رسمی';
    final bool isTelegramTarget = ann == null ||
        ann.isDefaultChannelLink ||
        ann.buttonUrl.toLowerCase().contains('t.me') ||
        ann.buttonUrl.toLowerCase().contains('telegram.me');

    return Dialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: colors.shadow,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space6,
        vertical: AppMetrics.space6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.space7),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppMetrics.telegramDialogWidth,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TelegramHeader(
                float: _floatController,
                channelHandle: effectiveHandle,
                icon: isTelegramTarget ? Icons.telegram : Icons.campaign_rounded,
                onTapHandle: _handleJoin,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.space6,
                  AppMetrics.space5,
                  AppMetrics.space6,
                  AppMetrics.space2,
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      titleText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppMetrics.fontMicro),
                    Text(
                      bodyText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.space6,
                  AppMetrics.space4,
                  AppMetrics.space6,
                  AppMetrics.space2,
                ),
                child: FilledButton.icon(
                  key: const Key('telegram_channel_join_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(AppMetrics.space10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppMetrics.radiusButton,
                      ),
                    ),
                    textStyle: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: Icon(
                    isTelegramTarget
                        ? Icons.telegram
                        : Icons.open_in_new_rounded,
                    size: AppMetrics.iconLg,
                    color: colors.onPrimary,
                  ),
                  label: Text(buttonText),
                  onPressed: _handleJoin,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: AppMetrics.space3),
                child: Center(
                  child: TextButton(
                    key: const Key('telegram_channel_later_button'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: _handleLater,
                    child: const Text('بعداً'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelegramHeader extends StatelessWidget {
  const _TelegramHeader({
    required this.float,
    required this.channelHandle,
    required this.icon,
    required this.onTapHandle,
  });

  final Animation<double> float;
  final String channelHandle;
  final IconData icon;
  final VoidCallback onTapHandle;

  /// مختصات افقی، مختصات عمودی، اختلاف فاز حرکت و اندازه ستاره های درخشان.
  static const List<(double, double, double, double)> _sparkles =
      <(double, double, double, double)>[
    (-0.72, -0.55, 0.0, 14.0),
    (0.78, -0.35, 2.1, 18.0),
    (-0.55, 0.62, 4.2, 10.0),
    (0.62, 0.70, 1.3, 12.0),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UmbrellaColors colors = context.colors;
    final List<Color> gradientColors = TelegramChannelDialog.headerGradientFor(
      colors,
      theme.brightness,
    );
    return RepaintBoundary(
      child: SizedBox(
        height: AppMetrics.telegramHeaderHeight,
        child: DecoratedBox(
          key: const Key('telegram_channel_header'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            border: Border(
              bottom: BorderSide(color: colors.border.withValues(alpha: 0.45)),
            ),
          ),
          child: AnimatedBuilder(
            animation: float,
            builder: (BuildContext context, Widget? child) {
              final double phase = float.value * 2 * math.pi;
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TelegramRingsPainter(
                        phase: phase,
                        ringColor: colors.onPrimary,
                      ),
                    ),
                  ),
                  for (final (double x, double y, double offset, double size)
                      in _sparkles)
                    Align(
                      alignment: Alignment(
                        x,
                        y + math.sin(phase + offset) * 0.05,
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        size: size,
                        color: colors.onPrimary.withValues(alpha: 0.55),
                      ),
                    ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Transform.translate(
                        offset: Offset(0, math.sin(phase) * 5),
                        child: Transform.rotate(
                          angle: math.sin(phase) * 0.05,
                          child: Container(
                            key: const Key('telegram_channel_avatar'),
                            width: AppMetrics.telegramAvatarSize,
                            height: AppMetrics.telegramAvatarSize,
                            decoration: BoxDecoration(
                              color: colors.onPrimary,
                              shape: BoxShape.circle,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color:
                                      colors.primaryDeep.withValues(alpha: 0.5),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              icon,
                              size: AppMetrics.telegramAvatarSize,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppMetrics.iconXs),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          key: const Key('telegram_channel_handle_badge'),
                          onTap: onTapHandle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppMetrics.space3,
                              vertical: AppMetrics.space1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.onPrimary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(
                                AppMetrics.radiusXl,
                              ),
                              border: Border.all(
                                color: colors.onPrimary.withValues(alpha: 0.36),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                channelHandle,
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onPrimary,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// حلقه های هم مرکز نرم پشت آیکون کانال با حرکت تنفسی ملایم.
class _TelegramRingsPainter extends CustomPainter {
  const _TelegramRingsPainter({
    required this.phase,
    required this.ringColor,
  });

  final double phase;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2 - 20);
    final double breath = 1 + math.sin(phase) * 0.03;
    for (int i = 1; i <= 4; i++) {
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ringColor.withValues(alpha: 0.22 - i * 0.04);
      canvas.drawCircle(center, (42 + i * 26) * breath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TelegramRingsPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.ringColor != ringColor;
  }
}

/// نوار فشرده و قابل بستن برای نمایش اعلان تبلیغاتی در صفحه اصلی اتصال.
class PromoBannerBar extends StatelessWidget {
  const PromoBannerBar({
    super.key,
    required this.promo,
    this.imageBytes,
    required this.onOpen,
    required this.onDismiss,
    this.onAction,
    this.dense = false,
  });

  final PromoAnnouncement promo;
  final Uint8List? imageBytes;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final String titleText = Fa.num(
      promo.title.trim().isEmpty ? 'پیشنهاد ویژه آمبرلا' : promo.title.trim(),
    );
    final String bodyText = Fa.num(promo.body.trim());
    final String actionText = Fa.num(
      promo.hasButton ? promo.buttonText.trim() : 'مشاهده',
    );
    final double thumbSize = dense ? 40 : 48;

    return Material(
      key: const Key('promo_banner_bar'),
      color: Colors.transparent,
      child: InkWell(
        onTap: withUiClick(context, onOpen),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? AppMetrics.space2 + 2 : AppMetrics.space3,
            vertical: dense ? AppMetrics.space2 : AppMetrics.space2 + 2,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: <Color>[
                Color.alphaBlend(
                  colors.primary.withValues(alpha: isDark ? 0.20 : 0.12),
                  colors.surfaceHigh,
                ),
                Color.alphaBlend(
                  colors.primaryDeep.withValues(alpha: isDark ? 0.14 : 0.08),
                  colors.surface,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.42),
            ),
          ),
          child: Row(
            children: <Widget>[
              _PromoThumbnail(
                bytes: imageBytes,
                size: thumbSize,
                colors: colors,
              ),
              SizedBox(width: dense ? AppMetrics.space2 : AppMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (dense
                              ? theme.textTheme.labelLarge
                              : theme.textTheme.titleSmall)
                          ?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (bodyText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        bodyText,
                        maxLines: dense ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: dense ? AppMetrics.fontMicro : null,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (promo.hasButton && onAction != null) ...<Widget>[
                const SizedBox(width: AppMetrics.space2),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: dense ? 104 : 132),
                  child: FilledButton(
                    key: const Key('promo_banner_action_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      elevation: 0,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.symmetric(
                        horizontal: dense ? AppMetrics.space2 : AppMetrics.space3,
                        vertical: AppMetrics.space1,
                      ),
                      minimumSize: Size(0, dense ? 30 : 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                      ),
                    ),
                    onPressed: withUiClick(context, onAction),
                    child: Text(
                      actionText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppMetrics.space1),
              IconButton(
                key: const Key('promo_banner_dismiss_button'),
                tooltip: 'بستن اعلان',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: withUiClick(context, onDismiss),
                icon: Icon(
                  Icons.close_rounded,
                  size: AppMetrics.iconSm,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoThumbnail extends StatelessWidget {
  const _PromoThumbnail({
    required this.bytes,
    required this.size,
    required this.colors,
  });

  final Uint8List? bytes;
  final double size;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.campaign_rounded,
        color: colors.primary,
        size: size * 0.52,
      ),
    );
    final Uint8List? raw = bytes;
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      child: Image.memory(
        raw,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// نمایش گفت و گوی کامل اعلان تبلیغاتی همراه با تصویر، متن و دکمه اقدام.
class PromoAnnouncementPrompt {
  const PromoAnnouncementPrompt._();

  static Future<bool> show(
    BuildContext context, {
    required PromoAnnouncement promo,
    Uint8List? initialImageBytes,
    Future<Uint8List?> Function()? loadImage,
    Future<bool> Function()? onActionLaunch,
  }) async {
    if (!context.mounted) {
      return false;
    }
    final Color barrier = Theme.of(context).brightness == Brightness.dark
        ? context.colors.shadow
        : context.colors.textPrimary.withValues(alpha: 0.48);
    final bool? acted = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'بستن',
      barrierColor: barrier,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return SafeArea(
          child: Center(
            child: PromoAnnouncementDialog(
              promo: promo,
              initialImageBytes: initialImageBytes,
              loadImage: loadImage,
              onActionLaunch: onActionLaunch,
            ),
          ),
        );
      },
      transitionBuilder: (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
    return acted ?? false;
  }
}

class PromoAnnouncementDialog extends StatefulWidget {
  const PromoAnnouncementDialog({
    super.key,
    required this.promo,
    this.initialImageBytes,
    this.loadImage,
    this.onActionLaunch,
  });

  final PromoAnnouncement promo;
  final Uint8List? initialImageBytes;
  final Future<Uint8List?> Function()? loadImage;
  final Future<bool> Function()? onActionLaunch;

  @override
  State<PromoAnnouncementDialog> createState() =>
      _PromoAnnouncementDialogState();
}

class _PromoAnnouncementDialogState extends State<PromoAnnouncementDialog> {
  Uint8List? _imageBytes;
  bool _loadingImage = false;
  bool _imageFailed = false;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.initialImageBytes;
    if (_imageBytes == null &&
        widget.promo.hasImage &&
        widget.loadImage != null) {
      _loadingImage = true;
      unawaited(_fetchImage());
    }
  }

  Future<void> _fetchImage() async {
    try {
      final Uint8List? bytes = await widget.loadImage!.call();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _loadingImage = false;
        _imageFailed = bytes == null || bytes.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingImage = false;
        _imageFailed = true;
      });
    }
  }

  void _handleAction() {
    playUiClick(context);
    final Future<bool> Function() launcher = widget.onActionLaunch ??
        () => TelegramChannelPrompt.openActionUrl(widget.promo.buttonUrl);
    Navigator.of(context).pop(true);
    unawaited(launcher());
  }

  void _handleClose() {
    playUiClick(context);
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UmbrellaColors colors = context.colors;
    final PromoAnnouncement promo = widget.promo;
    final String titleText = Fa.num(
      promo.title.trim().isEmpty ? 'پیشنهاد ویژه آمبرلا' : promo.title.trim(),
    );
    final String bodyText = Fa.num(promo.body.trim());
    final String buttonText = Fa.num(promo.buttonText.trim());
    final bool hasAction = promo.buttonUrl.trim().isNotEmpty;
    final bool isTelegramTarget =
        promo.buttonUrl.toLowerCase().contains('t.me') ||
            promo.buttonUrl.toLowerCase().contains('telegram.me');

    return Dialog(
      key: const Key('promo_announcement_dialog'),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: colors.shadow,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space6,
        vertical: AppMetrics.space6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.space7),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppMetrics.telegramDialogWidth,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildMediaHeader(colors, theme),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppMetrics.space6,
                  AppMetrics.space5,
                  AppMetrics.space6,
                  AppMetrics.space2,
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      titleText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                      ),
                    ),
                    if (bodyText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppMetrics.space3),
                      Text(
                        bodyText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.65,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasAction)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppMetrics.space6,
                    AppMetrics.space4,
                    AppMetrics.space6,
                    AppMetrics.space2,
                  ),
                  child: FilledButton.icon(
                    key: const Key('promo_dialog_action_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(AppMetrics.space10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppMetrics.radiusButton,
                        ),
                      ),
                      textStyle: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: Icon(
                      isTelegramTarget
                          ? Icons.telegram
                          : Icons.open_in_new_rounded,
                      size: AppMetrics.iconLg,
                      color: colors.onPrimary,
                    ),
                    label: Text(buttonText.isEmpty ? 'مشاهده جزئیات' : buttonText),
                    onPressed: _handleAction,
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(
                  top: hasAction ? 0 : AppMetrics.space2,
                  bottom: AppMetrics.space3,
                ),
                child: Center(
                  child: TextButton(
                    key: const Key('promo_dialog_close_button'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: _handleClose,
                    child: const Text('بستن'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaHeader(UmbrellaColors colors, ThemeData theme) {
    final Uint8List? bytes = _imageBytes;
    if (bytes != null && bytes.isNotEmpty && !_imageFailed) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240, minHeight: 140),
        child: Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            Image.memory(
              bytes,
              key: const Key('promo_dialog_image'),
              width: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_imageFailed) {
                    setState(() => _imageFailed = true);
                  }
                });
                return _buildFallbackHeader(colors, theme);
              },
            ),
            PositionedDirectional(
              top: AppMetrics.space3,
              start: AppMetrics.space3,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.space3,
                  vertical: AppMetrics.space1,
                ),
                decoration: BoxDecoration(
                  color: colors.background.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
                  border: Border.all(
                    color: colors.onPrimary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.campaign_rounded,
                      size: AppMetrics.iconSm,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppMetrics.space1),
                    Text(
                      'اطلاعیه ویژه',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_loadingImage) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: TelegramChannelDialog.headerGradientFor(
              colors,
              theme.brightness,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: colors.onPrimary,
        ),
      );
    }
    return _buildFallbackHeader(colors, theme);
  }

  Widget _buildFallbackHeader(UmbrellaColors colors, ThemeData theme) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: TelegramChannelDialog.headerGradientFor(
            colors,
            theme.brightness,
          ),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.onPrimary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.onPrimary.withValues(alpha: 0.40),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.campaign_rounded,
              size: 28,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(height: AppMetrics.space2),
          Text(
            'اطلاعیه ویژه آمبرلا',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
