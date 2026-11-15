import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/subscription_controller.dart';
import '../../platform/services.dart';
import '../../state/toast_controller.dart';
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

  /// باز کردن ربات تلگرام با شناسه همین حساب.
  ///
  /// ربات همان سرور و دیتابیس برنامه را دارد، پس با `?start=<uuid>` حساب
  /// ویندوز را می شناسد و سینک می کند. اگر شناسه نباشد، فقط ربات باز می شود.
  Future<void> _openTelegramBot(Account account, ToastController toasts) async {
    final String id = account.uuid.trim();
    final String url = id.isEmpty
        ? 'https://t.me/${AppConfig.botUsername}'
        : 'https://t.me/${AppConfig.botUsername}?start=$id';
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      toasts.error('نشانی ربات نامعتبر است');
      return;
    }
    try {
      final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        toasts.error('مرورگر باز نشد', 'دستی به آدرس t.me/${AppConfig.botUsername} بروید.');
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
                          // دکمه بررسی دستی نشانی ها و دکمه خواندن دوباره
                          // از پنل حذف شدند: کاربر آن ها را نمی خواست و همان
                          // کار را خواندن خودکار برنامه انجام می دهد.

                          const SizedBox(height: 14),
                          // ── سینک با تلگرام ─────────────────────────────
                          //
                          // یک دکمه که کاربر را به ربات می برد؛ ربات همان
                          // سرور، دیتابیس و حساب همین برنامه را دارد، پس
                          // با یک کلیک حساب ویندوز به تلگرام وصل می شود.
                          _TelegramSyncButton(
                            account: account,
                            onOpen: () => _openTelegramBot(account, toasts),
                          ),
                          const SizedBox(height: 8),
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
      borderRadius: BorderRadius.circular(14),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone.withValues(alpha: 0.42)),
        ),
        child: Row(
          children: <Widget>[
            IconSquare(
              icon: linked
                  ? Icons.verified_rounded
                  : Icons.send_rounded,
              color: tone,
              size: 34,
            ),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 2),
                  Text(
                    Fa.num(
                      linked
                          ? 'حساب و اشتراک شما در ربات به روز است.'
                          : 'با یک کلیک، حساب را به ربات آمبرلا وصل کنید.',
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 16, color: tone),
          ],
        ),
      ),
    );
  }
}
