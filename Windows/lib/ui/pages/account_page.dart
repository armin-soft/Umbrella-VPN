import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// حساب کاربری: پروفایل کامل کاربر از سرور، مصرف، اشتراک خودکار، کنترل محتوا
/// و مشخصات دستگاه.
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
  bool _refreshing = false;
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

  Future<void> _refreshFromServer(AuthController auth,
      SubscriptionController subs, ToastController toasts) async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    await auth.refreshAccount();
    await subs.syncPersonal();
    if (!mounted) {
      return;
    }
    setState(() => _refreshing = false);
    if (auth.error.isEmpty) {
      toasts.success('اطلاعات حساب و اشتراک از سرور به روز شد');
    } else {
      toasts.error('به روز رسانی ناموفق بود', auth.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
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
                      Fa.num('پروفایل کامل شما از سرور خوانده می شود'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              IconAction(
                icon: Icons.sync_rounded,
                tooltip: 'به روز رسانی از سرور',
                size: 44,
                onTap: _refreshing
                    ? () {}
                    : () => _refreshFromServer(auth, subs, toasts),
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
                                colors: <Color>[
                                  colors.primary,
                                  colors.primaryDeep,
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              Fa.num(account.displayName.isEmpty
                                  ? 'آ'
                                  : account.displayName.substring(0, 1)),
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
                                    account.phone.isNotEmpty
                                        ? account.phone
                                        : auth.phone,
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
                                : (account.healthy ? 'فعال' : 'غیرفعال'),
                            icon: account.expired
                                ? Icons.timer_off_rounded
                                : Icons.verified_rounded,
                            color: account.expired
                                ? colors.danger
                                : (account.healthy
                                    ? colors.success
                                    : colors.warning),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      InfoRow(
                        icon: Icons.fingerprint_rounded,
                        label: 'شناسه حساب',
                        value: account.uuid.isEmpty ? 'نامشخص' : account.uuid,
                        trailing: IconAction(
                          icon: Icons.copy_rounded,
                          size: 28,
                          tooltip: 'کپی شناسه حساب',
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: account.uuid),
                            );
                            toasts.success('شناسه حساب کپی شد');
                          },
                        ),
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.call_rounded,
                        label: 'شماره موبایل',
                        value: IranPhone.display(
                          account.phone.isNotEmpty ? account.phone : auth.phone,
                        ),
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.send_rounded,
                        label: 'تلگرام',
                        value: account.telegramId.isEmpty
                            ? 'وصل نشده'
                            : account.telegramId,
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.workspace_premium_rounded,
                        label: 'نوع سرویس',
                        value: account.planLabel,
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
                        valueColor:
                            account.expired ? colors.danger : colors.textPrimary,
                      ),
                      const Divider(height: 18),
                      InfoRow(
                        icon: Icons.hourglass_bottom_rounded,
                        label: 'روزهای باقی مانده',
                        value: Fa.days(account.daysLeft),
                        valueColor: account.daysLeft < 5
                            ? colors.warning
                            : colors.textPrimary,
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
                        centerValue:
                            Fa.decimal(account.currentUsageGb, fraction: 2),
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
                              icon: Icons.inventory_2_rounded,
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
                flex: 3,
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'اشتراک من',
                        subtitle:
                            'به صورت خودکار از سرور خوانده می شود؛ نیازی به وارد کردن نشانی نیست.',
                        trailing: Pill(
                          label: subs.personalLoading
                              ? 'در حال دریافت'
                              : (subs.personalLoaded ? 'آماده' : 'خطا'),
                          icon: subs.personalLoading
                              ? Icons.downloading_rounded
                              : (subs.personalLoaded
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded),
                          color: subs.personalLoading
                              ? colors.warning
                              : (subs.personalLoaded
                                  ? colors.success
                                  : colors.danger),
                          dense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (subs.personalSources.isEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            InfoRow(
                              icon: Icons.cloud_off_rounded,
                              label: 'اشتراک شخصی',
                              value: 'سرور هنوز داده اشتراک این حساب را نفرستاده است',
                              valueColor: colors.warning,
                            ),
                            const SizedBox(height: 12),
                            GradientButton(
                              label: 'دریافت از سرور',
                              icon: Icons.cloud_download_rounded,
                              expand: false,
                              loading: _refreshing,
                              onPressed: _refreshing
                                  ? null
                                  : () => _refreshFromServer(
                                        auth,
                                        subs,
                                        toasts,
                                      ),
                            ),
                          ],
                        )
                      else ...<Widget>[
                        for (final SourceState state in subs.personalSources) ...[
                          InfoRow(
                            icon: _formatIcon(state.source.format),
                            label: state.title,
                            value: state.loading
                                ? 'در حال دریافت'
                                : (state.loaded
                                    ? Fa.num('${Fa.num(state.count)} سرور')
                                    : 'بدون سرور'),
                            valueColor: state.loading
                                ? colors.warning
                                : (state.loaded
                                    ? colors.textPrimary
                                    : colors.danger),
                          ),
                          const Divider(height: 14),
                        ],
                        InfoRow(
                          icon: Icons.dns_rounded,
                          label: 'مجموع سرورهای اشتراک',
                          value: Fa.num('${Fa.num(subs.personalNodeCount)} سرور'),
                        ),
                        const Divider(height: 14),
                        InfoRow(
                          icon: Icons.schedule_rounded,
                          label: 'آخرین دریافت',
                          value: subs.personalCheckedAt == null
                              ? 'در انتظار'
                              : Fa.clock(subs.personalCheckedAt!),
                        ),
                        if (subs.personalErrors.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            Fa.num(subs.personalErrors.first),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colors.danger),
                          ),
                        ],
                        const SizedBox(height: 12),
                        GradientButton(
                          label: 'دریافت دوباره از سرور',
                          icon: Icons.sync_rounded,
                          expand: false,
                          loading: _refreshing || subs.personalLoading,
                          onPressed: _refreshing || subs.personalLoading
                              ? null
                              : () => _refreshFromServer(auth, subs, toasts),
                        ),
                      ],
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: 'کنترل محتوا',
                        subtitle: 'بین برنامه و ربات همگام است.',
                        trailing: Switch.adaptive(
                          value: _filterEnabled,
                          onChanged: (bool value) =>
                              setState(() => _filterEnabled = value),
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
                                  toasts.success(
                                    'تنظیمات کنترل محتوا ذخیره شد',
                                  );
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
                            value: device.username.isEmpty
                                ? 'نامشخص'
                                : device.username,
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
                            value: device.localIp.isEmpty
                                ? 'نامشخص'
                                : device.localIp,
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.public_rounded,
                            label: 'آی پی خروجی',
                            value: (vpn.exitIp.isNotEmpty
                                        ? vpn.exitIp
                                        : vpn.realIp)
                                    .isEmpty
                                ? 'نامشخص'
                                : (vpn.exitIp.isNotEmpty
                                    ? vpn.exitIp
                                    : vpn.realIp),
                          ),
                          const Divider(height: 14),
                          InfoRow(
                            icon: Icons.place_rounded,
                            label: 'موقعیت',
                            value: vpn.geo.isEmpty
                                ? 'نامشخص'
                                : vpn.geo.flagEmojiFreeLabel,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
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

  /// آیکون متناسب با قالب هر اشتراک.
  IconData _formatIcon(SubscriptionFormat format) {
    switch (format) {
      case SubscriptionFormat.xray:
        return Icons.bolt_rounded;
      case SubscriptionFormat.clash:
        return Icons.grid_view_rounded;
      case SubscriptionFormat.wireguard:
        return Icons.shield_rounded;
      case SubscriptionFormat.amnezia:
        return Icons.lock_rounded;
      case SubscriptionFormat.mieru:
        return Icons.route_rounded;
    }
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
              color: selected
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? colors.primary : colors.border,
              ),
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
