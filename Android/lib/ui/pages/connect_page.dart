import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/security_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';
import '../widgets/flag_view.dart';
import '../widgets/live_clock.dart';
import '../widgets/quick_connection_panel.dart';
import '../widgets/security_shield_dialog.dart';

/// صفحه اصلی اتصال؛ وضعیت و کنترل اتصال را در اولویت نگه می دارد.
///
/// گزینه های جانبی اتصال از دکمه اختصاصی باز می شوند تا صفحه اصلی خلوت بماند؛
/// حالت سرویس و اشتراک گذاری شبکه از پنجره تنظیمات اتصال در دسترس هستند.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  bool _preConnectBusy = false;
  int _preConnectEpoch = 0;

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
      if (auth.signedIn &&
          subs.totalNodes == 0 &&
          !subs.loadingAll &&
          !subs.personalLoading) {
        await subs.syncPersonal();
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
    if (_preConnectBusy && !vpn.status.busy) {
      setState(() {
        _preConnectEpoch++;
        _preConnectBusy = false;
      });
      toasts.info('اتصال لغو شد');
      return;
    }
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
    if (vpn.status.busy || _preConnectBusy) {
      return;
    }
    if (vpn.status.active) {
      await vpn.disconnect();
      if (!mounted) return;
      toasts.info('اتصال قطع شد');
      return;
    }
    final AuthController auth = context.read<AuthController>();
    if (!auth.signedIn) {
      toasts.error('ورود لازم است', 'ابتدا وارد حساب کاربری خود شوید.');
      return;
    }
    if (!auth.account.canConnect) {
      toasts.error(auth.account.statusLabelFa, auth.account.accessReason);
      return;
    }
    Future<ConnectOutcome>? pendingConnect;
    if (vpn.nodes.isEmpty) {
      final int epoch = ++_preConnectEpoch;
      setState(() => _preConnectBusy = true);
      try {
        await subs.syncPersonal();
        if (!mounted || epoch != _preConnectEpoch) {
          return;
        }
        if (vpn.nodes.isEmpty &&
            subs.emergencyEnabled &&
            subs.emergencyNodes.isEmpty &&
            !subs.emergencyLoading) {
          await subs.refreshEmergency();
          if (!mounted || epoch != _preConnectEpoch) return;
        }
        if (vpn.nodes.isEmpty &&
            !(subs.emergencyEnabled && subs.emergencyNodes.isNotEmpty)) {
          toasts.error(
            'اشتراک دریافت نشد',
            'بسته فعال حساب و اتصال اینترنت را بررسی کنید.',
          );
          return;
        }
        // Start `vpn.connect()` before clearing `_preConnectBusy` so the UI stays
        // in `در حال اتصال` continuously without a single disconnected frame.
        pendingConnect = vpn.connect();
      } finally {
        if (mounted && epoch == _preConnectEpoch && _preConnectBusy) {
          setState(() => _preConnectBusy = false);
        }
      }
    }
    final ConnectOutcome outcome = await (pendingConnect ?? vpn.connect());
    if (!mounted) {
      return;
    }
    if (outcome.ok) {
      toasts.success('به آمبرلا متصل شد', _connectedNote(vpn));
    } else if (outcome.needsSecurityCleanup) {
      toasts.error('سپر امنیتی اتصال را مسدود کرد', outcome.message);
      unawaited(SecurityShieldDialog.show(context));
    } else if (!outcome.cancelled) {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  void _openConnectionSettings() {
    final UmbrellaColors colors = context.colors;
    final Size viewport = MediaQuery.sizeOf(context);
    // When a display feature splits the viewport, Flutter's RTL fallback picks
    // the right pane; anchoring at the center avoids that directional bias.
    showModalBottomSheet<void>(
      context: context,
      anchorPoint: Offset(viewport.width / 2, viewport.height / 2),
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      enableDrag: true,
      constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
      backgroundColor: colors.surface,
      barrierColor: colors.background.withValues(alpha: 0.68),
      elevation: AppMetrics.space6,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppMetrics.radiusXxl),
        ),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (BuildContext context) => const _ConnectionSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final SettingsController settings = context.watch<SettingsController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
    final SecurityScannerController? security =
        context.maybeWatch<SecurityScannerController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final bool preConnecting =
        _preConnectBusy && vpn.status == VpnStatus.disconnected;
    final VpnStatus status =
        preConnecting ? VpnStatus.connecting : vpn.status;
    final String statusMessage =
        preConnecting ? 'در حال آماده سازی اتصال...' : vpn.message;
    final Color tone = VpnVisuals.color(context, status);
    final bool connected = status == VpnStatus.connected;
    final Account account = auth.account;

    final String shownIp = _deviceIp(vpn);
    final String flagCode = _flagForIp(vpn, connected, shownIp);
    final String countryName = CountryNames.fa(flagCode);
    final bool hasAccessBanner = !account.canConnect;
    final bool hasSecurityBlock = security?.hasThreats ?? false;
    final bool hasOccasionBanner = OccasionService.instance.active != null;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints outer) {
        final bool phoneSized = outer.maxWidth < 520;
        final EdgeInsets pagePad = phoneSized
            ? const EdgeInsets.symmetric(
                horizontal: AppMetrics.space3,
                vertical: AppMetrics.space2,
              )
            : AppMetrics.responsivePagePadding(context);
        final bool compactCard =
            outer.maxWidth < 480 || outer.maxHeight < 640;
        final EdgeInsets cardPad = phoneSized
            ? const EdgeInsets.symmetric(
                horizontal: AppMetrics.space3 + 2,
                vertical: AppMetrics.space2 + 2,
              )
            : (compactCard
                ? const EdgeInsets.fromLTRB(
                    AppMetrics.space4,
                    AppMetrics.space3,
                    AppMetrics.space4,
                    AppMetrics.space3,
                  )
                : const EdgeInsets.fromLTRB(
                    AppMetrics.space6,
                    AppMetrics.space5,
                    AppMetrics.space6,
                    AppMetrics.space5,
                  ));
        final double innerWidth =
            (outer.maxWidth - pagePad.horizontal - cardPad.horizontal)
                .clamp(200.0, 2000.0);
        final double innerHeight =
            (outer.maxHeight - pagePad.vertical - cardPad.vertical)
                .clamp(200.0, 2000.0);
        final bool landscapeSplit =
            innerWidth >= 480 && innerHeight < 470;
        final bool veryNarrow = innerWidth < 290;

        final Widget greetingBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: AppMetrics.space1 / 2),
                  child: Icon(
                    _greetingIcon(),
                    size: phoneSized ? AppMetrics.iconSm : AppMetrics.iconMd,
                    color: colors.warning,
                  ),
                ),
                const SizedBox(width: AppMetrics.space2),
                Expanded(
                  child: Text(
                    Fa.num(
                      'سلام ${account.displayName}، '
                      '${Fa.greeting()}',
                    ),
                    softWrap: true,
                    style: (phoneSized || landscapeSplit
                            ? Theme.of(context).textTheme.titleSmall
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            if (!landscapeSplit) ...<Widget>[
              const SizedBox(height: AppMetrics.space1 / 2),
              LiveDateTimeLine(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: phoneSized ? AppMetrics.fontCaption : null,
                    ),
              ),
            ],
          ],
        );

        final Widget ipBadge = _IpChip(
          ip: shownIp,
          flagCode: flagCode,
          country: connected ? countryName : '',
          connected: connected,
          dense: phoneSized || landscapeSplit,
        );

        final Widget header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (veryNarrow && !landscapeSplit) ...<Widget>[
              greetingBlock,
              const SizedBox(height: AppMetrics.space2),
              Wrap(
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (security != null)
                    const SecurityStatusBadge(dense: true),
                  ipBadge,
                  if (subs.needsLogin)
                    Pill(
                      label: 'برای اشتراک وارد شو',
                      icon: Icons.login_rounded,
                      color: colors.warning,
                      dense: true,
                    ),
                ],
              ),
            ] else ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: greetingBlock),
                  if (subs.needsLogin && innerWidth >= 420) ...<Widget>[
                    const SizedBox(width: AppMetrics.space2),
                    Pill(
                      label: 'برای اشتراک وارد شو',
                      icon: Icons.login_rounded,
                      color: colors.warning,
                      dense: landscapeSplit,
                    ),
                  ],
                  if (security != null && landscapeSplit) ...<Widget>[
                    const SizedBox(width: AppMetrics.space2),
                    const SecurityStatusBadge(dense: true),
                  ],
                  const SizedBox(width: AppMetrics.space2),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: innerWidth * 0.44,
                    ),
                    child: landscapeSplit
                        ? ipBadge
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (security != null) ...<Widget>[
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SecurityStatusBadge(dense: phoneSized),
                                ),
                                const SizedBox(height: AppMetrics.space1),
                              ],
                              ipBadge,
                            ],
                          ),
                  ),
                ],
              ),
              if (subs.needsLogin && innerWidth < 420 && !landscapeSplit)
                Padding(
                  padding: const EdgeInsets.only(top: AppMetrics.space1),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Pill(
                      label: 'برای اشتراک وارد شو',
                      icon: Icons.login_rounded,
                      color: colors.warning,
                      dense: true,
                    ),
                  ),
                ),
            ],
            if (hasSecurityBlock)
              Padding(
                padding: EdgeInsets.only(
                  top: landscapeSplit ? AppMetrics.space1 : AppMetrics.space2,
                ),
                child: _SecurityBlockBanner(
                  threats: security!.threats,
                  dense: phoneSized || landscapeSplit,
                  onOpenShield: () => SecurityShieldDialog.show(context),
                ),
              ),
            if (hasAccessBanner)
              Padding(
                padding: EdgeInsets.only(
                  top: landscapeSplit ? AppMetrics.space1 : AppMetrics.space2,
                ),
                child: _AccessBanner(
                  title: account.channelDisabled
                      ? 'عضویت در کانال رسمی تلگرام ضروری است'
                      : (account.enable
                          ? 'اشتراک شما اجازه اتصال ندارد'
                          : 'حساب شما مسدود شده است'),
                  message: account.accessReason,
                  dense: phoneSized || landscapeSplit,
                ),
              ),
            if (hasOccasionBanner && !landscapeSplit)
              Padding(
                padding: const EdgeInsets.only(top: AppMetrics.space2),
                child: OccasionBanner(
                  occasion: OccasionService.instance.active,
                  enabled: settings.settings.occasionEffects,
                ),
              ),
          ],
        );

        Widget buildOrbWidget(double orbSize) {
          return Semantics(
            button: true,
            label: status.busy
                ? 'لغو اتصال'
                : (status.active ? 'قطع اتصال' : 'اتصال'),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: status == VpnStatus.disconnecting
                  ? null
                  : withUiClick(
                      context,
                      status.busy
                          ? () => _cancelConnection(vpn, toasts)
                          : () => _toggleConnection(vpn, subs, toasts),
                    ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  StatusOrb(
                    image: status.image,
                    color: tone,
                    size: orbSize,
                    active: status.busy,
                  ),
                  if (!status.busy)
                    Positioned(
                      right: orbSize * 0.06,
                      bottom: orbSize * 0.06,
                      child: Container(
                        width: orbSize * 0.24,
                        height: orbSize * 0.24,
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
                          size: orbSize * 0.12,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        Widget buildStatusTexts({required bool dense}) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (connected && flagCode.isNotEmpty) ...<Widget>[
                    FlagView(
                      code: flagCode,
                      width: dense
                          ? AppMetrics.flagWidthSmall
                          : AppMetrics.flagWidth,
                    ),
                    const SizedBox(width: AppMetrics.space2),
                  ],
                  Flexible(
                    child: Text(
                      Fa.num(
                        connected ? 'به آمبرلا متصل شد' : status.label,
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: dense ? 21 : 26,
                            height: 1.25,
                            fontWeight: FontWeight.w900,
                            color: tone,
                          ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? AppMetrics.space1 / 2 : AppMetrics.space1),
              if (connected)
                _PingLine(pingMs: vpn.activePingMs)
              else
                Text(
                  Fa.num(statusMessage),
                  textAlign: TextAlign.center,
                  style: (dense
                          ? Theme.of(context).textTheme.bodySmall
                          : Theme.of(context).textTheme.bodyMedium)
                      ?.copyWith(color: colors.textSecondary),
                ),
            ],
          );
        }

        Widget buildControls({
          required double buttonHeight,
          required double secondaryHeight,
          required double gapAfterPrimary,
        }) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: AppMetrics.controlMaxWidth,
                child: status.busy
                    ? GradientButton(
                        label: status == VpnStatus.disconnecting
                            ? 'در حال لغو...'
                            : 'لغو اتصال',
                        icon: Icons.cancel_rounded,
                        height: buttonHeight,
                        tone: colors.warning,
                        loading: status == VpnStatus.disconnecting,
                        onPressed: status == VpnStatus.disconnecting
                            ? null
                            : () => _cancelConnection(vpn, toasts),
                      )
                    : GradientButton(
                        label: status.active ? 'قطع اتصال' : 'اتصال',
                        icon: Icons.power_settings_new_rounded,
                        height: buttonHeight,
                        tone: status.active ? colors.danger : colors.primary,
                        onPressed: () =>
                            _toggleConnection(vpn, subs, toasts),
                      ),
              ),
              if (!account.canConnect)
                Padding(
                  padding: const EdgeInsets.only(top: AppMetrics.space2),
                  child: Text(
                    Fa.num('اتصال تا تمدید یا رفع مسدودی اشتراک ممکن نیست.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.danger),
                  ),
                ),
              SizedBox(height: gapAfterPrimary),
              SizedBox(
                width: AppMetrics.controlMaxWidth,
                height: secondaryHeight,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>(
                    'connection-settings-button',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, secondaryHeight),
                    backgroundColor:
                        colors.surfaceHigh.withValues(alpha: 0.55),
                    side: BorderSide(
                      color: colors.border.withValues(alpha: 0.9),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppMetrics.space3,
                    ),
                    textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  onPressed: withUiClick(context, _openConnectionSettings),
                  icon: Icon(
                    Icons.tune_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.primary,
                  ),
                  label: const Text('تنظیمات اتصال'),
                ),
              ),
            ],
          );
        }

        final LinearGradient cardGradient = LinearGradient(
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
        );

        if (landscapeSplit) {
          return Padding(
            padding: pagePad,
            child: GlassCard(
              radius: AppMetrics.radiusXl,
              padding: cardPad,
              gradient: cardGradient,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  header,
                  Expanded(
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints centerBox) {
                        final double cW = centerBox.maxWidth;
                        final double cH = centerBox.maxHeight;
                        final double sideOrb = (cH - 58)
                            .clamp(108.0, 190.0)
                            .clamp(108.0, cW * 0.36);
                        return Row(
                          children: <Widget>[
                            Expanded(
                              flex: 4,
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      buildOrbWidget(sideOrb),
                                      const SizedBox(height: AppMetrics.space2),
                                      SizedBox(
                                        width: cW * 0.42,
                                        child: buildStatusTexts(dense: false),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppMetrics.space4),
                            Expanded(
                              flex: 5,
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: (cW * 0.54)
                                        .clamp(220.0, AppMetrics.controlMaxWidth),
                                    child: buildControls(
                                      buttonHeight: AppMetrics.controlHeightSmall,
                                      secondaryHeight: AppMetrics.controlHeightSmall,
                                      gapAfterPrimary: AppMetrics.space2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppMetrics.space2),
                  _ConnectionStats(
                    vpn: vpn,
                    connected: connected,
                    dense: true,
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: pagePad,
          child: GlassCard(
            radius: compactCard ? AppMetrics.radiusXl : AppMetrics.radiusHuge,
            padding: cardPad,
            gradient: cardGradient,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints centerBox) {
                      final double cW = centerBox.maxWidth;
                      final double cH = centerBox.maxHeight;
                      final bool desktopSized =
                          cH >= 480 && cW >= 540;
                      final double buttonHeight = desktopSized
                          ? AppMetrics.controlHeightLarge
                          : (cH >= 430
                              ? AppMetrics.controlHeight
                              : AppMetrics.controlHeightSmall);
                      const double secondaryHeight =
                          AppMetrics.controlHeightSmall;
                      final double gapStatus = desktopSized
                          ? AppMetrics.space3
                          : AppMetrics.space2;
                      final double gapButton = desktopSized
                          ? AppMetrics.space5
                          : AppMetrics.space3;
                      final double gapPrimary = desktopSized
                          ? AppMetrics.space4
                          : AppMetrics.space2 + 2;
                      final double reserved =
                          (desktopSized ? 72 : 66) +
                          buttonHeight +
                          secondaryHeight +
                          gapStatus +
                          gapButton +
                          gapPrimary +
                          (!account.canConnect ? 28 : 0) +
                          6;
                      final double maxOrb = desktopSized
                          ? (cH < 560 ? 250 : (cH < 640 ? 290 : 330))
                          : 224;
                      final double orb = (cH - reserved)
                          .clamp(126.0, maxOrb)
                          .clamp(126.0, (cW - 12).clamp(126.0, 330.0));

                      return Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: cW,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                buildOrbWidget(orb),
                                SizedBox(height: gapStatus),
                                buildStatusTexts(dense: false),
                                SizedBox(height: gapButton),
                                buildControls(
                                  buttonHeight: buttonHeight,
                                  secondaryHeight: secondaryHeight,
                                  gapAfterPrimary: gapPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  height: phoneSized ? AppMetrics.space2 : AppMetrics.space3,
                ),
                _ConnectionStats(
                  vpn: vpn,
                  connected: connected,
                  compact: phoneSized,
                  dense: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// برگه تنظیمات اتصال: ورود از پایین، گوشه های نرم و کنترل های لمسی استاندارد.
class _ConnectionSettingsSheet extends StatelessWidget {
  const _ConnectionSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final bool enabled = !context.watch<VpnController>().status.busy;
    return ConstrainedBox(
      key: const ValueKey<String>('connection-settings-sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppMetrics.space3,
        ),
        child: Center(
          child: QuickConnectionPanel(
            enabled: enabled,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

/// آمار زنده اتصال در پایین کارت اصلی.
class _ConnectionStats extends StatelessWidget {
  const _ConnectionStats({
    required this.vpn,
    required this.connected,
    this.compact = false,
    this.dense = false,
  });

  final VpnController vpn;
  final bool connected;
  final bool compact;
  final bool dense;

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
        final bool narrow = constraints.maxWidth < 540;
        final double gap = dense ? AppMetrics.space2 : AppMetrics.space3;
        final double tileWidth = narrow
            ? (constraints.maxWidth - gap) / 2
            : (constraints.maxWidth - gap * 3) / 4;
        return Wrap(
          spacing: gap,
          runSpacing: compact || dense ? AppMetrics.space1 + 2 : AppMetrics.space2,
          children: values
              .map(
                ((String, String, IconData, Color) value) => SizedBox(
                  width: tileWidth,
                  child: _ConnectionStatTile(
                    label: value.$1,
                    value: value.$2,
                    icon: value.$3,
                    accent: value.$4,
                    connected: connected,
                    compact: compact,
                    dense: dense,
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
    this.connected = false,
    this.compact = false,
    this.dense = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool connected;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense
            ? AppMetrics.space2
            : (compact ? AppMetrics.space2 : AppMetrics.space3),
        vertical: dense
            ? AppMetrics.space1 + 2
            : (compact ? AppMetrics.space1 + 1 : AppMetrics.space2 + 2),
      ),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(
          dense ? AppMetrics.radiusMd : AppMetrics.radiusLg,
        ),
        border: Border.all(
          color: connected && accent == colors.success
              ? colors.success.withValues(alpha: 0.35)
              : colors.border,
        ),
      ),
      child: Row(
        children: <Widget>[
          IconSquare(
            icon: icon,
            color: accent,
            size: dense ? 26 : (compact ? 28 : AppMetrics.iconBoxMd),
            radius: dense ? AppMetrics.radiusSm : AppMetrics.radiusMd,
          ),
          SizedBox(width: dense || compact ? AppMetrics.space2 : AppMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fa.num(label),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontSize: dense ? AppMetrics.fontMicro : null,
                      ),
                ),
                SizedBox(height: dense || compact ? 1 : AppMetrics.space1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    Fa.num(value),
                    maxLines: 1,
                    style: (dense
                            ? Theme.of(context).textTheme.labelMedium
                            : Theme.of(context).textTheme.titleSmall)
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
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
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.speed_rounded, size: AppMetrics.iconSm, color: tone),
        const SizedBox(width: AppMetrics.space2),
        Text(
          Fa.num(known ? 'پینگ ${Fa.ms(pingMs)}' : 'پینگ در حال اندازه گیری'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

/// بنر هشدار سپر امنیتی هنگام شناسایی بدافزار یا VPN ناسازگار روی گوشی.
class _SecurityBlockBanner extends StatelessWidget {
  const _SecurityBlockBanner({
    required this.threats,
    required this.onOpenShield,
    this.dense = false,
  });

  final List<SecurityThreat> threats;
  final VoidCallback onOpenShield;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String names = threats.take(2).map((SecurityThreat t) => t.name).join('، ');
    final String extra = threats.length > 2
        ? ' و ${Fa.num(threats.length - 2)} مورد دیگر'
        : '';
    return Container(
      key: const ValueKey<String>('connect-security-banner'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppMetrics.space2 : AppMetrics.space3,
        vertical: dense ? AppMetrics.space1 : AppMetrics.space2,
      ),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          SecurityShieldLogo(
            danger: true,
            size: dense ? AppMetrics.iconLg : AppMetrics.iconBoxSm,
          ),
          const SizedBox(width: AppMetrics.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'سپر امنیتی اتصال را مسدود کرده است',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: dense ? AppMetrics.fontCaption : null,
                        fontWeight: FontWeight.w800,
                        color: colors.danger,
                      ),
                ),
                Text(
                  'برنامه ناسازگار یا مخرب شناسایی شد: $names$extra',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppMetrics.space2),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor: colors.onPrimary,
              padding: EdgeInsets.symmetric(
                horizontal: dense ? AppMetrics.space2 : AppMetrics.space3,
                vertical: dense ? AppMetrics.space1 : AppMetrics.space2,
              ),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(
              Icons.cleaning_services_rounded,
              size: AppMetrics.iconSm,
            ),
            label: const Text('حذف و رفع مسدودی'),
            onPressed: onOpenShield,
          ),
        ],
      ),
    );
  }
}

/// هشدار دسترسی: اشتراک منقضی، مسدود یا تمام شده.
class _AccessBanner extends StatelessWidget {
  const _AccessBanner({
    required this.title,
    required this.message,
    this.dense = false,
  });

  final String title;
  final String message;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppMetrics.space3 : AppMetrics.space4,
        vertical: dense ? AppMetrics.space2 : AppMetrics.space3,
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
            size: dense ? AppMetrics.iconSm : AppMetrics.iconMd,
            color: colors.danger,
          ),
          const SizedBox(width: AppMetrics.space2),
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
    this.dense = false,
  });

  final String ip;
  final String flagCode;
  final String country;
  final bool connected;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String caption = connected
        ? (country.isNotEmpty ? 'آی پی اتصال · $country' : 'آی پی اتصال')
        : 'آی پی دستگاه';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppMetrics.space2 + 2 : AppMetrics.space3,
        vertical: dense ? AppMetrics.space1 + 2 : AppMetrics.space2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(
          dense ? AppMetrics.radiusMd : AppMetrics.radiusLg,
        ),
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
            FlagView(
              code: flagCode,
              width: dense ? AppMetrics.flagWidthSmall : AppMetrics.flagWidth,
            ),
            const SizedBox(width: AppMetrics.space2),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fa.num(caption),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: dense ? AppMetrics.fontMicro : null,
                        color:
                            connected ? colors.success : colors.textSecondary,
                        fontWeight:
                            connected ? FontWeight.w700 : FontWeight.w600,
                      ),
                ),
                SizedBox(height: dense ? 1 : AppMetrics.space1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    ip,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    style: (dense
                            ? Theme.of(context).textTheme.labelMedium
                            : Theme.of(context).textTheme.titleSmall)
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
