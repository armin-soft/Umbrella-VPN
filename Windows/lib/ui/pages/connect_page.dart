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

/// صفحه اتصال: یک نگاه، یک دکمه.
///
/// کارت اتصال تمام ارتفاع صفحه را می گیرد و دکمه بزرگ در مرکز آن است. انتخاب
/// هسته و حالت انتخاب سرور به شکل چیپ های کوچک زیر دکمه هستند و هر کدام یک
/// منوی کوچک باز می کنند؛ هیچ فهرست بلندی در صفحه نیست.
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
  /// داخلی کارت شبکه. هیچ حالتی «نامشخص» یا خط تیره نمی دهد.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final SubscriptionController subs = context.read<SubscriptionController>();
      final VpnController vpn = context.read<VpnController>();
      await OccasionService.instance.load();
      if (!mounted) {
        return;
      }
      setState(() {});
      if (subs.totalNodes == 0 && !subs.loadingAll) {
        await subs.fetchAll();
      }
      if (!vpn.measuring &&
          vpn.nodes.isNotEmpty &&
          vpn.nodes.every((VpnNode node) => !node.hasPing)) {
        unawaited(vpn.refreshPings());
      }
    });
  }

  /// خط دوم نوار بالا: تاریخ، و اگر معلوم باشد شهر و کشور دستگاه.
  String _subtitleLine(VpnController vpn) {
    final String date = Fa.longDate(DateTime.now());
    final String city = vpn.geo.city;
    final String country = vpn.geo.countryLabel;
    final List<String> place = <String>[
      if (city.isNotEmpty) city,
      if (country.isNotEmpty) country,
    ];
    if (place.isEmpty) {
      return date;
    }
    return '$date | ${place.join('، ')}';
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
    final AuthController auth = context.read<AuthController>();
    if (!auth.account.canConnect) {
      toasts.error('اجازه اتصال نیست', auth.account.accessReason);
      return;
    }
    if (vpn.nodes.isEmpty) {
      toasts.error('سروری موجود نیست', 'اول اشتراک باید خوانده شود.');
      return;
    }
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      toasts.success('اتصال برقرار شد', vpn.activeNode?.name ?? '');
    } else if (!outcome.cancelled) {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  /// انتخاب حالت اتصال (تونل کامل / پروکسی سیستمی) از منوی کوچک؛ سپس اتصال
  /// خودکار به پایدارترین سرور.
  ///
  /// هسته یکی است (هسته هیدیفای)؛ این منو فقط تعیین می کند ترافیک با تونل
  /// کامل رد شود یا با پروکسی سیستمی.
  Future<void> _pickConnectionMode(
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    final CorePreference? picked = await showDialog<CorePreference>(
      context: context,
      builder: (BuildContext context) => _ConnectionModeDialog(
        current: settings.settings.corePreference,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    await settings.setCorePreference(picked);
    toasts.info('حالت اتصال: ${picked.faName}');
    if (vpn.status.busy) {
      return;
    }
    if (vpn.status.active) {
      await vpn.disconnect();
    }
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      toasts.success('متصل شد', vpn.activeNode?.name ?? '');
    } else {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  /// انتخاب حالت انتخاب سرور از منوی کوچک؛ حالت واقعا اعمال می شود.
  Future<void> _pickMode(
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    final SelectionMode? picked = await showDialog<SelectionMode>(
      context: context,
      builder: (BuildContext context) => _ModeDialog(
        current: settings.settings.selectionMode,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    if (picked == settings.settings.selectionMode) {
      return;
    }
    await settings.setSelectionMode(picked);
    toasts.info('حالت انتخاب سرور: ${picked.faName}');
    if (vpn.status.busy || !vpn.status.active) {
      return;
    }
    await vpn.disconnect();
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      toasts.success(
        'با حالت ${picked.faName} دوباره وصل شد',
        vpn.activeNode?.name ?? '',
      );
    } else {
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

    final String flagCode = vpn.geo.flagCode.isNotEmpty
        ? vpn.geo.flagCode
        : (vpn.activeNode?.flagCode ?? '');
    // آی پی دستگاه هرگز «نامشخص» نمی شود: اول آی پی واقعی خوانده شده از
    // اینترنت، بعد آی پی خروجی تونل و در آخر آی پی داخلی کارت شبکه.
    final String shownIp = _deviceIp(vpn);
    final String countryName = CountryNames.fa(flagCode);

    // ارتفاع صفحه کامل استفاده می شود؛ هیچ نیمه خالی نمی ماند.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double orb = constraints.maxHeight < 650
            ? 210
            : (constraints.maxHeight < 780 ? 250 : 288);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 22),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 42,
            ),
            child: GlassCard(
              radius: 26,
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  tone.withValues(alpha: 0.10),
                  colors.surface,
                  colors.backgroundAlt,
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── نوار بالا: سلام و آی پی و پرچم ────────────────────
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              Fa.num('سلام ${account.displayName}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              // تاریخ و، اگر شناخته شده باشد، شهر و کشور همین
                              // دستگاه؛ بخش ناشناخته نوشته نمی شود تا خط
                              // «نامشخص، نامشخص» دیده نشود.
                              Fa.num(_subtitleLine(vpn)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (subs.needsLogin)
                        Pill(
                          label: 'برای اشتراک وارد شو',
                          icon: Icons.login_rounded,
                          color: colors.warning,
                        ),
                      const SizedBox(width: 8),
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
                      padding: const EdgeInsets.only(top: 10),
                      child: _AccessBanner(
                        title: account.enable
                            ? 'اشتراک شما اجازه اتصال ندارد'
                            : 'حساب شما مسدود شده است',
                        message: account.accessReason,
                      ),
                    ),
                  if (OccasionService.instance.active != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OccasionBanner(
                        occasion: OccasionService.instance.active,
                        enabled: settings.settings.occasionEffects,
                      ),
                    ),

                  // ── گنبد و دکمه اتصال در وسط ──────────────────────────
                  Column(
                    children: <Widget>[
                      Semantics(
                        button: true,
                        label: status.busy
                            ? 'لغو اتصال'
                            : (status.active ? 'قطع اتصال' : 'اتصال'),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          // زدن گنبد وسط در حال ساخت تونل هم اتصال را لغو
                          // می کند؛ نه فقط دکمه پایین.
                          onTap: status == VpnStatus.disconnecting
                              ? null
                              : (status.busy
                                  ? () => _cancelConnection(vpn, toasts)
                                  : () => _toggleConnection(vpn, toasts)),
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
                      const SizedBox(height: 8),
                      Text(
                        Fa.num(status.label),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: tone,
                            ),
                      ),
                      const SizedBox(height: 2),
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
                      const SizedBox(height: 14),
                      SizedBox(
                        width: 460,
                        child: status.busy
                            // هنگام ساخت تونل، دکمه به «لغو اتصال» تبدیل می شود؛
                            // تا پیش از این کاربر هیچ راهی برای پشیمان شدن نداشت.
                            ? GradientButton(
                                label: status == VpnStatus.disconnecting
                                    ? 'در حال لغو...'
                                    : 'لغو اتصال',
                                icon: Icons.cancel_rounded,
                                height: 60,
                                tone: colors.warning,
                                loading: status == VpnStatus.disconnecting,
                                onPressed: status == VpnStatus.disconnecting
                                    ? null
                                    : () => _cancelConnection(vpn, toasts),
                              )
                            : GradientButton(
                                label: status.active ? 'قطع اتصال' : 'اتصال',
                                icon: Icons.power_settings_new_rounded,
                                height: 60,
                                tone: status.active
                                    ? colors.danger
                                    : colors.primary,
                                onPressed: () => _toggleConnection(vpn, toasts),
                              ),
                      ),
                      if (!account.canConnect)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            Fa.num('اتصال تا تمدید یا رفع مسدودی اشتراک ممکن نیست.'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colors.danger),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // ── دو منوی کوچک: حالت اتصال و حالت انتخاب سرور ──
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: <Widget>[
                          _PickerChip(
                            label: 'حالت اتصال',
                            value: settings.settings.corePreference.faName,
                            icon: settings.settings.corePreference.icon,
                            enabled: !status.busy,
                            onTap: () => _pickConnectionMode(
                              vpn,
                              settings,
                              toasts,
                            ),
                          ),
                          _PickerChip(
                            label: 'حالت انتخاب سرور',
                            value: settings.settings.selectionMode.faName,
                            icon: settings.settings.selectionMode.icon,
                            enabled: !status.busy,
                            onTap: () => _pickMode(vpn, settings, toasts),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // نوار پایین عمدا حذف شده است: کارت پایین صفحه دیگر
                  // سرور فعال را نشان نمی دهد، چون کاربر نخواست نام سرور
                  // اینجا نمایش داده شود. آمار اتصال در «دستگاه من» و
                  // گزارش ها هست.
                  const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.lock_rounded, size: 20, color: colors.danger),
          const SizedBox(width: 10),
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

/// نشان آی پی با پرچم کشور.
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onRefresh,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (flagCode.isNotEmpty) ...<Widget>[
                FlagView(code: flagCode, width: 30),
                const SizedBox(width: 9),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fa.num(connected ? 'آی پی اتصال' : 'آی پی دستگاه'),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                  Text(
                    Fa.num(ip),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (country.isNotEmpty)
                    Text(
                      Fa.num(country),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: colors.info),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// چیپ کوچک انتخاب: عنوان + مقدار فعلی + فلش منو.
class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon ?? Icons.tune_rounded, size: 18,
                  color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                Fa.num(label),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(width: 6),
              Text(
                Fa.num(value),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 17,
                  color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// منوی کوچک انتخاب حالت اتصال (توضیح هر حالت زیر نامش می آید).
class _ConnectionModeDialog extends StatelessWidget {
  const _ConnectionModeDialog({required this.current});

  final CorePreference current;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 64, bottom: 24, left: 24, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Text(
                  Fa.num('حالت اتصال'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              for (final CorePreference pref in CorePreference.values)
                _MenuTile(
                  selected: pref == current,
                  enabled: pref.available,
                  title: pref.faName,
                  subtitle: pref.description,
                  leading: Icon(
                    pref.icon,
                    size: 20,
                    color: pref == current ? colors.primary : colors.textSecondary,
                  ),
                  onTap: () => Navigator.of(context).pop(pref),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// منوی کوچک حالت انتخاب سرور (مثل منوی کلاسیک: تیک کنار گزینه فعال).
class _ModeDialog extends StatelessWidget {
  const _ModeDialog({required this.current});

  final SelectionMode current;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 64, bottom: 24, left: 24, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Text(
                  Fa.num('حالت انتخاب سرور'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              for (final SelectionMode mode in SelectionMode.values)
                _MenuTile(
                  selected: mode == current,
                  title: mode.faName,
                  subtitle: mode.description,
                  leading: Icon(
                    mode.icon,
                    size: 20,
                    color: context.colors.textSecondary,
                  ),
                  onTap: () => Navigator.of(context).pop(mode),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.selected,
    required this.title,
    required this.onTap,
    required this.leading,
    this.subtitle = '',
    this.enabled = true,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final Widget leading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? colors.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(width: 28, child: Center(child: leading)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fa.num(title),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selected ? colors.primary : null,
                          ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        Fa.num(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 18, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
