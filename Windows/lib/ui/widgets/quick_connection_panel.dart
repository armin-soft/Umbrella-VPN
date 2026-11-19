import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import 'common.dart';
import 'lan_sharing_dialog.dart';

/// منوی کشویی تنظیمات سریع در صفحه اتصال:
/// به صورت پیش فرض بسته است و هرگز خودکار باز نمی شود؛ فقط با کلیک کاربر باز و
/// بسته می شود و شامل چهار بخش استاندارد با آیکون های دقیق است:
/// ۱. انتخاب سه گانه حالت سرویس (`پروکسی` | `پروکسی سیستم` | `تونل کامل`)
/// ۲. `اشتراک گذاری اتصال` در شبکه محلی به همراه رمزینه تصویری
/// ۳. `امنیت بیشتر` با منوی استاندارد انتخاب `وارپ` یا `سایفون`
/// ۴. `رفع فیلتر پروکسی` با منوی استاندارد انتخاب `وارپ` یا `سایفون`
class QuickConnectionPanel extends StatefulWidget {
  const QuickConnectionPanel({
    super.key,
    required this.enabled,
    this.onOpenChainSettings,
  });

  final bool enabled;
  final VoidCallback? onOpenChainSettings;

  @override
  State<QuickConnectionPanel> createState() => _QuickConnectionPanelState();
}

class _QuickConnectionPanelState extends State<QuickConnectionPanel> {
  /// همیشه به صورت بسته آغاز می شود و فقط با کلیک مستقیم کاربر تغییر می کند.
  bool _expanded = false;
  bool _headerHovered = false;

  Future<void> _selectServiceMode(
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    InboundServiceMode mode,
  ) async {
    if (settings.settings.serviceMode == mode) {
      return;
    }
    if (mode == InboundServiceMode.vpn && !settings.elevated) {
      toasts.info(
        'برای حالت تونل کامل برنامه را با دسترسی مدیر اجرا کنید',
        'حالت سرویس',
      );
    }
    await settings.setServiceMode(mode);
    if (vpn.status.active) {
      vpn.scheduleLiveReload();
    }
  }

  Future<void> _toggleLanSharing(
    SettingsController settings,
    VpnController vpn,
    bool value,
  ) async {
    await settings.setAllowConnectionFromLan(value);
    if (vpn.status.active) {
      vpn.scheduleLiveReload();
    }
  }

