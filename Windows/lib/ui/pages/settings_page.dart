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
import '../../vpn/cores.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';
import '../widgets/gateway_dialog.dart';

/// تنظیمات: ظاهر، اتصال، هسته ها، شبکه و حساب.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.onOpenAbout});

  final VoidCallback onOpenAbout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Set<String> _preparing = <String>{};
  List<String> _installed = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshInstalled());
  }

  Future<void> _refreshInstalled() async {
    final CoreProvisioner provisioner = context.read<CoreProvisioner>();
    final List<String> installed = <String>[];
    for (final CoreInfo core in provisioner.catalog) {
      if (await provisioner.hasCore(core.id)) {
        installed.add(core.id);
      }
    }
    if (mounted) {
      setState(() => _installed = installed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    final CoreProvisioner provisioner = context.read<CoreProvisioner>();
    final UmbrellaColors colors = context.colors;
    final AppSettings current = settings.settings;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            Fa.num('تنظیمات'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            Fa.num('همه گزینه های برنامه در یک جا'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionHeader(
                            title: 'ظاهر برنامه',
                            subtitle: 'تم تاریک و روشن با فونت وزیرمتن و چیدمان راست چین.',
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              for (final ThemePreference theme in ThemePreference.values)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: SelectionCard(
                                      title: theme.label,
                                      description: theme == ThemePreference.system
                                          ? 'بر اساس تنظیم ویندوز'
                                          : (theme == ThemePreference.dark
                                              ? 'مناسب شب و کاهش خستگی چشم'
                                              : 'روشن و شفاف برای روز'),
                                      icon: theme == ThemePreference.dark
                                          ? Icons.dark_mode_rounded
                                          : (theme == ThemePreference.light
                                              ? Icons.light_mode_rounded
                                              : Icons.brightness_auto_rounded),
                                      selected: current.theme == theme,
                                      onTap: () => settings.setTheme(theme),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ToggleRow(
                            icon: Icons.auto_awesome_rounded,
                            title: 'جلوه مناسبت ها',
                            subtitle: 'شب یلدا، نوروز، چهارشنبه سوری و دیگر مناسبت ها',
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
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionHeader(
                            title: 'اتصال و امنیت',
                            subtitle: 'حالت انتخاب سرور، کیل سوییچ و رفتار برنامه',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              for (final SelectionMode mode in SelectionMode.values)
                                if (mode != SelectionMode.manual)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: SelectionCard(
                                        title: mode.faName,
                                        description: mode.description,
                                        selected: current.selectionMode == mode,
                                        onTap: () => settings.setSelectionMode(mode),
                                        icon: mode == SelectionMode.auto
                                            ? Icons.auto_mode_rounded
                                            : (mode == SelectionMode.roundRobin
                                                ? Icons.sync_alt_rounded
                                                : (mode == SelectionMode.consistentHash
                                                    ? Icons.fingerprint_rounded
                                                    : Icons.push_pin_rounded)),
                                      ),
                                    ),
                                  ),
                              if (ModeLayout.isWide(context))
                                const Expanded(child: SizedBox()),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ToggleRow(
                            icon: Icons.gpp_good_rounded,
                            title: 'کیل سوییچ',
                            subtitle: 'با قطع تونل، ترافیک دستگاه مسدود می شود',
                            value: current.killSwitch,
                            onChanged: (bool value) async {
                              await settings.setKillSwitch(value);
                              await vpn.rebuildKillSwitch();
                            },
                            accent: colors.success,
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
                            subtitle: 'دکمه بستن پنجره را مخفی می کند، نه بستن برنامه',
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
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionHeader(
                            title: 'پیشرفته',
                            subtitle: 'برای کاربران حرفه ای؛ مقادیر پیش فرض مناسب است.',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  children: <Widget>[
                                    for (final TunStack stack in TunStack.values)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: SelectionCard(
                                          title: 'پشته ${stack.label}',
                                          description: stack == TunStack.mixed
                                              ? 'ترکیب سریع ترین حالت ها'
                                              : (stack == TunStack.gvisor
                                                  ? 'پایدارتر برای برنامه های خاص'
                                                  : 'هماهنگ با هسته سیستم'),
                                          selected: current.tunStack == stack,
                                          onTap: () => settings.setTunStack(stack),
                                          icon: Icons.layers_rounded,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  children: <Widget>[
                                    ToggleRow(
                                      icon: Icons.block_rounded,
                                      title: 'مسدودسازی آی پی نسخه ۶',
                                      value: current.blockIpv6,
                                      onChanged: settings.setBlockIpv6,
                                      accent: colors.warning,
                                    ),
                                    ToggleRow(
                                      icon: Icons.route_rounded,
                                      title: 'مسیر سخت گیرانه',
                                      value: current.strictRoute,
                                      onChanged: settings.setStrictRoute,
                                      accent: colors.info,
                                    ),
                                    ToggleRow(
                                      icon: Icons.dns_rounded,
                                      title: 'دی ان اس از داخل تونل',
                                      value: current.dnsOverTunnel,
                                      onChanged: settings.setDnsOverTunnel,
                                      accent: colors.success,
                                    ),
                                    ToggleRow(
                                      icon: Icons.flash_on_rounded,
                                      title: 'حالت توربو',
                                      value: current.turboMode,
                                      onChanged: settings.setTurboMode,
                                      accent: colors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            Fa.num('اندازه ام تی یو: ${Fa.num(current.mtu)}'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                          ),
                          Slider(
                            value: current.mtu.toDouble().clamp(1280, 9000),
                            min: 1280,
                            max: 9000,
                            divisions: 77,
                            onChanged: (double value) =>
                                settings.setMtu(value.round()),
                          ),
                          Text(
                            Fa.num('بازه سنجش پینگ: هر ${Fa.num(current.pingIntervalSeconds)} ثانیه'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                          ),
                          Slider(
                            value: current.pingIntervalSeconds.toDouble().clamp(30, 600),
                            min: 30,
                            max: 600,
                            divisions: 19,
                            onChanged: (double value) =>
                                settings.setPingInterval(value.round()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: <Widget>[
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionHeader(
                            title: 'هسته های اتصال',
                            subtitle: 'همراه همین نسخه نصب شده اند؛ برنامه چیزی دانلود نمی کند',
                            trailing: IconAction(
                              icon: Icons.refresh_rounded,
                              size: 32,
                              tooltip: 'بررسی دوباره',
                              onTap: _refreshInstalled,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (provisioner.catalog.isEmpty)
                            Text(
                              Fa.num('فهرست هسته ها خوانده نشد.'),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          for (final CoreInfo core in provisioner.catalog)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GlassCard(
                                padding: const EdgeInsets.all(14),
                                radius: 16,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        IconSquare(
                                          icon: _installed.contains(core.id)
                                              ? Icons.check_circle_rounded
                                              : Icons.download_rounded,
                                          color: _installed.contains(core.id)
                                              ? colors.success
                                              : colors.textSecondary,
                                          size: 34,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                Fa.num(core.title),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(fontWeight: FontWeight.w800),
                                              ),
                                              Text(
                                                Fa.num('${core.role} | نسخه ${core.version}'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(color: colors.textSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_preparing.contains(core.id))
                                          const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        else if (!_installed.contains(core.id))
                                          IconAction(
                                            icon: Icons.restore_rounded,
                                            size: 30,
                                            tooltip: 'آماده سازی از نسخه نصب',
                                            onTap: () => _provision(core, provisioner),
                                          ),
                                      ],
                                    ),
                                    if (!_installed.contains(core.id)) ...<Widget>[
                                      const SizedBox(height: 8),
                                      Text(
                                        Fa.num(
                                          core.bundledCore
                                              ? 'این هسته در نسخه نصب نیست؛ برای رفع آن برنامه را دوباره نصب کنید.'
                                              : 'این هسته همراه نسخه عرضه نمی شود و به صورت خودکار جایگزین می شود.',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: core.bundledCore
                                                  ? colors.danger
                                                  : colors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionHeader(
                            title: 'بازگردانی شبکه',
                            subtitle: 'اگر برنامه یا فیلترشکن دیگری تنظیمات شبکه را تغییر داد.',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.wifi_off_rounded,
                            label: 'پروکسی سیستمی ویندوز',
                            value: 'غیرفعال می شود',
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.gpp_bad_rounded,
                            label: 'قواعد کیل سوییچ',
                            value: 'پاک می شود',
                          ),
                          const Divider(height: 14),
                          InfoRow(
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
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionHeader(title: 'حساب و سرویس'),
                          const SizedBox(height: 8),
                          InfoRow(
                            icon: Icons.person_rounded,
                            label: 'کاربر',
                            value: auth.account.displayName,
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.cloud_rounded,
                            label: 'سرور برنامه',
                            value: Uri.tryParse(auth.baseUrl)?.host ?? 'نامشخص',
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: TextButton.icon(
                              onPressed: () => showGatewayDialog(context),
                              icon: const Icon(Icons.dns_rounded, size: 17),
                              label: Text(Fa.num('تغییر نشانی درگاه')),
                            ),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.verified_user_rounded,
                            label: 'دسترسی مدیر',
                            value: settings.elevated ? 'فعال' : 'غیرفعال',
                            valueColor: settings.elevated ? colors.success : colors.warning,
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
                            onPressed: () => context.read<WindowService>().quit(),
                            icon: const Icon(Icons.power_settings_new_rounded, size: 17),
                            label: Text(Fa.num('خروج کامل از برنامه')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              Fa.num('${AppConfig.appName} | ${AppConfig.versionLabel} | ${AppConfig.developer}'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// هسته همراه نسخه نصب است؛ اینجا فقط از پوشه کنار برنامه کپی می شود.
  Future<void> _provision(CoreInfo core, CoreProvisioner provisioner) async {
    setState(() => _preparing.add(core.id));
    final bool ok = await provisioner.provision(core);
    if (!mounted) {
      return;
    }
    setState(() => _preparing.remove(core.id));
    await _refreshInstalled();
    if (!mounted) {
      return;
    }
    final ToastController toasts = context.read<ToastController>();
    if (ok) {
      toasts.success('${core.title} آماده شد');
    } else {
      toasts.error(
        'هسته ${core.title} پیدا نشد',
        'برنامه را با نصب کننده رسمی دوباره نصب کنید؛ هسته ها همراه نسخه می آیند.',
      );
    }
  }
}

class ModeLayout {
  const ModeLayout._();

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width > 1400;
}
