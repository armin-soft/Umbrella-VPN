import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';

/// صفحه اختصاصی «حساب من»: پایش زنده حجم مصرفی، تقویم دقیق شمسی اشتراک،
/// مشخصات مالک حساب از وب سرویس نسخه ۲ پنل و همگام سازی تلگرام (کاملاً مجزا
/// از مشخصات سخت افزاری رایانه).
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _refreshing = false;
  bool _panelFresh = false;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPanel(true));
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPanel(bool silent) async {
    final AuthController auth = context.read<AuthController>();
    final bool ok = await auth.refreshFromPanel();
    if (!mounted) {
      return;
    }
    setState(() {
      _panelFresh = ok;
      _now = DateTime.now();
    });
    if (!silent) {
      final ToastController toasts = context.read<ToastController>();
      if (ok) {
        toasts.success('اطلاعات حساب از پنل کاربری به روز شد');
      } else {
        toasts.info('اطلاعات ذخیره شده حساب نمایش داده می شود');
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
      _now = DateTime.now();
    });
    if (auth.error.isEmpty) {
      toasts.success('اطلاعات حساب کاربری به روز شد');
    } else {
      toasts.error('به روز رسانی ناموفق بود', auth.error);
    }
  }

  Future<void> _copy(ToastController toasts, String label, String value) async {
    final String clean = value.trim();
    if (clean.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: clean));
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
        toasts.error('مرورگر باز نشد', 'ربات تلگرام آمبرلا');
      }
    } on Exception {
      toasts.error('باز کردن تلگرام ناموفق بود');
    }
  }

  static String _ownerNameFa(Account account) {
    final String raw = account.displayName.trim();
    if (raw.isEmpty || RegExp(r'[A-Za-z]').hasMatch(raw)) {
      return 'کاربر آمبرلا';
    }
    return Fa.num(raw);
  }

  static String _phoneWithOperatorFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'ثبت نشده';
    }
    final String formatted = Fa.phoneFa(clean);
    final MobileOperator op = IranPhone.operator(clean);
    if (op == MobileOperator.unknown) {
      return formatted;
    }
    return '$formatted (${op.label})';
  }

  static String _compactUuidFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'نامشخص';
    }
    final String digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) {
      return 'کد ${Fa.num(digits.substring(0, 4))}•••${Fa.num(digits.substring(digits.length - 4))}';
    }
    if (digits.isNotEmpty) {
      return 'کد ${Fa.num(digits)}';
    }
    return 'ثبت شده و آماده کپی';
  }

  static String _tunnelIpv4Fa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty || !RegExp(r'^[0-9.]+$').hasMatch(clean)) {
      return 'تخصیص خودکار';
    }
    return Fa.num(clean);
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;

    final Account account = auth.account;
    final DateTime tehranNow = Fa.toTehran(_now);
    final DateTime? expiry = account.effectiveExpiryDate;
    final bool expired = account.isExpiredAt(_now);
    final Duration remDuration = account.remainingDuration(_now);
    final int daysLeft = account.daysLeftAt(_now);
    final int daysElapsed = account.daysElapsedAt(_now);
    final bool soon = expiry != null && !expired && daysLeft <= 7;

    final double used = account.currentUsageGb;
    final double limit = account.usageLimitGb;
    final bool unlimited = account.unlimited;
    final double remaining = account.remainingGb;
    final double percent = account.usagePercent;
    final double daily = account.dailyAverageGb(_now);
    final bool onlineNow = account.isOnlineRecently(_now);

    final String name = _ownerNameFa(account);
    final String initial =
        name.isEmpty ? 'آ' : String.fromCharCode(name.runes.first);

    final Color statusTone = !account.enable || expired || account.quotaFinished
        ? colors.danger
        : (!account.isActive ? colors.warning : colors.success);
    final Color quotaTone = unlimited
        ? colors.success
        : (percent >= 90
            ? colors.danger
            : (percent >= 75 ? colors.warning : colors.success));
    final Color timeTone =
        expired ? colors.danger : (soon ? colors.warning : colors.success);

    final List<Widget> kpiCards = <Widget>[
      _AccountMetricTile(
        icon: Icons.data_usage_rounded,
        accent: quotaTone,
        label: 'حجم قابل استفاده',
        value: unlimited ? 'نامحدود' : Fa.gb(remaining),
        caption: unlimited
            ? 'مصرف کل: ${Fa.gb(used)}'
            : 'از مجموع ${Fa.grouped(limit)} گیگابایت',
      ),
      _AccountMetricTile(
        icon: Icons.event_available_rounded,
        accent: timeTone,
        label: 'اعتبار زمانی باقی مانده',
        value: expiry == null
            ? 'نامحدود'
            : (expired
                ? 'منقضی شده'
                : (daysLeft > 0
                    ? '${Fa.grouped(daysLeft)} روز'
                    : '${Fa.num(remDuration.inHours)} ساعت')),
        caption: expiry == null
            ? 'بدون محدودیت زمانی'
            : (expired
                ? 'پایان در ${Fa.tehranDate(expiry)}'
                : 'تا ${Fa.longDate(Fa.toTehran(expiry))}'),
      ),
      _AccountMetricTile(
        icon: Icons.trending_up_rounded,
        accent: colors.primary,
        label: 'میانگین مصرف روزانه',
        value: daily > 0
            ? '${Fa.decimal(daily, fraction: 2)} گیگابایت'
            : 'ابتدای دوره',
        caption: account.startDate == null
            ? account.modeLabelFa
            : 'طی ${Fa.grouped(daysElapsed)} روز سپری شده',
      ),
      _AccountMetricTile(
        icon: Icons.access_time_filled_rounded,
        accent: onlineNow ? colors.success : colors.info,
        label: 'آخرین فعالیت در پنل',
        value: account.lastOnline == null
            ? 'ثبت نشده'
            : (onlineNow
                ? 'آنلاین (همین حالا)'
                : Fa.relative(account.lastOnline, now: _now)),
        caption: account.lastOnline == null
            ? 'در انتظار همگام سازی'
            : '${Fa.tehranDate(account.lastOnline)} • ساعت ${Fa.tehranClock(account.lastOnline, seconds: false)}',
      ),
    ];

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'حساب من',
            subtitle:
                'پایش زنده حجم مصرفی، تقویم دقیق شمسی سرویس، مشخصات کاربری و تلگرام',
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
                label: Text(_refreshing ? 'در حال دریافت...' : 'به روز رسانی'),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نوار هویت کاربری ───────────────────────────────────────────
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
            subtitle: account.effectivePhone.isNotEmpty
                ? '${account.packageDurationLabel}  •  شماره ${_phoneWithOperatorFa(account.effectivePhone)}'
                : 'سرویس ${account.planLabel}',
            badges: <Widget>[
              Pill(
                label: account.statusLabelFa,
                icon: account.healthy
                    ? Icons.verified_rounded
                    : Icons.error_outline_rounded,
                color: statusTone,
                dense: true,
              ),
              if (onlineNow)
                Pill(
                  label: 'آنلاین در پنل',
                  icon: Icons.circle,
                  color: colors.success,
                  dense: true,
                ),
              if (account.telegramId.isNotEmpty)
                Pill(
                  label: 'متصل به تلگرام',
                  icon: Icons.send_rounded,
                  color: colors.info,
                  dense: true,
                ),
              if (account.panelId > 0)
                Pill(
                  label: 'کد کاربری ${Fa.grouped(account.panelId)}',
                  icon: Icons.tag_rounded,
                  color: colors.primary,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── طرح های هدیه همگام با ربات (اشتراک رایگان و نوروزی) ─────────
          if (auth.offers.hasVisibleOffer) ...<Widget>[
            _GiftPlansCard(
              offers: auth.offers,
              busy: auth.claimingOffer,
              activePlanType: auth.claimingPlanType,
              onClaim: (String planType) async {
                final String? message =
                    await auth.claimSubscriptionOffer(planType);
                if (!context.mounted) {
                  return;
                }
                if (message != null) {
                  toasts.success(message);
                } else if (auth.error.isNotEmpty) {
                  toasts.error('فعال سازی انجام نشد', auth.error);
                }
              },
            ),
            const SizedBox(height: AppMetrics.space4),
          ],

          // ── چهار کارت شاخص کلیدی حساب کاربری ──────────────────────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth >= AppMetrics.breakpointColumns) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: kpiCards[0]),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(child: kpiCards[1]),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(child: kpiCards[2]),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(child: kpiCards[3]),
                    ],
                  ),
                );
              }
              if (constraints.maxWidth >= AppMetrics.breakpointCompact) {
                return Column(
                  children: <Widget>[
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: kpiCards[0]),
                          const SizedBox(width: AppMetrics.space3),
                          Expanded(child: kpiCards[1]),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppMetrics.space3),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: kpiCards[2]),
                          const SizedBox(width: AppMetrics.space3),
                          Expanded(child: kpiCards[3]),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  kpiCards[0],
                  const SizedBox(height: AppMetrics.space3),
                  kpiCards[1],
                  const SizedBox(height: AppMetrics.space3),
                  kpiCards[2],
                  const SizedBox(height: AppMetrics.space3),
                  kpiCards[3],
                ],
              );
            },
          ),
          const SizedBox(height: AppMetrics.space5),

          // ── ردیف اول: تحلیل مصرف ترافیک + تقویم دقیق شمسی سرویس ────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget usage = _UsageCard(
                account: account,
                used: used,
                limit: limit,
                unlimited: unlimited,
                remaining: remaining,
                percent: percent,
                panelFresh: _panelFresh,
                tone: quotaTone,
                statusTone: statusTone,
                colors: colors,
              );
              final Widget days = _DaysCard(
                account: account,
                now: _now,
                tehranNow: tehranNow,
                tone: timeTone,
                colors: colors,
              );
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
                    const SizedBox(width: AppMetrics.space5),
                    Expanded(child: days),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppMetrics.space5),

          // ── ردیف دوم: مشخصات کاربری + همگام سازی با ربات تلگرام ────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget details = GlassCard(
                padding: AppMetrics.cardPadding,
                radius: AppMetrics.radiusXl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SectionHeader(
                      icon: Icons.badge_rounded,
                      title: 'مشخصات حساب و سرویس',
                      subtitle: 'اطلاعات ثبت شده کاربر در پنل کاربری آمبرلا',
                      trailing: Pill(
                        label: 'زبان ${account.langLabelFa}',
                        color: colors.info,
                        dense: true,
                      ),
                    ),
                    const Divider(height: AppMetrics.space5),
                    InfoRow(
                      icon: Icons.person_rounded,
                      label: 'نام صاحب حساب',
                      value: name,
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.phone_rounded,
                      label: 'شماره موبایل',
                      value: _phoneWithOperatorFa(account.effectivePhone),
                      trailing: account.effectivePhone.isEmpty
                          ? null
                          : IconAction(
                              icon: Icons.copy_rounded,
                              tooltip: 'کپی شماره موبایل',
                              size: AppMetrics.iconBoxSm,
                              onTap: () => _copy(
                                toasts,
                                'شماره موبایل',
                                account.effectivePhone,
                              ),
                            ),
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.category_rounded,
                      label: 'نوع بسته فعال',
                      value: account.packageDurationLabel,
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'شناسه یکتای حساب',
                      value: _compactUuidFa(account.uuid),
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
                    if (account.wgIpv4.isNotEmpty) ...<Widget>[
                      const Divider(height: AppMetrics.space2),
                      InfoRow(
                        icon: Icons.hub_rounded,
                        label: 'نشانی اختصاصی تونل استاندارد',
                        value: _tunnelIpv4Fa(account.wgIpv4),
                        trailing: IconAction(
                          icon: Icons.copy_rounded,
                          tooltip: 'کپی نشانی تونل استاندارد',
                          size: AppMetrics.iconBoxSm,
                          onTap: () => _copy(
                            toasts,
                            'نشانی تونل استاندارد',
                            account.wgIpv4,
                          ),
                        ),
                      ),
                    ],
                    if (account.awgIpv4.isNotEmpty) ...<Widget>[
                      const Divider(height: AppMetrics.space2),
                      InfoRow(
                        icon: Icons.auto_fix_high_rounded,
                        label: 'نشانی اختصاصی تونل پیشرفته',
                        value: _tunnelIpv4Fa(account.awgIpv4),
                        trailing: IconAction(
                          icon: Icons.copy_rounded,
                          tooltip: 'کپی نشانی تونل پیشرفته',
                          size: AppMetrics.iconBoxSm,
                          onTap: () => _copy(
                            toasts,
                            'نشانی تونل پیشرفته',
                            account.awgIpv4,
                          ),
                        ),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SectionHeader(
                          icon: Icons.send_rounded,
                          title: 'همگام سازی با تلگرام',
                          subtitle:
                              'مدیریت تمدید، اعلان ها و دستگاه های مجاز در ربات رسمی',
                        ),
                        const Divider(height: AppMetrics.space5),
                        InfoRow(
                          icon: Icons.link_rounded,
                          label: 'وضعیت اتصال به تلگرام',
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
                          label: 'شناسه عددی تلگرام',
                          value: account.telegramId.isEmpty
                              ? 'ثبت نشده'
                              : Fa.num(account.telegramId),
                          trailing: account.telegramId.isEmpty
                              ? null
                              : IconAction(
                                  icon: Icons.copy_rounded,
                                  tooltip: 'کپی شناسه تلگرام',
                                  size: AppMetrics.iconBoxSm,
                                  onTap: () => _copy(
                                    toasts,
                                    'شناسه تلگرام',
                                    account.telegramId,
                                  ),
                                ),
                        ),
                        if (account.panelId > 0) ...<Widget>[
                          const Divider(height: AppMetrics.space2),
                          InfoRow(
                            icon: Icons.tag_rounded,
                            label: 'شماره کاربری در پنل',
                            value: 'کاربر شماره ${Fa.grouped(account.panelId)}',
                          ),
                        ],
                        const Divider(height: AppMetrics.space2),
                        InfoRow(
                          icon: Icons.smart_toy_rounded,
                          label: 'ربات رسمی آمبرلا',
                          value: 'ربات تلگرام آمبرلا',
                          trailing: IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی نشانی ربات تلگرام',
                            size: AppMetrics.iconBoxSm,
                            onTap: () => _copy(
                              toasts,
                              'نشانی ربات تلگرام',
                              'https://t.me/UmbrellaVPN_BOT',
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: AppMetrics.space4),
                      child: _TelegramSyncButton(
                        account: account,
                        onOpen: () => _openTelegramBot(toasts),
                      ),
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
                    const SizedBox(width: AppMetrics.space5),
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

/// کارت شاخص کلیدی ویژه حساب کاربری.
class _AccountMetricTile extends StatelessWidget {
  const _AccountMetricTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return GlassCard(
      padding: const EdgeInsets.all(AppMetrics.space4),
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: icon,
                color: accent,
                size: AppMetrics.iconBoxMd,
                radius: AppMetrics.radiusMd,
              ),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppMetrics.space1),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// کارت مصرف ترافیک: حلقه درصد، حجم مصرفی و باقی مانده، الگوی بازنشانی و آخرین بازنشانی.
class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.account,
    required this.used,
    required this.limit,
    required this.unlimited,
    required this.remaining,
    required this.percent,
    required this.panelFresh,
    required this.tone,
    required this.statusTone,
    required this.colors,
  });

  final Account account;
  final double used;
  final double limit;
  final bool unlimited;
  final double remaining;
  final double percent;
  final bool panelFresh;
  final Color tone;
  final Color statusTone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.donut_large_rounded,
            title: 'مصرف ترافیک',
            subtitle: panelFresh
                ? 'آمار زنده و مستقیم از پنل کاربری'
                : 'آخرین آمار ثبت شده برای حساب شما',
            trailing: Pill(
              label: unlimited
                  ? 'نامحدود'
                  : '${Fa.decimal(percent, fraction: 1)}٪ مصرف',
              color: tone,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          Row(
            children: <Widget>[
              _PercentRing(
                ratio: unlimited ? 1 : (percent.clamp(0, 100) / 100),
                label: unlimited
                    ? 'آزاد'
                    : '${Fa.decimal(percent, fraction: 0)}٪',
                tone: tone,
                colors: colors,
              ),
              const SizedBox(width: AppMetrics.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${Fa.decimal(used, fraction: 2)} گیگابایت',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      unlimited
                          ? 'بسته بدون محدودیت حجم'
                          : 'مصرف شده از مجموع ${Fa.grouped(limit)} گیگابایت',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                    if (!unlimited) ...<Widget>[
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        'باقی مانده: ${Fa.gb(remaining)} (${Fa.decimal(account.remainingPercent, fraction: 1)} درصد)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            child: LinearProgressIndicator(
              value: unlimited ? 0 : (percent.clamp(0, 100) / 100),
              minHeight: AppMetrics.space2,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.autorenew_rounded,
            label: 'الگوی بازنشانی حجم',
            value: account.modeLabelFa,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.history_rounded,
            label: 'آخرین بازنشانی ترافیک',
            value: account.lastResetTime == null
                ? 'بازنشانی نشده'
                : Fa.tehranFullDateTime(account.lastResetTime, seconds: false),
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.verified_user_rounded,
            label: 'وضعیت مجوز حساب',
            value: account.statusLabelFa,
            valueColor: statusTone,
          ),
        ],
      ),
    );
  }
}

/// کارت تقویم دقیق هجری شمسی و زمان سنج زنده اعتبار سرویس.
class _DaysCard extends StatelessWidget {
  const _DaysCard({
    required this.account,
    required this.now,
    required this.tehranNow,
    required this.tone,
    required this.colors,
  });

  final Account account;
  final DateTime now;
  final DateTime tehranNow;
  final Color tone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final DateTime? start = account.startDate;
    final DateTime? expiry = account.effectiveExpiryDate;
    final bool hasDate = expiry != null;
    final bool expired = account.isExpiredAt(now);
    final Duration remaining = account.remainingDuration(now);
    final Duration elapsed = account.elapsedDuration(now);
    final double remPct = account.timeRemainingPercent(now);

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.calendar_month_rounded,
            title: 'تقویم شمسی و اعتبار زمانی',
            subtitle: 'محاسبه دقیق تاریخ هجری شمسی به وقت رسمی ایران',
            trailing: Pill(
              label: hasDate
                  ? (expired ? 'منقضی' : account.packageDurationLabel)
                  : 'نامحدود',
              color: tone,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          Row(
            children: <Widget>[
              _PercentRing(
                ratio: hasDate ? (remPct.clamp(0, 100) / 100) : 1,
                label: hasDate
                    ? '${Fa.decimal(remPct, fraction: 0)}٪'
                    : 'دائمی',
                tone: tone,
                colors: colors,
              ),
              const SizedBox(width: AppMetrics.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      !hasDate
                          ? 'بدون تاریخ انقضا'
                          : (expired
                              ? 'اعتبار زمانی پایان یافته'
                              : Fa.spanFa(remaining)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      start == null
                          ? 'تاریخ شروع پس از همگام سازی نمایش داده می شود'
                          : 'سپری شده از شروع: ${Fa.spanFa(elapsed, includeMinutes: false)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                    if (hasDate && !expired) ...<Widget>[
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        '${Fa.decimal(remPct, fraction: 1)} درصد از دوره سرویس باقی مانده',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            child: LinearProgressIndicator(
              value: hasDate ? (remPct.clamp(0, 100) / 100) : 1,
              minHeight: AppMetrics.space2,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.play_circle_outline_rounded,
            label: 'تاریخ شروع بسته',
            value: start == null
                ? 'ثبت نشده'
                : '${Fa.tehranFullDate(start)} (${Fa.tehranDate(start)})',
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.event_rounded,
            label: 'تاریخ پایان اعتبار',
            value: expiry == null
                ? 'نامحدود'
                : '${Fa.tehranFullDate(expiry)} (${Fa.tehranDate(expiry)})',
            valueColor: expired ? colors.danger : colors.textPrimary,
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.schedule_rounded,
            label: 'آخرین حضور آنلاین',
            value: account.lastOnline == null
                ? 'ثبت نشده'
                : Fa.tehranFullDateTime(account.lastOnline),
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.today_rounded,
            label: 'تقویم و ساعت رسمی ایران',
            value: '${Fa.fullDate(tehranNow)} • ساعت ${Fa.clock(tehranNow)}',
            valueColor: colors.primary,
            tooltip: true,
          ),
        ],
      ),
    );
  }
}

class _PercentRing extends StatelessWidget {
  const _PercentRing({
    required this.ratio,
    required this.label,
    required this.tone,
    required this.colors,
  });

  final double ratio;
  final String label;
  final Color tone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppMetrics.logoMd,
      height: AppMetrics.logoMd,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: AppMetrics.logoMd,
            height: AppMetrics.logoMd,
            child: CircularProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              strokeWidth: 6,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: tone,
                ),
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
                  linked
                      ? 'باز کردن ربات تلگرام (همگام شده)'
                      : 'اتصال و سینک حساب در تلگرام',
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

/// کارت فعال سازی اشتراک رایگان (یک بار مصرف) و اشتراک نوروزی (هنگام فعال بودن
/// منوی نوروزی در ربات تلگرام).
class _GiftPlansCard extends StatelessWidget {
  const _GiftPlansCard({
    required this.offers,
    required this.busy,
    required this.activePlanType,
    required this.onClaim,
  });

  final SubscriptionOffers offers;
  final bool busy;
  final String activePlanType;
  final Future<void> Function(String planType) onClaim;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final List<Widget> tiles = <Widget>[
      if (offers.showFree)
        _GiftOfferTile(
          icon: Icons.card_giftcard_rounded,
          accent: colors.primary,
          title: 'اشتراک رایگان',
          badge: 'هدیه اول',
          spec:
              '${Fa.num(offers.freeGb)} گیگابایت ترافیک  •  ${Fa.num(offers.freeDays)} روز اعتبار',
          note:
              'یک بار برای شروع آشنایی با سرویس قابل دریافت است و پس از فعال سازی بسته می شود.',
          buttonLabel: 'دریافت اشتراک رایگان',
          loading: busy && activePlanType == 'free',
          disabled: busy,
          onTap: () => onClaim('free'),
        ),
      if (offers.showNowruz)
        _GiftOfferTile(
          icon: Icons.local_florist_rounded,
          accent: colors.success,
          title: 'اشتراک نوروزی',
          badge: 'ویژه نوروز',
          spec:
              '${Fa.num(offers.nowruzGb)} گیگابایت ترافیک  •  ${Fa.num(offers.nowruzDays)} روز اعتبار',
          note:
              'هدیه مناسبتی نوروز همگام با ربات تلگرام؛ با یک کلیک روی همین حساب فعال می شود.',
          buttonLabel: 'دریافت اشتراک نوروزی',
          loading: busy && activePlanType == 'nowruz',
          disabled: busy,
          onTap: () => onClaim('nowruz'),
        ),
    ];

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      borderColor: colors.primary.withValues(alpha: 0.34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.redeem_rounded,
            title: 'طرح های هدیه قابل فعال سازی',
            subtitle:
                'همگام با ربات تلگرام؛ در صورت فعال سازی بی درنگ روی سرورهای شما اعمال می شود',
            trailing: Pill(
              label: '${Fa.num(tiles.length)} هدیه آماده',
              color: colors.success,
              icon: Icons.auto_awesome_rounded,
              dense: true,
            ),
          ),
          const SizedBox(height: AppMetrics.space4),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (tiles.length == 2 &&
                  constraints.maxWidth >= AppMetrics.breakpointCompact) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: tiles[0]),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(child: tiles[1]),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < tiles.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: AppMetrics.space3),
                    tiles[i],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GiftOfferTile extends StatelessWidget {
  const _GiftOfferTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.badge,
    required this.spec,
    required this.note,
    required this.buttonLabel,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String badge;
  final String spec;
  final String note;
  final String buttonLabel;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppMetrics.space4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: icon,
                color: accent,
                size: AppMetrics.iconBoxMd,
                radius: AppMetrics.radiusMd,
              ),
              const SizedBox(width: AppMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      spec,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              Pill(label: badge, color: accent, dense: true),
            ],
          ),
          const SizedBox(height: AppMetrics.space3),
          Text(
            note,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.6,
                ),
          ),
          const SizedBox(height: AppMetrics.space4),
          GradientButton(
            label: loading ? 'در حال فعال سازی...' : buttonLabel,
            icon: Icons.bolt_rounded,
            loading: loading,
            height: AppMetrics.controlHeightSmall,
            onPressed: disabled ? null : onTap,
          ),
        ],
      ),
    );
  }
}