  Future<void> _applyChain(
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    ChainSettings next,
  ) async {
    try {
      await settings.setChain(next);
      if (vpn.status.active) {
        vpn.scheduleLiveReload();
      }
    } on FormatException catch (error) {
      toasts.error(error.message, 'زنجیره اتصال');
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final SettingsController settings = context.watch<SettingsController>();
    final VpnController vpn = context.read<VpnController>();
    final ToastController toasts = context.read<ToastController>();
    final AppSettings cfg = settings.settings;
    final ChainSettings chain = cfg.chain;
    final bool extraOn = chain.position == ChainPosition.extraSecurity;
    final bool unblockerOn = chain.position == ChainPosition.unblocker;
    final bool chainActive = extraOn || unblockerOn;
    final Color chainColor =
        extraOn ? const Color(0xFF34C759) : const Color(0xFFFF8A3D);

    final Color borderColor = _expanded
        ? colors.primary.withValues(alpha: 0.45)
        : (_headerHovered
            ? colors.textSecondary.withValues(alpha: 0.45)
            : colors.border);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppMetrics.controlMaxWidth),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
          border: Border.all(color: borderColor),
          boxShadow: _expanded
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: AppMetrics.space4,
                    offset: const Offset(0, AppMetrics.space2),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ── نوار سربرگ منوی کشویی (بسته در حالت پیش فرض) ──────────────
            MouseRegion(
              onEnter: (_) => setState(() => _headerHovered = true),
              onExit: (_) => setState(() => _headerHovered = false),
              child: Material(
                color: _expanded
                    ? colors.surfaceHigh.withValues(alpha: 0.5)
                    : Colors.transparent,
                child: InkWell(
                  key: const ValueKey<String>('quick-panel-toggle'),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppMetrics.space4,
                      vertical: AppMetrics.space3,
                    ),
                    child: Row(
                      children: <Widget>[
                        IconSquare(
                          icon: Icons.tune_rounded,
                          color: colors.primary,
                          size: AppMetrics.iconBoxSm,
                          radius: AppMetrics.radiusSm,
                        ),
                        const SizedBox(width: AppMetrics.space3),
                        Expanded(
                          child: Text(
                            Fa.num('گزینه های اتصال'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(width: AppMetrics.space2),
                        // نشان فشرده حالت سرویس فعلی با آیکون دقیق
                        _HeaderStatusBadge(
                          icon: cfg.serviceMode.icon,
                          label: cfg.serviceMode.shortLabel,
                          color: colors.primary,
                          tooltip: 'حالت سرویس: ${cfg.serviceMode.shortLabel}',
                        ),
                        if (cfg.allowConnectionFromLan) ...<Widget>[
                          const SizedBox(width: AppMetrics.space1),
                          _HeaderIconDot(
                            icon: Icons.wifi_tethering_rounded,
                            color: colors.info,
                            tooltip: 'اشتراک گذاری اتصال فعال است',
                          ),
                        ],
                        if (chainActive) ...<Widget>[
                          const SizedBox(width: AppMetrics.space1),
                          _HeaderIconDot(
                            icon: chain.position.icon,
                            color: chainColor,
                            tooltip:
                                '${chain.position.label}: ${chain.transport.quickLabel}',
                          ),
                        ],
                        const SizedBox(width: AppMetrics.space2),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: AppMetrics.iconLg,
                            color: _expanded
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── بدنه منو (فقط پس از کلیک کاربر باز می شود) ─────────────────
            ClipRect(
              child: AnimatedAlign(
                alignment: Alignment.topCenter,
                heightFactor: _expanded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: ExcludeFocus(
                  excluding: !_expanded,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Divider(
                        height: AppMetrics.space1,
                        thickness: 1,
                        color: colors.border,
                      ),

                      // ── ۱. کلید سه گانه حالت سرویس با آیکون هر حالت ──────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppMetrics.space4,
                          AppMetrics.space3,
                          AppMetrics.space4,
                          AppMetrics.space3,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Icon(
                                  Icons.settings_input_component_rounded,
                                  size: AppMetrics.iconXs,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(width: AppMetrics.space2),
                                Text(
                                  Fa.num('حالت سرویس'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: colors.textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppMetrics.space2),
                            _ServiceModeSegmentedBar(
                              selected: cfg.serviceMode,
                              enabled: widget.enabled,
                              onSelected: (InboundServiceMode mode) =>
                                  _selectServiceMode(
                                settings,
                                vpn,
                                toasts,
                                mode,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: AppMetrics.space1,
                        thickness: 1,
                        color: colors.border,
                      ),

                      // ── ۲. اشتراک گذاری اتصال + رمزینه تصویری + کلید ──────
                      _LanSharingRow(
                        shared: cfg.allowConnectionFromLan,
                        port: cfg.lanSharingPort,
                        enabled: widget.enabled,
                        onOpenQr: () => LanSharingDialog.show(context),
                        onToggle: (bool value) =>
                            _toggleLanSharing(settings, vpn, value),
                      ),
                      Divider(
                        height: AppMetrics.space1,
                        thickness: 1,
                        color: colors.border,
                      ),

                      // ── ۳. امنیت بیشتر (عبور از وارپ یا سایفون پس از سرور)
                      _ChainQuickRow(
                        rowKey: const ValueKey<String>('quick-extra-security'),
                        title: 'امنیت بیشتر',
                        subtitle: 'وقتی به پروکسی اعتماد نداری',
                        icon: Icons.verified_user_rounded,
                        activeColor: const Color(0xFF34C759),
                        active: extraOn,
                        transport: chain.transport,
                        enabled: widget.enabled,
                        tips: <String>[
                          'نشانی آی پی شما را ${chain.transport.quickLabel} تعیین می کند',
                          'ارائه دهنده سرور نشانی نهایی را نمی بیند',
                          'مناسب افزایش حریم خصوصی در شبکه های عمومی',
                          'ممکن است سرعت کمی کاهش یابد',
                        ],
                        onTurnOff: () => _applyChain(
                          settings,
                          vpn,
                          toasts,
                          chain.deactivate(),
                        ),
                        onPickTransport: (ChainTransport picked) => _applyChain(
                          settings,
                          vpn,
                          toasts,
                          chain.activateExtraSecurity(picked),
                        ),
                        onConfigure: widget.onOpenChainSettings,
                      ),
                      Divider(
                        height: AppMetrics.space1,
                        thickness: 1,
                        color: colors.border,
                      ),

                      // ── ۴. رفع فیلتر پروکسی (عبور پیش از سرور اصلی) ───────
                      _ChainQuickRow(
                        rowKey:
                            const ValueKey<String>('quick-proxy-unblocker'),
                        title: 'رفع فیلتر پروکسی',
                        subtitle: 'عبور از فیلترینگ پروکسی',
                        icon: Icons.account_tree_rounded,
                        activeColor: const Color(0xFFFF8A3D),
                        active: unblockerOn,
                        transport: chain.transport,
                        enabled: widget.enabled,
                        tips: <String>[
                          'کمک به اتصال سرور در شبکه های محدودشده',
                          'عبور از ${chain.transport.quickLabel} پیش از سرور اصلی',
                          'جست وجوی خودکار نقطه اتصال تمیز فعال است',
                          'سرعت اتصال ممکن است کمی کاهش یابد',
                        ],
                        onTurnOff: () => _applyChain(
                          settings,
                          vpn,
                          toasts,
                          chain.deactivate(),
                        ),
                        onPickTransport: (ChainTransport picked) => _applyChain(
                          settings,
                          vpn,
                          toasts,
                          chain.activateUnblocker(picked),
                        ),
                        onConfigure: widget.onOpenChainSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderStatusBadge extends StatelessWidget {
  const _HeaderStatusBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: Fa.num(tooltip),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space2,
          vertical: AppMetrics.space1,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: AppMetrics.iconXs, color: color),
            const SizedBox(width: AppMetrics.space1),
            Text(
              Fa.num(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconDot extends StatelessWidget {
  const _HeaderIconDot({
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: Fa.num(tooltip),
      child: Container(
        width: AppMetrics.space6,
        height: AppMetrics.space6,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: AppMetrics.iconXs, color: color),
      ),
    );
  }
}

class _ServiceModeSegmentedBar extends StatelessWidget {
  const _ServiceModeSegmentedBar({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final InboundServiceMode selected;
  final bool enabled;
  final ValueChanged<InboundServiceMode> onSelected;

  static const List<InboundServiceMode> _modes = <InboundServiceMode>[
    InboundServiceMode.proxy,
    InboundServiceMode.systemProxy,
    InboundServiceMode.vpn,
  ];

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      height: AppMetrics.controlHeightSmall,
      padding: const EdgeInsets.all(AppMetrics.space1),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < _modes.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: AppMetrics.space1),
            Expanded(
              child: _segment(context, colors, _modes[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    UmbrellaColors colors,
    InboundServiceMode mode,
  ) {
    final bool isSelected = selected == mode;
    final Color fg = isSelected ? colors.primary : colors.textSecondary;
    return Tooltip(
      message: Fa.num(mode.description),
      child: Material(
        color: isSelected
            ? colors.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          onTap: enabled ? () => onSelected(mode) : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: AppMetrics.space2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
              border: isSelected
                  ? Border.all(color: colors.primary.withValues(alpha: 0.38))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(mode.icon, size: AppMetrics.iconXs, color: fg),
                const SizedBox(width: AppMetrics.space1),
                Flexible(
                  child: Text(
                    Fa.num(mode.shortLabel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isSelected
                              ? colors.primary
                              : colors.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
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

class _LanSharingRow extends StatelessWidget {
  const _LanSharingRow({
    required this.shared,
    required this.port,
    required this.enabled,
    required this.onOpenQr,
    required this.onToggle,
  });

  final bool shared;
  final int port;
  final bool enabled;
  final VoidCallback onOpenQr;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return InkWell(
      onTap: onOpenQr,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space4,
          vertical: AppMetrics.space3,
        ),
        child: Row(
          children: <Widget>[
            IconSquare(
              icon: Icons.wifi_tethering_rounded,
              color: shared ? colors.primary : colors.textSecondary,
              size: AppMetrics.iconBoxSm,
              radius: AppMetrics.radiusSm,
            ),
            const SizedBox(width: AppMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fa.num('اشتراک گذاری اتصال'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppMetrics.space1),
                  Text(
                    Fa.num(
                      shared
                          ? 'فعال روی پورت $port در شبکه محلی'
                          : 'اشتراک اینترنت با دستگاه های هم شبکه',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: shared
                              ? colors.primary
                              : colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppMetrics.space2),
            Tooltip(
              message: Fa.num('رمزینه تصویری اشتراک گذاری'),
              child: Material(
                color: shared
                    ? colors.primary.withValues(alpha: 0.16)
                    : colors.surfaceHigh.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                child: InkWell(
                  key: const ValueKey<String>('quick-lan-qr-button'),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  onTap: onOpenQr,
                  child: Container(
                    width: AppMetrics.iconBoxSm,
                    height: AppMetrics.iconBoxSm,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                      border: Border.all(
                        color: shared
                            ? colors.primary.withValues(alpha: 0.35)
                            : colors.border,
                      ),
                    ),
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: AppMetrics.iconSm,
                      color: shared ? colors.primary : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: AppMetrics.space6,
              child: VerticalDivider(
                width: AppMetrics.space4,
                color: colors.border,
              ),
            ),
            Switch.adaptive(
              key: const ValueKey<String>('quick-lan-switch'),
              value: shared,
              onChanged: enabled ? onToggle : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainQuickRow extends StatefulWidget {
  const _ChainQuickRow({
    required this.rowKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.activeColor,
    required this.active,
    required this.transport,
    required this.enabled,
    required this.tips,
    required this.onTurnOff,
    required this.onPickTransport,
    this.onConfigure,
  });

  final Key rowKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color activeColor;
  final bool active;
  final ChainTransport transport;
  final bool enabled;
  final List<String> tips;
  final VoidCallback onTurnOff;
  final ValueChanged<ChainTransport> onPickTransport;
  final VoidCallback? onConfigure;

  @override
  State<_ChainQuickRow> createState() => _ChainQuickRowState();
}

class _ChainQuickRowState extends State<_ChainQuickRow> {
  final MenuController _menuController = MenuController();
  Timer? _tipTimer;
  int _tipIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _ChainQuickRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.transport != widget.transport) {
      _tipIndex = 0;
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _tipTimer?.cancel();
    if (!widget.active || widget.tips.isEmpty) {
      return;
    }
    _tipTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() => _tipIndex = (_tipIndex + 1) % widget.tips.length);
      }
    });
  }

  void _toggleMenu() {
    if (!widget.enabled) {
      return;
    }
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String activeSubtitle = widget.active && widget.tips.isNotEmpty
        ? widget.tips[_tipIndex % widget.tips.length]
        : widget.subtitle;
    final bool isPsiphon = widget.transport == ChainTransport.psiphon;
    final String statusLabel =
        widget.active ? widget.transport.quickLabel : 'خاموش';
    final IconData statusIcon = widget.active
        ? widget.transport.quickIcon
        : Icons.power_settings_new_rounded;

    return InkWell(
      key: widget.rowKey,
      onTap: widget.enabled ? _toggleMenu : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space4,
          vertical: AppMetrics.space3,
        ),
        child: Row(
          children: <Widget>[
            IconSquare(
              icon: widget.icon,
              color: widget.active ? widget.activeColor : colors.textSecondary,
              size: AppMetrics.iconBoxSm,
              radius: AppMetrics.radiusSm,
            ),
            const SizedBox(width: AppMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fa.num(widget.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppMetrics.space1),
                  Text(
                    Fa.num(activeSubtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: widget.active
                              ? widget.activeColor
                              : colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppMetrics.space2),
            MenuAnchor(
              controller: _menuController,
              alignmentOffset: const Offset(0, AppMetrics.space1),
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll<Color>(colors.surface),
                surfaceTintColor:
                    const WidgetStatePropertyAll<Color>(Colors.transparent),
                shadowColor: WidgetStatePropertyAll<Color>(colors.shadow),
                elevation: const WidgetStatePropertyAll<double>(14),
                minimumSize: const WidgetStatePropertyAll<Size>(
                  Size(AppMetrics.buttonMaxWidth, 0),
                ),
                padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                  EdgeInsets.all(AppMetrics.space2),
                ),
                shape: WidgetStatePropertyAll<OutlinedBorder>(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
                    side: BorderSide(color: colors.border),
                  ),
                ),
              ),
              menuChildren: <Widget>[
                _AnchoredChainOption(
                  icon: Icons.power_settings_new_rounded,
                  iconColor: colors.textSecondary,
                  label: 'غیرفعال',
                  subtitle: 'بدون واسط اضافی',
                  selected: !widget.active,
                  onTap: () {
                    _menuController.close();
                    widget.onTurnOff();
                  },
                ),
                const SizedBox(height: AppMetrics.space1),
                _AnchoredChainOption(
                  icon: Icons.cloud_done_rounded,
                  iconColor: const Color(0xFFF6821F),
                  label: 'وارپ',
                  subtitle: 'تونل امن کلادفلر',
                  selected: widget.active && !isPsiphon,
                  onTap: () {
                    _menuController.close();
                    widget.onPickTransport(ChainTransport.automatic);
                  },
                ),
                const SizedBox(height: AppMetrics.space1),
                _AnchoredChainOption(
                  icon: Icons.language_rounded,
                  iconColor: const Color(0xFFE53935),
                  label: 'سایفون',
                  subtitle: 'شبکه ضد فیلتر سایفون',
                  selected: widget.active && isPsiphon,
                  onTap: () {
                    _menuController.close();
                    widget.onPickTransport(ChainTransport.psiphon);
                  },
                ),
                if (widget.onConfigure != null) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppMetrics.space1,
                    ),
                    child: Divider(
                      height: AppMetrics.space1,
                      color: colors.border,
                    ),
                  ),
                  _AnchoredChainOption(
                    icon: Icons.tune_rounded,
                    iconColor: colors.primary,
                    label: 'پیکربندی زنجیره',
                    subtitle: 'تنظیمات پیشرفته تونل و نویز',
                    selected: false,
                    trailingIcon: Icons.chevron_left_rounded,
                    onTap: () {
                      _menuController.close();
                      widget.onConfigure?.call();
                    },
                  ),
                ],
              ],
              builder: (
                BuildContext context,
                MenuController controller,
                Widget? child,
              ) {
                final bool open = controller.isOpen;
                final Color fg = widget.active
                    ? widget.activeColor
                    : (open ? colors.primary : colors.textSecondary);
                return Material(
                  color: widget.active
                      ? widget.activeColor.withValues(alpha: 0.14)
                      : colors.surfaceHigh.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                    onTap: widget.enabled ? _toggleMenu : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppMetrics.space3,
                        vertical: AppMetrics.space2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppMetrics.radiusMd),
                        border: Border.all(
                          color: open
                              ? colors.primary
                              : (widget.active
                                  ? widget.activeColor.withValues(alpha: 0.4)
                                  : colors.border),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(statusIcon, size: AppMetrics.iconXs, color: fg),
                          const SizedBox(width: AppMetrics.space1),
                          Text(
                            Fa.num(statusLabel),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(width: AppMetrics.space1),
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: AppMetrics.iconSm,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AnchoredChainOption extends StatelessWidget {
  const _AnchoredChainOption({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailingIcon,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return SizedBox(
      width: AppMetrics.buttonMaxWidth - (AppMetrics.space2 * 2),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.space3,
              vertical: AppMetrics.space2,
            ),
            child: Row(
              children: <Widget>[
                IconSquare(
                  icon: icon,
                  color: iconColor,
                  size: AppMetrics.iconBoxSm,
                  radius: AppMetrics.radiusSm,
                ),
                const SizedBox(width: AppMetrics.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        Fa.num(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w700,
                            ),
                      ),
                      Text(
                        Fa.num(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.primary,
                  )
                else if (trailingIcon != null)
                  Icon(
                    trailingIcon,
                    size: AppMetrics.iconSm,
                    color: colors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
