import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../platform/services.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// گفت و گوی تایید خروج و توقف سرویس VPN در اندروید.
class ExitPage extends StatefulWidget {
  const ExitPage({
    super.key,
    required this.onExit,
    this.onCancelTap,
  });

  final Future<void> Function() onExit;
  final VoidCallback? onCancelTap;

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
    final WindowService? window = context.read<WindowService?>();
    final UmbrellaColors colors = context.colors;
    final bool connected = vpn.status.active;

    return Center(
      child: SingleChildScrollView(
        padding: AppMetrics.responsivePagePadding(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
          child: GlassCard(
            padding: AppMetrics.responsivePagePadding(context),
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
                                (widget.onCancelTap ?? ExitPage.onCancel)?.call();
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
                if (connected) ...<Widget>[
                  const SizedBox(height: AppMetrics.space3),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            (widget.onCancelTap ?? ExitPage.onCancel)?.call();
                            window?.hide();
                          },
                    icon: const Icon(
                      Icons.layers_rounded,
                      size: AppMetrics.iconSm,
                    ),
                    label: Text(Fa.num('انتقال به پس زمینه (اتصال بماند)')),
                  ),
                ],
                const SizedBox(height: AppMetrics.space2),
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
      ),
    );
  }
}
