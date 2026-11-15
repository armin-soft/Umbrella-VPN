import 'dart:async';

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

/// منوی «خروج» — از تنظیمات جدا شد.
///
/// پیش از این دکمه «خروج کامل» ته کارت «حساب و سرویس» در تنظیمات بود؛ جایی که
/// کاربر دنبالش نمی گشت و خطرش هم بالا بود. حالا یک بخش مستقل در انتهای نوار
/// کناری است، با گزینه های روشن و توضیح هرکدام.
class ExitPage extends StatefulWidget {
  const ExitPage({super.key, required this.onExit, required this.onCloseWindow});

  /// بستن کامل برنامه (پروسه پایان می یابد).
  final Future<void> Function() onExit;

  /// بستن پنجره و ماندن در سینی سیستم.
  final Future<void> Function() onCloseWindow;

  @override
  State<ExitPage> createState() => _ExitPageState();
}

class _ExitPageState extends State<ExitPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                Fa.num('خروج'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                Fa.num('انتخاب کنید برنامه چطور بسته شود.'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 18),

              // وضعیت فعلی، تا کاربر بداند خروج یعنی چه.
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: <Widget>[
                    IconSquare(
                      icon: connected
                          ? Icons.shield_rounded
                          : Icons.shield_outlined,
                      color: connected ? colors.success : colors.textSecondary,
                      size: 40,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            Fa.num(
                              connected
                                  ? 'در حال حاضر متصل هستید'
                                  : 'در حال حاضر قطع هستید',
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Fa.num(
                              connected
                                  ? 'با خروج، اتصال بسته و تنظیمات شبکه به حالت '
                                      'عادی برمی گردد.'
                                  : 'اتصالی برای بستن نیست.',
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
              ),
              const SizedBox(height: 16),

              _ExitOption(
                icon: Icons.minimize_rounded,
                title: 'کوچک کردن به سینی سیستم',
                subtitle: settings.settings.closeToTray
                    ? 'اتصال باز می ماند و برنامه در سینی ویندوز فعال می ماند.'
                    : 'پنجره بسته می شود ولی برنامه در سینی می ماند.',
                tone: colors.info,
                label: 'کوچک کن',
                busy: _busy,
                onTap: () => _run(() async {
                  await widget.onCloseWindow();
                }),
              ),
              const SizedBox(height: 12),
              _ExitOption(
                icon: Icons.link_off_rounded,
                title: 'قطع اتصال',
                subtitle: 'تونل بسته و تنظیمات شبکه بازگردانی می شود؛ برنامه '
                    'باز می ماند.',
                tone: colors.warning,
                label: 'قطع کن',
                busy: _busy || !connected,
                onTap: () => _run(() async {
                  await vpn.disconnect();
                  toasts.info('اتصال قطع شد');
                }),
              ),
              const SizedBox(height: 12),
              _ExitOption(
                icon: Icons.logout_rounded,
                title: 'خروج کامل از برنامه',
                subtitle: 'اتصال قطع می شود و برنامه کاملا بسته می شود.',
                tone: colors.danger,
                label: 'خروج',
                busy: _busy,
                danger: true,
                onTap: () => _run(() async {
                  await vpn.disconnect(silent: true);
                  await widget.onExit();
                }),
              ),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  Fa.num('${AppConfig.appName} | ${AppConfig.versionPhrase}'),
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
    );
  }
}

class _ExitOption extends StatelessWidget {
  const _ExitOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.label,
    required this.busy,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tone;
  final String label;
  final bool busy;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // در پنجره باریک، دکمه زیر متن می رود نه کنارش.
          final bool narrow = constraints.maxWidth < 430;
          final Widget info = Row(
            children: <Widget>[
              IconSquare(icon: icon, color: tone, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fa.num(title),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Fa.num(subtitle),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          );
          final Widget button = GradientButton(
            label: label,
            icon: danger ? Icons.power_settings_new_rounded : null,
            height: 42,
            expand: false,
            tone: tone,
            loading: busy,
            onPressed: busy ? null : onTap,
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                info,
                const SizedBox(height: 12),
                button,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: info),
              const SizedBox(width: 14),
              button,
            ],
          );
        },
      ),
    );
  }
}
