import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/safe_url_launcher.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import 'common.dart';

/// مدیریت زمان بندی و نمایش گفت و گوی اعلان پویا / دعوت به کانال رسمی تلگرام آمبرلا.
///
/// به صورت پویا از پنل ادمین ربات تلگرام قابل تنظیم است و در صورت عدم تغییر
/// یا آفلاین بودن، از اعلان پیش فرض دعوت به کانال رسمی با چرخه ۷ روزه استفاده می کند.
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
      final Map<String, dynamic> state = Map<String, dynamic>.from(
        target.readJson(StoreKeys.appAnnouncementState),
      );
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
    final Map<String, dynamic> state = Map<String, dynamic>.from(
      target.readJson(StoreKeys.appAnnouncementState),
    );
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

  /// باز کردن کانال رسمی تلگرام: ابتدا در اپلیکیشن تلگرام اندروید و در غیر
  /// این صورت در مرورگر پیش فرض سیستم.
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

  /// نمایش گفت و گوی اعلان/عضویت و ثبت هم زمان تاریخ نمایش.
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

/// گفت و گوی دعوت به کانال رسمی تلگرام / اعلان پویای آمبرلا با پالت رنگی اختصاصی.
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
