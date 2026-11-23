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

enum _AccountSection { summary, wallet, subscription, profile }

extension _AccountSectionX on _AccountSection {
  String get title => switch (this) {
        _AccountSection.summary => 'خلاصه',
        _AccountSection.wallet => 'کیف پول',
        _AccountSection.subscription => 'اشتراک',
        _AccountSection.profile => 'مشخصات',
      };

  String get detail => switch (this) {
        _AccountSection.summary => 'حجم، اعتبار و وضعیت اتصال',
        _AccountSection.wallet => 'موجودی و پرداخت های امن',
        _AccountSection.subscription => 'وضعیت و تمدید سرویس',
        _AccountSection.profile => 'اطلاعات حساب کاربری',
      };

  IconData get icon => switch (this) {
        _AccountSection.summary => Icons.dashboard_rounded,
        _AccountSection.wallet => Icons.account_balance_wallet_rounded,
        _AccountSection.subscription => Icons.workspace_premium_rounded,
        _AccountSection.profile => Icons.badge_rounded,
      };
}

/// صفحه اختصاصی «حساب من»: پایش زنده حجم مصرفی، تقویم دقیق شمسی اشتراک،
/// مشخصات مالک حساب از وب سرویس نسخه ۲ پنل و همگام سازی تلگرام (کاملاً مجزا
/// از مشخصات سخت افزاری رایانه).
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _syncInFlight = false;
  bool _accountFresh = false;
  bool _wasTabActive = false;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _autoSyncTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      unawaited(_autoSync());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool active = TickerMode.of(context);
    if (active && !_wasTabActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_autoSync());
        }
      });
    }
    _wasTabActive = active;
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _autoSync() async {
    if (_syncInFlight || !mounted) {
      return;
    }
    final AuthController auth = context.read<AuthController>();
    final SubscriptionController subs = context.read<SubscriptionController>();
    if (!auth.signedIn) {
      return;
    }
    _syncInFlight = true;
    try {
      final bool accountFresh = await auth.refreshAccount(silent: true);
      await auth.refreshBotLinkStatus();
      if (auth.botLinked == true) {
        await auth.refreshWallet(silent: true);
        await auth.loadSubscriptionPlans();
      }
      await subs.syncPersonal();
      if (!mounted) {
        return;
      }
      setState(() {
        _accountFresh = accountFresh;
        _now = DateTime.now();
      });
    } catch (_) {
      // به روز رسانی پس زمینه کاملاً خودکار و بی صداست.
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> _purchasePlan(
    AuthController auth,
    ToastController toasts,
    SubscriptionPlan plan, {
    int? customDays, double? customGb,
  }) async {
    if (auth.botLinked != true) {
      toasts.info(
        'اتصال ربات لازم است',
        'برای خرید یا تمدید، ابتدا حساب را به ربات تلگرام پیوند دهید.',
      );
      return;
    }
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('خرید یا تمدید اشتراک'),
            content: Text(
              'پلن ${Fa.num(plan.name)} به مدت ${Fa.num(plan.days)} روز با قیمت '
              '${Fa.num(plan.price)} تومان انتخاب شده است.'
              '${auth.botLinked == true ? ' موجودی کیف پول مشترک شما ${Fa.num(auth.walletBalance)} تومان است.' : ''} '
              'ادامه می دهید؟',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: withUiClick(
                  dialogContext,
                  () => Navigator.pop(dialogContext, false),
                ),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: withUiClick(
                  dialogContext,
                  () => Navigator.pop(dialogContext, true),
                ),
                child: const Text('ادامه'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final result = await auth.purchaseSubscriptionPlan(plan.month, days: customDays, gb: customGb, quotedPrice: plan.price);
    if (!mounted) return;
    if (result == null) {
      if (auth.error.isNotEmpty) toasts.error('خرید انجام نشد', auth.error);
      return;
    }
    if (result.status == 'activated') {
      toasts.success(result.message.isNotEmpty ? result.message : 'اشتراک فعال شد.');
      return;
    }
    if (result.status == 'payment_required' && result.checkoutUrl.isNotEmpty) {
      final Uri? url = Uri.tryParse(result.checkoutUrl);
      final bool opened = url != null &&
          await launchUrl(url, mode: LaunchMode.externalApplication);
      if (opened) {
        toasts.info(
          'درگاه پرداخت باز شد',
          '${result.message} پس از پرداخت موفق، اشتراک از مسیر تایید ربات فعال می شود. برای دیدن نتیجه، تازه سازی را بزنید.',
        );
      } else {
        toasts.error('درگاه باز نشد', 'لطفاً دوباره تلاش کنید.');
      }
      return;
    }
    toasts.error('خرید انجام نشد', 'پاسخ نامعتبر از درگاه دریافت شد.');
  }

  Future<void> _purchaseCustomPlan(AuthController auth, ToastController toasts) async {
    if (auth.botLinked != true) {
      toasts.info(
        'اتصال ربات لازم است',
        'برای خرید اشتراک دلخواه، ابتدا حساب را به ربات تلگرام پیوند دهید.',
      );
      return;
    }
    final CustomSubscriptionTerms? terms = auth.customSubscriptionTerms;
    if (terms == null || !terms.available) return;
    final TextEditingController days =
        TextEditingController(text: Fa.num(terms.minDays));
    final TextEditingController gb = TextEditingController(
      text: Fa.num(terms.minGb).replaceAll('.', '٫'),
    );
    final selection = await showDialog<List<num>>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter update) {
          final int? dayValue = int.tryParse(Fa.toEn(days.text).trim());
          final double? gbValue = double.tryParse(Fa.toEn(gb.text).trim()
              .replaceAll('٫', '.').replaceAll(',', '.'));
          final bool valid = dayValue != null && dayValue >= terms.minDays &&
              dayValue <= terms.maxDays && gbValue != null && gbValue.isFinite &&
              gbValue >= terms.minGb && gbValue <= terms.maxGb &&
              terms.priceForDays(dayValue) > 0;
          return AlertDialog(
            title: const Text('اشتراک دلخواه'),
            content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('مدت مجاز: ${Fa.num(terms.minDays)} تا ${Fa.num(terms.maxDays)} روز'),
                TextField(controller: days, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'مدت (روز)'),
                  onChanged: (_) => update(() {})),
                const SizedBox(height: AppMetrics.space3),
                Text('حجم مجاز: ${Fa.num(terms.minGb)} تا ${Fa.num(terms.maxGb)} گیگابایت'),
                TextField(controller: gb, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'حجم (گیگابایت)'),
                  onChanged: (_) => update(() {})),
                const SizedBox(height: AppMetrics.space4),
                Text(valid ? 'قیمت تقریبی: ${Fa.num(terms.priceForDays(dayValue))} تومان'
                    : 'مدت و حجم را در محدوده مجاز وارد کنید.'),
                const Text('حجم هزینه جداگانه ندارد و مانند ربات به نزدیک ترین گیگابایت گرد می شود؛ قیمت نهایی توسط سرور محاسبه می شود.'),
              ],
            )),
            actions: <Widget>[
              TextButton(
                onPressed: withUiClick(
                  dialogContext,
                  () => Navigator.pop(dialogContext),
                ),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: valid
                    ? withUiClick(
                        dialogContext,
                        () => Navigator.pop(
                          dialogContext,
                          <num>[dayValue, gbValue],
                        ),
                      )
                    : null,
                child: const Text('ادامه'),
              ),
            ],
          );
        },
      ),
    );
    days.dispose();
    gb.dispose();
    if (selection == null || !mounted) return;
    await _purchasePlan(auth, toasts, SubscriptionPlan(month: '',
      name: 'دلخواه ${Fa.num(selection[1])} گیگابایت', days: selection[0].toInt(),
      price: terms.priceForDays(selection[0].toInt())),
      customDays: selection[0].toInt(), customGb: selection[1].toDouble());
  }

  Future<void> _refreshWallet(AuthController auth, ToastController toasts,
      {bool verify = false}) async {
    if (auth.botLinked != true) {
      toasts.info('اتصال ربات لازم است', 'ابتدا حساب را به ربات تلگرام پیوند دهید.');
      return;
    }
    final bool ok = await auth.refreshWallet(verify: verify);
    if (!mounted) return;
    if (!ok) {
      toasts.error('دریافت وضعیت کیف پول ناموفق بود', auth.error);
    } else if (verify && auth.walletPaymentPending) {
      toasts.info('پرداخت هنوز در حال بررسی است',
          'اگر مبلغ کسر شده دوباره پرداخت نکنید؛ دوباره بررسی کنید یا از پشتیبانی پیگیری کنید.');
    } else {
      toasts.success('موجودی و وضعیت کیف پول تازه شد.');
    }
  }

  Future<void> _cancelWalletPayment(AuthController auth, ToastController toasts) async {
    if (auth.walletPendingId.isEmpty) {
      final bool refreshed = await auth.refreshWallet();
      if (!mounted) return;
      if (!refreshed || !auth.walletPaymentPending || auth.walletPendingId.isEmpty) {
        toasts.error('لغو سفارش انجام نشد', !refreshed && auth.error.isNotEmpty
            ? auth.error
            : !auth.walletPaymentPending
                ? 'سفارش فعالی وجود ندارد؛ وضعیت کیف پول را بررسی کنید.'
                : 'شناسه امن سفارش از سرور دریافت نشد؛ سرویس پرداخت سرور باید به روز شود.');
        return;
      }
    }
    final String expectedPendingId = auth.walletPendingId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('لغو سفارش پرداخت؟'),
        content: const Text('لینک درگاه ممکن است همچنان قابل پرداخت باشد. اگر پرداخت دیرتر تأیید شود، مبلغ بدون کارمزد به کیف پول شما اضافه می شود و اشتراک لغوشده فعال نمی شود. اگر وجه کسر شده، دوباره پرداخت نکنید.'),
        actions: <Widget>[
          TextButton(
            onPressed: withUiClick(
              context,
              () => Navigator.pop(context, false),
            ),
            child: const Text('بازگشت'),
          ),
          FilledButton(
            onPressed: withUiClick(
              context,
              () => Navigator.pop(context, true),
            ),
            child: const Text('لغو سفارش'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await auth.cancelWalletPayment(expectedPendingId: expectedPendingId);
    if (!mounted) return;
    if (ok) {
      toasts.success('سفارش لغو شد؛ پرداخت دیرهنگام به کیف پول افزوده می شود.');
    } else {
      toasts.error('لغو سفارش انجام نشد', auth.error.isEmpty ? 'ابتدا وضعیت کیف پول را تازه سازی کنید.' : auth.error);
    }
  }

  Future<void> _openWalletCheckout(String link, ToastController toasts) async {
    final Uri? uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      toasts.error('نشانی امن درگاه در دسترس نیست', 'پرداخت را از ربات یا پشتیبانی پیگیری کنید.');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
        toasts.error('باز کردن درگاه ناموفق بود', 'از دکمه ادامه پرداخت استفاده کنید.');
      }
    } catch (_) {
      if (mounted) toasts.error('باز کردن درگاه ناموفق بود', 'از دکمه ادامه پرداخت استفاده کنید.');
    }
  }

  Future<void> _topupWallet(AuthController auth, ToastController toasts) async {
    if (auth.botLinked != true) {
      toasts.info('اتصال ربات لازم است', 'برای شارژ کیف پول، ابتدا حساب را پیوند دهید.');
      return;
    }
    if (!auth.walletLoaded || auth.walletPaymentPending) return;
    final TextEditingController controller = TextEditingController();
    final int? amount = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter update) {
          final String text = Fa.toEn(controller.text).trim();
          final int? value = RegExp(r'^[0-9]+$').hasMatch(text)
              ? int.tryParse(text)
              : null;
          final bool valid = value != null &&
              value >= auth.walletMinTopup &&
              value <= auth.walletMaxTopup;
          final List<int> presets = <int>[
            auth.walletMinTopup,
            auth.walletMinTopup * 2,
            auth.walletMinTopup * 5,
          ].where((int preset) =>
              preset >= auth.walletMinTopup &&
              preset <= auth.walletMaxTopup).toSet().toList();
          final UmbrellaColors colors = context.colors;

          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
              side: BorderSide(color: colors.border),
            ),
            title: const Text('افزایش اعتبار کیف پول'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'مبلغ شارژ به تومان؛ حداقل ${Fa.grouped(auth.walletMinTopup)} و حداکثر ${Fa.grouped(auth.walletMaxTopup)} تومان.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                  ),
                  if (presets.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppMetrics.space3),
                    Text(
                      'مبلغ پیشنهادی',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space2),
                    Wrap(
                      spacing: AppMetrics.space2,
                      runSpacing: AppMetrics.space1,
                      children: <Widget>[
                        for (final int preset in presets)
                          ChoiceChip(
                            label: Text('${Fa.grouped(preset)} تومان'),
                            selected: value == preset,
                            showCheckmark: false,
                            onSelected: (_) {
                              playUiClick(context);
                              final String next = '$preset';
                              controller.value = TextEditingValue(
                                text: next,
                                selection: TextSelection.collapsed(
                                  offset: next.length,
                                ),
                              );
                              update(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppMetrics.space3),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'مبلغ شارژ (تومان)',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    onChanged: (_) => update(() {}),
                  ),
                  const SizedBox(height: AppMetrics.space3),
                  Container(
                    padding: const EdgeInsets.all(AppMetrics.space3),
                    decoration: BoxDecoration(
                      color: colors.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                      border: Border.all(
                        color: colors.info.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Text(
                      'کارمزد درگاه پس از استعلام جداگانه نمایش داده می شود و به موجودی اضافه نمی شود.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: withUiClick(
                  dialogContext,
                  () => Navigator.pop(dialogContext),
                ),
                child: const Text('انصراف'),
              ),
              FilledButton.icon(
                onPressed: valid
                    ? withUiClick(
                        dialogContext,
                        () => Navigator.pop(dialogContext, value),
                      )
                    : null,
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('ثبت درخواست امن'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    final result = await auth.startWalletTopup(amount);
    if (!mounted) return;
    if (result == null) {
      toasts.error('ساخت درخواست شارژ ناموفق بود', auth.error);
      await auth.refreshWallet(silent: true);
      return;
    }
    final credit = JsonX.number(result['credit']);
    final total = JsonX.number(result['gateway_amount']);
    final fee = JsonX.number(result['fee']);
    final String link = JsonX.text(result['checkout_url']);
    final bool open = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            final UmbrellaColors colors = dialogContext.colors;
            return AlertDialog(
              backgroundColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
                side: BorderSide(color: colors.border),
              ),
              title: const Text('جزئیات پرداخت'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _PaymentAmountRow(label: 'اعتبار کیف پول', amount: credit),
                  _PaymentAmountRow(label: 'کارمزد درگاه', amount: fee),
                  const Divider(height: AppMetrics.space4),
                  _PaymentAmountRow(
                    label: 'جمع قابل پرداخت',
                    amount: total,
                    emphasize: true,
                  ),
                  const SizedBox(height: AppMetrics.space3),
                  Text(
                    'اعتبار فقط پس از تایید سرور درگاه اضافه می شود. اگر پرداخت را فعلاً ادامه ندهید، سفارش برای پیگیری در کیف پول باقی می ماند.',
                    style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.55,
                        ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: withUiClick(
                    dialogContext,
                    () => Navigator.pop(dialogContext, false),
                  ),
                  child: const Text('بعداً'),
                ),
                FilledButton.icon(
                  onPressed: withUiClick(
                    dialogContext,
                    () => Navigator.pop(dialogContext, true),
                  ),
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('رفتن به درگاه امن'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (open && mounted) await _openWalletCheckout(link, toasts);
  }

  Future<void> _refreshPaidPlans(
    AuthController auth,
    ToastController toasts,
  ) async {
    await auth.refreshBotLinkStatus();
    if (auth.botLinked != true) {
      if (mounted) {
        toasts.info(
          'اتصال ربات لازم است',
          'برای دریافت کیف پول و تعرفه ها، حساب را به ربات پیوند دهید.',
        );
      }
      return;
    }
    await auth.refreshAccount(silent: true);
    final bool loaded = await auth.loadSubscriptionPlans(silent: false);
    if (mounted && loaded) toasts.success('وضعیت اشتراک و کیف پول تازه شد.');
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

  Future<void> _joinBot(AuthController auth, ToastController toasts) async {
    final String? link = await auth.createBotMembershipLink();
    if (!mounted) return;
    if (link == null) {
      toasts.error('ساخت لینک انجام نشد', auth.error);
      return;
    }
    if (link.isEmpty) {
      toasts.success('حساب از قبل به ربات متصل است.');
      await _autoSync();
      return;
    }
    final Uri? uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'https' || uri.host != 't.me' ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) toasts.error('باز کردن تلگرام ناموفق بود', 'لینک جدید بگیرید و دوباره تلاش کنید.');
      return;
    }
    if (mounted) {
      toasts.info('ربات باز شد',
          'در تلگرام شروع و سپس اتصال حساب را تایید کنید. در صورت نیاز ابتدا عضو کانال شوید و همین لینک را دوباره باز کنید.');
    }
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

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;

    final Account account = auth.account;
    final DateTime? expiry = account.effectiveExpiryDate;
    final bool expired = account.isExpiredAt(_now);
    final Duration remDuration = account.remainingDuration(_now);
    final int daysLeft = account.daysLeftAt(_now);
    final int daysElapsed = account.daysElapsedAt(_now);
    final bool soon = expiry != null && !expired && daysLeft <= 7;
    final bool renewalDue = account.renewalDueAt(_now);
    final String renewalRemaining = remDuration.inSeconds <= 0
        ? 'کمتر از یک دقیقه'
        : Fa.spanFa(remDuration);
    final String? renewalNotice = expired
        ? 'اشتراک شما منقضی شده است؛ پلن مناسب را برای تمدید انتخاب کنید.'
        : (account.quotaFinished
            ? 'حجم اشتراک تمام شده است؛ برای ادامه پلن تازه انتخاب کنید.'
            : (renewalDue
                ? 'تنها $renewalRemaining تا پایان اعتبار باقی مانده است؛ پلن تمدید را انتخاب کنید.'
                : null));
    final Color? renewalTone = renewalDue
        ? (expired ? colors.danger : colors.warning)
        : null;

    final double used = account.currentUsageGb;
    final double limit = account.usageLimitGb;
    final bool unlimited = account.unlimited;
    final double remaining = account.remainingGb;
    final double percent = account.usagePercent;
    final double daily = account.dailyAverageGb(_now);
    final bool onlineNow = account.isOnlineRecently(_now);
    final String name = _ownerNameFa(account);

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
            ? 'پس از نخستین اتصال ثبت می شود'
            : '${Fa.tehranDate(account.lastOnline)} • ساعت ${Fa.tehranClock(account.lastOnline, seconds: false)}',
      ),
    ];

    return DefaultTabController(
      length: _AccountSection.values.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: AppMetrics.pagePadding,
            child: const PageHeader(
              title: 'حساب من',
              eyebrow: 'حساب و سرویس',
              premium: true,
              subtitle:
                  'مدیریت موجودی، اشتراک و مشخصات حساب از یک نمای منظم',
              icon: Icons.person_rounded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: AppMetrics.space6,
              right: AppMetrics.space6,
              bottom: AppMetrics.space3,
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double scale = MediaQuery.textScalerOf(context)
                    .scale(1)
                    .clamp(1.0, 2.0)
                    .toDouble();
                final bool scrollable = constraints.maxWidth / scale <
                    AppMetrics.breakpointCompact;
                return GlassCard(
                  key: const ValueKey<String>('account-section-tab-card'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.space2,
                    vertical: AppMetrics.space1,
                  ),
                  radius: AppMetrics.radiusXl,
                  child: TabBar(
                    key: const ValueKey<String>('account-section-tabs'),
                    onTap: (_) => playUiClick(context),
                    isScrollable: scrollable,
                    tabAlignment: scrollable ? TabAlignment.start : null,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorPadding: const EdgeInsets.all(AppMetrics.space1),
                    indicator: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.13),
                      borderRadius:
                          BorderRadius.circular(AppMetrics.radiusMd),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.28),
                      ),
                    ),
                    labelColor: colors.primary,
                    unselectedLabelColor: colors.textSecondary,
                    labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                    unselectedLabelStyle:
                        Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    tabs: <Widget>[
                      for (final _AccountSection section
                          in _AccountSection.values)
                        Tab(
                          key: ValueKey<String>(
                            'account-tab-${section.name}',
                          ),
                          icon: Tooltip(
                            message: Fa.num(
                              section == _AccountSection.wallet &&
                                      auth.botLinked != true
                                  ? 'برای دیدن موجودی، حساب را به ربات پیوند دهید'
                                  : section.detail,
                            ),
                            child: Icon(
                              section == _AccountSection.wallet &&
                                      auth.botLinked != true
                                  ? Icons.send_rounded
                                  : section.icon,
                              size: AppMetrics.iconMd,
                            ),
                          ),
                          iconMargin: const EdgeInsets.only(
                            bottom: AppMetrics.space1,
                          ),
                          text: Fa.num(
                            section == _AccountSection.wallet &&
                                    auth.botLinked != true
                                ? 'اتصال ربات'
                                : section.title,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppMetrics.space6,
                right: AppMetrics.space6,
                bottom: AppMetrics.space6,
              ),
              child: TabBarView(
                children: <Widget>[
                  _buildSummaryTab(
                    account: account,
                    kpiCards: kpiCards,
                    used: used,
                    limit: limit,
                    unlimited: unlimited,
                    remaining: remaining,
                    percent: percent,
                    quotaTone: quotaTone,
                    statusTone: statusTone,
                    timeTone: timeTone,
                  ),
                  _buildWalletTab(auth, toasts),
                  _buildSubscriptionTab(
                    auth: auth,
                    toasts: toasts,
                    account: account,
                    expiry: expiry,
                    daysLeft: daysLeft,
                    renewalNotice: renewalNotice,
                    renewalTone: renewalTone,
                  ),
                  _buildProfileTab(account: account, name: name, toasts: toasts),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab({
    required Account account,
    required List<Widget> kpiCards,
    required double used,
    required double limit,
    required bool unlimited,
    required double remaining,
    required double percent,
    required Color quotaTone,
    required Color statusTone,
    required Color timeTone,
  }) {
    final UmbrellaColors colors = context.colors;
    return SingleChildScrollView(
      key: const PageStorageKey<String>('account-section-content-summary'),
      padding: const EdgeInsets.only(bottom: AppMetrics.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double scale = MediaQuery.textScalerOf(context)
                  .scale(1)
                  .clamp(1.0, 2.0).toDouble();
              final double width = constraints.maxWidth / scale;
              if (width >= AppMetrics.breakpointColumns) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < kpiCards.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: AppMetrics.space3),
                        Expanded(child: kpiCards[i]),
                      ],
                    ],
                  ),
                );
              }
              if (width >= AppMetrics.breakpointCompact) {
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
                  for (int i = 0; i < kpiCards.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: AppMetrics.space3),
                    kpiCards[i],
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppMetrics.space5),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget usage = _UsageCard(
                account: account,
                used: used,
                limit: limit,
                unlimited: unlimited,
                remaining: remaining,
                percent: percent,
                accountFresh: _accountFresh,
                tone: quotaTone,
                statusTone: statusTone,
                colors: colors,
              );
              final Widget days = _DaysCard(
                account: account,
                now: _now,
                tone: timeTone,
                colors: colors,
              );
              final double scale = MediaQuery.textScalerOf(context)
                  .scale(1)
                  .clamp(1.0, 2.0).toDouble();
              if (constraints.maxWidth / scale < AppMetrics.breakpointColumns) {
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
          const SizedBox(height: AppMetrics.space4),
        ],
      ),
    );
  }

  Widget _buildWalletTab(AuthController auth, ToastController toasts) {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('account-section-content-wallet'),
      padding: const EdgeInsets.only(bottom: AppMetrics.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (auth.botLinked != true) ...<Widget>[
            GlassCard(
              padding: AppMetrics.cardPadding,
              radius: AppMetrics.radiusXl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SectionHeader(
                    icon: Icons.send_rounded,
                    title: 'اتصال امن به ربات تلگرام',
                    subtitle: 'برای استفاده از کیف پول مشترک، حساب را پیوند دهید',
                  ),
                  const SizedBox(height: AppMetrics.space3),
                  const Text(
                    'لینک اختصاصی را باز کنید و در ربات شروع و اتصال را تایید کنید. لینک فقط ۱۰ دقیقه معتبر و یک بار مصرف است؛ آن را برای دیگران نفرستید.',
                  ),
                  const SizedBox(height: AppMetrics.space3),
                  GradientButton(
                    onPressed: auth.linkingBot ? null : () => _joinBot(auth, toasts),
                    loading: auth.linkingBot,
                    icon: Icons.link_rounded,
                    label: auth.linkingBot
                        ? 'در حال ساخت لینک...'
                        : 'عضویت و اتصال ربات',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppMetrics.space4),
          ],
          if (auth.botLinked == true)
            _WalletCard(
              auth: auth,
              onTopup: () => _topupWallet(auth, toasts),
              onRefresh: () => _refreshWallet(auth, toasts),
              onVerify: () => _refreshWallet(auth, toasts, verify: true),
              onCancel: () => _cancelWalletPayment(auth, toasts),
              onContinue: () =>
                  _openWalletCheckout(auth.walletCheckoutUrl, toasts),
            ),
          const SizedBox(height: AppMetrics.space4),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTab({
    required AuthController auth,
    required ToastController toasts,
    required Account account,
    required DateTime? expiry,
    required int daysLeft,
    required String? renewalNotice,
    required Color? renewalTone,
  }) {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('account-section-content-subscription'),
      padding: const EdgeInsets.only(bottom: AppMetrics.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (auth.offers.hasVisibleOffer) ...<Widget>[
            _GiftPlansCard(
              offers: auth.offers,
              busy: auth.claimingOffer,
              activePlanType: auth.claimingPlanType,
              onClaim: (String planType) async {
                final String? message =
                    await auth.claimSubscriptionOffer(planType);
                if (!mounted) return;
                if (message != null) {
                  toasts.success(message);
                } else if (auth.error.isNotEmpty) {
                  toasts.error('فعال سازی انجام نشد', auth.error);
                }
              },
            ),
            const SizedBox(height: AppMetrics.space4),
          ],
          if (account.canConnect)
            _ActiveSubscriptionCard(
              account: account,
              expiry: expiry,
              daysLeft: daysLeft,
            )
          else
            _PaidPlansCard(
              plans: auth.subscriptionPlans,
              balance: auth.walletBalance,
              showBalance: auth.botLinked == true,
              canPurchase: auth.botLinked == true,
              onLinkBot: () => _joinBot(auth, toasts),
              custom: auth.customSubscriptionTerms,
              renewalNotice: renewalNotice,
              renewalTone: renewalTone,
              onCustom: () => _purchaseCustomPlan(auth, toasts),
              loading: auth.loadingSubscriptionPlans,
              busy: auth.purchasingSubscription,
              onRefresh: () => _refreshPaidPlans(auth, toasts),
              onPurchase: (SubscriptionPlan plan) =>
                  _purchasePlan(auth, toasts, plan),
            ),
          const SizedBox(height: AppMetrics.space4),
        ],
      ),
    );
  }

  Widget _buildProfileTab({
    required Account account,
    required String name,
    required ToastController toasts,
  }) {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('account-section-content-profile'),
      padding: const EdgeInsets.only(bottom: AppMetrics.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassCard(
            padding: AppMetrics.cardPadding,
            radius: AppMetrics.radiusXl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SectionHeader(
                  icon: Icons.badge_rounded,
                  title: 'مشخصات حساب و سرویس',
                  subtitle:
                      'اطلاعات حساب کاربری به صورت خودکار در پس زمینه به روز می شود',
                  trailing: IconAction(
                    icon: Icons.send_rounded,
                    tooltip: 'باز کردن ربات رسمی آمبرلا',
                    size: AppMetrics.iconBoxSm,
                    onTap: () => _openTelegramBot(toasts),
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
                  value: account.uuid.trim().isEmpty
                      ? 'نامشخص'
                      : account.uuid.trim(),
                  ltr: account.uuid.trim().isNotEmpty,
                  technicalValue: account.uuid.trim().isNotEmpty,
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
                if (account.telegramId.isNotEmpty) ...<Widget>[
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.alternate_email_rounded,
                    label: 'شناسه عددی تلگرام',
                    value: account.telegramId,
                    ltr: true,
                    technicalValue: true,
                    trailing: IconAction(
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
                ],
                if (account.wgIpv4.isNotEmpty) ...<Widget>[
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.hub_rounded,
                    label: 'نشانی اختصاصی تونل استاندارد',
                    value: account.wgIpv4,
                    ltr: true,
                    technicalValue: true,
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
                    value: account.awgIpv4,
                    ltr: true,
                    technicalValue: true,
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
          ),
          const SizedBox(height: AppMetrics.space4),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppMetrics.space1),
          Text(
            caption,
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
    required this.accountFresh,
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
  final bool accountFresh;
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
            subtitle: accountFresh
                ? 'آمار زنده و تاییدشدهٔ حساب'
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
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                    if (!unlimited) ...<Widget>[
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        'باقی مانده: ${Fa.gb(remaining)} (${Fa.decimal(account.remainingPercent, fraction: 1)} درصد)',
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
    required this.tone,
    required this.colors,
  });

  final Account account;
  final DateTime now;
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      start == null
                          ? 'تاریخ شروع پس از نخستین اتصال ثبت می شود'
                          : 'سپری شده از شروع: ${Fa.spanFa(elapsed, includeMinutes: false)}',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                    if (hasDate && !expired) ...<Widget>[
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        '${Fa.decimal(remPct, fraction: 1)} درصد از دوره سرویس باقی مانده',
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
          const _TehranClockRow(),
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

class _PaymentAmountRow extends StatelessWidget {
  const _PaymentAmountRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final TextStyle? style = emphasize
        ? Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w900,
            )
        : Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppMetrics.space1),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text('${_walletMoney(amount)} تومان', style: style),
        ],
      ),
    );
  }
}

String _walletMoney(double value) {
  if ((value - value.round()).abs() < 0.000001) return Fa.grouped(value);
  return Fa.decimal(value, fraction: 1);
}

/// کارت کیف پول با نمایش موجودی، پرداخت های معلق و اقدام های امن.
class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.auth,
    required this.onTopup,
    required this.onRefresh,
    required this.onVerify,
    required this.onCancel,
    required this.onContinue,
  });

  final AuthController auth;
  final VoidCallback onTopup;
  final VoidCallback onRefresh;
  final VoidCallback onVerify;
  final VoidCallback onCancel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color stateColor = !auth.walletLoaded
        ? colors.textSecondary
        : (auth.walletPaymentPending ? colors.warning : colors.success);
    final String stateLabel = !auth.walletLoaded
        ? 'همگام نشده'
        : (auth.walletPaymentPending ? 'در انتظار پرداخت' : 'آماده');

    return GlassCard(
      key: const ValueKey<String>('account-wallet-card'),
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      borderColor: colors.primary.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.account_balance_wallet_rounded,
            title: 'کیف پول مشترک',
            subtitle: 'موجودی قابل استفاده برای خرید اشتراک',
            trailing: Pill(
              label: stateLabel,
              icon: auth.walletLoaded
                  ? (auth.walletPaymentPending
                      ? Icons.hourglass_top_rounded
                      : Icons.check_circle_rounded)
                  : Icons.account_balance_wallet_outlined,
              color: stateColor,
              dense: true,
            ),
          ),
          const SizedBox(height: AppMetrics.space4),
          Container(
            padding: const EdgeInsets.all(AppMetrics.space4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: <Color>[colors.primary, colors.primaryDeep],
              ),
              borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.2),
                  blurRadius: AppMetrics.space5,
                  offset: const Offset(0, AppMetrics.space2),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'موجودی فعلی',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppMetrics.space1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          auth.walletLoaded
                              ? _walletMoney(auth.walletExactBalance)
                              : '— — —',
                          key: const ValueKey<String>('account-wallet-balance'),
                          maxLines: 1,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        auth.walletLoaded
                            ? 'تومان • همگام با کیف پول ربات'
                            : 'برای مشاهده موجودی، کیف پول را تازه سازی کنید',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppMetrics.space3),
                Container(
                  width: AppMetrics.iconBoxXl,
                  height: AppMetrics.iconBoxXl,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: AppMetrics.iconXl,
                  ),
                ),
              ],
            ),
          ),
          if (!auth.walletLoaded) ...<Widget>[
            const SizedBox(height: AppMetrics.space3),
            _WalletNotice(
              color: colors.info,
              icon: Icons.info_outline_rounded,
              message:
                  'برای استفاده از موجودی مشترک، حساب را به ربات متصل کنید و وضعیت کیف پول را تازه سازی کنید.',
            ),
          ],
          if (auth.walletPaymentPending) ...<Widget>[
            const SizedBox(height: AppMetrics.space3),
            _WalletNotice(
              color: colors.warning,
              icon: Icons.hourglass_top_rounded,
              message: auth.walletTopupPending
                  ? 'درخواست شارژ ${_walletMoney(auth.walletPendingCredit)} تومان در انتظار تایید است؛ مبلغ درگاه ${_walletMoney(auth.walletPendingAmount)} تومان. اگر مبلغ کسر شده، دوباره پرداخت نکنید.'
                  : 'یک پرداخت اشتراک در حال بررسی است؛ ابتدا آن را تکمیل یا از ربات پیگیری کنید.',
            ),
          ],
          const SizedBox(height: AppMetrics.space4),
          Wrap(
            spacing: AppMetrics.space2,
            runSpacing: AppMetrics.space2,
            children: <Widget>[
              if (auth.walletLoaded)
                GradientButton(
                  expand: false,
                  height: AppMetrics.controlHeightSmall,
                  onPressed: auth.walletBusy || auth.walletPaymentPending
                      ? null
                      : onTopup,
                  loading: auth.walletBusy,
                  icon: Icons.add_card_rounded,
                  label: 'افزایش اعتبار',
                ),
              if (auth.walletTopupPending &&
                  auth.walletCheckoutUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: auth.walletBusy
                      ? null
                      : withUiClick(context, onContinue),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('ادامه پرداخت'),
                ),
              if (auth.walletPaymentPending)
                OutlinedButton.icon(
                  onPressed: auth.walletBusy
                      ? null
                      : withUiClick(context, onVerify),
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('بررسی پرداخت'),
                ),
              if (auth.walletPaymentPending)
                OutlinedButton.icon(
                  onPressed: auth.walletBusy
                      ? null
                      : withUiClick(context, onCancel),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('لغو سفارش پرداخت'),
                ),
              OutlinedButton.icon(
                onPressed: auth.walletBusy
                    ? null
                    : withUiClick(context, onRefresh),
                icon: auth.walletBusy
                    ? const SizedBox.square(
                        dimension: AppMetrics.iconSm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(
                  auth.walletBusy ? 'در حال بررسی...' : 'تازه سازی موجودی',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletNotice extends StatelessWidget {
  const _WalletNotice({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppMetrics.space3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppMetrics.iconSm, color: color),
          const SizedBox(width: AppMetrics.space2),
          Expanded(
            child: Text(
              Fa.num(message),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textPrimary,
                    height: 1.55,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSubscriptionCard extends StatelessWidget {
  const _ActiveSubscriptionCard({
    required this.account,
    required this.expiry,
    required this.daysLeft,
  });

  final Account account;
  final DateTime? expiry;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String expiryLabel = expiry == null
        ? 'بدون محدودیت زمانی'
        : (daysLeft > 0
            ? '${Fa.grouped(daysLeft)} روز باقی مانده'
            : Fa.spanFa(account.remainingDuration()));

    return GlassCard(
      key: const ValueKey<String>('account-active-subscription'),
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      borderColor: colors.success.withValues(alpha: 0.36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.verified_user_rounded,
            accent: colors.success,
            title: 'اشتراک شما فعال است',
            subtitle: 'پلن فعلی آماده استفاده است',
            trailing: Pill(
              label: 'فعال',
              icon: Icons.check_circle_rounded,
              color: colors.success,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.category_rounded,
            label: 'نوع بسته',
            value: account.packageDurationLabel,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.event_available_rounded,
            label: 'اعتبار باقی مانده',
            value: expiryLabel,
            valueColor: colors.success,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.data_usage_rounded,
            label: 'حجم قابل استفاده',
            value: account.unlimited ? 'نامحدود' : Fa.gb(account.remainingGb),
          ),
        ],
      ),
    );
  }
}

/// پلن های پولی از تعرفه ربات می آیند و خرید با همان کیف پول/تسویه مشترک انجام می شود.
class _PaidPlansCard extends StatelessWidget {
  const _PaidPlansCard({
    required this.plans,
    required this.balance,
    required this.showBalance,
    required this.canPurchase,
    required this.onLinkBot,
    required this.custom,
    required this.renewalNotice,
    required this.renewalTone,
    required this.onCustom,
    required this.loading,
    required this.busy,
    required this.onRefresh,
    required this.onPurchase,
  });

  final List<SubscriptionPlan> plans;
  final int balance;
  final bool showBalance;
  final bool canPurchase;
  final VoidCallback onLinkBot;
  final CustomSubscriptionTerms? custom;
  final String? renewalNotice;
  final Color? renewalTone;
  final VoidCallback onCustom;
  final bool loading;
  final bool busy;
  final VoidCallback onRefresh;
  final Future<void> Function(SubscriptionPlan plan) onPurchase;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color noticeColor = renewalTone ?? colors.warning;
    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      borderColor: (renewalTone ?? colors.primary).withValues(alpha: 0.34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SectionHeader(
                  icon: renewalNotice == null
                      ? Icons.payments_rounded
                      : Icons.autorenew_rounded,
                  title: renewalNotice == null
                      ? 'خرید و تمدید اشتراک'
                      : 'تمدید اشتراک',
                  subtitle: renewalNotice == null
                      ? 'پلن ها و موجودی از حساب مشترک ربات تلگرام'
                      : 'یادآوری تمدید اشتراک',
                ),
              ),
              IconButton(
                tooltip: 'تازه سازی تعرفه، کیف پول و وضعیت اشتراک',
                onPressed: loading || busy
                    ? null
                    : withUiClick(context, onRefresh),
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (renewalNotice != null) ...<Widget>[
            const SizedBox(height: AppMetrics.space2),
            Container(
              key: const ValueKey<String>('account-renewal-notice'),
              padding: const EdgeInsets.all(AppMetrics.space3),
              decoration: BoxDecoration(
                color: noticeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                border: Border.all(
                  color: noticeColor.withValues(alpha: 0.32),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.notifications_active_rounded,
                    size: AppMetrics.iconSm,
                    color: noticeColor,
                  ),
                  const SizedBox(width: AppMetrics.space2),
                  Expanded(
                    child: Text(
                      Fa.num(renewalNotice!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textPrimary,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppMetrics.space3),
          ],
          if (showBalance) ...<Widget>[
            Text(
              'موجودی کیف پول: ${Fa.num(balance)} تومان',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.success,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppMetrics.space3),
          ],
          if (plans.isEmpty)
            Text(
              loading
                  ? 'در حال دریافت تعرفه های رسمی ربات...'
                  : 'تعرفه ای دریافت نشد. ارتباط حساب با ربات را بررسی و دوباره تازه سازی کنید.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.6,
                  ),
            )
          else
            for (int i = 0; i < plans.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: AppMetrics.space3),
              Row(
                children: <Widget>[
                  IconSquare(
                    icon: Icons.autorenew_rounded,
                    color: colors.primary,
                    size: AppMetrics.iconBoxSm,
                  ),
                  const SizedBox(width: AppMetrics.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          Fa.num(plans[i].name),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          '${Fa.num(plans[i].days)} روز • حجم نامحدود • ${Fa.num(plans[i].price)} تومان',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppMetrics.space2),
                  OutlinedButton(
                    onPressed: busy || !canPurchase
                        ? null
                        : withUiClick(context, () => onPurchase(plans[i])),
                    child: Text(busy ? '...' : 'انتخاب'),
                  ),
                ],
              ),
            ],
          if (custom?.available == true) ...<Widget>[
            const Divider(height: AppMetrics.space3),
            OutlinedButton.icon(
              onPressed: busy || loading || !canPurchase
                  ? null
                  : withUiClick(context, onCustom),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('اشتراک دلخواه: انتخاب مدت و حجم'),
            ),
          ],
          if (!canPurchase) ...<Widget>[
            const SizedBox(height: AppMetrics.space3),
            Text(
              'برای خرید با کیف پول مشترک، ابتدا حساب را به ربات تلگرام پیوند دهید.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: AppMetrics.space2),
            GradientButton(
              label: 'پیوند حساب به ربات',
              icon: Icons.link_rounded,
              loading: false,
              height: AppMetrics.controlHeightSmall,
              onPressed: onLinkBot,
            ),
          ],
          const SizedBox(height: AppMetrics.space2),
          Text(
            'پرداخت آنلاین در صورت نیاز، فقط پس از تایید زرین پال توسط سرور فعال می شود؛ تغییرات ربات نیز با تازه سازی در این صفحه دیده خواهد شد.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
          ),
        ],
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
                  constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) >= AppMetrics.breakpointCompact) {
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

/// تنها ردیف ساعت هر ثانیه بازسازی می شود، نه همه کارت های حساب.
class _TehranClockRow extends StatefulWidget {
  const _TehranClockRow();

  @override
  State<_TehranClockRow> createState() => _TehranClockRowState();
}

class _TehranClockRowState extends State<_TehranClockRow> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    if (TickerMode.of(context)) {
      _now = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = Fa.toTehran(_now);
    return InfoRow(
      icon: Icons.today_rounded,
      label: 'تقویم و ساعت رسمی ایران',
      value: '${Fa.fullDate(now)} • ساعت ${Fa.clock(now)}',
      valueColor: context.colors.primary,
      tooltip: true,
    );
  }
}
