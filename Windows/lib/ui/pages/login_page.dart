import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/theme.dart';
import '../../core/ui_formatters.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/gateway_dialog.dart';
import '../widgets/common.dart';
import '../widgets/shell_widgets.dart';

/// صفحه ورود: شماره موبایل، نام و نام خانوادگی برای کاربر جدید، کد پیامکی و
/// تایید دستگاه در تلگرام.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  MobileOperator _operator = MobileOperator.unknown;

  @override
  void initState() {
    super.initState();
    final AuthController auth = context.read<AuthController>();
    if (auth.phone.isNotEmpty) {
      _phone.text = IranPhone.display(auth.phone);
      _operator = IranPhone.operator(auth.phone);
    }
    _firstName.text = auth.firstName;
    _lastName.text = auth.lastName;
    _phone.addListener(_syncOperator);
  }

  void _syncOperator() {
    final MobileOperator value = IranPhone.operator(_phone.text);
    if (value != _operator) {
      setState(() => _operator = value);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final WindowService window = context.read<WindowService>();
    final UmbrellaColors colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: <Widget>[
          TitleBar(
            onDragStart: window.startDragging,
            onMinimize: window.minimize,
            onMaximize: window.toggleMaximize,
            onClose: window.quit,
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.8, -0.9),
                        radius: 1.5,
                        colors: <Color>[
                          colors.primary.withValues(alpha: 0.20),
                          colors.background,
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 54, vertical: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const BrandMark(size: 64),
                            const SizedBox(height: 28),
                            Text(
                              Fa.num('ورود امن با شماره موبایل'),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    height: 1.4,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              Fa.num(
                                'کد تایید پیامک می شود و جزئیات دستگاه شما در تلگرام نمایش داده می شود تا فقط خودتان ورود را تایید کنید.',
                              ),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    height: 1.9,
                                  ),
                            ),
                            const SizedBox(height: 26),
                            for (final (IconData icon, String text) item in const <(IconData, String)>[
                              (Icons.sms_rounded, 'کد تایید ۶ رقمی پیامکی'),
                              (Icons.phonelink_lock_rounded, 'تایید دستگاه در تلگرام'),
                              (Icons.verified_user_rounded, 'ثبت و همگام سازی حساب در ربات'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: <Widget>[
                                    Icon(item.$1, size: 17, color: colors.primary),
                                    const SizedBox(width: 10),
                                    Text(
                                      Fa.num(item.$2),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: colors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            const Spacer(),
                            Text(
                              Fa.num('نسخه ۱٫۰٫۰ | ویندوز ۱۰ و ۱۱'),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: GlassCard(
                              padding: const EdgeInsets.all(28),
                              radius: 28,
                              elevated: true,
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  child: _step(context, auth),
                                ),
                              ),
                            ),
                          ),
                        ),
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


  Widget _step(BuildContext context, AuthController auth) {
    switch (auth.phase) {
      case AuthPhase.profile:
        return _profileStep(context, auth);
      case AuthPhase.code:
        return _codeStep(context, auth);
      case AuthPhase.telegram:
        return _telegramStep(context, auth);
      case AuthPhase.phone:
      case AuthPhase.done:
        return _phoneStep(context, auth);
    }
  }

  Widget _phoneStep(BuildContext context, AuthController auth) {
    final UmbrellaColors colors = context.colors;
    return Column(
      key: const ValueKey<String>('phone'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          Fa.num('شماره موبایل'),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          Fa.num('شماره را وارد کنید تا کد تایید برای شما پیامک شود.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹+ ]')),
            const PersianDigitsFormatter(),
            LengthLimitingTextInputFormatter(14),
          ],
          decoration: const InputDecoration(
            hintText: '۰۹۱۲۳۴۵۶۷۸۹',
            prefixIcon: Icon(Icons.smartphone_rounded, size: 20),
          ),
          onSubmitted: (_) => _submitPhone(auth),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            OperatorBadge(operator: _operator),
            const Spacer(),
            if (_operator != MobileOperator.unknown)
              Text(
                Fa.num('اپراتور تشخیص داده شد'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.success,
                    ),
              ),
          ],
        ),
        if (auth.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _Message(text: auth.error, kind: _MessageKind.error),
          if (auth.error.contains('درگاه') ||
              auth.error.contains('سرور') ||
              auth.error.contains('ارتباط')) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(Icons.dns_rounded, size: 14, color: colors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    Fa.num('نشانی فعلی درگاه: ${auth.gatewayHost}'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () => showGatewayDialog(context),
                  child: Text(Fa.num('تغییر نشانی')),
                ),
              ],
            ),
          ],
        ],
        if (auth.info.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _Message(text: auth.info, kind: _MessageKind.info),
        ],
        const SizedBox(height: 24),
        GradientButton(
          label: 'دریافت کد تایید',
          icon: Icons.arrow_back_rounded,
          loading: auth.busy,
          onPressed: auth.busy ? null : () => _submitPhone(auth),
        ),
        const SizedBox(height: 16),
        Text(
          Fa.num('با ورود، شرایط استفاده و سیاست حریم خصوصی آمبرلا را می پذیرید.'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                height: 1.7,
              ),
        ),
      ],
    );
  }

  Widget _profileStep(BuildContext context, AuthController auth) {
    final UmbrellaColors colors = context.colors;
    return Column(
      key: const ValueKey<String>('profile'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconAction(
              icon: Icons.arrow_forward_rounded,
              onTap: auth.resetToPhoneStep,
              tooltip: 'بازگشت',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                Fa.num('تکمیل ثبت نام'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          Fa.num('این شماره در سیستم نیست؛ برای ساخت حساب نام و نام خانوادگی را وارد کنید.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _firstName,
          decoration: const InputDecoration(
            labelText: 'نام',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lastName,
          decoration: const InputDecoration(
            labelText: 'نام خانوادگی',
            prefixIcon: Icon(Icons.badge_outlined, size: 20),
          ),
        ),
        if (auth.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _Message(text: auth.error, kind: _MessageKind.error),
        ],
        const SizedBox(height: 22),
        GradientButton(
          label: 'ثبت نام و دریافت کد',
          icon: Icons.arrow_back_rounded,
          loading: auth.busy,
          onPressed: auth.busy
              ? null
              : () => auth.submitProfile(_firstName.text, _lastName.text),
        ),
      ],
    );
  }

  Widget _codeStep(BuildContext context, AuthController auth) {
    final UmbrellaColors colors = context.colors;
    return Column(
      key: const ValueKey<String>('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconAction(
              icon: Icons.arrow_forward_rounded,
              onTap: auth.resetToPhoneStep,
              tooltip: 'بازگشت',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                Fa.num('کد تایید'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          Fa.num('کد ارسال شده به ${IranPhone.display(auth.phone)} را وارد کنید.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          focusNode: _codeFocus,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹]')),
            const PersianDigitsFormatter(),
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            fontSize: 26,
            letterSpacing: 16,
            fontWeight: FontWeight.w900,
            fontFamily: AppTheme.fontFamily,
          ),
          decoration: const InputDecoration(hintText: 'ــــــ'),
          onSubmitted: (String value) => auth.verifyCode(value),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Icon(Icons.timer_outlined, size: 15, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              Fa.num('زمان باقی مانده: ${Fa.countdown(Duration(seconds: auth.secondsLeft))}'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: auth.resendIn > 0 ? null : auth.resendCode,
              child: Text(
                auth.resendIn > 0
                    ? Fa.num('ارسال دوباره تا ${Fa.num(auth.resendIn)} ثانیه')
                    : 'ارسال دوباره کد',
              ),
            ),
          ],
        ),
        if (auth.error.isNotEmpty) ...<Widget>[
          _Message(text: auth.error, kind: _MessageKind.error),
          const SizedBox(height: 12),
        ],
        GradientButton(
          label: 'تایید کد',
          icon: Icons.verified_rounded,
          loading: auth.busy,
          onPressed: auth.busy ? null : () => auth.verifyCode(_code.text),
        ),
      ],
    );
  }

  Widget _telegramStep(BuildContext context, AuthController auth) {
    final UmbrellaColors colors = context.colors;
    return Column(
      key: const ValueKey<String>('telegram'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconSquare(icon: Icons.send_rounded, color: colors.info, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                Fa.num('تایید در تلگرام'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          Fa.num(
            auth.stage == SignInStage.needsTelegram
                ? 'برای تایید دستگاه، یک بار ربات آمبرلا را باز کنید و دکمه شروع را بزنید؛ سپس اینجا بررسی کنید.'
                : 'جزئیات دستگاه و آی پی شما به تلگرام ارسال شد. اگر خودتان بودید «خودم بودم» و در غیر این صورت «نبودم» را بزنید.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.9,
              ),
        ),
        const SizedBox(height: 18),
        if (auth.stage == SignInStage.awaitingTelegram)
          Row(
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                Fa.num('در انتظار تایید شما در تلگرام...'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        if (auth.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _Message(text: auth.error, kind: _MessageKind.error),
        ],
        const SizedBox(height: 20),
        GradientButton(
          label: 'باز کردن تلگرام',
          icon: Icons.open_in_new_rounded,
          onPressed: () => _openBot(auth.botUrl),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: auth.busy ? null : auth.checkNow,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('بررسی دوباره وضعیت'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: auth.resetToPhoneStep,
          child: const Text('بازگشت به شماره موبایل'),
        ),
      ],
    );
  }

  Future<void> _submitPhone(AuthController auth) async {
    final bool ok = await auth.submitPhone(_phone.text);
    if (ok) {
      _code.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.read<AuthController>().phase == AuthPhase.code) {
          _codeFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _openBot(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Fa.num('باز کردن تلگرام ممکن نشد؛ ${AppConfig.botUsername} را دستی باز کنید.'))),
        );
      }
    }
  }
}

enum _MessageKind { info, error }

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.kind});

  final String text;
  final _MessageKind kind;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone = kind == _MessageKind.error ? colors.danger : colors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            kind == _MessageKind.error
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            size: 17,
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Fa.num(text),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textPrimary,
                    height: 1.8,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
