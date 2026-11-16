import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../widgets/common.dart';
import '../widgets/live_clock.dart';

/// حساب کاربری: هویت، مصرف دقیق (همان اعدادی که پنل نشان می دهد) و وضعیت
/// اشتراک. کنترل محتوا در تنظیمات و مشخصات دستگاه در «دستگاه من» است.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _refreshing = false;
  bool _panelFresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPanel(true));
  }

  /// خواندن اعداد دقیق از پنل؛ اگر پنل جواب نداد، همان داده درگاه می ماند.
  Future<void> _loadPanel(bool silent) async {
    final AuthController auth = context.read<AuthController>();
    final bool ok = await auth.refreshFromPanel();
    if (!mounted) {
      return;
    }
    setState(() => _panelFresh = ok);
    if (!silent) {
      final ToastController toasts = context.read<ToastController>();
      if (ok) {
        toasts.success('اطلاعات پنل به روز شد');
      } else {
        toasts.info('پنل پاسخ نداد', 'همان اطلاعات سرور نمایش داده می شود.');
      }
    }
  }

  Future<void> _refreshFromServer(
    AuthController auth,
    SubscriptionController subs,
    ToastController toasts,
  ) async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    await auth.refreshAccount();
    final bool panel = await auth.refreshFromPanel();
    await subs.syncPersonal();
    if (!mounted) {
      return;
    }
    setState(() {
      _refreshing = false;
      _panelFresh = panel;
    });
    if (auth.error.isEmpty) {
      toasts.success('حساب و اشتراک به روز شد');
    } else {
      toasts.error('به روز رسانی ناموفق بود', auth.error);
    }
  }

  /// باز کردن ربات رسمی حساب آمبرلا.
  Future<void> _openTelegramBot(ToastController toasts) async {
    final Uri uri = Uri.parse('https://t.me/UmbrellaVPN_BOT');
    try {
      final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) toasts.error('مرورگر باز نشد', 'https://t.me/UmbrellaVPN_BOT');
    } on Exception {
      toasts.error('باز کردن تلگرام ناموفق بود');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final Account account = auth.account;
    final double used = account.currentUsageGb;
    final double limit = account.usageLimitGb;
    final bool unlimited = limit <= 0;
    final double remaining = account.remainingGb;
    final double percent = account.usagePercent;

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
            title: 'حساب من',
            subtitle: 'هویت، مصرف دقیق و زمان اشتراک شما.',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: AppMetrics.space4),
          _AccountHero(
            account: account,
            colors: colors,
            refreshing: _refreshing,
            onRefresh: () => _refreshFromServer(auth, subs, toasts),
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── مصرف و روزهای باقی مانده در یک نگاه ──────────────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget usage = _UsageCard(
                used: used,
                limit: limit,
                unlimited: unlimited,
                remaining: remaining,
                percent: percent,
                panelFresh: _panelFresh,
                colors: colors,
              );
              final Widget days = _DaysCard(account: account, colors: colors);
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    usage,
                    const SizedBox(height: AppMetrics.space4),
                    days,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 3, child: usage),
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(flex: 2, child: days),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── جزئیات حساب و ارتباط ──────────────────────────────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget details = GlassCard(
                padding: const EdgeInsets.all(AppMetrics.space5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionHeader(
                      title: 'جزئیات سرویس',
                      subtitle: 'نوع و حالت اشتراک',
                    ),
                    const SizedBox(height: AppMetrics.space3),
                    InfoRow(
                      icon: Icons.category_rounded,
                      label: 'نوع سرویس',
                      value: Fa.num(account.planLabel),
                    ),
                    const Divider(height: AppMetrics.space4),
                    InfoRow(
                      icon: Icons.event_available_rounded,
                      label: 'روزهای باقی مانده',
                      value: account.expiryDate == null
                          ? 'نامشخص'
                          : (account.expired
                              ? 'منقضی شده'
                              : Fa.num('${Fa.num(account.daysLeft)} روز')),
                      valueColor: account.expired
                          ? colors.danger
                          : (account.daysLeft <= 3 &&
                                  account.expiryDate != null
                              ? colors.warning
                              : colors.textPrimary),
                    ),
                    if (account.mode.isNotEmpty) ...<Widget>[
                      const Divider(height: AppMetrics.space4),
                      InfoRow(
                        icon: Icons.tune_rounded,
                        label: 'حالت حساب',
                        value: Fa.num(account.mode),
                      ),
                    ],
                  ],
                ),
              );
              final Widget identity = GlassCard(
                padding: const EdgeInsets.all(AppMetrics.space5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionHeader(
                      title: 'حساب و ارتباط',
                      subtitle: 'شناسه و راه های تماس',
                    ),
                    const SizedBox(height: AppMetrics.space3),
                    InfoRow(
                      icon: Icons.badge_rounded,
                      label: 'شناسه حساب',
                      value: account.uuid.isEmpty ? 'نامشخص' : account.uuid,
                    ),
                    const Divider(height: AppMetrics.space4),
                    InfoRow(
                      icon: Icons.phone_rounded,
                      label: 'شماره موبایل',
                      value: account.phone.isEmpty ? 'ثبت نشده' : account.phone,
                    ),
                    const Divider(height: AppMetrics.space4),
                    InfoRow(
                      icon: Icons.send_rounded,
                      label: 'تلگرام',
                      value: account.telegramId.isEmpty
                          ? 'متصل نشده'
                          : account.telegramId,
                      valueColor: account.telegramId.isEmpty
                          ? colors.textSecondary
                          : colors.success,
                    ),
                    const SizedBox(height: AppMetrics.space4),
                    _TelegramSyncButton(
                      account: account,
                      onOpen: () => _openTelegramBot(toasts),
                    ),
                  ],
                ),
              );
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    details,
                    const SizedBox(height: AppMetrics.space4),
                    identity,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 3, child: details),
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(flex: 2, child: identity),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppMetrics.space4),
          Center(
            child: LiveDateTimeLine(
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// هدر حساب: آواتار حرف اول، نام، شناسه و دکمه به روز رسانی.
class _AccountHero extends StatelessWidget {
  const _AccountHero({
    required this.account,
    required this.colors,
    required this.refreshing,
    required this.onRefresh,
  });

  final Account account;
  final UmbrellaColors colors;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final String name = account.displayName;
    final String trimmed = name.trim();
    final String initial =
        trimmed.isEmpty ? 'U' : String.fromCharCode(trimmed.runes.first);
    return GlassCard(
      padding: AppMetrics.pagePadding,
      radius: AppMetrics.radiusXl,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: <Color>[
          colors.primary.withValues(alpha: 0.16),
          colors.surface,
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 520;
          final Widget avatar = Container(
            width: AppMetrics.iconBoxHero,
            height: AppMetrics.iconBoxHero,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.16),
              border: Border.all(color: colors.primary.withValues(alpha: 0.45)),
            ),
            child: Text(
              initial,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colors.primary,
                  ),
            ),
          );
          final Widget text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fa.num(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppMetrics.space1),
              Text(
                Fa.num(
                  account.phone.isNotEmpty
                      ? account.phone
                      : (account.uuid.isEmpty ? 'بدون شناسه' : account.uuid),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],
          );
          final Widget actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Pill(
                label: account.healthy ? 'حساب فعال' : 'نیازمند بررسی',
                icon: account.healthy
                    ? Icons.verified_rounded
                    : Icons.error_outline_rounded,
                color: account.healthy ? colors.success : colors.danger,
                dense: true,
              ),
              const SizedBox(width: AppMetrics.space3),
              OutlinedButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: AppMetrics.iconXs,
                        height: AppMetrics.iconXs,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: AppMetrics.iconSm),
                label: const Text('به روز رسانی'),
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    avatar,
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: AppMetrics.space3),
                actions,
              ],
            );
          }
          return Row(
            children: <Widget>[
              avatar,
              const SizedBox(width: AppMetrics.space5),
              Expanded(child: text),
              actions,
            ],
          );
        },
      ),
    );
  }
}

