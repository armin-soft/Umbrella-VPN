import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// صفحه «دستگاه من»: مشخصات کامل همین کامپیوتر، شبکه و اتصال.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  DeviceProfile _device = DeviceProfile.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_device.machineId.isEmpty) {
      final NativeBridge native = context.read<NativeBridge>();
      final DeviceProfile profile = await native.deviceInfo();
      if (!mounted) {
        return;
      }
      setState(() {
        _device = profile;
        _loading = false;
      });
      return;
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final SettingsController settings = context.watch<SettingsController>();
    final UmbrellaColors colors = context.colors;
    final DeviceProfile device = _device.machineId.isEmpty ? vpn.device : _device;
    final Account account = auth.account;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            Fa.num('دستگاه من'),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            Fa.num('مشخصات کامل این کامپیوتر، شبکه و اتصال فعلی.'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Column(
                  children: <Widget>[
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(
                            title: 'کامپیوتر',
                            subtitle: 'اطلاعات سخت افزاری و سیستم عامل',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.computer_rounded,
                            label: 'نام دستگاه',
                            value: Fa.num(device.deviceName),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.person_outline_rounded,
                            label: 'کاربر ویندوز',
                            value: Fa.num(device.username.isEmpty
                                ? 'نامشخص'
                                : device.username),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.memory_rounded,
                            label: 'پردازنده',
                            value: Fa.num(device.cpu.isEmpty
                                ? 'نامشخص'
                                : device.cpu),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.window_rounded,
                            label: 'سیستم عامل',
                            value: Fa.num(device.platformLabel),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.fingerprint_rounded,
                            label: 'شناسه یکتای دستگاه',
                            value: Fa.num(device.machineId.isEmpty
                                ? 'نامشخص'
                                : device.machineId),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.admin_panel_settings_rounded,
                            label: 'دسترسی مدیر',
                            value: device.elevated ? 'فعال' : 'غیرفعال',
                            valueColor: device.elevated
                                ? colors.success
                                : colors.warning,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(
                            title: 'شبکه',
                            subtitle: 'آدرس های همین دستگاه',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.lan_rounded,
                            label: 'آی پی داخلی',
                            value: Fa.num(device.localIp.isEmpty
                                ? 'نامشخص'
                                : device.localIp),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.wifi_rounded,
                            label: 'آدرس فیزیکی (MAC)',
                            value: Fa.num(device.mac.isEmpty
                                ? 'نامشخص'
                                : device.mac),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.public_rounded,
                            label: 'آی پی بیرونی',
                            value: Fa.num(vpn.exitIp.isNotEmpty
                                ? vpn.exitIp
                                : (vpn.realIp.isEmpty
                                    ? 'در حال بررسی'
                                    : vpn.realIp)),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.flag_rounded,
                            label: 'کشور خروجی',
                            value: Fa.num(vpn.geo.countryLabel.isEmpty
                                ? 'نامشخص'
                                : vpn.geo.countryLabel),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: Column(
                  children: <Widget>[
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(
                            title: 'اتصال فعلی',
                            subtitle: 'وضعیت تونل و هسته',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.shield_rounded,
                            label: 'وضعیت',
                            value: Fa.num(vpn.status.label),
                            valueColor: VpnVisuals.color(context, vpn.status),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.dns_rounded,
                            label: 'سرور',
                            value: Fa.num(vpn.activeNode?.name ?? 'انتخاب نشده'),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.memory_rounded,
                            label: 'هسته انتخابی',
                            value: Fa.num(settings.settings.corePreference.faName),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.lan_outlined,
                            label: 'حالت اتصال',
                            value: settings.settings.tunMode
                                ? 'تونل کامل (TUN)'
                                : 'پروکسی سیستمی',
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.timer_outlined,
                            label: 'مدت اتصال',
                            value: Fa.duration(vpn.stats.connectedFor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(
                            title: 'برنامه',
                            subtitle: 'نسخه و حساب',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.apps_rounded,
                            label: 'نسخه برنامه',
                            value: Fa.num(AppConfig.versionLabel),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.person_rounded,
                            label: 'حساب',
                            value: Fa.num(account.displayName),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.badge_rounded,
                            label: 'شناسه حساب',
                            value: Fa.num(account.uuid.isEmpty
                                ? 'نامشخص'
                                : account.uuid),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.category_rounded,
                            label: 'نوع سرویس',
                            value: Fa.num(account.planLabel),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
