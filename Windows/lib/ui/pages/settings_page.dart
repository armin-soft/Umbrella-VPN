import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';
import '../widgets/content_control.dart';
import '../widgets/network_settings.dart';

/// صفحه «تنظیمات»: چیدمان یکدست و ریسپانسیو هم تراز با سایر منوهای آمبرلا.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
            title: 'تنظیمات',
            subtitle: 'مدیریت اتصال، شبکه، ظاهر برنامه و رفتار ویندوز',
            icon: Icons.settings_rounded,
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نوار هویتی یکدست تنظیمات ─────────────────────────────────
          PageBanner(
            leading: IconSquare(
              icon: Icons.settings_rounded,
              color: colors.primary,
              size: AppMetrics.iconBoxHero,
              radius: AppMetrics.radiusLg,
            ),
            title: 'مرکز تنظیمات آمبرلا',
            subtitle: 'تمام تغییرات بلافاصله ذخیره می شوند',
            badges: <Widget>[
              Pill(
                label: vpn.status.active ? 'محافظت فعال' : 'آماده اتصال',
                icon: vpn.status.active
                    ? Icons.shield_rounded
                    : Icons.shield_outlined,
                color: vpn.status.active ? colors.success : colors.primary,
                dense: true,
              ),
              Pill(
                label: settings.elevated ? 'دسترسی مدیر فعال' : 'کاربر استاندارد',
                icon: settings.elevated
                    ? Icons.verified_user_rounded
                    : Icons.gpp_maybe_rounded,
                color: settings.elevated ? colors.success : colors.warning,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── دو ستون کاملاً متقارن و ریسپانسیو ─────────────────────────
          ResponsiveColumns(
            leftFlex: 1,
            rightFlex: 1,
            spacing: AppMetrics.space4,
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Section(
                  icon: Icons.shield_rounded,
                  title: 'اتصال و پایداری',
                  subtitle: 'رفتار هسته هنگام برقراری و حفظ اتصال',
                  children: <Widget>[
                    ToggleRow(
                      icon: Icons.lan_rounded,
                      title: 'حالت تونل کامل (پیشنهادی)',
                      subtitle:
                          'عبور تمام ترافیک سیستم از کارت شبکه مجازی آمبرلا',
                      value: current.tunMode,
                      onChanged: settings.setTunMode,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.swap_horiz_rounded,
                      title: 'جابه جایی خودکار سرور',
                      subtitle:
                          'سوییچ بی وقفه به سرور سالم در صورت افت کیفیت مسیر',
                      value: current.autoFailover,
                      onChanged: settings.setAutoFailover,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.lock_open_rounded,
                      title: 'آزادسازی خودکار پورت های هسته',
                      subtitle:
                          'بستن خودکار هسته های مزاحم پیش از شروع اتصال',
                      value: current.freeCorePorts,
                      onChanged: settings.setFreeCorePorts,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.power_settings_new_rounded,
                      title: 'اتصال خودکار در شروع برنامه',
                      subtitle: 'برقراری اتصال به محض باز شدن برنامه',
                      value: current.autoConnect,
                      onChanged: settings.setAutoConnect,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.terminal_rounded,
                      title: 'پنجره خط فرمان هسته',
                      subtitle: 'نمایش خروجی زنده هسته در یک پنجره جداگانه',
                      value: current.showCli,
                      onChanged: settings.setShowCli,
                    ),
                  ],
                ),
                const SizedBox(height: AppMetrics.space4),
                _Section(
                  icon: Icons.desktop_windows_rounded,
                  title: 'ظاهر و ویندوز',
                  subtitle: 'تم نمایش، اعلان ها و رفتار پنجره در سینی سیستم',
                  children: <Widget>[
                    InfoRow(
                      icon: isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      label: 'پوسته برنامه',
                      value: isDark ? 'تاریک' : 'روشن',
                      trailing: OutlinedButton(
                        onPressed: settings.toggleTheme,
                        child: Text(isDark ? 'تم روشن' : 'تم تاریک'),
                      ),
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.rocket_launch_rounded,
                      title: 'اجرای خودکار با ویندوز',
                      subtitle: 'اجرای برنامه هنگام روشن شدن سیستم',
                      value: current.startWithWindows,
                      onChanged: settings.setStartWithWindows,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.close_fullscreen_rounded,
                      title: 'بستن به سینی سیستم',
                      subtitle: 'فعال ماندن در کنار ساعت ویندوز هنگام بستن پنجره',
                      value: current.closeToTray,
                      onChanged: settings.setCloseToTray,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.speed_rounded,
                      title: 'نمایش سرعت در سینی سیستم',
                      subtitle: 'نمایش سرعت لحظه ای روی آیکون سینی ویندوز',
                      value: current.showSpeedInTray,
                      onChanged: settings.setShowSpeedInTray,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.notifications_active_rounded,
                      title: 'اعلان های ویندوز',
                      subtitle: 'نمایش پیام وضعیت اتصال و قطع در ویندوز',
                      value: current.notificationsEnabled,
                      onChanged: settings.setNotifications,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.volume_up_rounded,
                      title: 'صداهای برنامه',
                      subtitle: 'پخش افکت صوتی ملایم هنگام اتصال و قطع',
                      value: current.soundEnabled,
                      onChanged: settings.setSound,
                    ),
                    const Divider(height: AppMetrics.space2),
                    ToggleRow(
                      icon: Icons.auto_awesome_rounded,
                      title: 'جلوه مناسبت ها',
                      subtitle: 'نمایش پیام نوروز، یلدا و مناسبت های ویژه',
                      value: current.occasionEffects,
                      onChanged: settings.setOccasionEffects,
                    ),
                  ],
                ),
                const SizedBox(height: AppMetrics.space4),
                const ContentControlCard(),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _Section(
                  icon: Icons.dns_rounded,
                  title: 'شبکه و دی ان اس',
                  subtitle: 'پشته تونل، MTU، سرورهای دی ان اس و مسیریابی پیشرفته',
                  children: <Widget>[NetworkSettings()],
                ),
                const SizedBox(height: AppMetrics.space4),
                _Section(
                  icon: Icons.settings_backup_restore_rounded,
                  title: 'بازگردانی و دسترسی سیستم',
                  subtitle: 'تعمیر تنظیمات شبکه ویندوز و سطح دسترسی برنامه',
                  children: <Widget>[
                    InfoRow(
                      icon: Icons.person_rounded,
                      label: 'حساب فعال',
                      value: auth.account.displayName,
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.category_rounded,
                      label: 'نوع سرویس',
                      value: auth.account.planLabel,
                    ),
                    const Divider(height: AppMetrics.space2),
                    InfoRow(
                      icon: Icons.admin_panel_settings_rounded,
                      label: 'دسترسی مدیر ویندوز',
                      value: settings.elevated ? 'فعال' : 'غیرفعال',
                      valueColor:
                          settings.elevated ? colors.success : colors.warning,
                    ),
                    const Divider(height: AppMetrics.space2),
                    const InfoRow(
                      icon: Icons.cleaning_services_rounded,
                      label: 'بازگردانی شبکه',
                      value: 'پاک سازی پروکسی، تونل و کش دی ان اس',
                    ),
                    const SizedBox(height: AppMetrics.space4),
                    if (!settings.elevated) ...<Widget>[
                      GradientButton(
                        label: 'اجرای دوباره با دسترسی مدیر',
                        icon: Icons.admin_panel_settings_rounded,
                        height: AppMetrics.controlHeightSmall,
                        onPressed: () => settings.requestElevation(),
                      ),
                      const SizedBox(height: AppMetrics.space2),
                    ],
                    SizedBox(
                      height: AppMetrics.controlHeightSmall,
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.settings_backup_restore_rounded,
                          size: AppMetrics.iconMd,
                        ),
                        label: const Text('بازگردانی تنظیمات شبکه ویندوز'),
                        onPressed: () async {
                          await vpn.restoreNetwork();
                          toasts.success('تنظیمات شبکه بازگردانی شد');
                        },
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
}

/// کارت موضوعی تنظیمات با سرصفحه و جداکننده یکدست با سایر صفحات.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
          ),
          const Divider(height: AppMetrics.space5),
          ...children,
        ],
      ),
    );
  }
}