/// کارت مصرف: حلقه درصد + نوار پیشرفت + باقی مانده.
class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.used,
    required this.limit,
    required this.unlimited,
    required this.remaining,
    required this.percent,
    required this.panelFresh,
    required this.colors,
  });

  final double used;
  final double limit;
  final bool unlimited;
  final double remaining;
  final double percent;
  final bool panelFresh;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final Color tone = percent >= 90
        ? colors.danger
        : (percent >= 70 ? colors.warning : colors.success);
    return GlassCard(
      padding: const EdgeInsets.all(AppMetrics.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'مصرف ترافیک',
            subtitle: panelFresh
                ? 'اعداد مستقیم از پنل خوانده می شوند.'
                : 'منبع: سرور برنامه (پنل پاسخ نداد).',
          ),
          const SizedBox(height: AppMetrics.space4),
          Row(
            children: <Widget>[
              _UsageRing(
                percent: percent,
                unlimited: unlimited,
                tone: tone,
                colors: colors,
              ),
              const SizedBox(width: AppMetrics.space5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          Fa.decimal(used, fraction: 2),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: tone,
                              ),
                        ),
                        const SizedBox(width: AppMetrics.space2),
                        Text(
                          Fa.num('گیگابایت'),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      Fa.num(
                        unlimited
                            ? 'اشتراک نامحدود'
                            : 'از ${Fa.decimal(limit, fraction: 2)} گیگابایت',
                      ),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
            child: LinearProgressIndicator(
              value: unlimited ? 0 : (percent.clamp(0, 100) / 100).toDouble(),
              minHeight: 10,
              backgroundColor: colors.backgroundAlt,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          const SizedBox(height: AppMetrics.space2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                Fa.num(
                  unlimited
                      ? 'بدون سقف حجم'
                      : '${Fa.decimal(percent, fraction: 1)} درصد استفاده شده',
                ),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              Text(
                Fa.num(
                  unlimited
                      ? 'باقی مانده: نامحدود'
                      : 'باقی مانده: ${Fa.gb(remaining)}',
                ),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// حلقه درصد مصرف؛ با نامحدود بودن، حلقه خالی و برچسب «∞» است.
class _UsageRing extends StatelessWidget {
  const _UsageRing({
    required this.percent,
    required this.unlimited,
    required this.tone,
    required this.colors,
  });

  final double percent;
  final bool unlimited;
  final Color tone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final double value = unlimited ? 0 : (percent.clamp(0, 100) / 100).toDouble();
    return SizedBox(
      width: AppMetrics.logoLg,
      height: AppMetrics.logoLg,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: AppMetrics.logoLg,
            height: AppMetrics.logoLg,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 9,
              backgroundColor: colors.backgroundAlt,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          Text(
            Fa.num(
              unlimited ? '∞' : '${Fa.decimal(percent, fraction: 0)}٪',
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone,
                ),
          ),
        ],
      ),
    );
  }
}

/// کارت روزهای باقی مانده: عدد بزرگ + تاریخ انقضا.
class _DaysCard extends StatelessWidget {
  const _DaysCard({required this.account, required this.colors});

  final Account account;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final bool hasDate = account.expiryDate != null;
    final bool expired = account.expired;
    final bool soon = hasDate && !expired && account.daysLeft <= 3;
    final Color tone =
        expired ? colors.danger : (soon ? colors.warning : colors.success);
    return GlassCard(
      padding: const EdgeInsets.all(AppMetrics.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(
            title: 'زمان اشتراک',
            subtitle: 'تا پایان سرویس چقدر مانده',
          ),
          const SizedBox(height: AppMetrics.space4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                Fa.num(
                  hasDate ? (expired ? '0' : '${account.daysLeft}') : '—',
                ),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                    ),
              ),
              const SizedBox(width: AppMetrics.space2),
              Text(
                Fa.num(expired ? 'منقضی شده' : 'روز باقی مانده'),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          InfoRow(
            icon: Icons.event_rounded,
            label: 'تاریخ انقضا',
            value: Fa.dateTime(account.expiryDate),
          ),
          const Divider(height: AppMetrics.space4),
          InfoRow(
            icon: Icons.play_circle_outline_rounded,
            label: 'شروع سرویس',
            value: Fa.dateTime(account.startDate),
          ),
          const Divider(height: AppMetrics.space4),
          InfoRow(
            icon: Icons.schedule_rounded,
            label: 'آخرین اتصال',
            value: Fa.relative(account.lastOnline),
          ),
        ],
      ),
    );
  }
}

/// دکمه «سینک با تلگرام»: حساب ویندوز را به ربات همان سرویس وصل می کند.
class _TelegramSyncButton extends StatelessWidget {
  const _TelegramSyncButton({required this.account, required this.onOpen});

  final Account account;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool linked = account.telegramId.isNotEmpty;
    final Color tone = linked ? colors.success : const Color(0xFF29A9EB);
    return InkWell(
      borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space4, vertical: AppMetrics.space3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          border: Border.all(color: tone.withValues(alpha: 0.42)),
        ),
        child: Row(
          children: <Widget>[
            IconSquare(
              icon: linked ? Icons.verified_rounded : Icons.send_rounded,
              color: tone,
              size: AppMetrics.iconBoxMd,
            ),
            const SizedBox(width: AppMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fa.num(linked ? 'به تلگرام سینک شده' : 'سینک با تلگرام'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: tone,
                        ),
                  ),
                  const SizedBox(height: AppMetrics.space1),
                  Text(
                    Fa.num(
                      linked
                          ? 'حساب و اشتراک همگام شده‌اند.\nhttps://t.me/UmbrellaVPN_BOT'
                          : 'با یک کلیک به ربات رسمی متصل شوید.\nhttps://t.me/UmbrellaVPN_BOT',
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: AppMetrics.iconSm, color: tone),
          ],
        ),
      ),
    );
  }
}
