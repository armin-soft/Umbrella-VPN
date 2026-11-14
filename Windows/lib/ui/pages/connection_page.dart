import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// صفحه «وضعیت اتصال»: همه چیزی که به تونل، هسته و سرور مربوط است.
///
/// این اطلاعات از «دستگاه من» به اینجا منتقل شده اند تا آن صفحه فقط مشخصات
/// دستگاه را نشان دهد. اتصال واقعی از صفحه «اتصال» انجام می شود.
class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final SettingsController settings = context.watch<SettingsController>();
    final AuthController auth = context.watch<AuthController>();
    final UmbrellaColors colors = context.colors;
    final VpnNode? node = vpn.activeNode;
    final Color tone = VpnVisuals.color(context, vpn.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            Fa.num('وضعیت اتصال'),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            Fa.num('تونل، هسته و سرور فعال. برای وصل شدن به صفحه اتصال برو.'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SectionHeader(
                        title: 'تونل',
                        subtitle: 'وضعیت، سرعت و مدت اتصال',
                      ),
                      const SizedBox(height: 10),
                      InfoRow(
                        icon: Icons.shield_rounded,
                        label: 'وضعیت',
                        value: Fa.num(vpn.status.label),
                        valueColor: tone,
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.timer_outlined,
                        label: 'مدت اتصال',
                        value: Fa.duration(vpn.stats.connectedFor),
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.speed_rounded,
                        label: 'پینگ زنده',
                        value: vpn.activePingMs > 0
                            ? Fa.ms(vpn.activePingMs)
                            : 'در حال سنجش',
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.download_rounded,
                        label: 'دریافتی',
                        value: vpn.stats.available
                            ? Fa.bytes(vpn.stats.rx)
                            : '—',
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.upload_rounded,
                        label: 'ارسالی',
                        value: vpn.stats.available
                            ? Fa.bytes(vpn.stats.tx)
                            : '—',
                      ),
                      const Divider(height: 14),
                      InfoRow(
                        icon: Icons.verified_user_rounded,
                        label: 'تایید عبور ترافیک',
                        value: vpn.tunnelVerified ? 'تایید شد' : 'در انتظار',
                        valueColor: vpn.tunnelVerified
                            ? colors.success
                            : colors.warning,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: <Widget>[
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionHeader(
                            title: 'سرور و هسته',
                            subtitle: 'همان چیزی که اتصال را می سازد',
                          ),
                          const SizedBox(height: 10),
                          InfoRow(
                            icon: Icons.dns_rounded,
                            label: 'سرور فعال',
                            value: Fa.num(node?.name ?? 'انتخاب نشده'),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.lan_rounded,
                            label: 'پروتکل',
                            value: Fa.num(node?.protocol.label ?? '—'),
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
                            value: Fa.num(auth.account.displayName),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.category_rounded,
                            label: 'نوع سرویس',
                            value: Fa.num(auth.account.planLabel),
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
