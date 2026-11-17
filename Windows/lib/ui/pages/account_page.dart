import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../widgets/common.dart';

/// صفحه «حساب من»: وضعیت اشتراک، حجم مصرفی، زمان باقی مانده و همگام سازی تلگرام.
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
        toasts.success('اطلاعات حساب به روز شد');
      } else {
        toasts.info('اطلاعات ذخیره شده سرور نمایش داده می شود');
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

  Future<void> _copy(ToastController toasts, String label, String value) async {
    if (value.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (!mounted) {
      return;
    }
    toasts.success('$label کپی شد');
  }

  /// باز کردن ربات رسمی حساب آمبرلا.
  Future<void> _openTelegramBot(ToastController toasts) async {
    final Uri uri = Uri.parse('https://t.me/UmbrellaVPN_BOT');
    try {
      final bool ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        toasts.error('مرورگر باز نشد', 'https://t.me/UmbrellaVPN_BOT');
      }
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
    final String name = account.displayName;
    final String trimmed = name.trim();
    final String initial =
        trimmed.isEmpty ? 'U' : String.fromCharCode(trimmed.runes.first);

    final String statusText = !account.enable
        ? 'مسدود شده'
        : (account.expired ? 'منقضی شده' : 'فعال');
    final Color statusTone =
        account.healthy ? colors.success : colors.danger;

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'حساب من',
            subtitle: 'حجم مصرفی، اعتبار زمانی و مشخصات کاربری شما',
            icon: Icons.person_rounded,
            actions: <Widget>[
              OutlinedButton.icon(
                onPressed: _refreshing
                    ? null
                    : () => _refreshFromServer(auth, subs, toasts),
                icon: _refreshing
                    ? const SizedBox(
                        width: AppMetrics.iconXs,
                        height: AppMetrics.iconXs,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: AppMetrics.iconSm),
                label: const Text('به روز رسانی'),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نوار هویتی یکدست حساب ────────────────────────────────────
          PageBanner(
            leading: Container(
              width: AppMetrics.iconBoxHero,
              height: AppMetrics.iconBoxHero,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.32),
                ),
              ),
              child: Text(
                initial,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.primary,
                    ),
              ),
            ),
            title: name,
            subtitle: account.phone.isNotEmpty
                ? 'سرویس ${account.planLabel} • شماره ${account.phone}'
                : 'سرویس ${account.planLabel}',
            badges: <Widget>[
              Pill(
                label: account.healthy ? 'حساب فعال' : 'نیازمند بررسی',
                icon: account.healthy
                    ? Icons.verified_rounded
                    : Icons.error_outline_rounded,
                color: statusTone,
                dense: true,
              ),
              if (account.telegramId.isNotEmpty)
                Pill(
                  label: 'متصل به تلگرام',
                  icon: Icons.send_rounded,
                  color: colors.info,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── ردیف اول: دو کارت هم اندازه مصرف ترافیک و زمان اشتراک ────
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
              if (constraints.maxWidth < AppMetrics.breakpointColumns) {
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
                    Expanded(child: usage),
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(child: days),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── ردیف دوم: دو کارت هم اندازه مشخصات حساب و ارتباط تلگرام ──
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget details = GlassCard(
                padding: AppMetrics.cardPadding,
                radius: AppMetrics.radiusXl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SectionHeader(
                      icon: Icons.badge_rounded,
                      title: 'مشخصات حساب و سرویس',
                      subtitle: 'اطلاعات کاربری و وضعیت بسته فعال',
                    ),
                    const Divider(height: AppMetrics.space5),
                    InfoRow(
                      icon: Icons.category_rounded,
                      label: 'نوع سرویس',
                      value: Fa.num(account.planLabel),
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.verified_user_rounded,
                      label: 'وضعیت سرویس',
                      value: statusText,
                      valueColor: statusTone,
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.phone_rounded,
                      label: 'شماره موبایل',
                      value: account.phone.isEmpty
                          ? 'ثبت نشده'
                          : Fa.num(account.phone),
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'شناسه حساب',
                      value: account.uuid.isEmpty ? 'نامشخص' : account.uuid,
                      ltr: account.uuid.isNotEmpty,
                      tooltip: true,
                      trailing: account.uuid.isEmpty
                          ? null
                          : IconAction(
                              icon: Icons.copy_rounded,
                              tooltip: 'کپی شناسه حساب',
                              size: AppMetrics.iconBoxSm,
                              onTap: () =>
                                  _copy(toasts, 'شناسه حساب', account.uuid),
                            ),
                    ),
                    if (account.mode.isNotEmpty) ...<Widget>[
                      const Divider(height: AppMetrics.space2),
                      InfoRow(
                        icon: Icons.tune_rounded,
                        label: 'حالت حساب',
                        value: Fa.num(account.mode),
                      ),
                    ],
                  ],
                ),
              );

              final Widget telegram = GlassCard(
                padding: AppMetrics.cardPadding,
                radius: AppMetrics.radiusXl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SectionHeader(
                      icon: Icons.send_rounded,
                      title: 'همگام سازی با تلگرام',
                      subtitle: 'مدیریت تمدید، اعلان ها و دستگاه ها در ربات رسمی',
                    ),
                    const Divider(height: AppMetrics.space5),
                    InfoRow(
                      icon: Icons.link_rounded,
                      label: 'وضعیت اتصال',
                      value: account.telegramId.isEmpty
                          ? 'متصل نشده'
                          : 'متصل و همگام',
                      valueColor: account.telegramId.isEmpty
                          ? colors.textSecondary
                          : colors.success,
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.alternate_email_rounded,
                      label: 'شناسه تلگرام',
                      value: account.telegramId.isEmpty
                          ? 'ثبت نشده'
                          : account.telegramId,
                      ltr: account.telegramId.isNotEmpty,
                    ),
                    const Divider(height: AppMetrics.space2),
                    const InfoRow(
                      icon: Icons.smart_toy_rounded,
                      label: 'ربات رسمی',
                      value: '@UmbrellaVPN_BOT',
                      ltr: true,
                    ),
                    const SizedBox(height: AppMetrics.space4),
                    _TelegramSyncButton(
                      account: account,
                      onOpen: () => _openTelegramBot(toasts),
                    ),
                  ],
                ),
              );

              if (constraints.maxWidth < AppMetrics.breakpointColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    details,
                    const SizedBox(height: AppMetrics.space4),
                    telegram,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: details),
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(child: telegram),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// کارت مصرف ترافیک: حلقه درصد، عدد خوانا، نوار پیشرفت و حجم باقی مانده.
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
    final Color tone = unlimited
        ? colors.success
        : (percent >= 90
            ? colors.danger
            : (percent >= 70 ? colors.warning : colors.success));
    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionHeader(
                icon: Icons.data_usage_rounded,
                title: 'مصرف ترافیک',
                subtitle: panelFresh
                    ? 'همگام با پنل کاربری'
                    : 'همگام با سرور آمبرلا',
                trailing: Pill(
                  label: unlimited
                      ? 'نامحدود'
                      : '${Fa.decimal(percent, fraction: 0)}٪ مصرف',
                  color: tone,
                  dense: true,
                ),
              ),
              const Divider(height: AppMetrics.space5),
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
                                    color: colors.textPrimary,
                                  ),
                            ),
                            const SizedBox(width: AppMetrics.space2),
                            Text(
                              Fa.num('گیگابایت'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppMetrics.space1),
                        Text(
                          Fa.num(
                            unlimited
                                ? 'بدون محدودیت حجم'
                                : 'از مجموع ${Fa.decimal(limit, fraction: 2)} گیگابایت',
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppMetrics.space5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                  child: LinearProgressIndicator(
                    value:
                        unlimited ? 0 : (percent.clamp(0, 100) / 100).toDouble(),
                    minHeight: AppMetrics.space2,
                    backgroundColor: colors.surfaceHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(tone),
                  ),
                ),
                const SizedBox(height: AppMetrics.space3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      Fa.num(
                        unlimited
                            ? 'ترافیک آزاد'
                            : '${Fa.decimal(percent, fraction: 1)}٪ استفاده شده',
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    final double value =
        unlimited ? 0 : (percent.clamp(0, 100) / 100).toDouble();
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
              strokeWidth: 8,
              backgroundColor: colors.surfaceHigh,
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

/// کارت زمان اشتراک: روزهای باقی مانده و تاریخ های کلیدی.
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
    final String pillLabel = !hasDate
        ? 'نامحدود'
        : (expired ? 'منقضی' : (soon ? 'رو به پایان' : 'معتبر'));

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.event_available_rounded,
            title: 'اعتبار زمانی اشتراک',
            subtitle: 'روزهای باقی مانده و زمان بندی سرویس',
            trailing: Pill(label: pillLabel, color: tone, dense: true),
          ),
          const Divider(height: AppMetrics.space5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                Fa.num(
                  hasDate ? (expired ? '0' : '${account.daysLeft}') : '∞',
                ),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                    ),
              ),
              const SizedBox(width: AppMetrics.space2),
              Text(
                Fa.num(
                  !hasDate
                      ? 'بدون تاریخ انقضا'
                      : (expired ? 'روز (منقضی شده)' : 'روز باقی مانده'),
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.event_rounded,
            label: 'تاریخ انقضا',
            value: Fa.dateTime(account.expiryDate),
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.play_circle_outline_rounded,
            label: 'تاریخ شروع',
            value: Fa.dateTime(account.startDate),
          ),
          const Divider(height: AppMetrics.space2),
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

/// دکمه مرتب و استاندارد همگام سازی حساب با ربات رسمی تلگرام.
class _TelegramSyncButton extends StatelessWidget {
  const _TelegramSyncButton({required this.account, required this.onOpen});

  final Account account;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool linked = account.telegramId.isNotEmpty;
    final Color tone = linked ? colors.success : colors.primary;
    return Material(
      color: tone.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: onOpen,
        child: Container(
          height: AppMetrics.controlHeightSmall,
          padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(color: tone.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                linked ? Icons.verified_rounded : Icons.send_rounded,
                size: AppMetrics.iconSm,
                color: tone,
              ),
              const SizedBox(width: AppMetrics.space2),
              Flexible(
                child: Text(
                  Fa.num(
                    linked
                        ? 'باز کردن ربات تلگرام (همگام شده)'
                        : 'اتصال و سینک حساب در تلگرام',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: tone,
                      ),
                ),
              ),
              const SizedBox(width: AppMetrics.space2),
              Icon(
                Icons.open_in_new_rounded,
                size: AppMetrics.iconXs,
                color: tone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
