import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/subscription_controller.dart';
import '../../platform/services.dart';
import '../../state/toast_controller.dart';
import '../../data/subscription_diagnostics.dart';
import '../widgets/common.dart';

/// حساب کاربری: پروفایل، مصرف دقیق (همان اعدادی که پنل نشان می دهد) و وضعیت
/// اشتراک. کنترل محتوا به تنظیمات و مشخصات دستگاه به «دستگاه من» منتقل شده
/// است.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _refreshing = false;
  bool _panelFresh = false;
  bool _checkingLinks = false;
  List<EndpointCheck> _linkChecks = <EndpointCheck>[];

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

  /// بررسی هر هشت نشانی اشتراک پنل (خودکار، ساده، Base64، کلش متا، سینگ
  /// باکس، وایرگارد، آمنزیا، میرو) و نوشتن نتیجه در گزارش ها.
  Future<void> _checkEndpoints(AuthController auth, ToastController toasts) async {
    if (_checkingLinks) {
      return;
    }
    setState(() => _checkingLinks = true);
    final List<EndpointCheck> results =
        await SubscriptionDiagnostics().checkAll(
      subscriptionUrl: auth.account.subscriptionUrl,
      accountBase: auth.account.accountBase,
      uuid: auth.account.uuid,
    );
    final int working = results.where((EndpointCheck item) => item.ok).length;
    for (final EndpointCheck item in results) {
      AppLogger.instance.add(
        'بررسی اشتراک | ${item.line}',
        level: item.ok ? 'info' : 'warning',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _checkingLinks = false;
      _linkChecks = results;
    });
    toasts.success(
      'بررسی نشانی های اشتراک',
      '${Fa.num(working)} از ${Fa.num(results.length)} نشانی سرور داد.',
    );
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

  Future<void> _signOut(AuthController auth, ToastController toasts) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('خروج از حساب'),
        content: const Text('برای دریافت اشتراک باید دوباره وارد شوی. مطمئنی؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (sure != true) {
      return;
    }
    await auth.signOut();
    widget.onSignedOut();
    toasts.info('از حساب خارج شدی');
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fa.num(account.displayName),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fa.num(
                        account.phone.isNotEmpty
                            ? account.phone
                            : (account.uuid.isEmpty ? 'بدون شناسه' : account.uuid),
                      ),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Pill(
                label: account.healthy ? 'حساب فعال' : 'نیازمند بررسی',
                icon: account.healthy
                    ? Icons.verified_rounded
                    : Icons.error_outline_rounded,
                color: account.healthy ? colors.success : colors.danger,
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _refreshing
                    ? null
                    : () => _refreshFromServer(auth, subs, toasts),
                icon: _refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: const Text('به روز رسانی'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'مصرف ترافیک',
                        subtitle: _panelFresh
                            ? 'اعداد مستقیم از پنل خوانده می شوند.'
                            : 'منبع: سرور برنامه (پنل پاسخ نداد).',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Text(
                            Fa.num('${Fa.decimal(used, fraction: 2)}'),
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              Fa.num(
                                unlimited
                                    ? 'گیگابایت مصرف شده (نامحدود)'
                                    : 'از ${Fa.decimal(limit, fraction: 2)} گیگابایت',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: unlimited
                              ? 0
                              : (percent.clamp(0, 100) / 100).toDouble(),
                          minHeight: 12,
                          backgroundColor: colors.backgroundAlt,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            percent >= 90
                                ? colors.danger
                                : (percent >= 70 ? colors.warning : colors.success),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            Fa.num(unlimited
                                ? 'بدون سقف حجم'
                                : '${Fa.decimal(percent, fraction: 1)} درصد استفاده شده'),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colors.textSecondary),
                          ),
                          Text(
                            Fa.num(unlimited
                                ? 'باقی مانده: نامحدود'
                                : 'باقی مانده: ${Fa.gb(remaining)}'),
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
                      const SizedBox(height: 14),
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
                            : (account.daysLeft <= 3 && account.expiryDate != null
                                ? colors.warning
                                : colors.textPrimary),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.event_rounded,
                        label: 'تاریخ انقضا',
                        value: Fa.dateTime(account.expiryDate),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.play_circle_outline_rounded,
                        label: 'شروع سرویس',
                        value: Fa.dateTime(account.startDate),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.schedule_rounded,
                        label: 'آخرین اتصال حساب',
                        value: Fa.relative(account.lastOnline),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.category_rounded,
                        label: 'نوع سرویس',
                        value: Fa.num(account.planLabel),
                      ),
                      if (account.mode.isNotEmpty) ...<Widget>[
                        const Divider(height: 14),
                        InfoRow(
                          icon: Icons.tune_rounded,
                          label: 'حالت حساب',
                          value: Fa.num(account.mode),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Column(
                  children: <Widget>[
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(
                            title: 'اشتراک من',
                            subtitle: 'پنج قالب اشتراک، خودکار از سرور',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.dns_rounded,
                            label: 'مجموع سرورها',
                            value: Fa.num('${Fa.num(subs.personalNodeCount)} سرور'),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.check_circle_outline_rounded,
                            label: 'منابع سالم',
                            value: Fa.num(
                              '${Fa.num(subs.personalSources.where((SourceState s) => s.loaded).length)}'
                              ' از ${Fa.num(subs.personalSources.length)}',
                            ),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.schedule_rounded,
                            label: 'آخرین دریافت',
                            value: subs.personalCheckedAt == null
                                ? 'در انتظار'
                                : Fa.clock(subs.personalCheckedAt!),
                          ),
                          if (subs.needsLogin) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              'اشتراک اختصاصی فقط بعد از ورود به حساب در دسترس '
                              'است؛ دوباره وارد شو.',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.warning),
                            ),
                          ],
                          if (subs.personalErrors.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              Fa.num(subs.personalErrors.first),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.danger),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(
                            title: 'حساب',
                            subtitle: 'شناسه و ارتباط',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.badge_rounded,
                            label: 'شناسه حساب',
                            value: account.uuid.isEmpty ? 'نامشخص' : account.uuid,
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.phone_rounded,
                            label: 'شماره موبایل',
                            value: account.phone.isEmpty ? 'ثبت نشده' : account.phone,
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.send_rounded,
                            label: 'تلگرام',
                            value: account.telegramId.isEmpty
                                ? 'متصل نشده'
                                : account.telegramId,
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _checkingLinks
                                ? null
                                : () => _checkEndpoints(auth, toasts),
                            icon: _checkingLinks
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.fact_check_rounded, size: 18),
                            label: const Text('بررسی نشانی های اشتراک'),
                          ),
                          if (_linkChecks.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 8),
                            for (final EndpointCheck item in _linkChecks)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      item.ok
                                          ? Icons.check_circle_rounded
                                          : Icons.error_outline_rounded,
                                      size: 15,
                                      color: item.ok
                                          ? colors.success
                                          : colors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        Fa.num(item.line),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: item.ok
                                                  ? colors.textPrimary
                                                  : colors.textSecondary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: () => _loadPanel(false),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('خواندن دوباره از پنل'),
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () => _signOut(auth, toasts),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('خروج از حساب'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
