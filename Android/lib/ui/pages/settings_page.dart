import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../core/ui_formatters.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/power_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/advanced_network_settings.dart';
import '../widgets/common.dart';
import '../widgets/content_control.dart';
import '../widgets/bypass_control.dart';
import '../widgets/lan_sharing_dialog.dart';

/// دسته های تنظیمات برنامه اندروید.
enum SettingsCategory {
  general,
  routing,
  dns,
  inbound,
  tlsTricks,
  battery;

  static const List<SettingsCategory> navigationItems = <SettingsCategory>[
    SettingsCategory.general,
    SettingsCategory.routing,
    SettingsCategory.dns,
    SettingsCategory.inbound,
    SettingsCategory.tlsTricks,
    SettingsCategory.battery,
  ];
}

extension SettingsCategoryX on SettingsCategory {
  String get title {
    switch (this) {
      case SettingsCategory.general:
        return 'عمومی';
      case SettingsCategory.battery:
        return 'باتری دستگاه';
      case SettingsCategory.routing:
        return 'مسیریابی';
      case SettingsCategory.dns:
        return 'دی ان اس';
      case SettingsCategory.inbound:
        return 'ورودی';
      case SettingsCategory.tlsTricks:
        return 'ترفندهای اتصال امن';
    }
  }

  String get listSubtitle {
    switch (this) {
      case SettingsCategory.general:
        return 'پوسته برنامه، شروع خودکار، اتصال خودکار و گزارش ها';
      case SettingsCategory.battery:
        return 'کاهش مصرف پس زمینه هنگام استفاده از باتری';
      case SettingsCategory.routing:
        return 'منطقه مسیریابی، آی پی نسخه ۶، کنترل محتوا و تفکیک برنامه ها';
      case SettingsCategory.dns:
        return 'سرورهای دی ان اس اصلی و مستقیم و دی ان اس مجازی';
      case SettingsCategory.inbound:
        return 'حالت سرویس، کارت شبکه تونل، پروکسی محلی و اشتراک گذاری';
      case SettingsCategory.tlsTricks:
        return 'تکه تکه سازی بسته ها، مبهم سازی نام سرور و لایه پرکننده';
    }
  }

  String get detailSubtitle {
    switch (this) {
      case SettingsCategory.general:
        return 'پوسته برنامه، اجرای خودکار، انتخاب خودکار سرور، اعلان ها و گزارش ها';
      case SettingsCategory.battery:
        return 'مدیریت مصرف برنامه هنگام کار با باتری دستگاه';
      case SettingsCategory.routing:
        return 'منطقه مسیریابی، قوانین توکار، آی پی نسخه ۶، کنترل محتوا و تفکیک برنامه ها';
      case SettingsCategory.dns:
        return 'سرورهای دی ان اس اصلی و مستقیم، شیوه انتخاب نشانی و دی ان اس مجازی';
      case SettingsCategory.inbound:
        return 'حالت سرویس، تنظیمات کارت شبکه تونل، پروکسی محلی و اشتراک اتصال در شبکه محلی';
      case SettingsCategory.tlsTricks:
        return 'تکه تکه سازی بسته ها، درهم سازی حروف نام سرور و لایه گذاری برای عبور از محدودیت ها';
    }
  }

  IconData get icon {
    switch (this) {
      case SettingsCategory.general:
        return Icons.tune_rounded;
      case SettingsCategory.battery:
        return Icons.battery_saver_rounded;
      case SettingsCategory.routing:
        return Icons.alt_route_rounded;
      case SettingsCategory.dns:
        return Icons.dns_rounded;
      case SettingsCategory.inbound:
        return Icons.settings_input_component_rounded;
      case SettingsCategory.tlsTricks:
        return Icons.enhanced_encryption_rounded;
    }
  }

  Color accentColor(UmbrellaColors colors) {
    switch (this) {
      case SettingsCategory.general:
        return colors.primary;
      case SettingsCategory.battery:
        return colors.success;
      case SettingsCategory.routing:
        return colors.info;
      case SettingsCategory.dns:
        return colors.success;
      case SettingsCategory.inbound:
        return colors.primary;
      case SettingsCategory.tlsTricks:
        return colors.warning;
    }
  }
}

