import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';
import '../widgets/content_control.dart';
import '../widgets/network_settings.dart';

enum _SettingsSectionTab {
  connection,
  network,
  appearance,
  content,
}

/// صفحه پیشرفته، خلوت و دسته بندی شده تنظیمات آمبرلا.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsSectionTab _activeTab = _SettingsSectionTab.connection;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final SettingsController settings = context.watch<SettingsController>();
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    final AppSettings current = settings.settings;

    final int advancedBadge = (current.chain.enabled ? 1 : 0) +
        current.appRoutes.where((AppRouteRule r) => r.enabled).length;
    final int filterBadge =
        auth.filter.enabled ? auth.filter.categories.length : 0;

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
            title: 'تنظیمات',
            subtitle:
                'شخصی سازی رفتار اتصال، شبکه و دی ان اس، پوسته برنامه و فیلتر محتوا',
            icon: Icons.settings_rounded,
          ),
          const SizedBox(height: AppMetrics.space4),
          PageBanner(
            icon: Icons.tune_rounded,
            accent: colors.primary,
            title: 'مرکز کنترل پیشرفته آمبرلا',
            subtitle:
                'تغییرات به صورت خودکار ذخیره می شوند؛ هر بخش را از نوار زیر انتخاب کنید.',
            badges: <Widget>[
              StatusBadge(
                label: current.tunMode ? 'تونل کامل فعال' : 'پروکسی سیستمی',
                color: current.tunMode ? colors.success : colors.info,
              ),
              StatusBadge(
                label: settings.elevated ? 'دسترسی مدیر فعال' : 'کاربر استاندارد',
                color: settings.elevated ? colors.success : colors.warning,
              ),
              StatusBadge(
                label: 'پوسته ${current.theme.label}',
                color: colors.primary,
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          _SettingsTabBar(
            active: _activeTab,
            networkBadge: advancedBadge,
            contentBadge: filterBadge,
            onSelect: (_SettingsSectionTab next) {
              if (_activeTab != next) {
                setState(() => _activeTab = next);
              }
            },
          ),
          const SizedBox(height: AppMetrics.space5),
          _buildActiveSection(
            context: context,
            colors: colors,
            settings: settings,
            current: current,
            vpn: vpn,
            auth: auth,
            toasts: toasts,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSection({
    required BuildContext context,
    required UmbrellaColors colors,
    required SettingsController settings,
    required AppSettings current,
    required VpnController vpn,
    required AuthController auth,
    required ToastController toasts,
  }) {
    switch (_activeTab) {
      case _SettingsSectionTab.connection:
        return ResponsiveColumns(
          leftFlex: 6,
          rightFlex: 5,
          spacing: AppMetrics.space5,
          left: _Section(
            icon: Icons.shield_rounded,
            title: 'اتصال و پایداری هسته',
            subtitle: 'نحوه برقراری تونل، پایش سلامت و مدیریت خودکار پورت ها',
            children: <Widget>[
              ToggleRow(
                icon: Icons.lan_rounded,
                title: 'حالت تونل کامل (پیشنهادی)',
                subtitle: 'عبور تمام برنامه ها و بازی ها از کارت شبکه امن آمبرلا',
                value: current.tunMode,
                onChanged: settings.setTunMode,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.swap_horiz_rounded,
                title: 'جابه جایی خودکار مسیر',
                subtitle: 'انتقال بی وقفه به مسیر سالم در صورت افت کیفیت اتصال',
                value: current.autoFailover,
                onChanged: settings.setAutoFailover,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.lock_open_rounded,
                title: 'آزادسازی خودکار پورت های هسته',
                subtitle: 'بستن خودکار فرایندهای مزاحم پیش از شروع هر اتصال',
                value: current.freeCorePorts,
                onChanged: settings.setFreeCorePorts,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.power_settings_new_rounded,
                title: 'اتصال خودکار در شروع برنامه',
                subtitle: 'برقراری فوری اتصال امن به محض باز شدن آمبرلا',
                value: current.autoConnect,
                onChanged: settings.setAutoConnect,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.terminal_rounded,
                title: 'پنجره خط فرمان هسته',
                subtitle: 'نمایش کنسول اجرایی هسته در یک پنجره جداگانه برای عیب یابی',
                value: current.showCli,
                onChanged: settings.setShowCli,
              ),
            ],
          ),
          right: _Section(
            icon: Icons.admin_panel_settings_rounded,
            title: 'دسترسی سیستم و تعمیر شبکه',
            subtitle: 'وضعیت حساب، سطح دسترسی ویندوز و بازنشانی تنظیمات شبکه',
            children: <Widget>[
              InfoRow(
                icon: Icons.person_rounded,
                label: 'حساب فعال',
                value: auth.account.displayName,
              ),
              const Divider(height: AppMetrics.space3),
              InfoRow(
                icon: Icons.workspace_premium_rounded,
                label: 'نوع اشتراک',
                value: auth.account.planLabel,
              ),
              const Divider(height: AppMetrics.space3),
              InfoRow(
                icon: Icons.verified_user_rounded,
                label: 'دسترسی مدیر ویندوز',
                value: settings.elevated ? 'فعال و آماده تونل' : 'نیازمند ارتقا',
                valueColor: settings.elevated ? colors.success : colors.warning,
              ),
              const SizedBox(height: AppMetrics.space5),
              Container(
                padding: const EdgeInsets.all(AppMetrics.space4),
                decoration: BoxDecoration(
                  color: colors.surfaceHigh.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.build_circle_outlined,
                          size: AppMetrics.iconMd,
                          color: colors.primary,
                        ),
                        const SizedBox(width: AppMetrics.space2),
                        Expanded(
                          child: Text(
                            'تعمیر سریع شبکه ویندوز',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppMetrics.space2),
                    Text(
                      'در صورت اختلال در اینترنت سیستم، پروکسی ویندوز، کارت تونل و حافظه دی ان اس به حالت استاندارد برمی گردند.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.6,
                          ),
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
              ),
            ],
          ),
        );

      case _SettingsSectionTab.network:
        return _Section(
          icon: Icons.dns_rounded,
          title: 'شبکه، دی ان اس و مسیریابی پیشرفته',
          subtitle:
              'تنظیم دقیق پشته تونل، اندازه بسته، سرورهای دی ان اس، زنجیره WARP و تفکیک برنامه ها',
          trailing: SizedBox(
            height: AppMetrics.controlHeightSmall,
            child: OutlinedButton.icon(
              icon: const Icon(
                Icons.settings_backup_restore_rounded,
                size: AppMetrics.iconSm,
              ),
              label: const Text('تعمیر شبکه'),
              onPressed: () async {
                await vpn.restoreNetwork();
                toasts.success('تنظیمات شبکه بازگردانی شد');
              },
            ),
          ),
          children: const <Widget>[NetworkSettings()],
        );

      case _SettingsSectionTab.appearance:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Section(
              icon: Icons.palette_rounded,
              title: 'پوسته و رنگ بندی برنامه',
              subtitle:
                  'ظاهر مورد علاقه خود را انتخاب کنید؛ تغییر پوسته بلافاصله اعمال می شود',
              children: <Widget>[
                _ThemeCardSelector(
                  selected: current.theme,
                  onChanged: settings.setTheme,
                ),
              ],
            ),
            const SizedBox(height: AppMetrics.space5),
            ResponsiveColumns(
              leftFlex: 1,
              rightFlex: 1,
              spacing: AppMetrics.space5,
              left: _Section(
                icon: Icons.desktop_windows_rounded,
                title: 'پنجره و سینی ویندوز',
                subtitle: 'نحوه اجرا در شروع ویندوز و رفتار آیکون کنار ساعت',
                children: <Widget>[
                  ToggleRow(
                    icon: Icons.rocket_launch_rounded,
                    title: 'اجرای خودکار با ویندوز',
                    subtitle: 'باز شدن خودکار آمبرلا پس از ورود به ویندوز',
                    value: current.startWithWindows,
                    onChanged: settings.setStartWithWindows,
                  ),
                  const Divider(height: AppMetrics.space3),
                  ToggleRow(
                    icon: Icons.close_fullscreen_rounded,
                    title: 'بستن به سینی سیستم',
                    subtitle: 'فعال ماندن اتصال در کنار ساعت هنگام بستن پنجره',
                    value: current.closeToTray,
                    onChanged: settings.setCloseToTray,
                  ),
                  const Divider(height: AppMetrics.space3),
                  ToggleRow(
                    icon: Icons.speed_rounded,
                    title: 'نمایش سرعت در سینی سیستم',
                    subtitle: 'نمایش سرعت زنده دریافت و ارسال روی آیکون سینی',
                    value: current.showSpeedInTray,
                    onChanged: settings.setShowSpeedInTray,
                  ),
                ],
              ),
              right: _Section(
                icon: Icons.notifications_active_rounded,
                title: 'اعلان ها، صدا و جلوه ها',
                subtitle: 'مدیریت پیام های ویندوز، بازخورد صوتی و مناسبت ها',
                children: <Widget>[
                  ToggleRow(
                    icon: Icons.notifications_rounded,
                    title: 'اعلان های ویندوز',
                    subtitle: 'نمایش اعلان هنگام برقراری و قطع اتصال یا پیام جدید',
                    value: current.notificationsEnabled,
                    onChanged: settings.setNotifications,
                  ),
                  const Divider(height: AppMetrics.space3),
                  ToggleRow(
                    icon: Icons.volume_up_rounded,
                    title: 'صداهای برنامه',
                    subtitle: 'پخش افکت صوتی ملایم هنگام اتصال، قطع و اعلان',
                    value: current.soundEnabled,
                    onChanged: settings.setSound,
                  ),
                  const Divider(height: AppMetrics.space3),
                  ToggleRow(
                    icon: Icons.auto_awesome_rounded,
                    title: 'جلوه مناسبت ها',
                    subtitle: 'نمایش پیام های ویژه نوروز، یلدا و مناسبت ها',
                    value: current.occasionEffects,
                    onChanged: settings.setOccasionEffects,
                  ),
                ],
              ),
            ),
          ],
        );

      case _SettingsSectionTab.content:
        return const ContentControlCard();
    }
  }
}

/// نوار دسته بندی پیشرفته بخش های تنظیمات.
class _SettingsTabBar extends StatelessWidget {
  const _SettingsTabBar({
    required this.active,
    required this.networkBadge,
    required this.contentBadge,
    required this.onSelect,
  });

  final _SettingsSectionTab active;
  final int networkBadge;
  final int contentBadge;
  final ValueChanged<_SettingsSectionTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final List<_TabSpec> items = <_TabSpec>[
      const _TabSpec(
        tab: _SettingsSectionTab.connection,
        icon: Icons.shield_rounded,
        label: 'اتصال و سیستم',
      ),
      _TabSpec(
        tab: _SettingsSectionTab.network,
        icon: Icons.dns_rounded,
        label: 'شبکه و دی ان اس',
        badge: networkBadge,
      ),
      const _TabSpec(
        tab: _SettingsSectionTab.appearance,
        icon: Icons.palette_rounded,
        label: 'ظاهر و ویندوز',
      ),
      _TabSpec(
        tab: _SettingsSectionTab.content,
        icon: Icons.gpp_good_rounded,
        label: 'کنترل محتوا',
        badge: contentBadge,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppMetrics.space1),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool singleRow =
              constraints.maxWidth >= AppMetrics.breakpointGrid;
          if (singleRow) {
            return Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppMetrics.space1),
                  Expanded(
                    child: _SettingsTabButton(
                      spec: items[i],
                      selected: items[i].tab == active,
                      onTap: () => onSelect(items[i].tab),
                    ),
                  ),
                ],
              ],
            );
          }
          return Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SettingsTabButton(
                      spec: items[0],
                      selected: items[0].tab == active,
                      onTap: () => onSelect(items[0].tab),
                    ),
                  ),
                  const SizedBox(width: AppMetrics.space1),
                  Expanded(
                    child: _SettingsTabButton(
                      spec: items[1],
                      selected: items[1].tab == active,
                      onTap: () => onSelect(items[1].tab),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppMetrics.space1),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SettingsTabButton(
                      spec: items[2],
                      selected: items[2].tab == active,
                      onTap: () => onSelect(items[2].tab),
                    ),
                  ),
                  const SizedBox(width: AppMetrics.space1),
                  Expanded(
                    child: _SettingsTabButton(
                      spec: items[3],
                      selected: items[3].tab == active,
                      onTap: () => onSelect(items[3].tab),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.tab,
    required this.icon,
    required this.label,
    this.badge = 0,
  });

  final _SettingsSectionTab tab;
  final IconData icon;
  final String label;
  final int badge;
}

