import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../state/auth_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';
import '../widgets/live_clock.dart';

/// صفحه «دستگاه من»: مشخصات همین کامپیوتر و شبکه آن.
///
/// چیدمان: یک هدر هویتی (نام دستگاه + سیستم عامل + دسترسی مدیر)، بعد چند کارت
/// آماری برای شبکه، و در پایان دو کارت لیستی برای سخت افزار و هویت. وضعیت
/// تونل و حساب هر کدام صفحه خودشان را دارند.
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
    final UmbrellaColors colors = context.colors;
    final DeviceProfile device =
        _device.machineId.isEmpty ? vpn.device : _device;

    // آی پی بیرونی: اگر تونل وصل باشد آی پی خروجی، وگرنه آی پی واقعی.
    final String publicIp = vpn.status == VpnStatus.connected &&
            vpn.exitIp.isNotEmpty
        ? vpn.exitIp
        : (vpn.realIp.isNotEmpty
            ? vpn.realIp
            : (vpn.geo.ip.isNotEmpty
                ? vpn.geo.ip
                : (device.localIp.isEmpty ? 'در حال خواندن' : device.localIp)));
    final bool tunnelUp = vpn.status == VpnStatus.connected;

    // اعداد فارسی می شوند؛ رشته خالی «نامشخص» می شود.
    String orUnknown(String value) =>
        Fa.num(value.isEmpty ? 'نامشخص' : value);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
            title: 'دستگاه من',
            subtitle: 'مشخصات این کامپیوتر و شبکه آن؛ وضعیت اتصال صفحه خودش را دارد.',
            icon: Icons.devices_rounded,
          ),
          const SizedBox(height: 16),
          _DeviceHero(
            device: device,
            colors: colors,
            accountName: auth.account.displayName,
          ),
          const SizedBox(height: 16),

          // ── شبکه در یک نگاه ────────────────────────────────────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool narrow = constraints.maxWidth < 700;
              final Widget ip = StatTile(
                label: tunnelUp ? 'آی پی خروجی' : 'آی پی بیرونی',
                value: Fa.num(publicIp),
                icon: Icons.public_rounded,
                accent: tunnelUp ? colors.success : colors.info,
                compact: true,
              );
              final Widget local = StatTile(
                label: 'آی پی داخلی',
                value: orUnknown(device.localIp),
                icon: Icons.lan_rounded,
                accent: colors.primary,
                compact: true,
              );
              final Widget mac = StatTile(
                label: 'آدرس فیزیکی',
                value: device.mac.isEmpty ? 'نامشخص' : device.mac,
                icon: Icons.fingerprint_rounded,
                accent: colors.warning,
                compact: true,
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: ip),
                          const SizedBox(width: 12),
                          Expanded(child: local),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    mac,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 5, child: ip),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: local),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: mac),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── سخت افزار و هویت ──────────────────────────────────────
          ResponsiveColumns(
            leftFlex: 3,
            rightFlex: 2,
            left: GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    title: 'کامپیوتر',
                    subtitle: 'اطلاعات سخت افزاری و سیستم عامل',
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    icon: Icons.computer_rounded,
                    label: 'نام دستگاه',
                    value: orUnknown(device.deviceName),
                  ),
                  const Divider(height: 14),
                  InfoRow(
                    icon: Icons.memory_rounded,
                    label: 'پردازنده',
                    value: orUnknown(device.cpu),
                  ),
                  const Divider(height: 14),
                  InfoRow(
                    icon: Icons.window_rounded,
                    label: 'سیستم عامل',
                    value: Fa.num(device.platformLabel),
                  ),
                  const Divider(height: 14),
                  InfoRow(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'دسترسی مدیر',
                    value: device.elevated ? 'فعال' : 'غیرفعال',
                    valueColor: device.elevated ? colors.success : colors.warning,
                  ),
                  const Divider(height: 14),
                  InfoRow(
                    icon: Icons.badge_rounded,
                    label: 'شناسه یکتای دستگاه',
                    value: orUnknown(device.machineId),
                  ),
                ],
              ),
            ),
            right: Column(
              children: <Widget>[
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SectionHeader(
                        title: 'هویت دستگاه',
                        subtitle: 'همان شناسه ای که سرور می شناسد',
                      ),
                      const SizedBox(height: 12),
                      InfoRow(
                        icon: Icons.person_outline_rounded,
                        label: 'کاربر ویندوز',
                        value: orUnknown(device.username),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.person_rounded,
                        label: 'صاحب حساب',
                        value: Fa.num(auth.account.displayName),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.wifi_rounded,
                        label: 'کارت شبکه فعال',
                        value: device.localIp.isEmpty ? 'نامشخص' : 'متصل',
                        valueColor: device.localIp.isEmpty
                            ? colors.warning
                            : colors.success,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                LiveDateTimeLine(
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

/// هدر هویتی دستگاه: آیکون بزرگ + نام دستگاه + چند برچسب کوتاه.
class _DeviceHero extends StatelessWidget {
  const _DeviceHero({
    required this.device,
    required this.colors,
    required this.accountName,
  });

  final DeviceProfile device;
  final UmbrellaColors colors;
  final String accountName;

  @override
  Widget build(BuildContext context) {
    final String name =
        device.deviceName.isEmpty ? 'این دستگاه' : device.deviceName;
    return GlassCard(
      padding: const EdgeInsets.all(22),
      radius: 22,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: <Color>[
          colors.primary.withValues(alpha: 0.16),
          colors.surface,
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 470;
          final Widget icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: colors.primary.withValues(alpha: 0.16),
              border: Border.all(color: colors.primary.withValues(alpha: 0.45)),
            ),
            child: Icon(Icons.devices_rounded, size: 30, color: colors.primary),
          );
          final Widget text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fa.num(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                Fa.num('${device.platformLabel} • ${accountName}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],
          );
          final List<Widget> pills = <Widget>[
            Pill(
              label: device.elevated ? 'دسترسی مدیر' : 'بدون دسترسی مدیر',
              icon: device.elevated
                  ? Icons.verified_user_rounded
                  : Icons.gpp_maybe_rounded,
              color: device.elevated ? colors.success : colors.warning,
              dense: true,
            ),
            const SizedBox(width: 8),
            Pill(
              label: device.localIp.isEmpty ? 'شبکه نامشخص' : 'شبکه متصل',
              icon: Icons.wifi_rounded,
              color: device.localIp.isEmpty ? colors.warning : colors.info,
              dense: true,
            ),
          ];
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: text),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: pills),
              ],
            );
          }
          return Row(
            children: <Widget>[
              icon,
              const SizedBox(width: 18),
              Expanded(child: text),
              ...pills,
            ],
          );
        },
      ),
    );
  }
}
