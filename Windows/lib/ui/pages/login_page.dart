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
import '../../state/settings_controller.dart';
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
  bool _autoSubmittingCode = false;

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
    final SettingsController settings = context.watch<SettingsController>();
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
            onToggleTheme: () => settings.toggleTheme(
              effectiveBrightness: Theme.of(context).brightness,
            ),
            darkTheme: Theme.of(context).brightness == Brightness.dark,
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
                        padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space10, vertical: AppMetrics.space9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const BrandMark(size: AppMetrics.logoMd),
                            const SizedBox(height: AppMetrics.space7),
                            Text(
                              Fa.num('ورود امن با شماره موبایل'),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    height: 1.4,
                                  ),
                            ),
                            const SizedBox(height: AppMetrics.space3),
                            Text(
                              Fa.num(
                                'کد تایید پیامک می شود و جزئیات دستگاه شما در تلگرام نمایش داده می شود تا فقط خودتان ورود را تایید کنید.',
                              ),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    height: 1.9,
                                  ),
                            ),
                            const SizedBox(height: AppMetrics.space6),
                            for (final (IconData icon, String text) item in const <(IconData, String)>[
                              (Icons.sms_rounded, 'کد تایید ۶ رقمی پیامکی'),
                              (Icons.phonelink_lock_rounded, 'تایید دستگاه در تلگرام'),
                              (Icons.verified_user_rounded, 'ثبت و همگام سازی حساب در ربات'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: AppMetrics.space3),
                                child: Row(
                                  children: <Widget>[
                                    Icon(item.$1, size: AppMetrics.iconSm, color: colors.primary),
                                    const SizedBox(width: AppMetrics.space3),
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
                              Fa.num(
                                'نسخه ${AppConfig.versionLabel} | ویندوز ۱۰ و ۱۱',
                              ),
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
                          padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space9, vertical: AppMetrics.space9),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
                            child: GlassCard(
                              padding: const EdgeInsets.all(AppMetrics.space7),
                              radius: AppMetrics.radiusHuge,
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
        const SizedBox(height: AppMetrics.space2),
        Text(
          Fa.num('شماره را وارد کنید تا کد تایید برای شما پیامک شود.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
        const SizedBox(height: AppMetrics.space6),
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
            prefixIcon: Icon(Icons.smartphone_rounded, size: AppMetrics.iconMd),
          ),
          onSubmitted: (_) => _submitPhone(auth),
        ),
        const SizedBox(height: AppMetrics.space3),
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
          const SizedBox(height: AppMetrics.space4),
          _Message(text: auth.error, kind: _MessageKind.error),
          if (auth.error.contains('درگاه') ||
              auth.error.contains('سرور') ||
              auth.error.contains('ارتباط')) ...<Widget>[
            const SizedBox(height: AppMetrics.space2),
            Row(
              children: <Widget>[
                Icon(Icons.dns_rounded, size: AppMetrics.iconXs, color: colors.textSecondary),
                const SizedBox(width: AppMetrics.space2),
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
          const SizedBox(height: AppMetrics.space4),
          _Message(text: auth.info, kind: _MessageKind.info),
        ],
        const SizedBox(height: AppMetrics.space6),
        GradientButton(
          label: 'دریافت کد تایید',
          icon: Icons.arrow_back_rounded,
          loading: auth.busy,
          onPressed: auth.busy ? null : () => _submitPhone(auth),
        ),
        const SizedBox(height: AppMetrics.space4),
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
            const SizedBox(width: AppMetrics.space3),
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
        const SizedBox(height: AppMetrics.space2),
        Text(
          Fa.num('این شماره در سیستم نیست؛ برای ساخت حساب نام و نام خانوادگی را وارد کنید.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
        const SizedBox(height: AppMetrics.space5),
        TextField(
          controller: _firstName,
          decoration: const InputDecoration(
            labelText: 'نام',
            prefixIcon: Icon(Icons.person_outline_rounded, size: AppMetrics.iconMd),
          ),
        ),
        const SizedBox(height: AppMetrics.space3),
        TextField(
          controller: _lastName,
          decoration: const InputDecoration(
            labelText: 'نام خانوادگی',
            prefixIcon: Icon(Icons.badge_outlined, size: AppMetrics.iconMd),
          ),
        ),
        if (auth.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppMetrics.space4),
          _Message(text: auth.error, kind: _MessageKind.error),
        ],
        const SizedBox(height: AppMetrics.space6),
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
            const SizedBox(width: AppMetrics.space3),
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
        const SizedBox(height: AppMetrics.space2),
        Text(
          Fa.num('کد ارسال شده به ${IranPhone.display(auth.phone)} را وارد کنید.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
        const SizedBox(height: AppMetrics.space5),
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
            fontSize: AppMetrics.fontDisplay,
            letterSpacing: 16,
            fontWeight: FontWeight.w900,
            fontFamily: AppTheme.fontFamily,
          ),
          decoration: const InputDecoration(hintText: 'ــــــ'),
          onChanged: (String value) => _onCodeChanged(value, auth),
          onSubmitted: (String value) => auth.verifyCode(value),
        ),
        const SizedBox(height: AppMetrics.space4),
        Row(
          children: <Widget>[
            Icon(Icons.timer_outlined, size: AppMetrics.iconSm, color: colors.textSecondary),
            const SizedBox(width: AppMetrics.space2),
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
          const SizedBox(height: AppMetrics.space3),
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
            IconSquare(icon: Icons.send_rounded, color: colors.info, size: AppMetrics.iconBoxLg),
            const SizedBox(width: AppMetrics.space3),
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
        const SizedBox(height: AppMetrics.space3),
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
        const SizedBox(height: AppMetrics.space5),
        if (auth.stage == SignInStage.awaitingTelegram)
          Row(
            children: <Widget>[
              const SizedBox(
                width: AppMetrics.iconSm,
                height: AppMetrics.iconSm,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppMetrics.space3),
              Text(
                Fa.num('در انتظار تایید شما در تلگرام...'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        if (auth.error.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppMetrics.space3),
          _Message(text: auth.error, kind: _MessageKind.error),
        ],
        const SizedBox(height: AppMetrics.space5),
        GradientButton(
          label: 'باز کردن تلگرام',
          icon: Icons.open_in_new_rounded,
          onPressed: () => _openBot(auth.botUrl),
        ),
        const SizedBox(height: AppMetrics.space3),
        OutlinedButton.icon(
          onPressed: auth.busy ? null : auth.checkNow,
          icon: const Icon(Icons.refresh_rounded, size: AppMetrics.iconSm),
          label: const Text('بررسی دوباره وضعیت'),
        ),
        const SizedBox(height: AppMetrics.space3),
        TextButton(
          onPressed: auth.resetToPhoneStep,
          child: const Text('بازگشت به شماره موبایل'),
        ),
      ],
    );
  }

  Future<void> _onCodeChanged(String value, AuthController auth) async {
    if (value.length < 6) {
      _autoSubmittingCode = false;
      return;
    }
    if (value.length != 6 || auth.busy || _autoSubmittingCode) return;
    _autoSubmittingCode = true;
    await auth.verifyCode(value);
    _autoSubmittingCode = false;
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
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space4, vertical: AppMetrics.space3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            kind == _MessageKind.error
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            size: AppMetrics.iconSm,
            color: tone,
          ),
          const SizedBox(width: AppMetrics.space3),
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
