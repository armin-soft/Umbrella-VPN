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

  /// انتخاب هسته از منوی کوچک؛ سپس اتصال خودکار به پایدارترین سرور.
  Future<void> _pickCore(
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    final CorePreference? picked = await showDialog<CorePreference>(
      context: context,
      builder: (BuildContext context) => _CoreDialog(
        current: settings.settings.corePreference,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    await settings.setCorePreference(picked);
    if (!picked.available) {
      toasts.info(
        'هسته ${picked.faName} در این نسخه فعال نیست',
        'هسته این گزینه همراه نسخه عرضه نشده است.',
      );
      return;
    }
    toasts.info('هسته اتصال: ${picked.faName}');
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
    final String shownIp = vpn.exitIp.isNotEmpty
        ? vpn.exitIp
        : (vpn.realIp.isNotEmpty ? vpn.realIp : '—');
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
                              Fa.num(Fa.longDate(DateTime.now())),
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
                        child: GradientButton(
                          label: status.active && !status.busy
                              ? 'قطع اتصال'
                              : 'اتصال',
                          icon: Icons.power_settings_new_rounded,
                          height: 60,
                          tone: status.active && !status.busy
                              ? colors.danger
                              : colors.primary,
                          loading: status.busy,
                          onPressed: status.busy
                              ? null
                              : () => _toggleConnection(vpn, toasts),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── دو منوی کوچک: هسته و حالت انتخاب ────────────
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: <Widget>[
                          _PickerChip(
                            label: 'هسته اتصال',
                            value: settings.settings.corePreference.faName,
                            logo: settings.settings.corePreference.logoAsset,
                            enabled: !status.busy,
                            onTap: () => _pickCore(vpn, settings, toasts),
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

                  // ── نوار پایین: سرور فعال و آمار ──────────────────────
                  Column(
                    children: <Widget>[
                      _ActiveServerBar(vpn: vpn),
                      if (vpn.stats.available) ...<Widget>[
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _MiniStat(
                                label: 'دانلود',
                                value: Fa.speed(vpn.stats.downSpeed),
                                color: colors.success,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniStat(
                                label: 'آپلود',
                                value: Fa.speed(vpn.stats.upSpeed),
                                color: colors.info,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniStat(
                                label: 'دریافتی',
                                value: Fa.bytes(vpn.stats.rx),
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniStat(
                                label: 'مدت اتصال',
                                value: Fa.duration(vpn.stats.connectedFor),
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    this.logo,
    this.icon,
  });

  final String label;
  final String value;
  final String? logo;
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
              if (logo != null)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Image.asset(
                    logo!,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (BuildContext context, Object error, StackTrace? stack) =>
                            Icon(
                      Icons.memory_rounded,
                      size: 17,
                      color: colors.textSecondary,
                    ),
                  ),
                )
              else
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

/// نوار باریک سرور فعال؛ برای سرور متصل هیچ پینگی نمایش داده نمی شود.
class _ActiveServerBar extends StatelessWidget {
  const _ActiveServerBar({required this.vpn});

  final VpnController vpn;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final VpnNode? node = vpn.activeNode;
    final bool active = vpn.status.active;
    final String flagCode = node?.flagCode ?? '';
    if (node == null) {
      return Text(
        Fa.num('سروری انتخاب نشده است؛ با زدن دکمه اتصال، بهترین سرور خودکار '
            'انتخاب می شود.'),
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: colors.textSecondary),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.backgroundAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          if (flagCode.isNotEmpty) ...<Widget>[
            FlagView(code: flagCode, width: 26),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Text(
              Fa.num(node.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Pill(
            label: Fa.num(node.protocol.label),
            icon: Icons.lan_rounded,
            color: colors.info,
            dense: true,
          ),
          if (active) ...<Widget>[
            const SizedBox(width: 6),
            Pill(
              label: vpn.tunnelVerified ? 'تونل تایید شد' : 'متصل',
              icon: vpn.tunnelVerified
                  ? Icons.verified_user_rounded
                  : Icons.shield_rounded,
              color: colors.success,
              dense: true,
            ),
          ] else if (vpn.measuring) ...<Widget>[
            const SizedBox(width: 6),
            Pill(
              label: 'در حال سنجش',
              icon: Icons.speed_rounded,
              color: colors.warning,
              dense: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.backgroundAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            Fa.num(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
          ),
          Text(
            Fa.num(label),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// منوی کوچک انتخاب هسته با لوگوی رسمی هر هسته.
class _CoreDialog extends StatelessWidget {
  const _CoreDialog({required this.current});

  final CorePreference current;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Dialog(
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
                  Fa.num('هسته اتصال'),
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
                  leading: SizedBox(
                    width: 26,
                    height: 26,
                    child: Image.asset(
                      pref.logoAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (BuildContext context, Object error,
                              StackTrace? stack) =>
                          Icon(
                        Icons.memory_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ),
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
