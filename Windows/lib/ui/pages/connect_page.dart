import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../state/subscription_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';

/// صفحه اصلی اتصال: لوگوی وضعیت، دکمه اتصال، آمار زنده و میانبرها.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.onOpenServers});

  final VoidCallback onOpenServers;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final SubscriptionController subs = context.read<SubscriptionController>();
      final VpnController vpn = context.read<VpnController>();
      if (subs.totalNodes == 0 && !subs.loadingAll) {
        await subs.fetchAll();
      }
      // اگر سروری هست ولی هنوز عددی برای پینگ ندارد، سنجش خودکار شروع می شود.
      if (!vpn.measuring &&
          vpn.nodes.isNotEmpty &&
          vpn.nodes.every((VpnNode node) => !node.hasPing)) {
        unawaited(vpn.refreshPings());
      }
      await OccasionService.instance.load();
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// اتصال یا قطع اتصال، با گزارش نتیجه برای کاربر.
  Future<void> _toggleConnection(
    VpnController vpn,
    ToastController toasts,
  ) async {
    if (vpn.status.busy) {
      return;
    }
    if (vpn.status.active) {
      await vpn.disconnect();
      toasts.info('اتصال قطع شد');
      return;
    }
    if (vpn.nodes.isEmpty) {
      toasts.error('سروری موجود نیست', 'اول اشتراک باید خوانده شود.');
      return;
    }
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      toasts.success('اتصال برقرار شد', vpn.activeNode?.name ?? '');
    } else {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final SettingsController settings = context.watch<SettingsController>();
    final ToastController toasts = context.read<ToastController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
    final UmbrellaColors colors = context.colors;
    final VpnStatus status = vpn.status;
    final Color tone = VpnVisuals.color(context, status);
    final Account account = auth.account;
    final bool connected = status == VpnStatus.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fa.num('سلام ${account.displayName}، خوش آمدید'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fa.num(
                        '${Fa.longDate(DateTime.now())} | ${vpn.geo.cityLabel}${vpn.geo.countryLabel.isEmpty ? '' : '، ${vpn.geo.countryLabel}'}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              if (vpn.exitIp.isNotEmpty || vpn.realIp.isNotEmpty)
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  radius: 14,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.public_rounded, size: 16, color: colors.info),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            Fa.num(connected ? 'آی پی فعلی' : 'آی پی دستگاه'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                          ),
                          Text(
                            Fa.num(vpn.exitIp.isNotEmpty ? vpn.exitIp : vpn.realIp),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      IconAction(
                        icon: Icons.refresh_rounded,
                        size: 28,
                        onTap: () => vpn.refreshIp(),
                        tooltip: 'بررسی دوباره آی پی',
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          OccasionBanner(
            occasion: OccasionService.instance.active,
            enabled: settings.settings.occasionEffects,
          ),
          if (OccasionService.instance.active != null)
            const SizedBox(height: 16),
          if (vpn.nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded, color: colors.warning, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'هیچ سروری موجود نیست',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            Fa.num(
                              subs.needsLogin
                                  ? 'برای دریافت اشتراک باید وارد حساب شوی؛ سپس سرورها خودکار خوانده می شوند.'
                                  : (subs.personalErrors.isNotEmpty
                                      ? subs.personalErrors.first
                                      : 'اشتراک خوانده نشد؛ دوباره تلاش کن.'),
                            ),
                            maxLines: 3,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: subs.loadingAll ? null : () => subs.fetchAll(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('تلاش دوباره'),
                    ),
                  ],
                ),
              ),
            ),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            radius: 28,
            elevated: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                tone.withValues(alpha: 0.18),
                colors.surface,
                colors.backgroundAlt,
              ],
            ),
            child: Column(
              children: <Widget>[
                // دکمه بزرگ اتصال: کل دایره وسط صفحه قابل لمس است.
                Semantics(
                  button: true,
                  label: status.active ? 'قطع اتصال' : 'اتصال',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: status.busy
                        ? null
                        : () => _toggleConnection(vpn, toasts),
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        StatusOrb(
                          image: status.image,
                          color: tone,
                          size: 300,
                          active: status.busy,
                        ),
                        if (!status.busy)
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (status.active ? colors.danger : colors.primary)
                                  .withValues(alpha: 0.92),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: (status.active ? colors.danger : colors.primary)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 22,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.power_settings_new_rounded,
                              size: 38,
                              color: colors.onPrimary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  Fa.num(status.label),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: tone,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  Fa.num(vpn.message),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.7,
                      ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 320,
                  child: GradientButton(
                    label: status.active && !status.busy ? 'قطع اتصال' : 'اتصال',
                    icon: Icons.power_settings_new_rounded,
                    height: 60,
                    tone: status.active && !status.busy ? colors.danger : colors.primary,
                    loading: status.busy,
                    onPressed: status.busy
                        ? null
                        : () => _toggleConnection(vpn, toasts),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: <Widget>[
                    if (vpn.activeNode != null)
                      Pill(
                        label: Fa.num(
                          '${vpn.activeNode!.name} | '
                          '${vpn.activeNode!.hasPing ? Fa.ms(vpn.activeNode!.pingMs) : 'پینگ نامشخص'}',
                        ),
                        icon: Icons.dns_rounded,
                        color: colors.info,
                      )
                    else
                      Pill(
                        label: 'سروری انتخاب نشده است',
                        icon: Icons.dns_outlined,
                        color: colors.textSecondary,
                      ),
                    if (connected && vpn.tunnelVerified)
                      Pill(
                        label: 'تونل تایید شد',
                        icon: Icons.verified_user_rounded,
                        color: colors.info,
                      ),
                    if (vpn.measuring)
                      Pill(
                        label: 'در حال سنجش پینگ',
                        icon: Icons.speed_rounded,
                        color: colors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: widget.onOpenServers,
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: const Text('انتخاب سرور'),
                    ),
                    OutlinedButton.icon(
                      onPressed: vpn.measuring
                          ? null
                          : () async {
                              toasts.info('سنجش پینگ شروع شد');
                              await vpn.refreshPings();
                              toasts.success('سنجش پینگ تمام شد');
                            },
                      icon: const Icon(Icons.speed_rounded, size: 18),
                      label: const Text('سنجش پینگ سرورها'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (vpn.stats.available)
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'سرعت دانلود',
                  value: Fa.speed(vpn.stats.downSpeed),
                  icon: Icons.arrow_downward_rounded,
                  accent: colors.success,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'سرعت آپلود',
                  value: Fa.speed(vpn.stats.upSpeed),
                  icon: Icons.arrow_upward_rounded,
                  accent: colors.info,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'حجم دریافتی',
                  value: Fa.bytes(vpn.stats.rx),
                  icon: Icons.cloud_download_rounded,
                  accent: colors.primary,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'حجم ارسالی',
                  value: Fa.bytes(vpn.stats.tx),
                  icon: Icons.cloud_upload_rounded,
                  accent: colors.warning,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'مدت اتصال',
                  value: Fa.duration(vpn.stats.connectedFor),
                  icon: Icons.timer_outlined,
                  accent: colors.textSecondary,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'حالت انتخاب سرور',
                  subtitle: 'سرور فعال چطور انتخاب شود؟',
                ),
                const SizedBox(height: 14),
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
                              selected: settings.settings.selectionMode == mode,
                              onTap: () async {
                                await settings.setSelectionMode(mode);
                                toasts.info('حالت انتخاب سرور: ${mode.faName}');
                              },
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