class _SettingsTabButton extends StatelessWidget {
  const _SettingsTabButton({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: onTap,
        child: Container(
          height: AppMetrics.controlHeightSmall,
          padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                spec.icon,
                size: AppMetrics.iconSm,
                color: selected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: AppMetrics.space2),
              Flexible(
                child: Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                ),
              ),
              if (spec.badge > 0) ...<Widget>[
                const SizedBox(width: AppMetrics.space2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.space2,
                    vertical: AppMetrics.space1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                  ),
                  child: Text(
                    Fa.num(spec.badge),
                    style: TextStyle(
                      color: colors.onPrimary,
                      fontSize: AppMetrics.fontMicro,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// انتخابگر دیداری پوسته برنامه با پیش نمایش زنده تاریک، روشن و خودکار.
class _ThemeCardSelector extends StatelessWidget {
  const _ThemeCardSelector({
    required this.selected,
    required this.onChanged,
  });

  final ThemePreference selected;
  final ValueChanged<ThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      _ThemePreviewCard(
        preference: ThemePreference.dark,
        title: ThemePreference.dark.label,
        subtitle: 'پس زمینه تیره و مناسب استفاده طولانی',
        icon: Icons.dark_mode_rounded,
        selected: selected == ThemePreference.dark,
        onTap: () => onChanged(ThemePreference.dark),
      ),
      _ThemePreviewCard(
        preference: ThemePreference.light,
        title: ThemePreference.light.label,
        subtitle: 'روشن، شفاف و خوانا در محیط پرنور',
        icon: Icons.light_mode_rounded,
        selected: selected == ThemePreference.light,
        onTap: () => onChanged(ThemePreference.light),
      ),
      _ThemePreviewCard(
        preference: ThemePreference.system,
        title: ThemePreference.system.label,
        subtitle: 'تغییر خودکار بر اساس تنظیمات ویندوز',
        icon: Icons.brightness_auto_rounded,
        selected: selected == ThemePreference.system,
        onTap: () => onChanged(ThemePreference.system),
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= AppMetrics.breakpointGrid) {
          return Row(
            children: <Widget>[
              Expanded(child: cards[0]),
              const SizedBox(width: AppMetrics.space4),
              Expanded(child: cards[1]),
              const SizedBox(width: AppMetrics.space4),
              Expanded(child: cards[2]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            cards[0],
            const SizedBox(height: AppMetrics.space3),
            cards[1],
            const SizedBox(height: AppMetrics.space3),
            cards[2],
          ],
        );
      },
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    required this.preference,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ThemePreference preference;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.08)
          : colors.surfaceHigh.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppMetrics.space4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(
              color: selected ? colors.primary : colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _MiniThemeSwatch(preference: preference),
              const SizedBox(height: AppMetrics.space3),
              Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: AppMetrics.iconMd,
                    color: selected ? colors.primary : colors.textSecondary,
                  ),
                  const SizedBox(width: AppMetrics.space2),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: AppMetrics.iconMd,
                    color: selected ? colors.primary : colors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: AppMetrics.space1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniThemeSwatch extends StatelessWidget {
  const _MiniThemeSwatch({required this.preference});

  final ThemePreference preference;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    if (preference == ThemePreference.system) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: Container(
          height: AppMetrics.controlHeightLarge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: _halfSwatch(UmbrellaColors.dark)),
              Expanded(child: _halfSwatch(UmbrellaColors.light)),
            ],
          ),
        ),
      );
    }
    final UmbrellaColors palette = preference == ThemePreference.dark
        ? UmbrellaColors.dark
        : UmbrellaColors.light;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      child: Container(
        height: AppMetrics.controlHeightLarge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          border: Border.all(color: colors.border),
        ),
        child: _halfSwatch(palette),
      ),
    );
  }

  Widget _halfSwatch(UmbrellaColors palette) {
    return Container(
      color: palette.background,
      padding: const EdgeInsets.all(AppMetrics.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: AppMetrics.space2,
                height: AppMetrics.space2,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Container(
                  height: AppMetrics.space2,
                  decoration: BoxDecoration(
                    color: palette.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                  ),
                ),
              ),
            ],
          ),
          Container(
            height: AppMetrics.space4,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppMetrics.radiusXs),
              border: Border.all(color: palette.border),
            ),
          ),
        ],
      ),
    );
  }
}

/// کارت موضوعی تنظیمات با سرصفحه، فضای تنفس استاندارد و جداکننده تمیز.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;

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
            trailing: trailing,
          ),
          const Divider(height: AppMetrics.space5),
          ...children,
        ],
      ),
    );
  }
}
