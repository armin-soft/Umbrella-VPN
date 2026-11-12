import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../data/gateway_client.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';

/// درباره برنامه و توسعه دهنده.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassCard(
            padding: const EdgeInsets.all(28),
            radius: 26,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                colors.primary.withValues(alpha: 0.18),
                colors.surface,
              ],
            ),
            child: Row(
              children: <Widget>[
                const BrandMark(size: 84, showTitle: false),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        Fa.num(AppConfig.appName),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        Fa.num('نسخه ${AppConfig.version} | نسخه بیلد ${Fa.num(AppConfig.buildNumber)}'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        Fa.num(
                          'فیلترشکن آمبرلا یک کلاینت ویندوزی تمام عیار است: تونل کامل دستگاه، پنج هسته اتصال، انتخاب خودکار پایدارترین سرور، کیل سوییچ، ورود پیامکی با تایید تلگرام و رابط فارسی راست چین با فونت وزیرمتن.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.9,
                            ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Pill(label: 'ویندوز ۱۰ و ۱۱', icon: Icons.window_rounded),
                          Pill(label: 'نسخه ۶۴ بیت', icon: Icons.memory_rounded),
                          Pill(label: 'فلاتر', icon: Icons.flutter_dash),
                          Pill(label: 'تونل کامل', icon: Icons.lock_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'توسعه دهنده',
                        subtitle: 'پشتیبانی، پیشنهاد و گزارش خطا',
                      ),
                      const SizedBox(height: 12),
                      InfoRow(
                        icon: Icons.business_rounded,
                        label: 'شرکت',
                        value: AppConfig.company,
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.public_rounded,
                        label: 'وبسایت',
                        value: AppConfig.developerSite,
                        onTap: () => _open(AppConfig.developerSite),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.support_agent_rounded,
                        label: 'پشتیبانی تلگرام',
                        value: '@UmbrellaSupport',
                        onTap: () => _open(AppConfig.supportUrl),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.campaign_rounded,
                        label: 'کانال اطلاع رسانی',
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
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'اجزای فنی',
                        subtitle: 'ساخته شده با فناوری های نسل جدید',
                      ),
                      const SizedBox(height: 12),
                      for (final (IconData icon, String title, String value)
                          row in <(IconData, String, String)>[
                        (Icons.flutter_dash, 'رابط کاربری', 'فلاتر نسخه ۳ با متریال ۳'),
                        (Icons.memory_rounded, 'پل بومی', 'سی پلاس پلاس بهینه برای ویندوز'),
                        (Icons.shield_rounded, 'تونل', 'هسته سینگ باکس با درایور وین تون'),
                        (Icons.hub_rounded, 'پروتکل ها', 'وی لس، وی مس، تروجان، شادوساکس، وایرگارد، آمنزیا، میرو، هیستریا و توئیک'),
                        (Icons.security_rounded, 'امنیت', 'کیل سوییچ با سیاست خروجی ویندوز فایروال'),
                        (Icons.sms_rounded, 'ورود', 'پیامک الگویی آی پی پنل و تایید تلگرام'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: <Widget>[
                              Icon(row.$1, size: 16, color: colors.primary),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 84,
                                child: Text(
                                  Fa.num(row.$2),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  Fa.num(row.$3),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: colors.textPrimary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(title: 'سرویس های متصل'),
                      const SizedBox(height: 10),
                      InfoRow(
                        icon: Icons.cloud_rounded,
                        label: 'درگاه برنامه',
                        value: Uri.tryParse(AppConfig.gatewayBase)?.host ?? 'نامشخص',
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.dns_rounded,
                        label: 'پنل وب سرویس',
                        value: Uri.tryParse(AppConfig.panelBase)?.host ?? 'نامشخص',
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.link_rounded,
                        label: 'اشتراک کاربری',
                        value: 'به صورت خودکار از درگاه خوانده می شود',
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.backup_rounded,
                        label: 'منابع پشتیبان',
                        value: '${Fa.num(AppConfig.subscriptionSources.length)} منبع عمومی',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        Fa.num(
                          'نشانی اشتراک هر کاربر را سرور می دهد و برنامه خودش آن را می خواند؛ هیچ نشانی دستی وارد نمی شود. منابع عمومی فقط پشتیبان هستند.',
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.8,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(title: 'تست سرویس'),
                      const SizedBox(height: 10),
                      Text(
                        Fa.num('برای اطمینان از دسترسی به درگاه، یک بار بررسی کنید.'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 14),
                      _PingTestButton(),
                      const SizedBox(height: 16),
                      Text(
                        Fa.num(
                          'تمام حقوق محفوظ است. استفاده از برنامه به معنای پذیرش شرایط سرویس آمبرلا است.',
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.8,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _PingTestButton extends StatefulWidget {
  @override
  State<_PingTestButton> createState() => _PingTestButtonState();
}

class _PingTestButtonState extends State<_PingTestButton> {
  String _result = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GradientButton(
          label: 'بررسی اتصال به سرور',
          icon: Icons.network_check_rounded,
          height: 46,
          loading: _busy,
          onPressed: _busy
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _result = '';
                  });
                  final bool ok = await GatewayClient().ping();
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _busy = false;
                    _result = ok
                        ? 'ارتباط با سرور آمبرلا برقرار است.'
                        : 'ارتباط برقرار نشد؛ اینترنت یا نشانی درگاه را بررسی کنید.';
                  });
                },
        ),
        if (_result.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                _result.startsWith('ارتباط با') ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 16,
                color: _result.startsWith('ارتباط با') ? colors.success : colors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Fa.num(_result),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
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
