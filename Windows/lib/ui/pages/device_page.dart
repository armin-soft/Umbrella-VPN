import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';

enum _DeviceSectionTab {
  overview,
  network,
  hardware,
}

/// صفحه پیشرفته «دستگاه من»: پایش زنده اشتراک پنل، تقویم دقیق شمسی، شبکه و سخت افزار.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  _DeviceSectionTab _activeTab = _DeviceSectionTab.overview;
  DeviceProfile _device = DeviceProfile.empty;
  DateTime _now = DateTime.now();
  DateTime? _lastSyncAt;
  Timer? _clockTimer;
  bool _loading = true;
  bool _syncing = false;
  bool _panelSynced = false;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAll(silent: true));
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncAll({bool silent = false}) async {
    if (_syncing) {
      return;
    }
    if (mounted) {
      setState(() {
        _syncing = true;
        if (_device.machineId.isEmpty) {
          _loading = true;
        }
      });
    }
    final NativeBridge native = context.read<NativeBridge>();
    final AuthController auth = context.read<AuthController>();
    final VpnController vpn = context.read<VpnController>();

    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      native.deviceInfo().catchError((_) => DeviceProfile.empty),
      auth.refreshFromPanel().catchError((_) => false),
      if (!silent) vpn.refreshIp().then<Object?>((_) => true).catchError((_) => false),
    ]);

    if (!mounted) {
      return;
    }
    final DeviceProfile fetched = results[0] is DeviceProfile
        ? results[0] as DeviceProfile
        : DeviceProfile.empty;
    final bool panelOk = results[1] == true;

    setState(() {
      if (fetched.hostname.isNotEmpty ||
          fetched.machineId.isNotEmpty ||
          fetched.localIp.isNotEmpty ||
          fetched.ramTotalMb > 0) {
        _device = fetched;
      }
      _panelSynced = panelOk || _panelSynced;
      _lastSyncAt = DateTime.now();
      _now = DateTime.now();
      _loading = false;
      _syncing = false;
    });

    if (!silent) {
      context.read<ToastController>().success(
            panelOk
                ? 'اطلاعات دستگاه و پنل کاربری به روز شد'
                : 'اطلاعات سخت افزار و شبکه دستگاه به روز شد',
          );
    }
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

  /// نمایش فشرده و کاملاً فارسی شناسه های طولانی بدون شلوغ کردن صفحه.
  static String _compactCodeFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'ثبت نشده';
    }
    final String digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= 8) {
      return 'کد ${Fa.num(digitsOnly.substring(0, 4))}•••${Fa.num(digitsOnly.substring(digitsOnly.length - 4))}';
    }
    if (digitsOnly.isNotEmpty) {
      return 'کد ${Fa.num(digitsOnly)}';
    }
    return 'ثبت شده و آماده کپی';
  }

  /// نمایش کاملاً فارسی وضعیت نشانی نسل ششم بدون حروف لاتین.
  static String _ipv6LabelFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'غیرفعال یا خودکار';
    }
    final List<String> parts = clean.split('::');
    final String tail = parts.length > 1 ? parts.last : '';
    if (tail.isNotEmpty && RegExp(r'^\d+$').hasMatch(tail)) {
      return 'فعال • گره شماره ${Fa.num(tail)}';
    }
    return 'فعال و آماده کپی';
  }

  /// قالب بندی نشانی شبکه با ارقام کاملاً فارسی و بدون حروف لاتین.
  static String _formatAddressFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'شناسایی نشده';
    }
    if (clean.contains(':')) {
      return _ipv6LabelFa(clean);
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(clean)) {
      return Fa.num(clean);
    }
    return 'فعال و آماده کپی';
  }

  /// نمایش نام صاحب اشتراک به فارسی و با ارقام فارسی.
  static String _ownerNameFa(Account account) {
    final String raw = account.displayName.trim();
    if (raw.isEmpty || RegExp(r'[A-Za-z]').hasMatch(raw)) {
      return 'کاربر آمبرلا';
    }
    return Fa.num(raw);
  }

  /// نمایش شماره همراه به همراه نام فارسی اپراتور.
  static String _phoneWithOperatorFa(String raw) {
    final String clean = raw.trim();
    if (clean.isEmpty) {
      return 'ثبت نشده';
    }
    final String formatted = Fa.phoneFa(clean);
    final MobileOperator op = IranPhone.operator(clean);
    if (op == MobileOperator.unknown) {
      return formatted;
    }
    return '$formatted (${op.label})';
  }

  /// گزارش متنی کاملاً فارسی برای کپی با یک کلیک.
  String _buildPersianSummary(DeviceProfile device, Account account, int cores) {
    final DateTime tehranNow = Fa.toTehran(_now);
    final DateTime? expiry = account.effectiveExpiryDate;
    return <String>[
      'گزارش مشخصات دستگاه و اشتراک آمبرلا',
      'زمان تهیه گزارش: ${Fa.fullDate(tehranNow)} • ساعت ${Fa.clock(tehranNow)}',
      'صاحب اشتراک: ${_ownerNameFa(account)}',
      if (account.panelId > 0) 'کد کاربری پنل: ${Fa.grouped(account.panelId)}',
      'وضعیت اشتراک: ${account.statusLabelFa}',
      if (!account.unlimited)
        'مصرف ترافیک: ${Fa.gb(account.currentUsageGb)} از ${Fa.gb(account.usageLimitGb)} '
            '(باقی مانده: ${Fa.gb(account.remainingGb)})',
      if (account.startDate != null)
        'تاریخ شروع بسته: ${Fa.tehranFullDate(account.startDate)} (${Fa.tehranDate(account.startDate)})',
      if (expiry != null)
        'تاریخ پایان اعتبار: ${Fa.tehranFullDate(expiry)} (${Fa.tehranDate(expiry)})',
      if (expiry != null)
        'اعتبار زمانی باقی مانده: ${Fa.spanFa(account.remainingDuration(_now))}',
      if (account.lastOnline != null)
        'آخرین فعالیت آنلاین: ${Fa.tehranFullDateTime(account.lastOnline)}',
      'سیستم عامل: ${device.platformLabel}',
      'پردازنده: ${device.cpuLabelFa} (${Fa.num(cores)} هسته)',
      if (device.ramTotalMb > 0)
        'حافظه رم: ${Fa.decimal(device.ramUsedGb)} از ${Fa.decimal(device.ramTotalGb)} گیگابایت '
            '(${Fa.percent(device.ramPercent)})',
      if (device.localIp.isNotEmpty)
        'نشانی شبکه محلی: ${Fa.num(device.localIp)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final UmbrellaColors colors = context.colors;

    final DeviceProfile device = (_device.hostname.isEmpty &&
            _device.machineId.isEmpty &&
            _device.localIp.isEmpty)
        ? vpn.device
        : _device;
    final Account account = auth.account;
    final DateTime tehranNow = Fa.toTehran(_now);

    final bool tunnelProtected = vpn.status == VpnStatus.connected;
    final bool onlineNow = tunnelProtected || account.isOnlineRecently(_now);
    final bool hasLocalIp = device.localIp.isNotEmpty;
    final int cores = device.cpuCores > 0
        ? device.cpuCores
        : Platform.numberOfProcessors;

    final int liveUptimeSeconds = device.uptimeSeconds > 0
        ? device.uptimeSeconds +
            (_lastSyncAt == null
                ? 0
                : _now.difference(_lastSyncAt!).inSeconds.clamp(0, 86400))
        : 0;
    final Duration liveUptime = Duration(seconds: liveUptimeSeconds);

    final int tunnelAddrCount = <String>[
      device.localIp,
      account.wgIpv4,
      account.wgIpv6,
      account.awgIpv4,
      account.awgIpv6,
    ].where((String item) => item.trim().isNotEmpty).length;

    final Color accountTone = !account.enable ||
            account.isExpiredAt(_now) ||
            account.quotaFinished
        ? colors.danger
        : (!account.isActive ? colors.warning : colors.success);

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'دستگاه من',
            subtitle:
                'پایش هوشمند سیستم، شبکه، اشتراک کاربری و محاسبه دقیق تاریخ و ساعت شمسی',
            icon: Icons.devices_rounded,
            actions: <Widget>[
              OutlinedButton.icon(
                onPressed: (_loading || _syncing)
                    ? null
                    : () => _syncAll(silent: false),
                icon: (_loading || _syncing)
                    ? const SizedBox(
                        width: AppMetrics.iconXs,
                        height: AppMetrics.iconXs,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: AppMetrics.iconSm),
                label: Text(
                  (_loading || _syncing) ? 'در حال دریافت...' : 'همگام سازی زنده',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نوار هویت و ساعت رسمی زنده شمسی ───────────────────────────
          PageBanner(
            leading: IconSquare(
              icon: Icons.computer_rounded,
              color: colors.primary,
              size: AppMetrics.iconBoxHero,
              radius: AppMetrics.radiusLg,
            ),
            title: '${_ownerNameFa(account)} • رایانه شخصی ویندوز',
            subtitle:
                '${device.platformLabel}  •  ${Fa.fullDate(tehranNow)} ساعت ${Fa.clock(tehranNow)}',
            badges: <Widget>[
              Pill(
                label: onlineNow ? 'آنلاین و فعال' : account.statusLabelFa,
                icon: onlineNow
                    ? Icons.circle
                    : (account.canConnect
                        ? Icons.verified_rounded
                        : Icons.error_outline_rounded),
                color: onlineNow ? colors.success : accountTone,
                dense: true,
              ),
              Pill(
                label: device.elevated ? 'دسترسی مدیر فعال' : 'کاربر استاندارد',
                icon: device.elevated
                    ? Icons.verified_user_rounded
                    : Icons.gpp_maybe_rounded,
                color: device.elevated ? colors.success : colors.warning,
                dense: true,
              ),
              Pill(
                label: hasLocalIp ? 'شبکه متصل' : 'بررسی شبکه',
                icon: Icons.wifi_rounded,
                color: hasLocalIp ? colors.info : colors.warning,
                dense: true,
              ),
              if (account.panelId > 0)
                Pill(
                  label: 'شناسه کاربری ${Fa.grouped(account.panelId)}',
                  icon: Icons.tag_rounded,
                  color: colors.primary,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نوار دسته بندی پیشرفته بخش های دستگاه من ──────────────────
          _DeviceTabBar(
            active: _activeTab,
            networkCount: tunnelAddrCount,
            coreCount: cores,
            onSelect: (_DeviceSectionTab next) {
              if (_activeTab != next) {
                setState(() => _activeTab = next);
              }
            },
          ),
          const SizedBox(height: AppMetrics.space5),

          // ── محتوای بخش انتخاب شده ─────────────────────────────────────
          _buildTabBody(
            context: context,
            colors: colors,
            device: device,
            account: account,
            vpn: vpn,
            tehranNow: tehranNow,
            liveUptime: liveUptime,
            cores: cores,
            tunnelProtected: tunnelProtected,
            onlineNow: onlineNow,
            accountTone: accountTone,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody({
    required BuildContext context,
    required UmbrellaColors colors,
    required DeviceProfile device,
    required Account account,
    required VpnController vpn,
    required DateTime tehranNow,
    required Duration liveUptime,
    required int cores,
    required bool tunnelProtected,
    required bool onlineNow,
    required Color accountTone,
  }) {
    switch (_activeTab) {
      case _DeviceSectionTab.overview:
        return _buildOverviewTab(
          context: context,
          colors: colors,
          device: device,
          account: account,
          tehranNow: tehranNow,
          cores: cores,
          onlineNow: onlineNow,
          accountTone: accountTone,
        );
      case _DeviceSectionTab.network:
        return _buildNetworkTab(
          context: context,
          colors: colors,
          device: device,
          account: account,
          vpn: vpn,
          tunnelProtected: tunnelProtected,
        );
      case _DeviceSectionTab.hardware:
        return _buildHardwareTab(
          context: context,
          colors: colors,
          device: device,
          account: account,
          liveUptime: liveUptime,
          cores: cores,
        );
    }
  }

  Widget _buildOverviewTab({
    required BuildContext context,
    required UmbrellaColors colors,
    required DeviceProfile device,
    required Account account,
    required DateTime tehranNow,
    required int cores,
    required bool onlineNow,
    required Color accountTone,
  }) {
    final DateTime? expiry = account.effectiveExpiryDate;
    final bool expired = account.isExpiredAt(_now);
    final Duration remDuration = account.remainingDuration(_now);
    final int daysLeft = account.daysLeftAt(_now);
    final int remHours = remDuration.inHours.remainder(24);
    final bool soon = expiry != null && !expired && daysLeft <= 7;
    final Color timeTone =
        expired ? colors.danger : (soon ? colors.warning : colors.success);

    final double usedGb = account.currentUsageGb;
    final double limitGb = account.usageLimitGb;
    final double remGb = account.remainingGb;
    final double usedPct = account.usagePercent;
    final bool unlimited = account.unlimited;
    final Color quotaTone = unlimited
        ? colors.success
        : (usedPct >= 90
            ? colors.danger
            : (usedPct >= 75 ? colors.warning : colors.success));

    final List<Widget> kpiCards = <Widget>[
      _MetricSummaryCard(
        icon: Icons.event_available_rounded,
        accent: timeTone,
        label: 'اعتبار زمانی باقی مانده',
        value: expiry == null
            ? 'نامحدود'
            : (expired
                ? 'منقضی شده'
                : (daysLeft > 0
                    ? '${Fa.grouped(daysLeft)} روز'
                    : '${Fa.num(remHours)} ساعت')),
        caption: expiry == null
            ? 'بدون محدودیت زمانی'
            : (expired
                ? 'پایان در ${Fa.tehranDate(expiry)}'
                : 'تا ${Fa.longDate(Fa.toTehran(expiry))}'),
      ),
      _MetricSummaryCard(
        icon: Icons.data_usage_rounded,
        accent: quotaTone,
        label: 'حجم قابل استفاده',
        value: unlimited ? 'نامحدود' : Fa.gb(remGb),
        caption: unlimited
            ? 'مصرف کل: ${Fa.gb(usedGb)}'
            : 'از مجموع ${Fa.grouped(limitGb)} گیگابایت',
      ),
      _MetricSummaryCard(
        icon: Icons.access_time_filled_rounded,
        accent: onlineNow ? colors.success : colors.info,
        label: 'آخرین فعالیت آنلاین',
        value: account.lastOnline == null
            ? (onlineNow ? 'همین حالا' : 'ثبت نشده')
            : (account.isOnlineRecently(_now)
                ? 'آنلاین (همین حالا)'
                : Fa.relative(account.lastOnline, now: _now)),
        caption: account.lastOnline == null
            ? 'آماده همگام سازی با پنل'
            : '${Fa.tehranDate(account.lastOnline)} • ساعت ${Fa.tehranClock(account.lastOnline, seconds: false)}',
      ),
      _MetricSummaryCard(
        icon: Icons.memory_rounded,
        accent: colors.primary,
        label: device.ramTotalMb > 0 ? 'حافظه و پردازنده' : 'توان پردازشی دستگاه',
        value: device.ramTotalMb > 0
            ? '${Fa.decimal(device.ramPercent, fraction: 0)} درصد رم'
            : '${Fa.num(cores)} هسته فعال',
        caption: device.ramTotalMb > 0
            ? '${Fa.decimal(device.ramUsedGb)} از ${Fa.decimal(device.ramTotalGb)} گیگابایت • ${Fa.num(cores)} هسته'
            : device.platformLabel,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── چهار کارت شاخص کلیدی هم اندازه ────────────────────────────
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth >= AppMetrics.breakpointColumns) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: kpiCards[0]),
                    const SizedBox(width: AppMetrics.space3),
                    Expanded(child: kpiCards[1]),
                    const SizedBox(width: AppMetrics.space3),
                    Expanded(child: kpiCards[2]),
                    const SizedBox(width: AppMetrics.space3),
                    Expanded(child: kpiCards[3]),
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
                        Expanded(child: kpiCards[0]),
                        const SizedBox(width: AppMetrics.space3),
                        Expanded(child: kpiCards[1]),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppMetrics.space3),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(child: kpiCards[2]),
                        const SizedBox(width: AppMetrics.space3),
                        Expanded(child: kpiCards[3]),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                kpiCards[0],
                const SizedBox(height: AppMetrics.space3),
                kpiCards[1],
                const SizedBox(height: AppMetrics.space3),
                kpiCards[2],
                const SizedBox(height: AppMetrics.space3),
                kpiCards[3],
              ],
            );
          },
        ),
        const SizedBox(height: AppMetrics.space5),

        // ── دو کارت تحلیلی متقارن: مصرف ترافیک + تقویم دقیق شمسی ──────
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget quotaCard = _QuotaAnalyticsCard(
              account: account,
              now: _now,
              panelSynced: _panelSynced,
              tone: quotaTone,
              accountTone: accountTone,
              colors: colors,
            );
            final Widget calendarCard = _JalaliTimelineCard(
              account: account,
              now: _now,
              tehranNow: tehranNow,
              tone: timeTone,
              colors: colors,
            );
            if (constraints.maxWidth >= AppMetrics.breakpointColumns) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: quotaCard),
                    const SizedBox(width: AppMetrics.space5),
                    Expanded(child: calendarCard),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                quotaCard,
                const SizedBox(height: AppMetrics.space4),
                calendarCard,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildNetworkTab({
    required BuildContext context,
    required UmbrellaColors colors,
    required DeviceProfile device,
    required Account account,
    required VpnController vpn,
    required bool tunnelProtected,
  }) {
    final bool hasLocal = device.localIp.isNotEmpty;
    final bool hasMac = device.mac.isNotEmpty;
    final String publicStatus = tunnelProtected
        ? 'محافظت شده در تونل امن'
        : (vpn.realIp.isNotEmpty
            ? _formatAddressFa(vpn.realIp)
            : (hasLocal ? 'آماده اتصال امن' : 'در حال بررسی شبکه'));

    final Widget tunnelCard = GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.shield_rounded,
            title: 'نشانی های اختصاصی تونل کاربری',
            subtitle: 'نشانی های داخلی تخصیص یافته به اشتراک شما در پنل',
            trailing: Pill(
              label: account.wgIpv4.isNotEmpty || account.awgIpv4.isNotEmpty
                  ? 'تخصیص یافته'
                  : 'خودکار',
              color: account.wgIpv4.isNotEmpty || account.awgIpv4.isNotEmpty
                  ? colors.success
                  : colors.textSecondary,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.hub_rounded,
            label: 'تونل استاندارد (نسل چهارم)',
            value: account.wgIpv4.isEmpty
                ? 'تخصیص خودکار'
                : _formatAddressFa(account.wgIpv4),
            trailing: account.wgIpv4.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی نشانی تونل استاندارد نسل چهارم',
                    size: AppMetrics.iconBoxSm,
                    onTap: () =>
                        _copy('نشانی تونل استاندارد', account.wgIpv4),
                  ),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.auto_fix_high_rounded,
            label: 'تونل پیشرفته (نسل چهارم)',
            value: account.awgIpv4.isEmpty
                ? 'تخصیص خودکار'
                : _formatAddressFa(account.awgIpv4),
            trailing: account.awgIpv4.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی نشانی تونل پیشرفته نسل چهارم',
                    size: AppMetrics.iconBoxSm,
                    onTap: () =>
                        _copy('نشانی تونل پیشرفته', account.awgIpv4),
                  ),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.public_rounded,
            label: 'تونل استاندارد (نسل ششم)',
            value: _ipv6LabelFa(account.wgIpv6),
            trailing: account.wgIpv6.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی نشانی نسل ششم تونل استاندارد',
                    size: AppMetrics.iconBoxSm,
                    onTap: () =>
                        _copy('نشانی نسل ششم تونل استاندارد', account.wgIpv6),
                  ),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.language_rounded,
            label: 'تونل پیشرفته (نسل ششم)',
            value: _ipv6LabelFa(account.awgIpv6),
            trailing: account.awgIpv6.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی نشانی نسل ششم تونل پیشرفته',
                    size: AppMetrics.iconBoxSm,
                    onTap: () =>
                        _copy('نشانی نسل ششم تونل پیشرفته', account.awgIpv6),
                  ),
          ),
        ],
      ),
    );

    final Widget adapterCard = GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.lan_rounded,
            title: 'رابط شبکه محلی این رایانه',
            subtitle: 'وضعیت کارت شبکه و نشانی های فعال ویندوز',
            trailing: Pill(
              label: hasLocal ? 'متصل' : 'قطع یا نامشخص',
              color: hasLocal ? colors.success : colors.warning,
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
            value: _formatAddressFa(device.localIp),
            trailing: hasLocal
                ? IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی نشانی شبکه داخلی',
                    size: AppMetrics.iconBoxSm,
                    onTap: () => _copy('نشانی شبکه داخلی', device.localIp),
                  )
                : null,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.travel_explore_rounded,
            label: 'وضعیت نشانی اینترنت',
            value: publicStatus,
            valueColor: tunnelProtected ? colors.success : colors.textPrimary,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.fingerprint_rounded,
            label: 'شناسه فیزیکی کارت شبکه',
            value: hasMac ? 'ثبت شده و آماده کپی' : 'شناسایی نشده',
            trailing: hasMac
                ? IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی شناسه فیزیکی کارت شبکه',
                    size: AppMetrics.iconBoxSm,
                    onTap: () => _copy('شناسه فیزیکی کارت شبکه', device.mac),
                  )
                : null,
          ),
        ],
      ),
    );

    return ResponsiveColumns(
      leftFlex: 1,
      rightFlex: 1,
      spacing: AppMetrics.space5,
      left: tunnelCard,
      right: adapterCard,
    );
  }

  Widget _buildHardwareTab({
    required BuildContext context,
    required UmbrellaColors colors,
    required DeviceProfile device,
    required Account account,
    required Duration liveUptime,
    required int cores,
  }) {
    final DateTime? bootAt = liveUptime > Duration.zero
        ? _now.toUtc().subtract(liveUptime)
        : null;
    final String phoneText = _phoneWithOperatorFa(account.effectivePhone);
    final String osVersion = device.osVersionLabelFa;

    final Widget systemCard = GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.memory_rounded,
            title: 'سخت افزار و سیستم عامل',
            subtitle: 'مشخصات پردازشی، حافظه رم و زمان کارکرد این رایانه',
            trailing: Pill(
              label: device.archLabelFa,
              color: colors.primary,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          if (device.ramTotalMb > 0) ...<Widget>[
            _RamUsageBanner(device: device, colors: colors),
            const SizedBox(height: AppMetrics.space4),
          ],
          InfoRow(
            icon: Icons.window_rounded,
            label: 'سیستم عامل',
            value: device.osLabelFa,
            tooltip: true,
          ),
          if (osVersion.isNotEmpty) ...<Widget>[
            const Divider(height: AppMetrics.space3),
            InfoRow(
              icon: Icons.layers_rounded,
              label: 'ویرایش سالانه ویندوز',
              value: osVersion,
            ),
          ],
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.developer_board_rounded,
            label: 'پردازنده مرکزی',
            value: device.cpuLabelFa,
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.grid_view_rounded,
            label: 'رشته های پردازشی',
            value: '${Fa.num(cores)} هسته منطقی فعال',
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.admin_panel_settings_rounded,
            label: 'سطح دسترسی برنامه',
            value: device.elevated ? 'مدیر سیستم (کامل)' : 'کاربر استاندارد',
            valueColor: device.elevated ? colors.success : colors.warning,
          ),
          if (liveUptime > Duration.zero) ...<Widget>[
            const Divider(height: AppMetrics.space3),
            InfoRow(
              icon: Icons.timer_outlined,
              label: 'مدت روشن بودن ویندوز',
              value: Fa.spanFa(liveUptime),
            ),
          ],
          if (bootAt != null) ...<Widget>[
            const Divider(height: AppMetrics.space3),
            InfoRow(
              icon: Icons.restart_alt_rounded,
              label: 'زمان روشن شدن سیستم',
              value: Fa.tehranCompactDateTime(bootAt),
            ),
          ],
        ],
      ),
    );

    final Widget identityCard = GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.verified_user_rounded,
            title: 'هویت کاربری و شناسه دستگاه',
            subtitle: 'مشخصات ثبت شده مالک اشتراک و شناسه یکتای این سیستم',
            trailing: Pill(
              label: 'زبان ${account.langLabelFa}',
              color: colors.info,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.person_rounded,
            label: 'نام صاحب اشتراک',
            value: _ownerNameFa(account),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.phone_android_rounded,
            label: 'شماره همراه ثبت شده',
            value: phoneText,
            trailing: account.effectivePhone.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی شماره همراه',
                    size: AppMetrics.iconBoxSm,
                    onTap: () =>
                        _copy('شماره همراه', account.effectivePhone),
                  ),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.send_rounded,
            label: 'شناسه تلگرام متصل',
            value: account.telegramId.isEmpty
                ? 'ثبت نشده'
                : Fa.num(account.telegramId),
            trailing: account.telegramId.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی شناسه تلگرام',
                    size: AppMetrics.iconBoxSm,
                    onTap: () => _copy('شناسه تلگرام', account.telegramId),
                  ),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.badge_rounded,
            label: 'شناسه یکتای اشتراک',
            value: _compactCodeFa(account.uuid),
            trailing: account.uuid.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی شناسه یکتای اشتراک',
                    size: AppMetrics.iconBoxSm,
                    onTap: () => _copy('شناسه اشتراک', account.uuid),
                  ),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.phonelink_lock_rounded,
            label: 'شناسه یکتای این دستگاه',
            value: _compactCodeFa(device.machineId),
            trailing: device.machineId.isEmpty
                ? null
                : IconAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'کپی شناسه یکتای دستگاه',
                    size: AppMetrics.iconBoxSm,
                    onTap: () => _copy('شناسه دستگاه', device.machineId),
                  ),
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.update_rounded,
            label: 'آخرین همگام سازی اطلاعات',
            value: _lastSyncAt == null
                ? 'در حال دریافت'
                : Fa.tehranFullDateTime(_lastSyncAt),
          ),
          const SizedBox(height: AppMetrics.space5),
          SizedBox(
            height: AppMetrics.controlHeightSmall,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.copy_all_rounded, size: AppMetrics.iconSm),
              label: const Text('کپی گزارش کامل دستگاه به فارسی'),
              onPressed: () => _copy(
                'گزارش دستگاه',
                _buildPersianSummary(device, account, cores),
              ),
            ),
          ),
        ],
      ),
    );

    return ResponsiveColumns(
      leftFlex: 1,
      rightFlex: 1,
      spacing: AppMetrics.space5,
      left: systemCard,
      right: identityCard,
    );
  }
}

