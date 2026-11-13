import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../state/subscription_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';
import '../widgets/flag_view.dart';

/// صفحه اصلی اتصال: آی پی و پرچم، دکمه بزرگ اتصال، انتخاب هسته، حالت انتخاب
/// سرور و آمار زنده. همه چیز در همین صفحه است؛ منوی جدا برای سرورها وجود
/// ندارد.
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
      if (subs.totalNodes == 0 && !subs.loadingAll) {
        await subs.fetchAll();
      }
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

  /// انتخاب هسته و اتصال خودکار به پایدارترین سرور همان هسته.
  Future<void> _selectCore(
    CorePreference pref,
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    if (!pref.available) {
      toasts.info(
        'هسته ${pref.faName} در این نسخه فعال نیست',
        'این هسته به همراه نسخه عرضه نشده است.',
      );
      return;
    }
    await settings.setCorePreference(pref);
    toasts.info('هسته اتصال: ${pref.faName}');
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

  /// تغییر حالت انتخاب سرور. حالت واقعا روی انتخاب اثر می گذارد و اگر کاربر
  /// متصل است، با همان حالت دوباره وصل می شود تا اثرش را ببیند.
  Future<void> _applyMode(
    SelectionMode mode,
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    await settings.setSelectionMode(mode);
    toasts.info('حالت انتخاب سرور: ${mode.faName}');
    if (vpn.status.busy || !vpn.status.active) {
      return;
    }
    if (vpn.status.active) {
      await vpn.disconnect();
    }
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      toasts.success(
        'با حالت ${mode.faName} دوباره وصل شد',
        vpn.activeNode?.name ?? '',
      );
    } else {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  Future<void> _openServerPicker(
    VpnController vpn,
    ToastController toasts,
  ) async {
    final VpnNode? picked = await showDialog<VpnNode>(
      context: context,
      builder: (BuildContext context) => _ServerPickerDialog(vpn: vpn),
    );
    if (picked == null || !mounted) {
      return;
    }
    // انتخاب دستی، حالت انتخاب سرور را هم روی «دستی» می گذارد تا اتصال بعدی
    // دقیقا همین سرور را بردارد.
    final SettingsController settings = context.read<SettingsController>();
    if (settings.settings.selectionMode != SelectionMode.manual) {
      await settings.setSelectionMode(SelectionMode.manual);
    }
    final ConnectOutcome outcome = await vpn.switchTo(picked);
    if (outcome.ok) {
      toasts.success('متصل شد', picked.name);
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
    final String flagCode = vpn.geo.flagCode.isNotEmpty
        ? vpn.geo.flagCode
        : (vpn.activeNode?.flagCode ?? '');
    final String shownIp = vpn.exitIp.isNotEmpty ? vpn.exitIp : vpn.realIp;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── سرصفحه: سلام، آی پی فعلی و پرچم کشور ────────────────────
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fa.num('سلام ${account.displayName}، خوش آمدید'),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fa.num(Fa.longDate(DateTime.now())),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (shownIp.isNotEmpty)
                GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  radius: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (flagCode.isNotEmpty) FlagView(code: flagCode, width: 38),
                      if (flagCode.isNotEmpty) const SizedBox(width: 10),
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
                            Fa.num(shownIp),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (connected && vpn.geo.countryLabel.isNotEmpty)
                            Text(
                              Fa.num(CountryNames.fa(flagCode).isEmpty
                                  ? vpn.geo.countryLabel
                                  : '${CountryNames.fa(flagCode)} | ${vpn.geo.countryLabel}'),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.info),
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
          const SizedBox(height: 14),
          OccasionBanner(
            occasion: OccasionService.instance.active,
            enabled: settings.settings.occasionEffects,
          ),
          if (OccasionService.instance.active != null)
            const SizedBox(height: 14),
          if (vpn.nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded,
                        color: colors.warning, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Fa.num(
                          subs.needsLogin
                              ? 'برای دریافت اشتراک باید وارد حساب شوی؛ سپس سرورها خودکار خوانده می شوند.'
                              : (subs.personalErrors.isNotEmpty
                                  ? subs.personalErrors.first
                                  : 'اشتراک خوانده نشد؛ دوباره تلاش کن.'),
                        ),
                        maxLines: 3,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: colors.textSecondary),
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

          // ── کارت بزرگ اتصال ────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
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
                          size: 288,
                          active: status.busy,
                        ),
                        if (!status.busy)
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (status.active
                                      ? colors.danger
                                      : colors.primary)
                                  .withValues(alpha: 0.92),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: (status.active
                                          ? colors.danger
                                          : colors.primary)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 22,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.power_settings_new_rounded,
                              size: 40,
                              color: colors.onPrimary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  Fa.num(status.label),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: tone,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  Fa.num(vpn.message),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.6,
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 420,
                  child: GradientButton(
                    label: status.active && !status.busy ? 'قطع اتصال' : 'اتصال',
                    icon: Icons.power_settings_new_rounded,
                    height: 58,
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
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: <Widget>[
                    if (vpn.activeNode != null)
                      // برای سرور متصل هیچ پینگی نشان داده نمی شود؛ فقط نام و
                      // وضعیت، چون عدد پینگ همان تونلی است که در حال کار است.
                      Pill(
                        label: Fa.num(
                          status.active
                              ? '${vpn.activeNode!.name} | متصل'
                              : vpn.activeNode!.name,
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
                        color: colors.success,
                      ),
                    if (vpn.measuring)
                      Pill(
                        label: 'در حال سنجش پینگ',
                        icon: Icons.speed_rounded,
                        color: colors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: vpn.nodes.isEmpty
                          ? null
                          : () => _openServerPicker(vpn, toasts),
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: const Text('انتخاب سرور'),
                    ),
                    const SizedBox(width: 12),
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
          const SizedBox(height: 14),

          // ── انتخاب هسته ────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'هسته اتصال',
                  subtitle: 'با انتخاب هر هسته، خودکار به پایدارترین سرور وصل می شوی',
                  trailing: Pill(
                    label: Fa.num(settings.settings.corePreference.faName),
                    icon: Icons.memory_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    // در پنجره باریک، کارت ها کنار هم می لغزند تا هیچ چیز
                    // فشرده یا بریده نشود.
                    const double gap = 8;
                    final double width =
                        (constraints.maxWidth - gap * 5) / 6;
                    final double cell = width < 88 ? 88 : width;
                    final Widget row = Row(
                      children: <Widget>[
                        for (final CorePreference pref in CorePreference.values)
                          Padding(
                            padding: const EdgeInsets.only(left: gap),
                            child: SizedBox(
                              width: cell,
                              child: _CoreChip(
                                pref: pref,
                                selected:
                                    settings.settings.corePreference == pref,
                                enabled: pref.available,
                                busy: status.busy,
                                onTap: () =>
                                    _selectCore(pref, vpn, settings, toasts),
                              ),
                            ),
                          ),
                      ],
                    );
                    if (cell == 88 && constraints.maxWidth < 88 * 6 + gap * 5) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: row,
                      );
                    }
                    return row;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── حالت انتخاب سرور (فشرده) ───────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  title: 'حالت انتخاب سرور',
                  subtitle: settings.settings.selectionMode.description,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final SelectionMode mode in SelectionMode.values)
                      if (mode != SelectionMode.manual)
                        _ModeChip(
                          label: mode.faName,
                          icon: mode.icon,
                          selected: settings.settings.selectionMode == mode,
                          onTap: () => _applyMode(mode, vpn, settings, toasts),
                        ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
                    label: 'مدت اتصال',
                    value: Fa.duration(vpn.stats.connectedFor),
                    icon: Icons.timer_outlined,
                    accent: colors.textSecondary,
                    compact: true,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// نشان هسته با لوگوی رسمی.
class _CoreChip extends StatelessWidget {
  const _CoreChip({
    required this.pref,
    required this.selected,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final CorePreference pref;
  final bool selected;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color border = selected ? colors.primary : colors.border;
    return Tooltip(
      message: pref.description,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy || !enabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: border,
                width: selected ? 1.6 : 1,
              ),
              color: selected
                  ? colors.primary.withValues(alpha: 0.10)
                  : colors.surface,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: 34,
                  width: 34,
                  child: Image.asset(
                    pref.logoAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.memory_rounded,
                      size: 26,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Fa.num(pref.faName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? colors.primary : colors.textPrimary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: selected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              Fa.num(label),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? colors.primary : colors.textPrimary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// فهرست سرورها در یک پنجره؛ سروری که همین حالا وصل هستیم نمایش داده نمی شود.
class _ServerPickerDialog extends StatefulWidget {
  const _ServerPickerDialog({required this.vpn});

  final VpnController vpn;

  @override
  State<_ServerPickerDialog> createState() => _ServerPickerDialogState();
}

class _ServerPickerDialogState extends State<_ServerPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String connectedId =
        widget.vpn.activeNode?.id ?? (widget.vpn.status.active ? '' : '');
    final List<VpnNode> nodes = widget.vpn.nodes
        .where((VpnNode node) =>
            node.id != connectedId &&
            VpnController.usable(node) &&
            (_query.isEmpty ||
                node.name.toLowerCase().contains(_query.toLowerCase())))
        .toList();
    final List<VpnNode> sorted = <VpnNode>[...nodes]..sort((VpnNode a, VpnNode b) {
        if (a.hasPing != b.hasPing) {
          return a.hasPing ? -1 : 1;
        }
        return a.pingMs.compareTo(b.pingMs);
      });

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconSquare(
                    icon: Icons.dns_rounded,
                    color: colors.info,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Fa.num('انتخاب سرور'),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconAction(
                    icon: Icons.close_rounded,
                    size: 30,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (String value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'جست وجوی سرور یا کشور',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: sorted.isEmpty
                    ? const EmptyState(
                        icon: Icons.dns_outlined,
                        title: 'سروری برای نمایش نیست',
                        message: 'یا همه سرورها فیلتر شده اند یا اشتراک خالی است.',
                      )
                    : ListView.separated(
                        itemCount: sorted.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (BuildContext context, int index) {
                          final VpnNode node = sorted[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(context).pop(node),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: colors.backgroundAlt,
                                border: Border.all(color: colors.border),
                              ),
                              child: Row(
                                children: <Widget>[
                                  if (node.flagCode.isNotEmpty) ...<Widget>[
                                    FlagView(code: node.flagCode, width: 26),
                                    const SizedBox(width: 8),
                                  ],
                                  Pill(
                                    label: node.hasPing
                                        ? Fa.num(node.pingMs)
                                        : '—',
                                    icon: Icons.speed_rounded,
                                    color: node.hasPing
                                        ? (node.pingMs < 150
                                            ? colors.success
                                            : colors.warning)
                                        : colors.textSecondary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      Fa.num(node.name),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    Fa.num(node.protocol.label),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
