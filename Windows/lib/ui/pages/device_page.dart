import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// صفحه «دستگاه من»: مشخصات سخت افزاری، هویت و وضعیت شبکه این کامپیوتر.
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

  Future<void> _load({bool force = false}) async {
    if (!force && _device.machineId.isNotEmpty) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    if (mounted) {
      setState(() => _loading = true);
    }
    final NativeBridge native = context.read<NativeBridge>();
    final DeviceProfile profile = await native.deviceInfo();
    if (!mounted) {
      return;
    }
    setState(() {
      _device = profile;
      _loading = false;
    });
  }

  Future<void> _copy(String label, String value) async {
    if (value.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (!mounted) {
      return;
    }
    context.read<ToastController>().success('$label کپی شد');
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final UmbrellaColors colors = context.colors;
    final DeviceProfile device =
        _device.machineId.isEmpty ? vpn.device : _device;

    final bool tunnelUp = vpn.status == VpnStatus.connected;
    final String rawPublicIp = tunnelUp && vpn.exitIp.isNotEmpty
        ? vpn.exitIp
        : (vpn.realIp.isNotEmpty
            ? vpn.realIp
            : (vpn.geo.ip.isNotEmpty ? vpn.geo.ip : device.localIp));
    final bool hasPublicIp = rawPublicIp.isNotEmpty;
    final String publicIp = hasPublicIp ? rawPublicIp : 'در حال خواندن';
    final bool hasLocalIp = device.localIp.isNotEmpty;
    final bool hasMac = device.mac.isNotEmpty;
    final String deviceName =
        device.deviceName.isEmpty ? 'این دستگاه' : device.deviceName;

    String orUnknown(String value) => value.isEmpty ? 'نامشخص' : value;

    return SingleChildScrollView(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'دستگاه من',
            subtitle: 'مشخصات سیستم، شناسه و شبکه فعال این کامپیوتر',
            icon: Icons.computer_rounded,
            actions: <Widget>[
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () async {
                        await _load(force: true);
                        await vpn.refreshIp();
                        if (context.mounted) {
                          context
                              .read<ToastController>()
                              .info('اطلاعات دستگاه به روز شد');
                        }
                      },
                icon: _loading
                    ? const SizedBox(
                        width: AppMetrics.iconXs,
                        height: AppMetrics.iconXs,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: AppMetrics.iconSm),
                label: const Text('به روز رسانی'),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نوار هویتی یکدست دستگاه ───────────────────────────────────
          PageBanner(
            leading: IconSquare(
              icon: Icons.computer_rounded,
              color: colors.primary,
              size: AppMetrics.iconBoxHero,
              radius: AppMetrics.radiusLg,
            ),
            title: deviceName,
            subtitle:
                '${device.platformLabel} • حساب ${auth.account.displayName}',
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
                label: hasLocalIp ? 'شبکه متصل' : 'شبکه نامشخص',
                icon: Icons.wifi_rounded,
                color: hasLocalIp ? colors.success : colors.warning,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── نشانی های شبکه در یک نگاه (سه کارت هم اندازه و خوانا) ────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow =
                  constraints.maxWidth < AppMetrics.breakpointGrid;
              final Widget ipTile = StatTile(
                label: tunnelUp ? 'آی پی خروجی' : 'آی پی بیرونی',
                value: publicIp,
                ltr: hasPublicIp,
                icon: Icons.public_rounded,
                accent: tunnelUp ? colors.success : colors.primary,
                compact: true,
              );
              final Widget localTile = StatTile(
                label: 'آی پی داخلی شبکه',
                value: hasLocalIp ? device.localIp : 'نامشخص',
                ltr: hasLocalIp,
                icon: Icons.lan_rounded,
                accent: colors.primary,
                compact: true,
              );
              final Widget macTile = StatTile(
                label: 'آدرس فیزیکی (MAC)',
                value: hasMac ? device.mac : 'نامشخص',
                ltr: hasMac,
                icon: Icons.fingerprint_rounded,
                accent: colors.primary,
                compact: true,
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ipTile,
                    const SizedBox(height: AppMetrics.space3),
                    localTile,
                    const SizedBox(height: AppMetrics.space3),
                    macTile,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: ipTile),
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(child: localTile),
                    const SizedBox(width: AppMetrics.space4),
                    Expanded(child: macTile),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── دو کارت متقارن سخت افزار و هویت (۴ ردیف در هر ستون) ──────
          ResponsiveColumns(
            leftFlex: 1,
            rightFlex: 1,
            spacing: AppMetrics.space4,
            left: GlassCard(
              padding: AppMetrics.cardPadding,
              radius: AppMetrics.radiusXl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SectionHeader(
                    icon: Icons.memory_rounded,
                    title: 'سخت افزار و سیستم عامل',
                    subtitle: 'مشخصات فنی سیستم فعلی',
                  ),
                  const Divider(height: AppMetrics.space5),
                  InfoRow(
                    icon: Icons.computer_rounded,
                    label: 'نام دستگاه',
                    value: orUnknown(device.deviceName),
                    ltr: device.deviceName.isNotEmpty,
                    tooltip: true,
                  ),
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.window_rounded,
                    label: 'سیستم عامل',
                    value: Fa.num(device.platformLabel),
                    tooltip: true,
                  ),
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.developer_board_rounded,
                    label: 'پردازنده',
                    value: orUnknown(device.cpu),
                    ltr: device.cpu.isNotEmpty,
                    tooltip: true,
                  ),
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'دسترسی مدیر ویندوز',
                    value: device.elevated ? 'فعال' : 'غیرفعال',
                    valueColor:
                        device.elevated ? colors.success : colors.warning,
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
                  const SectionHeader(
                    icon: Icons.verified_user_rounded,
                    title: 'هویت و اتصال شبکه',
                    subtitle: 'مشخصات ثبت شده دستگاه در حساب کاربری',
                  ),
                  const Divider(height: AppMetrics.space5),
                  InfoRow(
                    icon: Icons.badge_rounded,
                    label: 'شناسه دستگاه',
                    value: orUnknown(device.machineId),
                    ltr: device.machineId.isNotEmpty,
                    tooltip: true,
                    trailing: device.machineId.isEmpty
                        ? null
                        : IconAction(
                            icon: Icons.copy_rounded,
                            tooltip: 'کپی شناسه دستگاه',
                            size: AppMetrics.iconBoxSm,
                            onTap: () =>
                                _copy('شناسه دستگاه', device.machineId),
                          ),
                  ),
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'کاربر ویندوز',
                    value: orUnknown(device.username),
                    ltr: device.username.isNotEmpty,
                    tooltip: true,
                  ),
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.person_rounded,
                    label: 'صاحب حساب',
                    value: Fa.num(auth.account.displayName),
                  ),
                  const Divider(height: AppMetrics.space2),
                  InfoRow(
                    icon: Icons.wifi_rounded,
                    label: 'وضعیت کارت شبکه',
                    value: hasLocalIp ? 'متصل و آماده' : 'نامشخص',
                    valueColor: hasLocalIp ? colors.success : colors.warning,
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
