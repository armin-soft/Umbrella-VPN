import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../vpn/speed_test.dart';
import '../../vpn/vpn_controller.dart';
import 'common.dart';

class SpeedTestCard extends StatelessWidget {
  const SpeedTestCard({super.key});
  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final SpeedTestResult? result = vpn.speedResult;
    final bool connected = vpn.status == VpnStatus.connected;
    return GlassCard(padding: AppMetrics.cardPadding, child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('سنجش مسیر اتصال', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppMetrics.space3),
        const Text('آزمون سرعت به کلادفلر: حدود ۴ مگابایت دریافت و ۲ مگابایت ارسال آزمایشی، به علاوه سربار شبکه. حجم از اشتراک کم می شود؛ فایل شخصی ارسال نمی شود. نتیجه نمونه برداری مسیر فعلی است، نه تضمین ظرفیت اینترنت.'),
        const SizedBox(height: AppMetrics.space3),
        if (vpn.speedTesting) ...<Widget>[
          const LinearProgressIndicator(),
          const SizedBox(height: AppMetrics.space2),
          Text(vpn.speedPhase == 'upload' ? 'اندازه گیری ارسال...' : 'اندازه گیری دریافت...'),
        ],
        if (result != null) ...<Widget>[
          InfoRow(stacked: false, icon: Icons.download_rounded, label: 'دریافت', value: '${Fa.decimal(result.download.megabitsPerSecond, fraction: 2)} مگابیت بر ثانیه'),
          InfoRow(stacked: false, icon: Icons.upload_rounded, label: 'ارسال', value: '${Fa.decimal(result.upload.megabitsPerSecond, fraction: 2)} مگابیت بر ثانیه'),
          Text('زمان سنجش: ${Fa.dateTime(result.measuredAt.toLocal())}'),
        ],
        if (vpn.speedError.isNotEmpty) Text(Fa.num(vpn.speedError), style: TextStyle(color: context.colors.warning)),
        const SizedBox(height: AppMetrics.space3),
        Wrap(spacing: AppMetrics.space3, runSpacing: AppMetrics.space2, children: <Widget>[
          FilledButton.icon(icon: const Icon(Icons.speed_rounded), label: const Text('شروع آزمایش با مصرف حدود ۶ مگابایت'),
            onPressed: connected && !vpn.speedTesting ? vpn.measureSpeed : null),
          if (vpn.speedTesting) OutlinedButton(onPressed: vpn.cancelSpeedTest, child: const Text('لغو آزمایش')),
        ]),
        const Divider(height: AppMetrics.space6),
        const Text('نشت دی ان اس: نتیجه ای ثبت نشده است. تایید اتصال امن و آزمایش سرعت، نبود نشت دی ان اس یا پوشش همه برنامه ها را ثابت نمی کنند. آزمایش مرورگر را در حالت تونل کامل VPN انجام دهید؛ مرورگر نباید از VPN مستثنی شده باشد. حالت فقط پروکسی، ترافیک سایر برنامه های گوشی را پوشش نمی دهد.'),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(
          icon: const Icon(Icons.open_in_new_rounded), label: const Text('آزمون مستقل دی ان اس در مرورگر'),
          onPressed: !connected ? null : () async {
            final bool opened = await launchUrl(Uri.parse('https://www.dnsleaktest.com/'), mode: LaunchMode.externalApplication);
            if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مرورگر باز نشد؛ صفحه آزمون نشت دی ان اس را دستی باز کنید.')));
          },
        )),
        const Text('این دکمه سرویس بیرونی را باز می کند و نشانی آی پی و دی ان اس اتصال شما در اختیار آن سرویس قرار می گیرد. آمبرلا نتیجه آن صفحه را خودکار تایید نمی کند.'),
      ],
    ));
  }
}
