import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../data/gateway_client.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';

/// درباره برنامه و توسعه دهنده.
///
/// چیدمان پیشین چند کارت جزئیات فنی داشت که به کاربر عادی چیزی نمی گفت و
/// صفحه را شلوغ می کرد. حالا سه بخش روشن است: معرفی برنامه، توسعه دهنده با
/// لوگو، و بررسی دسترسی. بررسی اتصال هم که ته صفحه گم شده بود، جای مشخص
/// خودش را در کارت بررسی دارد.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Hero(colors: colors),
              const SizedBox(height: 16),
              // در پنجره باریک کارت ها زیر هم می روند، نه کنار هم.
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool narrow = constraints.maxWidth < 640;
                  final Widget developer = _DeveloperCard(colors: colors);
                  final Widget check = _AccessCheckCard(colors: colors);
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        developer,
                        const SizedBox(height: 16),
                        check,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: developer),
                      const SizedBox(width: 16),
                      Expanded(child: check),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  Fa.num(
                    'تمام حقوق محفوظ است. استفاده از برنامه به معنای پذیرش '
                    'شرایط سرویس آمبرلا است.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.8,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.colors});

  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(26),
      radius: 24,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: <Color>[
          colors.primary.withValues(alpha: 0.18),
          colors.surface,
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 480;
          final Widget mark = const BrandMark(size: 78, showTitle: false);
          final Widget text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                Fa.num(AppConfig.appName),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                Fa.num('نسخه ${AppConfig.version}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
              const SizedBox(height: 9),
              Text(
                Fa.num(
                  'فیلترشکن آمبرلا یک کلاینت ویندوزی کامل است: تونل کامل دستگاه، '
                  'انتخاب خودکار پایدارترین سرور، کیل سوییچ، و رابط فارسی '
                  'راست چین.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.9,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const <Widget>[
                  Pill(label: 'ویندوز ۱۰ و ۱۱', icon: Icons.window_rounded),
                  Pill(label: 'نسخه ۶۴ بیت', icon: Icons.memory_rounded),
                  Pill(label: 'تونل کامل', icon: Icons.lock_rounded),
                ],
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                mark,
                const SizedBox(height: 14),
                text,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              mark,
              const SizedBox(width: 22),
              Expanded(child: text),
            ],
          );
        },
      ),
    );
  }
}

/// کارت توسعه دهنده: لوگوی سازنده، راه های ارتباط و بررسی اتصال.
class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({required this.colors});

  final UmbrellaColors colors;

  Future<void> _open(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── لوگوی توسعه دهنده ────────────────────────────────────────
          Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: <Color>[
                      colors.primary.withValues(alpha: 0.28),
                      colors.primary.withValues(alpha: 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.35),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  BrandAssets.logo,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error,
                          StackTrace? stack) =>
                      Icon(
                    Icons.verified_rounded,
                    size: 28,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fa.num(AppConfig.developer),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Fa.num('پشتیبانی، پیشنهاد و گزارش خطا'),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.verified_rounded,
                size: 20,
                color: colors.primary.withValues(alpha: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InfoRow(
            icon: Icons.public_rounded,
            label: 'وبسایت',
            value: AppConfig.developerSite,
            onTap: () => _open(AppConfig.developerSite),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.support_agent_rounded,
            label: 'پشتیبانی',
            value: '@UmbrellaSupport',
            onTap: () => _open(AppConfig.supportUrl),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.campaign_rounded,
            label: 'کانال',
            value: '@UmbrellaChannel',
            onTap: () => _open(AppConfig.channelUrl),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.smart_toy_rounded,
            label: 'ربات تلگرام',
            value: '@${AppConfig.botUsername}',
            onTap: () => _open('https://t.me/${AppConfig.botUsername}'),
          ),
        ],
      ),
    );
  }
}

/// بررسی دسترسی به سرور سرویس.
///
/// پیش از این دکمه «بررسی اتصال به سرور» ته صفحه و جدا از هر چیزی بود؛ حالا
/// کارت مستقل خودش را دارد با توضیح روشن که چه چیزی سنجیده می شود.
class _AccessCheckCard extends StatelessWidget {
  const _AccessCheckCard({required this.colors});

  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: Icons.network_check_rounded,
                color: colors.info,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fa.num('بررسی دسترسی'),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      Fa.num('آیا سرور سرویس از این شبکه در دسترس است؟'),
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
          const SizedBox(height: 16),
          const _PingTestButton(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded,
                    size: 15, color: colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Fa.num(
                      'این بررسی فقط دسترسی به درگاه را می سنجد، نه اتصال VPN را.',
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.textSecondary, height: 1.6),
                  ),
                ),
              ],
            ),
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
          ? 'درگاه در دسترس است (${Fa.ms(watch.elapsedMilliseconds)})'
          : 'درگاه پاسخ نداد؛ شبکه یا فیلتر را بررسی کنید.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GradientButton(
          label: 'بررسی اتصال به سرور',
          icon: Icons.wifi_tethering_rounded,
          height: 44,
          tone: colors.info,
          loading: _running,
          onPressed: _running ? null : _run,
        ),
        if (_result.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                _ok ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 16,
                color: _ok ? colors.success : colors.danger,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  Fa.num(_result),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _ok ? colors.success : colors.danger,
                        height: 1.6,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
