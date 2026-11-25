import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/safe_url_launcher.dart';
import '../../core/theme.dart';
import '../../data/gateway_client.dart';
import '../widgets/common.dart';
import '../widgets/telegram_channel_dialog.dart';

/// صفحه «درباره»: معرفی برنامه، راه های ارتباطی و بررسی درگاه سرویس با ساختار
/// کاملاً یکدست با منوهای دستگاه من، حساب من و تنظیمات.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'درباره',
            eyebrow: 'درباره آمبرلا',
            premium: true,
            subtitle: 'مشخصات نسخه، راه های ارتباط با پشتیبانی و بررسی دسترسی',
            icon: Icons.info_rounded,
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── دو کارت هم اندازه و هم تراز: ارتباط و پشتیبانی | نسخه و بررسی ──
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget developer = _DeveloperCard(colors: colors);
              final Widget check = _AccessCheckCard(colors: colors);
              if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) < AppMetrics.breakpointColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    developer,
                    const SizedBox(height: AppMetrics.space4),
                    check,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: developer),
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(child: check),
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

/// کارت توسعه دهنده و راه های رسمی ارتباط و پشتیبانی.
class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({required this.colors});

  final UmbrellaColors colors;

  Future<void> _open(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri != null) {
      await SafeUrlLauncher.open(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.support_agent_rounded,
            title: AppConfig.developer,
            subtitle: 'پشتیبانی، اطلاع رسانی و ارتباط رسمی',
            trailing: Icon(
              Icons.verified_rounded,
              size: AppMetrics.iconMd,
              color: colors.primary,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.public_rounded,
            label: 'وبسایت رسمی',
            value: 'درگاه رسمی آرمین سافت',
            onTap: () => _open(AppConfig.developerSite),
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.headset_mic_rounded,
            label: 'پشتیبانی تلگرام',
            value: 'پشتیبانی رسمی آمبرلا',
            onTap: () => _open(AppConfig.supportUrl),
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.telegram,
            label: 'کانال اطلاع رسانی',
            value: AppConfig.channelHandle,
            ltr: true,
            technicalValue: true,
            onTap: () => unawaited(TelegramChannelPrompt.openChannel()),
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.smart_toy_rounded,
            label: 'ربات تلگرام',
            value: 'ربات رسمی آمبرلا',
            onTap: () => _open('https://t.me/${AppConfig.botUsername}'),
          ),
        ],
      ),
    );
  }
}

/// کارت مشخصات انتشار و بررسی دسترسی به درگاه سرویس.
class _AccessCheckCard extends StatelessWidget {
  const _AccessCheckCard({required this.colors});

  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
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
              const SectionHeader(
                icon: Icons.network_check_rounded,
                title: 'نسخه و بررسی دسترسی',
                subtitle: 'مشخصات انتشار و سنجش ارتباط مستقیم با درگاه سرویس',
              ),
              const Divider(height: AppMetrics.space5),
              InfoRow(
                icon: Icons.tag_rounded,
                label: 'نسخه نصب شده',
                value: Fa.num(AppConfig.version),
              ),
              const Divider(height: AppMetrics.space2),
              const InfoRow(
                icon: Icons.desktop_windows_rounded,
                label: 'سیستم عامل هدف',
                value: 'ویندوز ۱۰ و ۱۱ (۶۴ بیت)',
              ),
              const Divider(height: AppMetrics.space2),
              const InfoRow(
                icon: Icons.cloud_done_rounded,
                label: 'محدوده بررسی',
                value: 'پاسخگویی درگاه حساب و اشتراک',
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: AppMetrics.space4),
            child: _PingTestButton(),
          ),
        ],
      ),
    );
  }
}

class _PingTestButton extends StatefulWidget {
  const _PingTestButton();

  @override
  State<_PingTestButton> createState() => _PingTestButtonState();
}

class _PingTestButtonState extends State<_PingTestButton> {
  bool _running = false;
  String _result = '';
  bool _ok = false;

  Future<void> _run() async {
    if (_running) {
      return;
    }
    setState(() {
      _running = true;
      _result = '';
    });
    final Stopwatch watch = Stopwatch()..start();
    bool ok = false;
    try {
      ok = await GatewayClient().ping();
    } on Exception {
      ok = false;
    }
    watch.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _ok = ok;
      _result = ok
          ? 'درگاه سرویس در دسترس است (${Fa.ms(watch.elapsedMilliseconds)})'
          : 'درگاه پاسخ نداد؛ اتصال اینترنت خود را بررسی کنید.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color statusColor = _ok ? colors.success : colors.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_result.isNotEmpty) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.space3,
              vertical: AppMetrics.space2,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
              border: Border.all(color: statusColor.withValues(alpha: 0.32)),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  _ok ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: AppMetrics.iconSm,
                  color: statusColor,
                ),
                const SizedBox(width: AppMetrics.space2),
                Expanded(
                  child: Text(
                    Fa.num(_result),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppMetrics.space3),
        ],
        GradientButton(
          label: 'بررسی اتصال به سرور',
          icon: Icons.wifi_tethering_rounded,
          height: AppMetrics.controlHeightSmall,
          loading: _running,
          onPressed: _running ? null : _run,
        ),
      ],
    );
  }
}
