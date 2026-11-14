import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../platform/services.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';
import '../widgets/content_control.dart';

/// تنظیمات: چیدمان دو ستونی، هر کارت یک موضوع روشن.
/// «کنترل محتوا» هم اینجا زندگی می کند.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onOpenAbout});

  final VoidCallback onOpenAbout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final AppSettings current = settings.settings;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            Fa.num('تنظیمات'),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            Fa.num('هر بخش یک موضوع؛ گزینه ها با یک نگاه خوانده می شوند.'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── ستون راست: ظاهر، کنترل محتوا، اتصال ─────────────────
              Expanded(
                child: Column(
                  children: <Widget>[
                    _Section(
                      icon: Icons.palette_rounded,
                      title: 'ظاهر برنامه',
                      subtitle: 'فونت وزیرمتن، چیدمان راست چین و جلوه مناسبت ها',
                      color: colors.primary,
                      children: <Widget>[
                        InfoRow(
                          icon: Icons.brightness_6_rounded,
                          label: 'تم روشن و تاریک',
                          value: 'از دکمه ماه و خورشید بالای پنجره',
                        ),
                        ToggleRow(
                          icon: Icons.auto_awesome_rounded,
                          title: 'جلوه مناسبت ها',
                          subtitle:
                              'شب یلدا، نوروز، چهارشنبه سوری و دیگر مناسبت ها',
                          value: current.occasionEffects,
                          onChanged: settings.setOccasionEffects,
                          accent: colors.warning,
                        ),
                        ToggleRow(
                          icon: Icons.volume_up_rounded,
                          title: 'صداهای برنامه',
                          subtitle: 'صدای اتصال، قطع و خطا با امکان خاموش کردن',
                          value: current.soundEnabled,
                          onChanged: settings.setSound,
                          accent: colors.info,
                        ),
                        ToggleRow(
                          icon: Icons.notifications_active_rounded,
                          title: 'اعلان ها',
                          subtitle: 'نمایش اعلان اتصال و خطا در گوشه ویندوز',
                          value: current.notificationsEnabled,
                          onChanged: settings.setNotifications,
                          accent: colors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const ContentControlCard(),
                    const SizedBox(height: 16),
                    _Section(
                      icon: Icons.shield_rounded,
                      title: 'اتصال و امنیت',
                      subtitle: 'رفتار برنامه در زمان اتصال',
                      color: colors.success,
                      children: <Widget>[
                        ToggleRow(
                          icon: Icons.lan_rounded,
                          title: 'حالت تونل (پیشنهاد شده)',
                          subtitle: 'سریع ترین و پایدارترین حالت: تمام '
                              'ترافیک از کارت شبکه مجازی رد می شود. اگر برنامه با '
                              'دسترسی مدیر اجرا نشود، خودکار با پروکسی سیستمی '
                              'وصل می شود',
                          value: current.tunMode,
                          onChanged: settings.setTunMode,
                          accent: colors.success,
                        ),
                        ToggleRow(
                          icon: Icons.terminal_rounded,
                          title: 'پنجره خط فرمان هسته',
                          subtitle: 'هنگام اتصال، پنجره خط فرمان هسته باز می شود و '
                              'گزارش زنده اتصال را نشان می دهد؛ همین پنجره پوششی '
                              'است که هسته پشت آن اجرا می شود',
                          value: current.showCli,
                          onChanged: settings.setShowCli,
                          accent: colors.textSecondary,
                        ),
                        ToggleRow(
                          icon: Icons.swap_horiz_rounded,
                          title: 'جابه جایی خودکار سرور',
                          subtitle: 'در صورت افت اتصال، سرور دیگری امتحان می شود',
                          value: current.autoFailover,
                          onChanged: settings.setAutoFailover,
                          accent: colors.info,
                        ),
                        ToggleRow(
                          icon: Icons.power_settings_new_rounded,
                          title: 'اتصال خودکار در اجرا',
                          subtitle: 'برنامه پس از باز شدن، خودکار وصل می شود',
                          value: current.autoConnect,
                          onChanged: settings.setAutoConnect,
                          accent: colors.warning,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ── ستون چپ: ویندوز، شبکه، حساب ─────────────────────────
              Expanded(
                child: Column(
                  children: <Widget>[
                    _Section(
                      icon: Icons.window_rounded,
                      title: 'ویندوز و سینی سیستم',
                      subtitle: 'نحوه اجرا و رفتار پنجره',
                      color: colors.info,
                      children: <Widget>[
                        ToggleRow(
                          icon: Icons.rocket_launch_rounded,
                          title: 'اجرای خودکار با ویندوز',
                          subtitle: 'ثبت برنامه در استارتاپ ویندوز',
                          value: current.startWithWindows,
                          onChanged: settings.setStartWithWindows,
                          accent: colors.primary,
                        ),
                        ToggleRow(
                          icon: Icons.close_fullscreen_rounded,
                          title: 'بستن به سینی سیستم',
                          subtitle:
                              'دکمه بستن پنجره را مخفی می کند، نه بستن برنامه',
                          value: current.closeToTray,
                          onChanged: settings.setCloseToTray,
                          accent: colors.textSecondary,
                        ),
                        ToggleRow(
                          icon: Icons.speed_rounded,
                          title: 'نمایش سرعت در سینی',
                          subtitle: 'نمایش سرعت لحظه ای در تولتیپ آیکون سینی',
                          value: current.showSpeedInTray,
                          onChanged: settings.setShowSpeedInTray,
                          accent: colors.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      icon: Icons.settings_backup_restore_rounded,
                      title: 'بازگردانی شبکه',
                      subtitle:
                          'اگر برنامه یا فیلترشکن دیگری تنظیمات شبکه را تغییر داد.',
                      color: colors.warning,
                      children: <Widget>[
                        const InfoRow(
                          icon: Icons.wifi_off_rounded,
                          label: 'پروکسی سیستمی ویندوز',
                          value: 'غیرفعال می شود',
                        ),
                        const Divider(height: 14),
                        const InfoRow(
                          icon: Icons.lan_outlined,
                          label: 'کارت شبکه مجازی',
                          value: 'بسته می شود',
                        ),
                        const Divider(height: 14),
                        const InfoRow(
                          icon: Icons.dns_outlined,
                          label: 'حافظه دی ان اس',
                          value: 'پاک می شود',
                        ),
                        const SizedBox(height: 12),
                        GradientButton(
                          label: 'بازگردانی تنظیمات شبکه',
                          icon: Icons.settings_backup_restore_rounded,
                          height: 44,
                          tone: colors.warning,
                          onPressed: () async {
                            await vpn.restoreNetwork();
                            toasts.success('تنظیمات شبکه بازگردانی شد');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      icon: Icons.person_rounded,
                      title: 'حساب و سرویس',
                      subtitle: 'کاربر، دسترسی و خروج',
                      color: colors.primary,
                      children: <Widget>[
                        InfoRow(
                          icon: Icons.person_rounded,
                          label: 'کاربر',
                          value: auth.account.displayName,
                        ),
                        const Divider(height: 14),
                        InfoRow(
                          icon: Icons.category_rounded,
                          label: 'نوع سرویس',
                          value: auth.account.planLabel,
                        ),
                        const Divider(height: 14),
                        InfoRow(
                          icon: Icons.verified_user_rounded,
                          label: 'دسترسی مدیر',
                          value: settings.elevated ? 'فعال' : 'غیرفعال',
                          valueColor:
                              settings.elevated ? colors.success : colors.warning,
                        ),
                        const SizedBox(height: 10),
                        if (!settings.elevated)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GradientButton(
                              label: 'اجرای دوباره با دسترسی مدیر',
                              icon: Icons.admin_panel_settings_rounded,
                              height: 44,
                              onPressed: () => settings.requestElevation(),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: widget.onOpenAbout,
                          icon: const Icon(Icons.info_outline_rounded, size: 17),
                          label: const Text('درباره برنامه و توسعه دهنده'),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              context.read<WindowService>().quit(),
                          icon: const Icon(
                            Icons.power_settings_new_rounded,
                            size: 17,
                          ),
                          label: Text(Fa.num('خروج کامل از برنامه')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              Fa.num(
                '${AppConfig.appName} | ${AppConfig.versionLabel} | ${AppConfig.developer}',
              ),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// کارت موضوعی تنظیمات: عنوان با آیکون رنگی و بدنه یکدست.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(icon: icon, color: color, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fa.num(title),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      Fa.num(subtitle),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
