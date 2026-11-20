import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';

/// صفحه اختصاصی «دستگاه من»: فقط اطلاعات سخت افزار، حافظه، سیستم عامل، شبکه محلی
/// و شناسه یکتای همین رایانه (کاملاً مجزا از اطلاعات حساب کاربری و اشتراک).
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  DeviceProfile _device = DeviceProfile.empty;
  DateTime _now = DateTime.now();
  DateTime? _lastCheckedAt;
  Timer? _uptimeTimer;
  Timer? _autoRefreshTimer;
  bool _loading = true;
  bool _refreshing = false;
  bool _wasTabActive = false;

  @override
  void initState() {
    super.initState();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      unawaited(_refreshDevice());
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_refreshDevice(includePublicIp: true)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool active = TickerMode.of(context);
    if (active && !_wasTabActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_refreshDevice(includePublicIp: true));
        }
      });
    }
    _wasTabActive = active;
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshDevice({bool includePublicIp = false}) async {
    if (_refreshing) {
      return;
    }
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (_device.machineId.isEmpty && _device.hostname.isEmpty) {
          _loading = true;
        }
      });
    }
    final NativeBridge native = context.read<NativeBridge>();
    final VpnController vpn = context.read<VpnController>();

    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      native.deviceInfo().catchError((_) => DeviceProfile.empty),
      if (includePublicIp && !vpn.status.active && !vpn.status.busy)
        vpn.refreshIp().then<Object?>((_) => true).catchError((_) => false),
    ]);

    if (!mounted) {
      return;
    }
    final DeviceProfile fetched = results[0] is DeviceProfile
        ? results[0] as DeviceProfile
        : DeviceProfile.empty;

    final DateTime checked = DateTime.now();
    setState(() {
      if (fetched.hostname.isNotEmpty ||
          fetched.machineId.isNotEmpty ||
          fetched.localIp.isNotEmpty ||
          fetched.ramTotalMb > 0 ||
          fetched.diskTotalMb > 0) {
        _device = fetched;
      }
      _lastCheckedAt = checked;
      _now = checked;
      _loading = false;
      _refreshing = false;
    });
  }

  Future<void> _copy(String label, String value) async {
    final String clean = value.trim();
    if (clean.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: clean));
    if (!mounted) {
      return;
    }
    context.read<ToastController>().success('$label کپی شد');
  }

  /// نمایش فشرده و کاملاً فارسی شناسه سخت افزاری بدون حروف لاتین.
  static String _hardwareCodeFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'شناسایی نشده';
    }
    final String digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) {
      return 'کد ${Fa.num(digits.substring(0, 4))}•••${Fa.num(digits.substring(digits.length - 4))}';
    }
    if (digits.isNotEmpty) {
      return 'کد ${Fa.num(digits)}';
    }
    return 'ثبت شده و آماده کپی';
  }

  /// قالب بندی نشانی شبکه با ارقام فارسی و بدون حروف لاتین.
  static String _ipLabelFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'شناسایی نشده';
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(clean)) {
      return Fa.num(clean);
    }
    return 'فعال (نسل ششم)';
  }

  /// نمایش فارسی نام رایانه یا حساب ویندوز بدون نشت حروف لاتین.
  static String _systemNameFa(String raw, String fallback) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'شناسایی نشده';
    }
    if (RegExp(r'[A-Za-z]').hasMatch(clean)) {
      return fallback;
    }
    return Fa.num(clean);
  }

  /// گزارش متنی کاملاً فارسی و اختصاصی مشخصات فنی همین رایانه.
  String _buildDeviceReport(
    DeviceProfile device,
    int cores,
    Duration liveUptime,
    DateTime? bootAt,
  ) {
    return <String>[
      'گزارش مشخصات فنی دستگاه',
      'زمان تهیه گزارش: ${Fa.tehranFullDateTime(_now)}',
      'نوع دستگاه: ${device.formFactorFa}',
      'سیستم عامل: ${device.platformLabel}',
      if (device.osVersionLabelFa.isNotEmpty)
        'ویرایش سالانه ویندوز: ${device.osVersionLabelFa}',
      'پردازنده مرکزی: ${device.cpuLabelFa}',
      'رشته های پردازشی: ${Fa.num(cores)} هسته منطقی',
      if (device.ramTotalMb > 0)
        'حافظه رم: ${Fa.decimal(device.ramUsedGb, fraction: 1)} از '
            '${Fa.decimal(device.ramTotalGb, fraction: 1)} گیگابایت '
            '(${Fa.percent(device.ramPercent)})',
      if (device.diskTotalMb > 0)
        'درایو سیستم ویندوز: ${Fa.decimal(device.diskUsedGb, fraction: 1)} از '
            '${Fa.decimal(device.diskTotalGb, fraction: 1)} گیگابایت '
            '(آزاد: ${Fa.decimal(device.diskFreeGb, fraction: 1)} گیگابایت)',
      if (device.screenWidth > 0 && device.screenHeight > 0)
        'وضوح نمایشگر اصلی: ${device.screenLabelFa}',
      'منبع تغذیه: ${device.powerLabelFa}',
      'سطح دسترسی برنامه: ${device.elevated ? 'مدیر سیستم (کامل)' : 'کاربر استاندارد'}',
      if (liveUptime > Duration.zero)
        'مدت روشن بودن ویندوز: ${Fa.spanFa(liveUptime)}',
      if (bootAt != null)
        'زمان روشن شدن رایانه: ${Fa.tehranFullDateTime(bootAt, seconds: false)}',
      'نوع کارت شبکه: ${device.adapterLabelFa}',
      if (device.localIp.isNotEmpty)
        'نشانی شبکه داخلی: ${_ipLabelFa(device.localIp)}',
      'نسخه نرم افزار: ${Fa.num(AppConfig.versionPhrase)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final UmbrellaColors colors = context.colors;

    final DeviceProfile device = (_device.hostname.isEmpty &&
            _device.machineId.isEmpty &&
            _device.localIp.isEmpty &&
            _device.ramTotalMb <= 0)
        ? vpn.device
        : _device;

    final int cores =
        device.cpuCores > 0 ? device.cpuCores : Platform.numberOfProcessors;
    final int build = device.resolvedOsBuild;
    final bool hasLocalIp = device.localIp.isNotEmpty;
    final bool hasMac = device.mac.isNotEmpty;
    final bool hasRam = device.ramTotalMb > 0;
    final bool hasDisk = device.diskTotalMb > 0;
    final bool tunnelProtected = vpn.status == VpnStatus.connected;

    final int elapsedSinceCheck = _lastCheckedAt == null
        ? 0
        : _now.difference(_lastCheckedAt!).inSeconds.clamp(0, 86400);
    final Duration liveUptime = device.uptimeSeconds > 0
        ? Duration(seconds: device.uptimeSeconds + elapsedSinceCheck)
        : Duration.zero;
    final DateTime? bootAt = liveUptime > Duration.zero
        ? _now.toUtc().subtract(liveUptime)
        : null;

    final double ramPct = device.ramPercent;
    final Color ramTone = !hasRam
        ? colors.info
        : (ramPct >= 85
            ? colors.danger
            : (ramPct >= 70 ? colors.warning : colors.success));

    final String internetAddressStatus = tunnelProtected
        ? 'محافظت شده در تونل امن'
        : (vpn.realIp.isNotEmpty
            ? _ipLabelFa(vpn.realIp)
            : (hasLocalIp ? 'متصل به اینترنت' : 'در حال بررسی شبکه'));

    final List<Widget> summaryTiles = <Widget>[
      _DeviceMetricTile(
        icon: Icons.window_rounded,
        accent: colors.primary,
        label: 'سیستم عامل',
        value: device.osTitleFa,
        caption: build > 0
            ? 'ساخت ${Fa.grouped(build)} • ${device.archLabelFa}'
            : device.archLabelFa,
      ),
      _DeviceMetricTile(
        icon: Icons.developer_board_rounded,
        accent: colors.info,
        label: 'پردازنده مرکزی',
        value: '${Fa.num(cores)} هسته منطقی',
        caption: device.cpuLabelFa,
      ),
      _DeviceMetricTile(
        icon: Icons.memory_rounded,
        accent: ramTone,
        label: 'حافظه رم سیستم',
        value: hasRam
            ? '${Fa.decimal(ramPct, fraction: 0)} درصد فعال'
            : 'در حال پایش',
        caption: hasRam
            ? '${Fa.decimal(device.ramUsedGb, fraction: 1)} از ${Fa.decimal(device.ramTotalGb, fraction: 1)} گیگابایت'
            : 'حافظه اصلی ویندوز',
      ),
      _DeviceMetricTile(
        icon: Icons.timer_outlined,
        accent: colors.success,
        label: 'کارکرد پیوسته سیستم',
        value: liveUptime > Duration.zero
            ? Fa.spanFa(liveUptime, includeMinutes: liveUptime.inDays == 0)
            : 'فعال و آماده',
        caption: bootAt != null
            ? 'روشن شده: ${Fa.tehranDate(bootAt)} ساعت ${Fa.tehranClock(bootAt, seconds: false)}'
            : 'زمان سنج سیستم عامل',
      ),
    ];

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'دستگاه من',
            subtitle:
                'مشخصات سخت افزار، حافظه، سیستم عامل، شبکه محلی و شناسه این رایانه',
            icon: Icons.devices_rounded,
            actions: _loading
                ? const <Widget>[
                    SizedBox(
                      width: AppMetrics.iconSm,
                      height: AppMetrics.iconSm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ]
                : const <Widget>[],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نوار هویت اختصاصی رایانه ───────────────────────────────────
          PageBanner(
            leading: IconSquare(
              icon: device.hasBattery
                  ? Icons.laptop_windows_rounded
                  : Icons.computer_rounded,
              color: colors.primary,
              size: AppMetrics.iconBoxHero,
              radius: AppMetrics.radiusLg,
            ),
            title: _systemNameFa(device.hostname, device.formFactorFa),
            subtitle: '${device.platformLabel}  •  ${device.cpuLabelFa}',
            badges: <Widget>[
              Pill(
                label: device.elevated ? 'دسترسی مدیر فعال' : 'کاربر استاندارد',
                icon: device.elevated
                    ? Icons.verified_user_rounded
                    : Icons.gpp_maybe_rounded,
                color: device.elevated ? colors.success : colors.warning,
                dense: true,
              ),
              Pill(
                label: hasLocalIp ? 'شبکه محلی متصل' : 'بررسی شبکه',
                icon: Icons.lan_rounded,
                color: hasLocalIp ? colors.success : colors.warning,
                dense: true,
              ),
              Pill(
                label: device.adapterLabelFa,
                icon: Icons.wifi_rounded,
                color: colors.info,
                dense: true,
              ),
              Pill(
                label: device.hasBattery && device.batteryPercent >= 0
                    ? 'باتری ${Fa.num(device.batteryPercent)}٪'
                    : 'برق مستقیم',
                icon: device.hasBattery
                    ? (device.powerPlugged
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_std_rounded)
                    : Icons.power_rounded,
                color: device.hasBattery &&
                        device.batteryPercent >= 0 &&
                        device.batteryPercent <= 20 &&
                        !device.powerPlugged
                    ? colors.danger
                    : colors.primary,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── چهار کارت شاخص کلیدی هم اندازه سخت افزار و سیستم ──────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth >= AppMetrics.breakpointColumns) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: summaryTiles[0]),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(child: summaryTiles[1]),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(child: summaryTiles[2]),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(child: summaryTiles[3]),
                    ],
                  ),
                );
              }
              if (constraints.maxWidth >= AppMetrics.breakpointCompact) {
                return Column(
                  children: <Widget>[
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: summaryTiles[0]),
                          const SizedBox(width: AppMetrics.space3),
                          Expanded(child: summaryTiles[1]),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppMetrics.space3),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: summaryTiles[2]),
                          const SizedBox(width: AppMetrics.space3),
                          Expanded(child: summaryTiles[3]),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  summaryTiles[0],
                  const SizedBox(height: AppMetrics.space3),
                  summaryTiles[1],
                  const SizedBox(height: AppMetrics.space3),
                  summaryTiles[2],
                  const SizedBox(height: AppMetrics.space3),
                  summaryTiles[3],
                ],
              );
            },
          ),
          const SizedBox(height: AppMetrics.space5),

          // ── ردیف اول: منابع حافظه و ذخیره سازی + سخت افزار و نمایشگر ───
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget memoryCard = _MemoryAndStorageCard(
                device: device,
                hasRam: hasRam,
                hasDisk: hasDisk,
                ramTone: ramTone,
                colors: colors,
              );
              final Widget hardwareCard = _ProcessorAndSystemCard(
                device: device,
                cores: cores,
                liveUptime: liveUptime,
                bootAt: bootAt,
                colors: colors,
              );
              if (constraints.maxWidth >= AppMetrics.breakpointColumns) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: memoryCard),
                      const SizedBox(width: AppMetrics.space5),
                      Expanded(child: hardwareCard),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  memoryCard,
                  const SizedBox(height: AppMetrics.space4),
                  hardwareCard,
                ],
              );
            },
          ),
          const SizedBox(height: AppMetrics.space5),

          // ── ردیف دوم: رابط شبکه رایانه + شناسه و امنیت دستگاه ──────────
          ResponsiveColumns(
            leftFlex: 1,
            rightFlex: 1,
            spacing: AppMetrics.space5,
            left: GlassCard(
              padding: AppMetrics.cardPadding,
              radius: AppMetrics.radiusXl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SectionHeader(
                    icon: Icons.lan_rounded,
                    title: 'شبکه و رابط ارتباطی رایانه',
                    subtitle: 'وضعیت کارت شبکه فیزیکی و نشانی های فعال سیستم',
                    trailing: Pill(
                      label: hasLocalIp ? 'متصل' : 'نامشخص',
                      color: hasLocalIp ? colors.success : colors.warning,
                      dense: true,
                    ),
                  ),
                  const Divider(height: AppMetrics.space5),
                  InfoRow(
                    icon: Icons.settings_ethernet_rounded,
                    label: 'نوع کارت شبکه فعال',
                    value: device.adapterLabelFa,
                  ),
                  const Divider(height: AppMetrics.space3),
                  InfoRow(
                    icon: Icons.router_rounded,
                    label: 'نشانی شبکه داخلی',
                    value: _ipLabelFa(device.localIp),
                    trailing: hasLocalIp
                        ? IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی نشانی شبکه داخلی',
                            size: AppMetrics.iconBoxSm,
                            onTap: () =>
                                _copy('نشانی شبکه داخلی', device.localIp),
                          )
                        : null,
                  ),
                  const Divider(height: AppMetrics.space3),
                  InfoRow(
                    icon: Icons.travel_explore_rounded,
                    label: 'وضعیت نشانی اینترنت',
                    value: internetAddressStatus,
                    valueColor:
                        tunnelProtected ? colors.success : colors.textPrimary,
                    trailing: (!tunnelProtected && vpn.realIp.isNotEmpty)
                        ? IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی نشانی اینترنت',
                            size: AppMetrics.iconBoxSm,
                            onTap: () =>
                                _copy('نشانی اینترنت دستگاه', vpn.realIp),
                          )
                        : null,
                  ),
                  const Divider(height: AppMetrics.space3),
                  InfoRow(
                    icon: Icons.perm_device_information_rounded,
                    label: 'شناسه فیزیکی کارت شبکه',
                    value: hasMac ? 'ثبت شده و آماده کپی' : 'شناسایی نشده',
                    trailing: hasMac
                        ? IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی شناسه فیزیکی کارت شبکه',
                            size: AppMetrics.iconBoxSm,
                            onTap: () =>
                                _copy('شناسه فیزیکی کارت شبکه', device.mac),
                          )
                        : null,
                  ),
                  const Divider(height: AppMetrics.space3),
                  InfoRow(
                    icon: Icons.update_rounded,
                    label: 'آخرین بررسی شبکه و سیستم',
                    value: _lastCheckedAt == null
                        ? 'در حال بررسی'
                        : Fa.tehranFullDateTime(_lastCheckedAt),
                    tooltip: true,
                  ),
                ],
              ),
            ),
            right: GlassCard(
              padding: AppMetrics.cardPadding,
              radius: AppMetrics.radiusXl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SectionHeader(
                    icon: Icons.phonelink_lock_rounded,
                    title: 'هویت و امنیت این دستگاه',
                    subtitle: 'شناسه سخت افزاری ویندوز و سطح مجوز اجرایی برنامه',
                    trailing: Pill(
                      label: device.machineId.isNotEmpty
                          ? 'شناسایی شده'
                          : 'در حال بررسی',
                      color: device.machineId.isNotEmpty
                          ? colors.success
                          : colors.textSecondary,
                      dense: true,
                    ),
                  ),
                  const Divider(height: AppMetrics.space5),
                  InfoRow(
                    icon: Icons.desktop_windows_rounded,
                    label: 'نام رایانه در ویندوز',
                    value: _systemNameFa(device.hostname, 'ثبت شده در ویندوز'),
                    trailing: device.hostname.isEmpty
                        ? null
                        : IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی نام رایانه',
                            size: AppMetrics.iconBoxSm,
                            onTap: () => _copy('نام رایانه', device.hostname),
                          ),
                  ),
                  const Divider(height: AppMetrics.space3),
                  InfoRow(
                    icon: Icons.account_box_rounded,
                    label: 'حساب کاربری ویندوز',
                    value: _systemNameFa(device.username, 'کاربر محلی ویندوز'),
                    trailing: device.username.isEmpty
                        ? null
                        : IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی نام کاربری ویندوز',
                            size: AppMetrics.iconBoxSm,
                            onTap: () =>
                                _copy('نام کاربری ویندوز', device.username),
                          ),
                  ),
                  const Divider(height: AppMetrics.space3),
                  InfoRow(
                    icon: Icons.fingerprint_rounded,
                    label: 'شناسه یکتای سخت افزاری',
                    value: _hardwareCodeFa(device.machineId),
                    trailing: device.machineId.isEmpty
                        ? null
                        : IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی شناسه یکتای دستگاه',
                            size: AppMetrics.iconBoxSm,
                            onTap: () =>
                                _copy('شناسه یکتای دستگاه', device.machineId),
                          ),
                  ),
                  const Divider(height: AppMetrics.space3),
                  InfoRow(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'سطح دسترسی اجرایی',
                    value: device.elevated
                        ? 'مدیر سیستم (دسترسی کامل)'
                        : 'کاربر استاندارد',
                    valueColor:
                        device.elevated ? colors.success : colors.warning,
                  ),
                  const SizedBox(height: AppMetrics.space4),
                  SizedBox(
                    height: AppMetrics.controlHeightSmall,
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.copy_all_rounded,
                        size: AppMetrics.iconSm,
                      ),
                      label: const Text('کپی مشخصات فنی این دستگاه'),
                      onPressed: () => _copy(
                        'مشخصات فنی دستگاه',
                        _buildDeviceReport(device, cores, liveUptime, bootAt),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// کارت شاخص سریع ویژه مشخصات دستگاه.
class _DeviceMetricTile extends StatelessWidget {
  const _DeviceMetricTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return GlassCard(
      padding: const EdgeInsets.all(AppMetrics.space4),
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: icon,
                color: accent,
                size: AppMetrics.iconBoxMd,
                radius: AppMetrics.radiusMd,
              ),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppMetrics.space1),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// کارت پایش زنده حافظه رم و فضای ذخیره سازی درایو سیستم ویندوز.
class _MemoryAndStorageCard extends StatelessWidget {
  const _MemoryAndStorageCard({
    required this.device,
    required this.hasRam,
    required this.hasDisk,
    required this.ramTone,
    required this.colors,
  });

  final DeviceProfile device;
  final bool hasRam;
  final bool hasDisk;
  final Color ramTone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final double ramPct = device.ramPercent;
    final double diskPct = device.diskPercent;
    final Color diskTone = !hasDisk
        ? colors.info
        : (diskPct >= 90
            ? colors.danger
            : (diskPct >= 75 ? colors.warning : colors.info));
    final String ramState = !hasRam
        ? 'فعال'
        : (ramPct >= 85
            ? 'مصرف بالا'
            : (ramPct >= 70 ? 'متعادل' : 'سبک و بهینه'));

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.memory_rounded,
            title: 'حافظه رم و فضای ذخیره سازی',
            subtitle: 'پایش زنده مصرف حافظه اصلی و درایو سیستم ویندوز',
            trailing: Pill(
              label: ramState,
              color: ramTone,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          Row(
            children: <Widget>[
              SizedBox(
                width: AppMetrics.logoMd,
                height: AppMetrics.logoMd,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: AppMetrics.logoMd,
                      height: AppMetrics.logoMd,
                      child: CircularProgressIndicator(
                        value: hasRam ? (ramPct / 100).clamp(0, 1) : 0,
                        strokeWidth: 6,
                        backgroundColor: colors.surfaceHigh,
                        valueColor: AlwaysStoppedAnimation<Color>(ramTone),
                      ),
                    ),
                    Text(
                      hasRam ? '${Fa.decimal(ramPct, fraction: 0)}٪' : '—',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: ramTone,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppMetrics.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      hasRam
                          ? '${Fa.decimal(device.ramUsedGb, fraction: 1)} از ${Fa.decimal(device.ramTotalGb, fraction: 1)} گیگابایت'
                          : 'حافظه اصلی سیستم',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      hasRam
                          ? 'حافظه رم آزاد: ${Fa.decimal(device.ramFreeGb, fraction: 1)} گیگابایت'
                          : 'اطلاعات حافظه پس از بررسی بومی نمایش داده می شود',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            child: LinearProgressIndicator(
              value: hasRam ? (ramPct / 100).clamp(0, 1) : 0,
              minHeight: AppMetrics.space2,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(ramTone),
            ),
          ),
          const Divider(height: AppMetrics.space5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  'فضای درایو سیستم ویندوز',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                hasDisk ? Fa.percent(diskPct) : 'در حال بررسی',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: diskTone,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space2),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            child: LinearProgressIndicator(
              value: hasDisk ? (diskPct / 100).clamp(0, 1) : 0,
              minHeight: AppMetrics.space2,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(diskTone),
            ),
          ),
          const SizedBox(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.storage_rounded,
            label: 'ظرفیت کل درایو سیستم',
            value: hasDisk
                ? '${Fa.decimal(device.diskTotalGb, fraction: 1)} گیگابایت'
                : 'شناسایی نشده',
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.folder_open_rounded,
            label: 'فضای خالی قابل استفاده',
            value: hasDisk
                ? '${Fa.decimal(device.diskFreeGb, fraction: 1)} گیگابایت'
                : 'شناسایی نشده',
            valueColor: hasDisk ? colors.success : colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// کارت مشخصات پردازنده، سیستم عامل، نمایشگر، تغذیه و زمان روشن شدن شمسی.
class _ProcessorAndSystemCard extends StatelessWidget {
  const _ProcessorAndSystemCard({
    required this.device,
    required this.cores,
    required this.liveUptime,
    required this.bootAt,
    required this.colors,
  });

  final DeviceProfile device;
  final int cores;
  final Duration liveUptime;
  final DateTime? bootAt;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final String annualVer = device.osVersionLabelFa.isEmpty
        ? 'نسخه رسمی پایدار'
        : device.osVersionLabelFa;
    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.developer_board_rounded,
            title: 'سخت افزار، نمایشگر و سیستم عامل',
            subtitle: 'اجزای پردازشی، نسخه ویندوز و زمان دقیق روشن شدن به شمسی',
            trailing: Pill(
              label: device.archLabelFa,
              color: colors.primary,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.window_rounded,
            label: 'سیستم عامل و شماره ساخت',
            value: device.osLabelFa,
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.layers_rounded,
            label: 'ویرایش سالانه ویندوز',
            value: annualVer,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.memory_rounded,
            label: 'مدل پردازنده مرکزی',
            value: '${device.cpuLabelFa} (${Fa.num(cores)} هسته)',
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.monitor_rounded,
            label: 'وضوح نمایشگر اصلی',
            value: device.screenLabelFa,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: device.hasBattery
                ? Icons.battery_charging_full_rounded
                : Icons.power_rounded,
            label: 'منبع تغذیه و باتری',
            value: device.powerLabelFa,
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.timer_outlined,
            label: 'مدت روشن بودن ویندوز',
            value: liveUptime > Duration.zero
                ? Fa.spanFa(liveUptime)
                : 'در حال محاسبه',
          ),
          const Divider(height: AppMetrics.space2),
          InfoRow(
            icon: Icons.restart_alt_rounded,
            label: 'زمان روشن شدن رایانه',
            value: bootAt == null
                ? 'شناسایی نشده'
                : Fa.tehranFullDateTime(bootAt, seconds: false),
            tooltip: true,
          ),
        ],
      ),
    );
  }
}
