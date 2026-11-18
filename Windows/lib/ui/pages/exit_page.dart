import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../platform/services.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// منوی «خروج».
///
/// کاربر خواست دقیقا یک چیز: «روی خروج کلیک شد، بدون هیچ صفحه ای که باز شود،
/// بله و خیر خروج بزند.» پس این صفحه چند گزینه ندارد؛ یک کارت ساده است با
/// دو دکمه «بله، خارج شو» و «نه، بمان»، و همان کاری را می کند که از اسمش
/// برمی آید. بستن پنجره از دکمه پنجره و سینی سیستم انجام می شود، نه از اینجا.
class ExitPage extends StatefulWidget {
  const ExitPage({super.key, required this.onExit});

  /// بستن کامل برنامه (پروسه پایان می یابد).
  final Future<void> Function() onExit;

  /// هنگام «نه، بمان» صدا زده می شود تا پوسته به صفحه اتصال برگردد.
  ///
  /// صفحه های پوسته در `IndexedStack` هستند و چیزی برای `pop` وجود ندارد،
  /// پس بازگشت با یک callback به پوسته انجام می شود.
  static VoidCallback? onCancel;

  @override
  State<ExitPage> createState() => _ExitPageState();
}

class _ExitPageState extends State<ExitPage> {
  bool _busy = false;

  Future<void> _leave() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final VpnController vpn = context.read<VpnController>();
    try {
      // اتصال اول قطع می شود تا تنظیمات شبکه به حالت عادی برگردد و
      // کارت شبکه مجازی پاک شود؛ وگرنه بعد از خروج اینترنت کاربر خراب
      // می ماند.
      await vpn.shutdownForExit();
      await widget.onExit();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final SettingsController settings = context.watch<SettingsController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final bool connected = vpn.status.active;

    return Center(
      child: SingleChildScrollView(
        padding: AppMetrics.pagePadding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
          child: GlassCard(
            padding: AppMetrics.pagePadding,
            radius: AppMetrics.radiusXl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: IconSquare(
                    icon: Icons.logout_rounded,
                    color: colors.danger,
                    size: AppMetrics.iconBoxHero,
                  ),
                ),
                const SizedBox(height: AppMetrics.space4),
                Text(
                  Fa.num('از برنامه خارج می شوید؟'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppMetrics.space2),
                Text(
                  Fa.num(
                    connected
                        ? 'اتصال قطع می شود و تنظیمات شبکه به حالت عادی '
                            'برمی گردد، بعد برنامه بسته می شود.'
                        : 'برنامه بسته می شود.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.8,
                      ),
                ),
                const SizedBox(height: AppMetrics.space6),

                // ── بله / نه ──────────────────────────────────────────
                Row(
                  children: <Widget>[
                    Expanded(
                      child: GradientButton(
                        label: 'نه، بمان',
                        icon: Icons.close_rounded,
                        height: AppMetrics.controlHeightSmall,
                        tone: colors.surfaceHigh,
                        onPressed: _busy
                            ? null
                            : () {
                                ExitPage.onCancel?.call();
                              },
                      ),
                    ),
                    const SizedBox(width: AppMetrics.space3),
                    Expanded(
                      child: GradientButton(
                        label: 'بله، خارج شو',
                        icon: Icons.power_settings_new_rounded,
                        height: AppMetrics.controlHeightSmall,
                        tone: colors.danger,
                        loading: _busy,
                        onPressed: _busy ? null : _leave,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppMetrics.space4),

                // میانبر «بستن به سینی» جدا و کم رنگ می ماند تا با خروج
                // اشتباه نشود.
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          context.read<WindowService>().onWindowClose();
                          toasts.info('برنامه در سینی سیستم ماند');
                        },
                  icon: const Icon(Icons.minimize_rounded, size: AppMetrics.iconSm),
                  label: Text(Fa.num('فقط کوچک کن به سینی')),
                ),
                const SizedBox(height: AppMetrics.space2),
                Center(
                  child: Text(
                    Fa.num('${AppConfig.appName} | ${AppConfig.versionPhrase}'
                        '${settings.elevated ? ' | دسترسی مدیر' : ''}'),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
