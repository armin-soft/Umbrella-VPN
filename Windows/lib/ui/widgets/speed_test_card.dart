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
        const Text('آزمون سرعت به Cloudflare: حدود ۴ مگابایت دانلود و ۲ مگابایت آپلود آزمایشی، به‌علاوه سربار شبکه. حجم از اشتراک کم می‌شود؛ فایل شخصی ارسال نمی‌شود. نتیجه نمونه‌برداری مسیر فعلی است، نه تضمین ظرفیت اینترنت.'),
        const SizedBox(height: AppMetrics.space3),
        if (vpn.speedTesting) ...<Widget>[
          const LinearProgressIndicator(),
          const SizedBox(height: AppMetrics.space2),
          Text(vpn.speedPhase == 'upload' ? 'اندازه‌گیری آپلود…' : 'اندازه‌گیری دانلود…'),
        ],
        if (result != null) ...<Widget>[
          InfoRow(icon: Icons.download_rounded, label: 'دانلود', value: '${Fa.num(result.download.megabitsPerSecond.toStringAsFixed(2))} Mbps'),
          InfoRow(icon: Icons.upload_rounded, label: 'آپلود', value: '${Fa.num(result.upload.megabitsPerSecond.toStringAsFixed(2))} Mbps'),
          Text('زمان سنجش: ${Fa.num(result.measuredAt.toLocal().toString().split('.').first)}'),
        ],
        if (vpn.speedError.isNotEmpty) Text(vpn.speedError, style: TextStyle(color: context.colors.warning)),
        const SizedBox(height: AppMetrics.space3),
        Wrap(spacing: AppMetrics.space3, runSpacing: AppMetrics.space2, children: <Widget>[
          FilledButton.icon(icon: const Icon(Icons.speed_rounded), label: const Text('شروع تست با مصرف حدود ۶ MB'),
            onPressed: connected && !vpn.speedTesting ? vpn.measureSpeed : null),
          if (vpn.speedTesting) OutlinedButton(onPressed: vpn.cancelSpeedTest, child: const Text('لغو تست')),
        ]),
        const Divider(height: AppMetrics.space6),
        const Text('نشت DNS: نتیجه‌ای ثبت نشده است. تأیید HTTPS و تست سرعت، نبود نشت DNS یا پوشش همه برنامه‌ها را ثابت نمی‌کنند. آزمایش مرورگر را در حالت تونل انجام دهید؛ مرورگر نباید قانون «مستقیم» داشته باشد. حالت پروکسی سیستمی همه DNS ویندوز را پوشش نمی‌دهد.'),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(
          icon: const Icon(Icons.open_in_new_rounded), label: const Text('آزمون مستقل DNS در مرورگر'),
          onPressed: !connected ? null : () async {
            final bool opened = await launchUrl(Uri.parse('https://www.dnsleaktest.com/'), mode: LaunchMode.externalApplication);
            if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مرورگر باز نشد؛ dnsleaktest.com را دستی باز کنید.')));
          },
        )),
        const Text('این دکمه سرویس بیرونی را باز می‌کند و IP/DNS اتصال شما در اختیار آن سرویس قرار می‌گیرد. آمبرلا نتیجه آن صفحه را خودکار تأیید نمی‌کند.'),
      ],
    ));
  }
}
