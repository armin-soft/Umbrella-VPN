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
      if (subs.totalNodes == 0 && !subs.loadingAll) {
        unawaited(subs.fetchAll());
      }
      await OccasionService.instance.load();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final SettingsController settings = context.watch<SettingsController>();
    final ToastController toasts = context.read<ToastController>();
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
          GlassCard(
            padding: const EdgeInsets.all(24),
            radius: 26,
            elevated: true,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                tone.withValues(alpha: 0.16),
                colors.surface,
                colors.backgroundAlt,
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                StatusOrb(
                  image: status.image,
                  color: tone,
                  size: 232,
                  active: status.busy,
                ),
                const SizedBox(width: 26),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Pill(
                            label: status.label,
                            icon: VpnVisuals.icon(status),
                            color: tone,
                          ),
                          if (vpn.killSwitchOn)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Pill(
                                label: 'کیل سوییچ فعال',
                                icon: Icons.gpp_good_rounded,
                                color: colors.success,
                              ),
                            ),
                          if (connected && vpn.tunnelVerified)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Pill(
                                label: 'تونل تایید شد',
                                icon: Icons.verified_user_rounded,
                                color: colors.info,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        Fa.num(vpn.message),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              height: 1.8,
                            ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: <Widget>[
                          if (vpn.activeNode != null) ...<Widget>[
                            Icon(Icons.dns_rounded, size: 16, color: colors.textSecondary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                Fa.num(
                                  '${vpn.activeNode!.name} | ${vpn.activeNode!.hasPing ? Fa.ms(vpn.activeNode!.pingMs) : 'پینگ نامشخص'}',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                              ),
                            ),
                          ] else
                            Text(
                              Fa.num('سروری انتخاب نشده است'),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: <Widget>[
                          SizedBox(
                            width: 220,
                            child: GradientButton(
                              label: status.active && !status.busy
                                  ? 'قطع اتصال'
                                  : (status.busy ? status.label : 'اتصال'),
                              icon: status.active && !status.busy
                                  ? Icons.power_settings_new_rounded
                                  : Icons.power_settings_new_rounded,
                              tone: status.active && !status.busy
                                  ? colors.danger
                                  : colors.primary,
                              loading: status.busy,
                              onPressed: status.busy
                                  ? null
                                  : () async {
                                      if (status.active) {
                                        await vpn.disconnect();
                                        toasts.info('اتصال قطع شد');
                                      } else {
                                        final ConnectOutcome outcome =
                                            await vpn.connect();
                                        if (outcome.ok) {
                                          toasts.success(
                                            'اتصال برقرار شد',
                                            vpn.activeNode?.name ?? '',
                                          );
                                        } else {
                                          toasts.error('اتصال برقرار نشد', outcome.message);
                                        }
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: widget.onOpenServers,
                            icon: const Icon(Icons.dns_outlined, size: 18),
                            label: const Text('انتخاب سرور'),
                          ),
                          const SizedBox(width: 12),
                          IconAction(
                            icon: Icons.speed_rounded,
                            tooltip: 'سنجش پینگ همه سرورها',
                            size: 44,
                            onTap: vpn.measuring
                                ? () {}
                                : () async {
                                    toasts.info('سنجش پینگ شروع شد');
                                    await vpn.refreshPings();
                                    toasts.success('سنجش پینگ تمام شد');
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
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