/// نوار زبانه های پیشرفته صفحه دستگاه من.
class _DeviceTabBar extends StatelessWidget {
  const _DeviceTabBar({
    required this.active,
    required this.networkCount,
    required this.coreCount,
    required this.onSelect,
  });

  final _DeviceSectionTab active;
  final int networkCount;
  final int coreCount;
  final ValueChanged<_DeviceSectionTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final List<_DeviceTabItem> tabs = <_DeviceTabItem>[
      const _DeviceTabItem(
        tab: _DeviceSectionTab.overview,
        icon: Icons.space_dashboard_rounded,
        label: 'خلاصه و تقویم شمسی',
      ),
      _DeviceTabItem(
        tab: _DeviceSectionTab.network,
        icon: Icons.lan_rounded,
        label: 'شبکه و نشانی های تونل',
        badge: networkCount > 0 ? Fa.num(networkCount) : '',
      ),
      _DeviceTabItem(
        tab: _DeviceSectionTab.hardware,
        icon: Icons.memory_rounded,
        label: 'سخت افزار و هویت',
        badge: coreCount > 0 ? '${Fa.num(coreCount)} هسته' : '',
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
          if (constraints.maxWidth >= AppMetrics.breakpointGrid) {
            return Row(
              children: <Widget>[
                for (int i = 0; i < tabs.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppMetrics.space1),
                  Expanded(
                    child: _DeviceTabButton(
                      item: tabs[i],
                      selected: tabs[i].tab == active,
                      onTap: () => onSelect(tabs[i].tab),
                    ),
                  ),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < tabs.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppMetrics.space1),
                _DeviceTabButton(
                  item: tabs[i],
                  selected: tabs[i].tab == active,
                  onTap: () => onSelect(tabs[i].tab),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DeviceTabItem {
  const _DeviceTabItem({
    required this.tab,
    required this.icon,
    required this.label,
    this.badge = '',
  });

  final _DeviceSectionTab tab;
  final IconData icon;
  final String label;
  final String badge;
}

class _DeviceTabButton extends StatelessWidget {
  const _DeviceTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _DeviceTabItem item;
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
                item.icon,
                size: AppMetrics.iconSm,
                color: selected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: AppMetrics.space2),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color:
                            selected ? colors.textPrimary : colors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                ),
              ),
              if (item.badge.isNotEmpty) ...<Widget>[
                const SizedBox(width: AppMetrics.space2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.space2,
                    vertical: AppMetrics.space1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary
                        : colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                  ),
                  child: Text(
                    item.badge,
                    style: TextStyle(
                      color: selected ? colors.onPrimary : colors.textSecondary,
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

/// کارت شاخص سریع در بالای زبانه خلاصه.
class _MetricSummaryCard extends StatelessWidget {
  const _MetricSummaryCard({
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

/// کارت تحلیلی مصرف ترافیک ثبت شده در پنل با ارقام و واحدهای کاملاً فارسی.
class _QuotaAnalyticsCard extends StatelessWidget {
  const _QuotaAnalyticsCard({
    required this.account,
    required this.now,
    required this.panelSynced,
    required this.tone,
    required this.accountTone,
    required this.colors,
  });

  final Account account;
  final DateTime now;
  final bool panelSynced;
  final Color tone;
  final Color accountTone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final bool unlimited = account.unlimited;
    final double used = account.currentUsageGb;
    final double limit = account.usageLimitGb;
    final double remaining = account.remainingGb;
    final double pct = account.usagePercent;
    final double daily = account.dailyAverageGb(now);

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.donut_large_rounded,
            title: 'وضعیت مصرف ترافیک اشتراک',
            subtitle: panelSynced
                ? 'اطلاعات زنده و دقیق دریافت شده از پنل کاربری'
                : 'آخرین آمار ثبت شده برای حساب شما',
            trailing: Pill(
              label: unlimited
                  ? 'نامحدود'
                  : '${Fa.decimal(pct, fraction: 1)}٪ مصرف',
              color: tone,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          Row(
            children: <Widget>[
              _CircularGauge(
                ratio: unlimited ? 1 : (pct.clamp(0, 100) / 100),
                centerText: unlimited
                    ? 'آزاد'
                    : '${Fa.decimal(pct, fraction: 0)}٪',
                tone: tone,
                colors: colors,
              ),
              const SizedBox(width: AppMetrics.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${Fa.decimal(used, fraction: 2)} گیگابایت',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      unlimited
                          ? 'بسته بدون سقف حجم ترافیک'
                          : 'مصرف شده از مجموع ${Fa.grouped(limit)} گیگابایت',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                    if (!unlimited) ...<Widget>[
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        'باقی مانده: ${Fa.gb(remaining)} (${Fa.decimal(account.remainingPercent, fraction: 1)} درصد)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            child: LinearProgressIndicator(
              value: unlimited ? 0 : (pct.clamp(0, 100) / 100),
              minHeight: AppMetrics.space2,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.trending_up_rounded,
            label: 'میانگین مصرف روزانه',
            value: daily > 0
                ? '${Fa.decimal(daily, fraction: 2)} گیگابایت در روز'
                : 'در ابتدای دوره',
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.autorenew_rounded,
            label: 'الگوی بازنشانی حجم',
            value: account.modeLabelFa,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.history_rounded,
            label: 'آخرین بازنشانی ترافیک',
            value: account.lastResetTime == null
                ? 'بازنشانی نشده'
                : Fa.tehranFullDateTime(account.lastResetTime, seconds: false),
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.verified_user_rounded,
            label: 'وضعیت مجوز و اشتراک',
            value: account.statusLabelFa,
            valueColor: accountTone,
          ),
        ],
      ),
    );
  }
}

/// کارت تقویم دقیق هجری شمسی و زمان سنج زنده اعتبار اشتراک.
class _JalaliTimelineCard extends StatelessWidget {
  const _JalaliTimelineCard({
    required this.account,
    required this.now,
    required this.tehranNow,
    required this.tone,
    required this.colors,
  });

  final Account account;
  final DateTime now;
  final DateTime tehranNow;
  final Color tone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final DateTime? start = account.startDate;
    final DateTime? expiry = account.effectiveExpiryDate;
    final bool expired = account.isExpiredAt(now);
    final Duration remaining = account.remainingDuration(now);
    final Duration elapsed = account.elapsedDuration(now);
    final double remPct = account.timeRemainingPercent(now);

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.calendar_month_rounded,
            title: 'تقویم شمسی و زمان بندی سرویس',
            subtitle: 'محاسبه دقیق تاریخ هجری شمسی و ساعت رسمی ایران',
            trailing: Pill(
              label: account.packageDurationLabel,
              color: colors.primary,
              dense: true,
            ),
          ),
          const Divider(height: AppMetrics.space5),
          Row(
            children: <Widget>[
              _CircularGauge(
                ratio: expiry == null ? 1 : (remPct.clamp(0, 100) / 100),
                centerText: expiry == null
                    ? 'دائمی'
                    : '${Fa.decimal(remPct, fraction: 0)}٪',
                tone: tone,
                colors: colors,
              ),
              const SizedBox(width: AppMetrics.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      expiry == null
                          ? 'بدون محدودیت زمانی'
                          : (expired
                              ? 'اعتبار زمانی پایان یافته'
                              : Fa.spanFa(remaining)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      start == null
                          ? 'تاریخ شروع پس از اولین همگام سازی نمایش داده می شود'
                          : 'سپری شده از شروع: ${Fa.spanFa(elapsed, includeMinutes: false)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                    if (expiry != null && !expired) ...<Widget>[
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        '${Fa.decimal(remPct, fraction: 1)} درصد از دوره بسته باقی مانده است',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            child: LinearProgressIndicator(
              value: expiry == null ? 1 : (remPct.clamp(0, 100) / 100),
              minHeight: AppMetrics.space2,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          const Divider(height: AppMetrics.space5),
          InfoRow(
            icon: Icons.play_circle_outline_rounded,
            label: 'تاریخ شروع بسته',
            value: start == null
                ? 'ثبت نشده'
                : '${Fa.tehranFullDate(start)} (${Fa.tehranDate(start)})',
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.event_rounded,
            label: 'تاریخ پایان اعتبار',
            value: expiry == null
                ? 'نامحدود'
                : '${Fa.tehranFullDate(expiry)} (${Fa.tehranDate(expiry)})',
            valueColor: expired ? colors.danger : colors.textPrimary,
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.wifi_tethering_rounded,
            label: 'آخرین حضور آنلاین',
            value: account.lastOnline == null
                ? 'ثبت نشده'
                : Fa.tehranFullDateTime(account.lastOnline),
            tooltip: true,
          ),
          const Divider(height: AppMetrics.space3),
          InfoRow(
            icon: Icons.schedule_rounded,
            label: 'تقویم و ساعت زنده ایران',
            value: '${Fa.fullDate(tehranNow)} • ساعت ${Fa.clock(tehranNow)} '
                '(فصل ${Fa.jalali(tehranNow).seasonFa})',
            valueColor: colors.primary,
            tooltip: true,
          ),
        ],
      ),
    );
  }
}

/// حلقه نمایش درصد یکدست با اعداد فارسی.
class _CircularGauge extends StatelessWidget {
  const _CircularGauge({
    required this.ratio,
    required this.centerText,
    required this.tone,
    required this.colors,
  });

  final double ratio;
  final String centerText;
  final Color tone;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppMetrics.logoMd,
      height: AppMetrics.logoMd,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: AppMetrics.logoMd,
            height: AppMetrics.logoMd,
            child: CircularProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              strokeWidth: 6,
              backgroundColor: colors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          Text(
            centerText,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

/// نوار نمایش وضعیت زنده حافظه رم ویندوز.
class _RamUsageBanner extends StatelessWidget {
  const _RamUsageBanner({
    required this.device,
    required this.colors,
  });

  final DeviceProfile device;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final double pct = device.ramPercent;
    final Color tone = pct >= 85
        ? colors.danger
        : (pct >= 70 ? colors.warning : colors.success);
    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  'وضعیت حافظه رم سیستم',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                Fa.percent(pct),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space2),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: AppMetrics.space2,
              backgroundColor: colors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
          const SizedBox(height: AppMetrics.space2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  'مصرف شده: ${Fa.decimal(device.ramUsedGb, fraction: 1)} گیگابایت',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ),
              Flexible(
                child: Text(
                  'آزاد: ${Fa.decimal(device.ramFreeGb, fraction: 1)} از ${Fa.decimal(device.ramTotalGb, fraction: 1)} گیگابایت',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
