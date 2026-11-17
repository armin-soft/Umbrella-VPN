import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';
import '../widgets/flag_view.dart';
import '../widgets/live_clock.dart';

/// صفحه اتصال: یک نگاه، یک دکمه، منوی اتصال مرتب و خوانا.
///
/// کارت اتصال تمام ارتفاع صفحه را می گیرد و دکمه بزرگ در مرکز آن قرار دارد.
/// تنظیمات «حالت اتصال» و «حالت انتخاب سرور» در دو کارت هم اندازه و خوانا زیر
/// دکمه چیده شده اند و آمار زنده اتصال در نوار پایینی نمایش داده می شود.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  /// آی پی دستگاه برای نمایش در نوار بالا.
  ///
  /// وقتی تونل وصل است، آی پی خروجی نشان داده می شود. وقتی قطع است، آی پی
  /// واقعی همین دستگاه؛ و اگر خواندن آن از اینترنت هنوز تمام نشده باشد، آی پی
  /// داخلی کارت شبکه.
  String _deviceIp(VpnController vpn) {
    if (vpn.status == VpnStatus.connected && vpn.exitIp.isNotEmpty) {
      return vpn.exitIp;
    }
    if (vpn.realIp.isNotEmpty) {
      return vpn.realIp;
    }
    if (vpn.geo.ip.isNotEmpty) {
      return vpn.geo.ip;
    }
    final String local = vpn.device.localIp;
    return local.isEmpty ? 'در حال خواندن' : local;
  }

  /// پرچم مناسب همان آی پی که نشان می دهیم.
  static String _flagForIp(VpnController vpn, bool connected, String ip) {
    if (connected) {
      if (vpn.geo.ip.isNotEmpty &&
          vpn.geo.ip == ip &&
          vpn.geo.flagCode.isNotEmpty) {
        return vpn.geo.flagCode;
      }
      final String fromNode = vpn.activeNode?.flagCode ?? '';
      if (fromNode.isNotEmpty) {
        return fromNode;
      }
      final String fromGeo = vpn.geo.flagCode;
      if (fromGeo.isNotEmpty && !_isPrivateIp(ip)) {
        return fromGeo;
      }
      return '';
    }
    if (_isPrivateIp(ip) || ip == 'در حال خواندن') {
      return '';
    }
    if (vpn.geo.ip.isNotEmpty && vpn.geo.ip == ip) {
      return vpn.geo.flagCode;
    }
    return '';
  }

  /// آی پی داخلی است؟ (بدون پرچم، بدون کشور)
  static bool _isPrivateIp(String ip) {
    final String value = ip.trim();
    if (value.isEmpty) {
      return false;
    }
    if (value.startsWith('10.') ||
        value.startsWith('192.168.') ||
        value.startsWith('127.') ||
        value.startsWith('169.254.')) {
      return true;
    }
    if (value.startsWith('172.')) {
      final List<String> parts = value.split('.');
      if (parts.length > 1) {
        final int? second = int.tryParse(parts[1]);
        if (second != null && second >= 16 && second <= 31) {
          return true;
        }
      }
    }
    return value.toLowerCase().startsWith('fe80') || value == '::1';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final SubscriptionController subs =
          context.read<SubscriptionController>();
      final AuthController auth = context.read<AuthController>();
      final VpnController vpn = context.read<VpnController>();
      await OccasionService.instance.load();
      if (!mounted) {
        return;
      }
      setState(() {});
      if (subs.totalNodes == 0 && !subs.loadingAll && !subs.personalLoading) {
        if (auth.signedIn) {
          await subs.syncPersonal();
        } else {
          await subs.fetchAll();
        }
      }
      if (mounted &&
          !vpn.measuring &&
          vpn.nodes.isNotEmpty &&
          vpn.nodes.every((VpnNode node) => !node.hasPing)) {
        unawaited(vpn.refreshPings(all: false, tunnelProbe: false));
      }
    });
  }

  /// خط دوم اعلان اتصال، بدون نام سرور: فقط پینگ و وضعیت.
  static String _connectedNote(VpnController vpn) {
    final int ping = vpn.activePingMs;
    if (ping > 0) {
      return 'پینگ ${Fa.ms(ping)}';
    }
    return 'اتصال امن برقرار است';
  }

  /// آیکون مناسب همان سلام ساعت روز (صبح، ظهر، عصر، شب).
  static IconData _greetingIcon() {
    switch (Fa.greetingKey()) {
      case 'morning':
        return Icons.wb_twilight_rounded;
      case 'noon':
        return Icons.wb_sunny_rounded;
      case 'evening':
        return Icons.nights_stay_rounded;
      default:
        return Icons.bedtime_rounded;
    }
  }

  /// لغو اتصال در حال ساخت (دکمه «لغو اتصال»).
  Future<void> _cancelConnection(
    VpnController vpn,
    ToastController toasts,
  ) async {
    await vpn.cancel();
    if (!mounted) {
      return;
    }
    toasts.info('اتصال لغو شد');
  }

  Future<void> _toggleConnection(
    VpnController vpn,
    SubscriptionController subs,
    ToastController toasts,
  ) async {
    if (vpn.status.busy) {
      return;
    }
    if (vpn.status.active) {
      await vpn.disconnect();
      if (mounted) {
        toasts.info('اتصال قطع شد');
      }
      return;
    }
    final AuthController auth = context.read<AuthController>();
    if (!auth.account.canConnect) {
      toasts.error('اجازه اتصال نیست', auth.account.accessReason);
      return;
    }
    if (vpn.nodes.isEmpty) {
      if (auth.signedIn) {
        await subs.syncPersonal();
      } else {
        await subs.fetchAll();
      }
      if (!mounted) {
        return;
      }
      if (vpn.nodes.isEmpty) {
        toasts.error('سروری موجود نیست', 'ابتدا دریافت اشتراک را بررسی کنید.');
        return;
      }
    }
    final ConnectOutcome outcome = await vpn.connect();
    if (!mounted) {
      return;
    }
    if (outcome.ok) {
      toasts.success('به آمبرلا متصل شد', _connectedNote(vpn));
    } else if (!outcome.cancelled) {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  /// تغییر مستقیم حالت اتصال از فهرست بازشوی استاندارد (خودکار / تونل کامل / پروکسی سیستمی).
  Future<void> _changeConnectionMode(
    CorePreference picked,
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    if (!mounted || picked == settings.settings.corePreference) {
      return;
    }
    await settings.setCorePreference(picked);
    if (!mounted) {
      return;
    }
    toasts.info('حالت اتصال: ${picked.faName}');
    if (vpn.status.busy || !vpn.status.active) {
      return;
    }
    await vpn.disconnect();
    final ConnectOutcome outcome = await vpn.connect();
    if (!mounted) {
      return;
    }
    if (outcome.ok) {
      toasts.success('به آمبرلا متصل شد', _connectedNote(vpn));
    } else if (!outcome.cancelled) {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  /// تغییر مستقیم حالت انتخاب سرور از فهرست بازشوی استاندارد.
  Future<void> _changeSelectionMode(
    SelectionMode picked,
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    if (!mounted || picked == settings.settings.selectionMode) {
      return;
    }
    await settings.setSelectionMode(picked);
    if (!mounted) {
      return;
    }
    toasts.info('حالت انتخاب سرور: ${picked.faName}');
    if (vpn.status.busy || !vpn.status.active) {
      return;
    }
    await vpn.disconnect();
    final ConnectOutcome outcome = await vpn.connect();
    if (!mounted) {
      return;
    }
    if (outcome.ok) {
      toasts.success(
        'با حالت ${picked.faName} دوباره وصل شد',
        _connectedNote(vpn),
      );
    } else if (!outcome.cancelled) {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final SettingsController settings = context.watch<SettingsController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final VpnStatus status = vpn.status;
    final Color tone = VpnVisuals.color(context, status);
    final bool connected = status == VpnStatus.connected;
    final Account account = auth.account;

    final String shownIp = _deviceIp(vpn);
    final String flagCode = _flagForIp(vpn, connected, shownIp);
    final String countryName = CountryNames.fa(flagCode);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double orb = constraints.maxHeight < 650
            ? 200
            : (constraints.maxHeight < 780 ? 240 : 272);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.space7,
            AppMetrics.space5,
            AppMetrics.space7,
            AppMetrics.space6,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 42,
            ),
            child: GlassCard(
              radius: AppMetrics.radiusHuge,
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.space6,
                AppMetrics.space5,
                AppMetrics.space6,
                AppMetrics.space5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color.alphaBlend(
                    tone.withValues(
                      alpha: Theme.of(context).brightness == Brightness.light
                          ? 0.08
                          : 0.12,
                    ),
                    colors.surface,
                  ),
                  colors.surface,
                  colors.backgroundAlt,
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── نوار بالا: خوش آمدگویی، تاریخ زنده و آی پی ────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Icon(
                                      _greetingIcon(),
                                      size: AppMetrics.iconMd,
                                      color: colors.warning,
                                    ),
                                    const SizedBox(width: AppMetrics.space2),
                                    Flexible(
                                      child: Text(
                                        Fa.num(
                                          'سلام ${account.displayName}، '
                                          '${Fa.greeting()}',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppMetrics.space1),
                                LiveDateTimeLine(
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (subs.needsLogin) ...<Widget>[
                            Pill(
                              label: 'برای اشتراک وارد شو',
                              icon: Icons.login_rounded,
                              color: colors.warning,
                            ),
                            const SizedBox(width: AppMetrics.space2),
                          ],
                          _IpChip(
                            ip: shownIp,
                            flagCode: flagCode,
                            country: connected ? countryName : '',
                            connected: connected,
                            onRefresh: () => vpn.refreshIp(),
                          ),
                        ],
                      ),
                      if (!account.canConnect)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: AppMetrics.space3),
                          child: _AccessBanner(
                            title: account.enable
                                ? 'اشتراک شما اجازه اتصال ندارد'
                                : 'حساب شما مسدود شده است',
                            message: account.accessReason,
                          ),
                        ),
                      if (OccasionService.instance.active != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: AppMetrics.space3),
                          child: OccasionBanner(
                            occasion: OccasionService.instance.active,
                            enabled: settings.settings.occasionEffects,
                          ),
                        ),
                    ],
                  ),

                  // ── مرکز صفحه: گنبد وضعیت، دکمه اصلی و منوی اتصال ─────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppMetrics.space4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Semantics(
                          button: true,
                          label: status.busy
                              ? 'لغو اتصال'
                              : (status.active ? 'قطع اتصال' : 'اتصال'),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: status == VpnStatus.disconnecting
                                ? null
                                : (status.busy
                                    ? () => _cancelConnection(vpn, toasts)
                                    : () =>
                                        _toggleConnection(vpn, subs, toasts)),
                            child: Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                StatusOrb(
                                  image: status.image,
                                  color: tone,
                                  size: orb,
                                  active: status.busy,
                                ),
                                if (!status.busy)
                                  Container(
                                    width: orb * 0.28,
                                    height: orb * 0.28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (status.active
                                              ? colors.danger
                                              : colors.primary)
                                          .withValues(alpha: 0.94),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: (status.active
                                                  ? colors.danger
                                                  : colors.primary)
                                              .withValues(alpha: 0.38),
                                          blurRadius: 24,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.power_settings_new_rounded,
                                      size: orb * 0.14,
                                      color: colors.onPrimary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppMetrics.space3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            if (connected && flagCode.isNotEmpty) ...<Widget>[
                              FlagView(
                                code: flagCode,
                                width: AppMetrics.flagWidth,
                              ),
                              const SizedBox(width: AppMetrics.space2),
                            ],
                            Flexible(
                              child: Text(
                                Fa.num(
                                  connected
                                      ? 'به آمبرلا متصل شد'
                                      : status.label,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: tone,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppMetrics.space1),
                        if (connected)
                          _PingLine(pingMs: vpn.activePingMs)
                        else
                          Text(
                            Fa.num(vpn.message),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        const SizedBox(height: AppMetrics.space5),
                        SizedBox(
                          width: AppMetrics.controlMaxWidth,
                          child: status.busy
                              ? GradientButton(
                                  label: status == VpnStatus.disconnecting
                                      ? 'در حال لغو...'
                                      : 'لغو اتصال',
                                  icon: Icons.cancel_rounded,
                                  height: AppMetrics.controlHeightLarge,
                                  tone: colors.warning,
                                  loading: status == VpnStatus.disconnecting,
                                  onPressed: status == VpnStatus.disconnecting
                                      ? null
                                      : () => _cancelConnection(vpn, toasts),
                                )
                              : GradientButton(
                                  label: status.active ? 'قطع اتصال' : 'اتصال',
                                  icon: Icons.power_settings_new_rounded,
                                  height: AppMetrics.controlHeightLarge,
                                  tone: status.active
                                      ? colors.danger
                                      : colors.primary,
                                  onPressed: () =>
                                      _toggleConnection(vpn, subs, toasts),
                                ),
                        ),
                        if (!account.canConnect)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: AppMetrics.space2),
                            child: Text(
                              Fa.num(
                                'اتصال تا تمدید یا رفع مسدودی اشتراک ممکن نیست.',
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.danger),
                            ),
                          ),
                        const SizedBox(height: AppMetrics.space5),

                        // ── کنترل های استاندارد حالت اتصال و حالت انتخاب سرور ──
                        _ConnectionOptionsBar(
                          connectionMode: settings.settings.corePreference,
                          selectionMode: settings.settings.selectionMode,
                          enabled: !status.busy,
                          onConnectionModeChanged: (CorePreference picked) =>
                              _changeConnectionMode(
                            picked,
                            vpn,
                            settings,
                            toasts,
                          ),
                          onSelectionModeChanged: (SelectionMode picked) =>
                              _changeSelectionMode(
                            picked,
                            vpn,
                            settings,
                            toasts,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── نوار پایین: آمار زنده اتصال ───────────────────────
                  _ConnectionStats(vpn: vpn, connected: connected),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// دو فهرست بازشوی استاندارد، هم تراز و خوانا برای «حالت اتصال» و «حالت انتخاب سرور»
/// که مستقیماً زیر خود فیلد باز می شوند (بدون پنجره پاپ آپ وسط صفحه).
class _ConnectionOptionsBar extends StatelessWidget {
  const _ConnectionOptionsBar({
    required this.connectionMode,
    required this.selectionMode,
    required this.enabled,
    required this.onConnectionModeChanged,
    required this.onSelectionModeChanged,
  });

  final CorePreference connectionMode;
  final SelectionMode selectionMode;
  final bool enabled;
  final ValueChanged<CorePreference> onConnectionModeChanged;
  final ValueChanged<SelectionMode> onSelectionModeChanged;

  @override
  Widget build(BuildContext context) {
    final Widget connectionSelect = AnchoredSelectField<CorePreference>(
      key: const ValueKey<String>('connect-mode-select'),
      label: 'حالت اتصال',
      value: connectionMode,
      enabled: enabled,
      options: <SelectOption<CorePreference>>[
        for (final CorePreference pref in CorePreference.values)
          SelectOption<CorePreference>(
            value: pref,
            label: pref.faName,
            subtitle: pref.description,
            icon: pref.icon,
            enabled: pref.available,
          ),
      ],
      onChanged: onConnectionModeChanged,
    );

    final Widget serverModeSelect = AnchoredSelectField<SelectionMode>(
      key: const ValueKey<String>('selection-mode-select'),
      label: 'حالت انتخاب سرور',
      value: SelectionModeList.visible.contains(selectionMode)
          ? selectionMode
          : SelectionMode.auto,
      enabled: enabled,
      options: <SelectOption<SelectionMode>>[
        for (final SelectionMode mode in SelectionModeList.visible)
          SelectOption<SelectionMode>(
            value: mode,
            label: mode.label,
            subtitle: mode.description,
            icon: mode.icon,
          ),
      ],
      onChanged: onSelectionModeChanged,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppMetrics.breakpointCompact,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < AppMetrics.controlMaxWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                connectionSelect,
                const SizedBox(height: AppMetrics.space3),
                serverModeSelect,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: connectionSelect),
              const SizedBox(width: AppMetrics.space3),
              Expanded(child: serverModeSelect),
            ],
          );
        },
      ),
    );
  }
}

/// آمار زنده اتصال در پایین کارت اصلی.
class _ConnectionStats extends StatelessWidget {
  const _ConnectionStats({required this.vpn, required this.connected});

  final VpnController vpn;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final List<(String, String, IconData, Color)> values =
        <(String, String, IconData, Color)>[
      (
        'پینگ',
        vpn.activePingMs > 0 ? Fa.ms(vpn.activePingMs) : '—',
        Icons.speed_rounded,
        colors.success,
      ),
      (
        'مدت اتصال',
        connected ? Fa.duration(vpn.stats.connectedFor) : '—',
        Icons.timer_outlined,
        colors.info,
      ),
      (
        'دریافتی',
        vpn.stats.available ? Fa.bytes(vpn.stats.rx) : '—',
        Icons.south_rounded,
        colors.primary,
      ),
      (
        'ارسالی',
        vpn.stats.available ? Fa.bytes(vpn.stats.tx) : '—',
        Icons.north_rounded,
        colors.warning,
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < AppMetrics.breakpointGrid;
        const double gap = AppMetrics.space3;
        final double tileWidth = narrow
            ? (constraints.maxWidth - gap) / 2
            : (constraints.maxWidth - gap * 3) / 4;
        return Wrap(
          spacing: gap,
          runSpacing: AppMetrics.space2,
          children: values
              .map(
                ((String, String, IconData, Color) value) => SizedBox(
                  width: tileWidth,
                  child: _ConnectionStatTile(
                    label: value.$1,
                    value: value.$2,
                    icon: value.$3,
                    accent: value.$4,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ConnectionStatTile extends StatelessWidget {
  const _ConnectionStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space3,
        vertical: AppMetrics.space3,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          IconSquare(
            icon: icon,
            color: accent,
            size: AppMetrics.iconBoxMd,
            radius: AppMetrics.radiusMd,
          ),
          const SizedBox(width: AppMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fa.num(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppMetrics.space1),
                Text(
                  Fa.num(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// پینگ سرور متصل، زیر وضعیت اتصال.
class _PingLine extends StatelessWidget {
  const _PingLine({required this.pingMs});

  final int pingMs;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool known = pingMs > 0;
    final Color tone = !known
        ? colors.textSecondary
        : (pingMs < 80
            ? colors.success
            : (pingMs < 180 ? colors.warning : colors.danger));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.speed_rounded, size: AppMetrics.iconSm, color: tone),
        const SizedBox(width: AppMetrics.space2),
        Text(
          Fa.num(known ? 'پینگ ${Fa.ms(pingMs)}' : 'پینگ در حال اندازه گیری'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

/// هشدار دسترسی: اشتراک منقضی، مسدود یا تمام شده.
class _AccessBanner extends StatelessWidget {
  const _AccessBanner({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space4,
        vertical: AppMetrics.space3,
      ),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.lock_rounded,
            size: AppMetrics.iconMd,
            color: colors.danger,
          ),
          const SizedBox(width: AppMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fa.num(title),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.danger,
                      ),
                ),
                Text(
                  Fa.num(message),
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
    );
  }
}

/// نشان خوانا و مرتب آی پی با پرچم کشور و دکمه تازه سازی.
class _IpChip extends StatelessWidget {
  const _IpChip({
    required this.ip,
    required this.flagCode,
    required this.country,
    required this.connected,
    required this.onRefresh,
  });

  final String ip;
  final String flagCode;
  final String country;
  final bool connected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String caption = connected
        ? (country.isNotEmpty ? 'آی پی اتصال · $country' : 'آی پی اتصال')
        : 'آی پی دستگاه';
    return Tooltip(
      message: 'به روز رسانی آی پی',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        onTap: onRefresh,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.space3,
            vertical: AppMetrics.space2,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(
              color: connected
                  ? colors.success.withValues(alpha: 0.35)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (flagCode.isNotEmpty) ...<Widget>[
                FlagView(code: flagCode, width: AppMetrics.flagWidth),
                const SizedBox(width: AppMetrics.space2),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fa.num(caption),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              connected ? colors.success : colors.textSecondary,
                          fontWeight:
                              connected ? FontWeight.w700 : FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppMetrics.space1),
                  Text(
                    Fa.num(ip),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(width: AppMetrics.space2),
              Icon(
                Icons.refresh_rounded,
                size: AppMetrics.iconSm,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