/// صفحه تنظیمات آمبرلا برای پیکربندی اتصال و تجربه کاربری.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialSection});

  final SettingsCategory? initialSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsCategory? _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _section = widget.initialSection;
    }
  }

  Future<void> _applyRuntime(
    VpnController vpn,
    Future<void> Function() action,
  ) async {
    await action();
    if (vpn.status.active) {
      vpn.scheduleLiveReload();
    }
  }

  Future<void> _editTextValue({
    required String title,
    required String label,
    required String initialValue,
    String hint = '',
    bool numericOnly = false,
    String? Function(String value)? validator,
    required Future<void> Function(String value) onSubmit,
  }) async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _ValueInputDialog(
        title: title,
        label: label,
        initialValue: initialValue,
        hint: hint,
        numericOnly: numericOnly,
        validator: validator,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    try {
      await onSubmit(result);
    } on FormatException catch (error) {
      if (mounted) {
        context.read<ToastController>().error(error.message, title);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final SettingsController settings = context.watch<SettingsController>();
    // آمار اتصال هر ثانیه عوض می شود؛ تنظیمات فقط برای فرمان ها به vpn نیاز دارد.
    final VpnController vpn = context.read<VpnController>();
    final bool batterySaving = context.select<PowerController?, bool>(
      (power) => power?.active == true,
    );
    final ToastController toasts = context.read<ToastController>();
    final AppSettings cfg = settings.settings;

    if (_section == null) {
      return _buildRootMenu(context, colors, cfg);
    }

    final SettingsCategory active = _section!;
    // سربرگ و بازگشت همیشه در دسترس هستند، حتی پس از پیمایش گزینه های طولانی.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            setState(() => _section = null);
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: AppMetrics.responsivePagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PageHeader(
                  title: active.title,
                  eyebrow: 'بخش تنظیمات',
                  premium: true,
                  subtitle: active.detailSubtitle,
                  icon: active.icon,
                  actions: <Widget>[
                    OutlinedButton.icon(
                      key: const ValueKey<String>('settings-back-button'),
                      onPressed: () => setState(() => _section = null),
                      icon: const Icon(Icons.arrow_back_rounded, size: AppMetrics.iconSm),
                      label: const Text('بازگشت به تنظیمات'),
                    ),
                  ],
                ),
                const SizedBox(height: AppMetrics.space4),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey<String>('settings-detail-${active.name}'),
                    child: _buildCategoryContent(
                      context: context,
                      category: active,
                      colors: colors,
                      settings: settings,
                      vpn: vpn,
                      toasts: toasts,
                      cfg: cfg,
                      batterySaving: batterySaving,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRootMenu(
    BuildContext context,
    UmbrellaColors colors,
    AppSettings cfg,
  ) {
    const List<SettingsCategory> categories = SettingsCategory.navigationItems;
    return SingleChildScrollView(
      key: const PageStorageKey<String>('settings-root-scroll'),
      padding: AppMetrics.responsivePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
            title: 'تنظیمات',
            eyebrow: 'مرکز تنظیمات',
            premium: true,
            subtitle:
                'پیکربندی عمومی، مسیریابی، دی ان اس، ورودی و ترفندهای اتصال امن',
            icon: Icons.settings_rounded,
          ),
          const SizedBox(height: AppMetrics.space4),
          GlassCard(
            radius: AppMetrics.radiusXl,
            padding: const EdgeInsets.symmetric(vertical: AppMetrics.space2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < categories.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: AppMetrics.space1,
                      indent: AppMetrics.space9,
                      endIndent: AppMetrics.space4,
                      color: colors.border,
                    ),
                  _CategoryNavTile(
                    category: categories[i],
                    badge: _categoryBadge(
                      context,
                      categories[i],
                      cfg,
                    ),
                    onTap: () {
                      playUiClick(context);
                      setState(() => _section = categories[i]);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _categoryBadge(
    BuildContext context,
    SettingsCategory category,
    AppSettings cfg,
  ) {
    switch (category) {
      case SettingsCategory.general:
        return null;
      case SettingsCategory.battery:
        return cfg.batteryOptimization ? 'روشن' : 'خاموش';
      case SettingsCategory.routing:
        final bool hasActiveRules = context.select<AuthController?, bool>(
          (auth) => auth?.filter.hasActiveRules ?? false,
        );
        if (hasActiveRules) {
          return 'کنترل محتوا';
        }
        if (cfg.routingRegion != RoutingRegion.other) {
          return cfg.routingRegion.label;
        }
        final int activeApps =
            cfg.appRoutes.where((AppRouteRule r) => r.enabled).length;
        if (activeApps > 0) {
          return Fa.num('$activeApps برنامه');
        }
        return cfg.blockAds ? 'ضد تبلیغات' : null;
      case SettingsCategory.dns:
        return cfg.enableFakeDns ? 'دی ان اس مجازی' : null;
      case SettingsCategory.inbound:
        return cfg.allowConnectionFromLan
            ? '${cfg.serviceMode.shortLabel} · اشتراک روشن'
            : cfg.serviceMode.shortLabel;
      case SettingsCategory.tlsTricks:
        return cfg.tlsTricks.anyEnabled ? 'فعال' : null;
    }
  }

  Widget _buildCategoryContent({
    required BuildContext context,
    required SettingsCategory category,
    required UmbrellaColors colors,
    required SettingsController settings,
    required VpnController vpn,
    required ToastController toasts,
    required AppSettings cfg,
    required bool batterySaving,
  }) {
    switch (category) {
      case SettingsCategory.battery:
        return _buildBatterySection(settings, cfg, batterySaving);
      case SettingsCategory.general:
        return _buildGeneralSection(
          context,
          colors,
          settings,
          vpn,
          toasts,
          cfg,
        );
      case SettingsCategory.routing:
        return _buildRoutingSection(
          context,
          colors,
          settings,
          vpn,
          toasts,
          cfg,
        );
      case SettingsCategory.dns:
        return _buildDnsSection(context, colors, settings, vpn, cfg);
      case SettingsCategory.inbound:
        return _buildInboundSection(
          context,
          colors,
          settings,
          vpn,
          toasts,
          cfg,
        );
      case SettingsCategory.tlsTricks:
        return _buildTlsTricksSection(context, colors, settings, vpn, cfg);
    }
  }

  Widget _buildBatterySection(
    SettingsController settings, AppSettings cfg, bool active,
  ) {
    return _Section(
      icon: Icons.battery_saver_rounded,
      title: 'بهینه سازی باتری دستگاه',
      subtitle: 'فاصله سنجش سرعت و پینگ نمایشی بیشتر می شود؛ اتصال، پایش سلامت و اعلان ها حفظ می شوند.',
      children: <Widget>[
        ToggleRow(
          key: const ValueKey<String>('battery-optimization-toggle'),
          icon: Icons.battery_saver_rounded,
          title: 'بهینه سازی خودکار باتری',
          subtitle: !cfg.batteryOptimization
              ? 'خاموش است'
              : active
                  ? 'اکنون فعال است'
                  : 'در حالت صرفه جویی باتری فعال می شود',
          value: cfg.batteryOptimization,
          onChanged: settings.setBatteryOptimization,
        ),
        const Divider(height: AppMetrics.space4),
        Wrap(
          spacing: AppMetrics.space2,
          runSpacing: AppMetrics.space2,
          children: <Widget>[
            OutlinedButton.icon(
              icon: const Icon(Icons.battery_alert_rounded, size: AppMetrics.iconSm),
              label: const Text('لغو محدودیت باتری'),
              onPressed: () => context
                  .read<NativeBridge>()
                  .requestIgnoreBatteryOptimization(),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ۱. عمومی
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildGeneralSection(
    BuildContext context,
    UmbrellaColors colors,
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    AppSettings cfg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Section(
          icon: Icons.palette_rounded,
          title: 'حالت پوسته',
          subtitle: 'انتخاب رنگ بندی تیره، روشن یا هماهنگ با سیستم',
          children: <Widget>[
            _ThemeCardSelector(
              selected: cfg.theme,
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
            icon: Icons.smartphone_rounded,
            title: 'دستگاه و اتصال خودکار',
            subtitle: 'شروع با دستگاه و رفتار خودکار اتصال',
            children: <Widget>[
              ToggleRow(
                icon: Icons.rocket_launch_rounded,
                title: 'شروع هنگام ورود به سیستم',
                subtitle: 'اجرای خودکار آمبرلا پس از روشن شدن دستگاه',
                value: cfg.startOnBoot,
                onChanged: settings.setStartOnBoot,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.bolt_rounded,
                title: 'اتصال خودکار در شروع برنامه',
                subtitle: 'برقراری خودکار اتصال به محض باز شدن آمبرلا',
                value: cfg.autoConnect,
                onChanged: settings.setAutoConnect,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.swap_horiz_rounded,
                title: 'جابه جایی خودکار سرور',
                subtitle: 'انتخاب بی وقفه سرور سالم هنگام افت مسیر فعال',
                value: cfg.autoFailover,
                onChanged: (bool v) =>
                    _applyRuntime(vpn, () => settings.setAutoFailover(v)),
              ),
            ],
          ),
          right: _Section(
            icon: Icons.tune_rounded,
            title: 'انتخاب سرور، اعلان ها و عیب یابی',
            subtitle: 'پروکسی پیش فرض، پیام های سیستم، سطح گزارش و تعمیر شبکه',
            children: <Widget>[
              AnchoredSelectField<SelectionMode>(
                label: 'پروکسی پیش فرض',
                leadingIcon: Icons.alt_route_rounded,
                value: SelectionModeList.visible.contains(cfg.selectionMode)
                    ? cfg.selectionMode
                    : SelectionMode.auto,
                options: <SelectOption<SelectionMode>>[
                  for (final SelectionMode mode in SelectionModeList.visible)
                    SelectOption<SelectionMode>(
                      value: mode,
                      label: mode.label,
                      subtitle: mode.description,
                      icon: mode.icon,
                    ),
                ],
                onChanged: (SelectionMode picked) => _applyRuntime(
                  vpn,
                  () => settings.setSelectionMode(picked),
                ),
              ),
              const SizedBox(height: AppMetrics.space3),
              AnchoredSelectField<String>(
                label: 'سطح گزارش هسته',
                leadingIcon: Icons.receipt_long_rounded,
                value: CoreLogLevel.normalize(cfg.logLevel),
                options: const <SelectOption<String>>[
                  SelectOption<String>(
                    value: 'warn',
                    label: 'هشدار (پیشنهادی)',
                    subtitle: 'سبک و بهینه برای استفاده روزمره',
                    icon: Icons.warning_amber_rounded,
                  ),
                  SelectOption<String>(
                    value: 'info',
                    label: 'اطلاعات',
                    subtitle: 'ثبت رویدادهای اصلی اتصال',
                    icon: Icons.info_outline_rounded,
                  ),
                  SelectOption<String>(
                    value: 'debug',
                    label: 'عیب یابی (۱۰ دقیقه)',
                    subtitle: 'جزئیات کامل با بازگشت خودکار به هشدار',
                    icon: Icons.bug_report_rounded,
                  ),
                  SelectOption<String>(
                    value: 'error',
                    label: 'فقط خطا',
                    subtitle: 'ثبت خطاهای بحرانی',
                    icon: Icons.error_outline_rounded,
                  ),
                ],
                onChanged: (String level) =>
                    _applyRuntime(vpn, () => settings.setLogLevel(level)),
              ),
              const Divider(height: AppMetrics.space4),
              ToggleRow(
                icon: Icons.notifications_active_rounded,
                title: 'اعلان های سیستم',
                subtitle: 'نمایش اعلان های کوتاه برای تغییر وضعیت اتصال و حساب',
                value: cfg.notificationsEnabled,
                onChanged: settings.setNotifications,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.volume_up_rounded,
                title: 'صداهای برنامه',
                subtitle: 'پخش صدا برای منوها، کنترل ها، اعلان ها و وضعیت اتصال',
                value: cfg.soundEnabled,
                onChanged: settings.setSound,
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.auto_awesome_rounded,
                title: 'جلوه مناسبت ها',
                subtitle: 'نمایش المان های تصویری مناسبتی در صفحه اتصال',
                value: cfg.occasionEffects,
                onChanged: settings.setOccasionEffects,
              ),
              const Divider(height: AppMetrics.space4),
              Wrap(
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space2,
                children: <Widget>[
                  SizedBox(
                    height: AppMetrics.controlHeightSmall,
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.settings_backup_restore_rounded,
                        size: AppMetrics.iconSm,
                      ),
                      label: const Text('تعمیر شبکه دستگاه'),
                      onPressed: () async {
                        await vpn.restoreNetwork();
                        toasts.success('تنظیمات شبکه دستگاه بازگردانی شد');
                      },
                    ),
                  ),
                  SizedBox(
                    height: AppMetrics.controlHeightSmall,
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.vpn_lock_rounded,
                        size: AppMetrics.iconSm,
                      ),
                      label: const Text('تنظیمات اتصال همیشگی'),
                      onPressed: () =>
                          context.read<NativeBridge>().openVpnSystemSettings(),
                    ),
                  ),
                  SizedBox(
                    height: AppMetrics.controlHeightSmall,
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.battery_saver_rounded,
                        size: AppMetrics.iconSm,
                      ),
                      label: const Text('لغو محدودیت باتری'),
                      onPressed: () => context
                          .read<NativeBridge>()
                          .requestIgnoreBatteryOptimization(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildRoutingSection(
    BuildContext context,
    UmbrellaColors colors,
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    AppSettings cfg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Section(
          icon: Icons.route_rounded,
          title: 'منطقه و قوانین مسیریابی',
          subtitle:
              'عبور مستقیم ترافیک داخلی منطقه انتخابی، شبکه محلی، مسدودسازی تبلیغات و تنظیم آی پی نسخه ۶',
          children: <Widget>[
            AnchoredSelectField<RoutingRegion>(
              label: 'منطقه',
              leadingIcon: Icons.public_rounded,
              value: cfg.routingRegion,
              options: <SelectOption<RoutingRegion>>[
                for (final RoutingRegion r in RoutingRegion.values)
                  SelectOption<RoutingRegion>(
                    value: r,
                    label: r.label,
                    icon: r.icon,
                    subtitle: r == RoutingRegion.other
                        ? 'عبور تمام ترافیک از مسیر انتخابی'
                        : 'اتصال مستقیم سایت ها و نشانی های داخلی ${r.shortLabel}',
                  ),
              ],
              onChanged: (RoutingRegion picked) =>
                  _applyRuntime(vpn, () => settings.setRoutingRegion(picked)),
            ),
            const SizedBox(height: AppMetrics.space3),
            AnchoredSelectField<Ipv6RouteMode>(
              label: 'حالت مسیریابی آی پی نسخه ۶',
              leadingIcon: Icons.language_rounded,
              value: cfg.ipv6RouteMode,
              options: <SelectOption<Ipv6RouteMode>>[
                for (final Ipv6RouteMode m in Ipv6RouteMode.values)
                  SelectOption<Ipv6RouteMode>(
                    value: m,
                    label: m.label,
                    subtitle: m.description,
                    icon: m.icon,
                  ),
              ],
              onChanged: (Ipv6RouteMode picked) =>
                  _applyRuntime(vpn, () => settings.setIpv6RouteMode(picked)),
            ),
            const Divider(height: AppMetrics.space4),
            ToggleRow(
              icon: Icons.lan_outlined,
              title: 'دور زدن شبکه محلی',
              subtitle: 'ارسال مستقیم ترافیک شبکه خانگی و اداری بدون عبور از تونل',
              value: cfg.bypassLan,
              onChanged: (bool v) =>
                  _applyRuntime(vpn, () => settings.setBypassLan(v)),
            ),
            const Divider(height: AppMetrics.space3),
            ToggleRow(
              icon: Icons.gpp_bad_outlined,
              title: 'مسدودسازی تبلیغات و بدافزار',
              subtitle: 'مسدود کردن دامنه های تبلیغاتی و ردیاب در سطح هسته',
              value: cfg.blockAds,
              onChanged: (bool v) =>
                  _applyRuntime(vpn, () => settings.setBlockAds(v)),
            ),
            const Divider(height: AppMetrics.space3),
            ToggleRow(
              icon: Icons.travel_explore_rounded,
              title: 'گشودن نشانی مقصد',
              subtitle: 'تبدیل نام دامنه به نشانی آی پی پیش از ارسال به خروجی',
              value: cfg.resolveDestination,
              onChanged: (bool v) =>
                  _applyRuntime(vpn, () => settings.setResolveDestination(v)),
            ),
            const Divider(height: AppMetrics.space3),
            ToggleRow(
              icon: Icons.speed_outlined,
              title: 'مسدودسازی کوئیک',
              subtitle: 'هدایت مرورگرها به اتصال پایدار برای جلوگیری از قطع و وصل',
              value: cfg.blockQuic,
              onChanged: (bool v) =>
                  _applyRuntime(vpn, () => settings.setBlockQuic(v)),
            ),
          ],
        ),
        const SizedBox(height: AppMetrics.space5),
        const _Section(
          icon: Icons.apps_rounded,
          title: 'مسیریابی بر اساس برنامه',
          subtitle:
              'تعیین کنید هر برنامه از تونل عبور کند، مستقیم وصل شود یا مسدود گردد',
          children: <Widget>[AdvancedNetworkSettings()],
        ),
        const SizedBox(height: AppMetrics.space5),
        const _Section(
          icon: Icons.family_restroom_rounded,
          title: 'کنترل محتوا',
          subtitle:
              'فیلتر دسته بندی شده دامنه ها، هماهنگ خودکار با حساب کاربری شما',
          children: <Widget>[ContentControlCard()],
        ),
        const SizedBox(height: AppMetrics.space5),
        const _Section(
          icon: Icons.alt_route_rounded,
          title: 'عبور مستقیم سایت ها',
          subtitle: 'سایت های انتخاب شده خارج از تونل، همگام با ربات تلگرام',
          children: <Widget>[BypassControlCard()],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ۴. DNS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDnsSection(
    BuildContext context,
    UmbrellaColors colors,
    SettingsController settings,
    VpnController vpn,
    AppSettings cfg,
  ) {
    final List<SelectOption<String>> dnsOptions = <SelectOption<String>>[
      for (final MapEntry<String, String> entry in NetworkDns.presets.entries)
        SelectOption<String>(
          value: entry.key,
          label: entry.value,
          subtitle: NetworkDns.subtitleFa(entry.key),
          icon: NetworkDns.iconFor(entry.key),
        ),
    ];
    final List<SelectOption<DnsDomainStrategy>> strategyOptions =
        <SelectOption<DnsDomainStrategy>>[
      for (final DnsDomainStrategy s in DnsDomainStrategy.values)
        SelectOption<DnsDomainStrategy>(
          value: s,
          label: s.label,
          icon: s.icon,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Section(
          icon: Icons.cloud_done_outlined,
          title: 'دی ان اس اصلی (داخل تونل)',
          subtitle:
              'پاسخ گویی به نام دامنه سایت هایی که از سرور آمبرلا عبور می کنند',
          children: <Widget>[
            AnchoredSelectField<String>(
              label: 'دی ان اس اصلی',
              leadingIcon: Icons.dns_rounded,
              value: NetworkDns.normalizeRemote(cfg.remoteDns),
              options: dnsOptions,
              onChanged: (String v) =>
                  _applyRuntime(vpn, () => settings.setRemoteDns(v)),
            ),
            const SizedBox(height: AppMetrics.space3),
            AnchoredSelectField<DnsDomainStrategy>(
              label: 'شیوه انتخاب نشانی دی ان اس اصلی',
              leadingIcon: Icons.alt_route_rounded,
              value: cfg.remoteDnsStrategy,
              options: strategyOptions,
              onChanged: (DnsDomainStrategy s) =>
                  _applyRuntime(vpn, () => settings.setRemoteDnsStrategy(s)),
            ),
            const Divider(height: AppMetrics.space4),
            ToggleRow(
              icon: Icons.flash_on_rounded,
              title: 'فعال سازی دی ان اس مجازی',
              subtitle:
                  'پاسخ فوری با نشانی مجازی برای کاهش تاخیر باز شدن دامنه ها در حالت تونل کامل',
              value: cfg.enableFakeDns,
              onChanged: (bool v) =>
                  _applyRuntime(vpn, () => settings.setEnableFakeDns(v)),
            ),
          ],
        ),
        const SizedBox(height: AppMetrics.space5),
        _Section(
          icon: Icons.router_outlined,
          title: 'دی ان اس پروکسی ها (مستقیم)',
          subtitle:
              'برای پیدا کردن نشانی سرورهای پروکسی و سایت های بدون فیلتر استفاده می شود',
          children: <Widget>[
            AnchoredSelectField<String>(
              label: 'دی ان اس مستقیم',
              leadingIcon: Icons.router_rounded,
              value: NetworkDns.normalizeDirect(cfg.directDns),
              options: dnsOptions,
              onChanged: (String v) =>
                  _applyRuntime(vpn, () => settings.setDirectDns(v)),
            ),
            const SizedBox(height: AppMetrics.space3),
            AnchoredSelectField<DnsDomainStrategy>(
              label: 'شیوه انتخاب نشانی دی ان اس مستقیم',
              leadingIcon: Icons.call_split_rounded,
              value: cfg.directDnsStrategy,
              options: strategyOptions,
              onChanged: (DnsDomainStrategy s) =>
                  _applyRuntime(vpn, () => settings.setDirectDnsStrategy(s)),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ۵. ورودی
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildInboundSection(
    BuildContext context,
    UmbrellaColors colors,
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    AppSettings cfg,
  ) {
    final String secret = cfg.lanSharingPassword.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Section(
          icon: Icons.login_rounded,
          title: 'حالت سرویس و کارت شبکه تونل',
          subtitle: 'انتخاب شیوه دریافت ترافیک سیستم و تنظیمات سطح پایین تونل',
          children: <Widget>[
            AnchoredSelectField<InboundServiceMode>(
              label: 'حالت سرویس',
              leadingIcon: Icons.shield_outlined,
              value: cfg.serviceMode == InboundServiceMode.proxy
                  ? InboundServiceMode.proxy
                  : InboundServiceMode.vpn,
              options: const <SelectOption<InboundServiceMode>>[
                SelectOption<InboundServiceMode>(
                  value: InboundServiceMode.vpn,
                  label: 'تونل کامل',
                  subtitle: 'عبور تمام برنامه ها و بازی ها از کارت شبکه امن مجازی',
                  icon: Icons.vpn_lock_rounded,
                ),
                SelectOption<InboundServiceMode>(
                  value: InboundServiceMode.proxy,
                  label: 'فقط سرویس پروکسی',
                  subtitle: 'ایجاد پروکسی محلی ساکس ۵ و وب بدون فعال سازی تونل',
                  icon: Icons.hub_rounded,
                ),
              ],
              onChanged: (InboundServiceMode picked) async {
                await _applyRuntime(
                  vpn,
                  () => settings.setServiceMode(picked),
                );
              },
            ),
            const SizedBox(height: AppMetrics.space3),
            AnchoredSelectField<TunStack>(
              label: 'پیاده سازی کارت شبکه تونل',
              leadingIcon: Icons.layers_outlined,
              value: cfg.tunStack,
              options: <SelectOption<TunStack>>[
                for (final TunStack stack in TunStack.values)
                  SelectOption<TunStack>(
                    value: stack,
                    label: stack.label,
                    icon: stack.icon,
                  ),
              ],
              onChanged: (TunStack picked) =>
                  _applyRuntime(vpn, () => settings.setTunStack(picked)),
            ),
            const Divider(height: AppMetrics.space4),
            _EditableValueRow(
              icon: Icons.straighten_rounded,
              title: 'اندازه بسته تونل',
              value: Fa.num('${cfg.mtu}'),
              onTap: () => _editTextValue(
                title: 'اندازه بسته تونل',
                label: 'بین ۱۲۸۰ تا ۹۰۰۰ (پیش فرض ۹۰۰۰)',
                initialValue: '${cfg.mtu}',
                numericOnly: true,
                validator: (String v) {
                  final int? n = int.tryParse(v.trim());
                  return n != null && n >= 1280 && n <= 9000
                      ? null
                      : 'عددی بین ۱۲۸۰ تا ۹۰۰۰ وارد کنید';
                },
                onSubmit: (String v) => _applyRuntime(
                  vpn,
                  () => settings.setMtu(int.parse(v.trim())),
                ),
              ),
            ),
            const Divider(height: AppMetrics.space3),
            ToggleRow(
              icon: Icons.lock_outline_rounded,
              title: 'مسیربندی سخت گیرانه',
              subtitle: 'جلوگیری از نشت بسته ها خارج از کارت شبکه تونل',
              value: cfg.strictRoute,
              onChanged: (bool v) =>
                  _applyRuntime(vpn, () => settings.setStrictRoute(v)),
            ),
          ],
        ),
        const SizedBox(height: AppMetrics.space5),
        ResponsiveColumns(
          leftFlex: 1,
          rightFlex: 1,
          spacing: AppMetrics.space5,
          left: _Section(
            icon: Icons.computer_rounded,
            title: 'پروکسی محلی (این دستگاه)',
            subtitle: 'پورت ترکیبی ساکس ۵ و وب روی نشانی ۱۲۷.۰.۰.۱',
            children: <Widget>[
              _EditableValueRow(
                icon: Icons.settings_ethernet_rounded,
                title: 'پورت پروکسی محلی',
                value: Fa.num('${cfg.mixedPort}'),
                onTap: () => _editTextValue(
                  title: 'پورت پروکسی محلی',
                  label: 'بین ۱۰۲۴ تا ۶۵۵۳۵',
                  initialValue: '${cfg.mixedPort}',
                  numericOnly: true,
                  validator: (String v) {
                    final int? p = int.tryParse(v.trim());
                    return p != null &&
                            LanSharing.isValidPort(
                              p,
                              forbiddenPort: cfg.lanSharingPort,
                            )
                        ? null
                        : 'پورتی بین ۱۰۲۴ تا ۶۵۵۳۵ و متفاوت از پورت اشتراک وارد کنید';
                  },
                  onSubmit: (String v) => _applyRuntime(
                    vpn,
                    () => settings.setMixedPort(int.parse(v.trim())),
                  ),
                ),
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.swap_calls_rounded,
                title: 'باز ماندن در حالت تونل کامل',
                subtitle: 'فعال ماندن پورت ۱۲۷.۰.۰.۱ هنگام روشن بودن تونل کامل',
                value: cfg.localProxyInVpn,
                onChanged: (bool v) =>
                    _applyRuntime(vpn, () => settings.setLocalProxyInVpn(v)),
              ),
              const Divider(height: AppMetrics.space3),
              ToggleRow(
                icon: Icons.password_rounded,
                title: 'درخواست رمز در پروکسی محلی',
                subtitle: 'الزام به وارد کردن رمز پروکسی برای برنامه های محلی',
                value: cfg.localProxyAuth,
                onChanged: (bool v) async {
                  if (v && secret.isEmpty) {
                    await settings.setLanSharingPassword(
                      LanSharing.generateSecret(),
                    );
                  }
                  await _applyRuntime(
                    vpn,
                    () => settings.setLocalProxyAuth(v),
                  );
                },
              ),
            ],
          ),
          right: _Section(
            icon: Icons.wifi_tethering_rounded,
            title: 'اشتراک گذاری اتصال در شبکه محلی',
            subtitle:
                'اتصال گوشی، لپ تاپ و سایر دستگاه های هم شبکه با رمزینه تصویری',
            trailing: SizedBox(
              height: AppMetrics.controlHeightSmall,
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.qr_code_2_rounded,
                  size: AppMetrics.iconSm,
                ),
                label: const Text('رمزینه تصویری'),
                onPressed: () => LanSharingDialog.show(context),
              ),
            ),
            children: <Widget>[
              ToggleRow(
                icon: Icons.share_rounded,
                title: 'اشتراک در شبکه محلی',
                subtitle: 'باز کردن درگاه ساکس ۵ روی شبکه وای فای و کابلی فعلی',
                value: cfg.allowConnectionFromLan,
                onChanged: (bool v) => _applyRuntime(
                  vpn,
                  () => settings.setAllowConnectionFromLan(v),
                ),
              ),
              const Divider(height: AppMetrics.space3),
              _EditableValueRow(
                icon: Icons.numbers_rounded,
                title: 'پورت اشتراک',
                value: Fa.num('${cfg.lanSharingPort}'),
                onTap: () => _editTextValue(
                  title: 'پورت اشتراک شبکه محلی',
                  label: 'بین ۱۰۲۴ تا ۶۵۵۳۵ (پیش فرض ۱۲۳۳۸)',
                  initialValue: '${cfg.lanSharingPort}',
                  numericOnly: true,
                  validator: (String v) {
                    final int? p = int.tryParse(v.trim());
                    return p != null &&
                            LanSharing.isValidPort(
                              p,
                              forbiddenPort: cfg.mixedPort,
                            )
                        ? null
                        : 'پورتی بین ۱۰۲۴ تا ۶۵۵۳۵ و متفاوت از پورت محلی وارد کنید';
                  },
                  onSubmit: (String v) => _applyRuntime(
                    vpn,
                    () => settings.setLanSharingPort(int.parse(v.trim())),
                  ),
                ),
              ),
              const Divider(height: AppMetrics.space3),
              _EditableValueRow(
                icon: secret.isEmpty
                    ? Icons.lock_open_rounded
                    : Icons.lock_rounded,
                title: 'رمز پروکسی',
                value: secret.isEmpty ? 'رمز تنظیم نشده' : 'تنظیم شده (••••••••)',
                valueColor: secret.isEmpty ? colors.danger : colors.success,
                onTap: () =>
                    LanSharingDialog.editPassword(context, settings, vpn),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ۶. ترفندهای اتصال امن
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTlsTricksSection(
    BuildContext context,
    UmbrellaColors colors,
    SettingsController settings,
    VpnController vpn,
    AppSettings cfg,
  ) {
    final TlsTricksSettings tls = cfg.tlsTricks;

    Future<void> saveTls(TlsTricksSettings next) =>
        _applyRuntime(vpn, () => settings.setTlsTricks(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Section(
          icon: Icons.content_cut_rounded,
          title: 'تکه تکه سازی بسته ها',
          subtitle:
              'تقسیم بسته اولیه اتصال امن به تکه های کوچک با مکث تصادفی برای عبور از بازرسی عمیق شبکه',
          children: <Widget>[
            ToggleRow(
              icon: Icons.call_split_rounded,
              title: 'فعال سازی تکه تکه سازی',
              subtitle: 'اعمال خودکار روی خروجی های رمزنگاری شده پشتیبان',
              value: tls.enableFragment,
              onChanged: (bool v) => saveTls(tls.copyWith(enableFragment: v)),
            ),
            const Divider(height: AppMetrics.space3),
            _EditableValueRow(
              icon: Icons.straighten_rounded,
              title: 'اندازه تکه ها (بایت)',
              value: Fa.num(tls.fragmentSize),
              ltrValue: true,
              onTap: () => _editTextValue(
                title: 'اندازه تکه ها',
                label: 'عدد یا بازه (پیش فرض ۱۰-۱۰۰)',
                initialValue: tls.fragmentSize,
                hint: '۱۰-۱۰۰',
                validator: (String v) => TlsTricksSettings.isValidRange(v)
                    ? null
                    : 'بازه عددی معتبر وارد کنید (مانند ۱۰-۱۰۰)',
                onSubmit: (String v) =>
                    saveTls(tls.copyWith(fragmentSize: v.trim())),
              ),
            ),
            const Divider(height: AppMetrics.space3),
            _EditableValueRow(
              icon: Icons.timer_outlined,
              title: 'تاخیر بین تکه ها (میلی ثانیه)',
              value: Fa.num(tls.fragmentSleep),
              ltrValue: true,
              onTap: () => _editTextValue(
                title: 'تاخیر بین تکه ها',
                label: 'عدد یا بازه (پیش فرض ۵۰-۲۰۰)',
                initialValue: tls.fragmentSleep,
                hint: '۵۰-۲۰۰',
                validator: (String v) =>
                    TlsTricksSettings.isValidRange(v, min: 0)
                        ? null
                        : 'بازه عددی معتبر وارد کنید (مانند ۵۰-۲۰۰)',
                onSubmit: (String v) =>
                    saveTls(tls.copyWith(fragmentSleep: v.trim())),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppMetrics.space5),
        _Section(
          icon: Icons.enhanced_encryption_outlined,
          title: 'مبهم سازی نام سرور و اندازه بسته',
          subtitle: 'تغییر تصادفی حروف نام دامنه و طول بسته آغاز اتصال امن',
          children: <Widget>[
            ToggleRow(
              icon: Icons.text_fields_rounded,
              title: 'درهم سازی حروف نام سرور',
              subtitle: 'ترکیب تصادفی حروف در نام دامنه ارسالی هنگام برقراری اتصال',
              value: tls.mixedSniCase,
              onChanged: (bool v) => saveTls(tls.copyWith(mixedSniCase: v)),
            ),
            const Divider(height: AppMetrics.space3),
            ToggleRow(
              icon: Icons.unfold_more_rounded,
              title: 'افزودن لایه پرکننده بسته',
              subtitle: 'تغییر اندازه بسته آغاز اتصال به بازه دلخواه',
              value: tls.enablePadding,
              onChanged: (bool v) => saveTls(tls.copyWith(enablePadding: v)),
            ),
            const Divider(height: AppMetrics.space3),
            _EditableValueRow(
              icon: Icons.photo_size_select_large_rounded,
              title: 'اندازه لایه پرکننده (بایت)',
              value: Fa.num(tls.paddingSize),
              ltrValue: true,
              onTap: () => _editTextValue(
                title: 'اندازه لایه پرکننده',
                label: 'عدد یا بازه بین ۱ تا ۱۶٬۰۰۰ (پیش فرض ۱۲۰۰-۱۵۰۰)',
                initialValue: tls.paddingSize,
                hint: '۱۲۰۰-۱۵۰۰',
                validator: (String v) => TlsTricksSettings.isValidRange(
                  v,
                  min: 1,
                  max: TlsTricksSettings.maxPaddingSize,
                )
                    ? null
                    : 'بازه عددی بین ۱ تا ۱۶٬۰۰۰ وارد کنید (مانند ۱۲۰۰-۱۵۰۰)',
                onSubmit: (String v) =>
                    saveTls(tls.copyWith(paddingSize: v.trim())),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryNavTile extends StatelessWidget {
  const _CategoryNavTile({
    required this.category,
    required this.onTap,
    this.badge,
  });

  final SettingsCategory category;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String subtitle = category.listSubtitle;
    final Color accent = category.accentColor(colors);

    return InkWell(
      key: ValueKey<String>('settings-category-${category.name}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space5,
          vertical: AppMetrics.space4,
        ),
        child: Row(
          children: <Widget>[
            IconSquare(
              icon: category.icon,
              color: accent,
              size: AppMetrics.iconBoxMd,
              radius: AppMetrics.radiusMd,
            ),
            const SizedBox(width: AppMetrics.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fa.num(category.title),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppMetrics.space1),
                  Text(
                    Fa.num(subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...<Widget>[
              Pill(
                label: badge!,
                icon: Icons.check_circle_rounded,
                color: accent,
                dense: true,
              ),
              const SizedBox(width: AppMetrics.space2),
            ],
            Icon(
              Icons.chevron_left_rounded,
              size: AppMetrics.iconMd,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableValueRow extends StatelessWidget {
  const _EditableValueRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.ltrValue = false,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool ltrValue;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space2,
          vertical: AppMetrics.space2,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: AppMetrics.iconMd, color: colors.textSecondary),
            const SizedBox(width: AppMetrics.space3),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: AppMetrics.space2),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  Fa.num(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltrValue ? TextDirection.ltr : null,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: valueColor ?? colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            const SizedBox(width: AppMetrics.space2),
            Icon(
              Icons.edit_rounded,
              size: AppMetrics.iconXs,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueInputDialog extends StatefulWidget {
  const _ValueInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.hint,
    required this.numericOnly,
    this.validator,
  });

  final String title;
  final String label;
  final String initialValue;
  final String hint;
  final bool numericOnly;
  final String? Function(String value)? validator;

  @override
  State<_ValueInputDialog> createState() => _ValueInputDialogState();
}

class _ValueInputDialogState extends State<_ValueInputDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: Fa.num(widget.initialValue));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = Fa.toEn(_ctrl.text.trim());
    final String? err = widget.validator?.call(value);
    if (err != null) {
      setState(() => _error = Fa.num(err));
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
        side: BorderSide(color: colors.border),
      ),
      title: Row(
        children: <Widget>[
          IconSquare(
            icon: widget.numericOnly
                ? Icons.pin_rounded
                : Icons.edit_note_rounded,
            color: colors.primary,
            size: AppMetrics.iconBoxSm,
            radius: AppMetrics.radiusSm,
          ),
          const SizedBox(width: AppMetrics.space3),
          Expanded(
            child: Text(
              Fa.num(widget.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textDirection: TextDirection.ltr,
        keyboardType:
            widget.numericOnly ? TextInputType.number : TextInputType.text,
        inputFormatters: widget.numericOnly
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹]')),
                const PersianDigitsFormatter(),
              ]
            : const <TextInputFormatter>[
                PersianDigitsFormatter(),
              ],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: Fa.num(widget.label),
          hintText: widget.hint.isEmpty ? null : Fa.num(widget.hint),
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

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
      radius: AppMetrics.radiusXl,
      padding: AppMetrics.responsiveCardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: title,
            subtitle: subtitle,
            icon: icon,
            trailing: trailing,
          ),
          const SizedBox(height: AppMetrics.space4),
          ...children,
        ],
      ),
    );
  }
}

class _ThemeCardSelector extends StatelessWidget {
  const _ThemeCardSelector({
    required this.selected,
    required this.onChanged,
  });

  final ThemePreference selected;
  final ValueChanged<ThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    const List<(ThemePreference, String, String)> items =
        <(ThemePreference, String, String)>[
      (ThemePreference.dark, 'تیره', 'کنتراست بالا و مناسب شب'),
      (ThemePreference.light, 'روشن', 'خوانا در محیط های پرنور'),
      (ThemePreference.system, 'هماهنگ با سیستم', 'تغییر خودکار با سیستم'),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scale = MediaQuery.textScalerOf(context)
            .scale(1)
            .clamp(1.0, 2.0)
            .toDouble();
        if (constraints.maxWidth / scale < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < items.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppMetrics.space2),
                _ThemeOptionCard(
                  preference: items[i].$1,
                  title: items[i].$2,
                  subtitle: items[i].$3,
                  selected: selected == items[i].$1,
                  onTap: () {
                    playUiClick(context);
                    onChanged(items[i].$1);
                  },
                ),
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < items.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppMetrics.space3),
                Expanded(
                  child: _ThemeOptionCard(
                    preference: items[i].$1,
                    title: items[i].$2,
                    subtitle: items[i].$3,
                    selected: selected == items[i].$1,
                    onTap: () {
                      playUiClick(context);
                      onChanged(items[i].$1);
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.preference,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final ThemePreference preference;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (preference) {
      case ThemePreference.dark:
        return Icons.dark_mode_rounded;
      case ThemePreference.light:
        return Icons.light_mode_rounded;
      case ThemePreference.system:
        return Icons.brightness_auto_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.12)
          : colors.surfaceHigh.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppMetrics.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(
              color: selected ? colors.primary : colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _icon,
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
