import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// حساب کاربری: پروفایل، مصرف، اعتبار، اشتراک ها، کنترل محتوا و دستگاه.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  List<String> _categories = <String>[];
  bool _filterEnabled = false;
  bool _savingFilter = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final FilterSettings filter = context.read<AuthController>().filter;
      _categories = List<String>.of(filter.categories);
      _filterEnabled = filter.enabled;
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final VpnController vpn = context.watch<VpnController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final Account account = auth.account;
    final DeviceProfile device = auth.device;

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
                      Fa.num('حساب من'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fa.num('پروفایل، مصرف و تنظیمات حساب شما در آمبرلا'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              IconAction(
                icon: Icons.refresh_rounded,
                tooltip: 'به روز رسانی اطلاعات حساب',
                size: 44,
                onTap: () async {
                  await auth.refreshAccount();
                  toasts.success('اطلاعات حساب به روز شد');
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: <Color>[colors.primary, colors.primaryDeep],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              Fa.num(account.displayName.isEmpty ? 'آ' : account.displayName.substring(0, 1)),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: colors.onPrimary,
                                fontFamily: AppTheme.fontFamily,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  Fa.num(account.displayName),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  Fa.num(IranPhone.display(
                                    account.phone.isNotEmpty ? account.phone : auth.phone,
                                  )),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Pill(
                            label: account.expired
                                ? 'منقضی'
                                : (account.isActive ? 'فعال' : 'غیرفعال'),
                            icon: account.expired
                                ? Icons.timer_off_rounded
                                : Icons.verified_rounded,
                            color: account.expired
                                ? colors.danger
                                : (account.isActive ? colors.success : colors.warning),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      InfoRow(
                        icon: Icons.tag_rounded,
                        label: 'شناسه حساب',
                        value: account.uuid.isEmpty ? 'نامشخص' : account.uuid,
                        trailing: IconAction(
                          icon: Icons.copy_rounded,
                          size: 28,
                          tooltip: 'کپی شناسه',
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: account.uuid));
                            toasts.success('شناسه کپی شد');
                          },
                        ),
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.send_rounded,
                        label: 'شناسه تلگرام',
                        value: account.telegramId.isEmpty ? 'وصل نشده' : account.telegramId,
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.event_available_rounded,
                        label: 'تاریخ شروع',
                        value: Fa.date(account.startDate),
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.event_busy_rounded,
                        label: 'تاریخ انقضا',
                        value: Fa.date(account.expiryDate),
                        valueColor: account.expired ? colors.danger : colors.textPrimary,
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.hourglass_bottom_rounded,
                        label: 'روزهای باقی مانده',
                        value: Fa.days(account.daysLeft),
                        valueColor: account.daysLeft < 5 ? colors.warning : colors.textPrimary,
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.timelapse_rounded,
                        label: 'آخرین اتصال',
                        value: Fa.relative(account.lastOnline),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: <Widget>[
                      SectionHeader(title: 'مصرف ترافیک'),
                      const SizedBox(height: 16),
                      UsageRing(
                        percent: account.usagePercent,
                        centerValue: Fa.decimal(account.currentUsageGb, fraction: 2),
                        centerLabel: 'گیگابایت مصرف شده',
                        size: 176,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: StatTile(
                              label: 'حجم کل',
                              value: Fa.gb(account.usageLimitGb),
                              icon: Icons.data_usage_rounded,
                              compact: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StatTile(
                              label: 'باقی مانده',
                              value: Fa.gb(account.remainingGb),
                              icon: Icons.battery_charging_full_rounded,
                              accent: colors.success,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        Fa.num(
                          account.usageLimitGb <= 0
                              ? 'برای این حساب سقف حجم تعیین نشده است.'
                              : '${Fa.percent(account.usagePercent)} از حجم سرویس مصرف شده است.',
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'اشتراک های من',
                        subtitle: 'تنها منابع مجاز برنامه؛ برای کپی یا باز کردن بزنید.',
                      ),
                      const SizedBox(height: 12),
                      for (final SubscriptionSource source
                          in AppConfig.subscriptionSources)
                        InfoRow(
                          icon: Icons.link_rounded,
                          label: source.title,
                          value: source.format.label,
                          onTap: () async {
                            final Uri? uri = Uri.tryParse(source.url);
                            if (uri != null) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          trailing: IconAction(
                            icon: Icons.copy_rounded,
                            size: 28,
                            tooltip: 'کپی نشانی',
                            onTap: () async {
                              await Clipboard.setData(ClipboardData(text: source.url));
                              toasts.success('نشانی ${source.title} کپی شد');
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'کنترل محتوا',
                        subtitle: 'بین برنامه و ربات همگام است.',
                        trailing: Switch.adaptive(
                          value: _filterEnabled,
                          onChanged: (bool value) => setState(() => _filterEnabled = value),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final MapEntry<String, String> entry
                              in FilterSettings.categoryLabels.entries)
                            _CategoryToggle(
                              label: entry.value,
                              selected: _categories.contains(entry.key),
                              enabled: _filterEnabled,
                              onTap: () {
                                if (!_filterEnabled) {
                                  return;
                                }
                                setState(() {
                                  if (_categories.contains(entry.key)) {
                                    _categories.remove(entry.key);
                                  } else {
                                    _categories.add(entry.key);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GradientButton(
                        label: 'ذخیره تنظیمات کنترل محتوا',
                        icon: Icons.save_rounded,
                        loading: _savingFilter,
                        height: 46,
                        onPressed: _savingFilter
                            ? null
                            : () async {
                                setState(() => _savingFilter = true);
                                final bool ok = await auth.saveFilter(
                                  FilterSettings(
                                    enabled: _filterEnabled,
                                    categories: _categories,
                                  ),
                                );
                                setState(() => _savingFilter = false);
                                if (ok) {
                                  toasts.success('تنظیمات کنترل محتوا ذخیره شد');
                                } else {
                                  toasts.error('ذخیره ناموفق بود', auth.error);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'دستگاه من',
                  subtitle: 'اطلاعات دقیق دستگاهی که با آن وارد شده اید.',
                  trailing: Pill(
                    label: device.elevated ? 'دسترسی مدیر' : 'بدون دسترسی مدیر',
                    icon: device.elevated
                        ? Icons.admin_panel_settings_rounded
                        : Icons.lock_outline_rounded,
                    color: device.elevated ? colors.success : colors.warning,
                    dense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          InfoRow(
                            icon: Icons.computer_rounded,
                            label: 'نام دستگاه',
                            value: device.deviceName,
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.memory_rounded,
                            label: 'سیستم عامل',
                            value: device.platformLabel,
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.person_outline_rounded,
                            label: 'کاربر ویندوز',
                            value: device.username.isEmpty ? 'نامشخص' : device.username,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          InfoRow(
                            icon: Icons.lan_rounded,
                            label: 'آی پی داخلی',
                            value: device.localIp.isEmpty ? 'نامشخص' : device.localIp,
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.public_rounded,
                            label: 'آی پی خروجی',
                            value: (vpn.exitIp.isNotEmpty ? vpn.exitIp : vpn.realIp)
                                    .isEmpty
                                ? 'نامشخص'
                                : (vpn.exitIp.isNotEmpty ? vpn.exitIp : vpn.realIp),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.place_rounded,
                            label: 'موقعیت',
                            value: vpn.geo.isEmpty ? 'نامشخص' : vpn.geo.flagEmojiFreeLabel,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await auth.signOut();
                      widget.onSignedOut();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('خروج از حساب'),
                    style: TextButton.styleFrom(foregroundColor: colors.danger),
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

class _CategoryToggle extends StatelessWidget {
  const _CategoryToggle({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? colors.primary.withValues(alpha: 0.14) : colors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? colors.primary : colors.border),
            ),
            child: Text(
              Fa.num(label),
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
