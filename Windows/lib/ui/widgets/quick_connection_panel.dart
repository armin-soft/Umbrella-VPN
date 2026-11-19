import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import 'lan_sharing_dialog.dart';

/// پنل تنظیمات سریع در صفحه اتصال:
/// ۱. انتخاب سه گانه حالت سرویس (`پروکسی` | `پروکسی سیستم` | `VPN`)
/// ۲. `اشتراک گذاری اتصال` در شبکه محلی به همراه دکمه کد QR
/// ۳. `امنیت بیشتر` (`وقتی به پروکسی اعتماد نداری`) با انتخاب Psiphon / WARP
/// ۴. `رفع فیلتر پروکسی` (`عبور از فیلترینگ پروکسی`) با انتخاب Psiphon / WARP
class QuickConnectionPanel extends StatelessWidget {
  const QuickConnectionPanel({
    super.key,
    required this.enabled,
    this.onOpenChainSettings,
  });

  final bool enabled;
  final VoidCallback? onOpenChainSettings;

  Future<void> _selectServiceMode(
    BuildContext context,
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
        'برای حالت VPN برنامه را با دسترسی مدیر اجرا کنید',
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
    BuildContext context,
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppMetrics.controlMaxWidth),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppMetrics.radiusXxl),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ── ۱. کلید سه گانه حالت سرویس (پروکسی | پروکسی سیستم | VPN) ──
            Padding(
              padding: const EdgeInsets.all(AppMetrics.space4),
              child: _ServiceModeSegmentedBar(
                selected: cfg.serviceMode,
                enabled: enabled,
                onSelected: (InboundServiceMode mode) => _selectServiceMode(
                  context,
                  settings,
                  vpn,
                  toasts,
                  mode,
                ),
              ),
            ),
            Divider(
              height: AppMetrics.space1,
              thickness: 1,
              color: colors.border,
            ),

            // ── ۲. اشتراک گذاری اتصال + دکمه QR + کلید روشن/خاموش ─────────
            _LanSharingRow(
              shared: cfg.allowConnectionFromLan,
              enabled: enabled,
              onOpenQr: () => LanSharingDialog.show(context),
              onToggle: (bool value) =>
                  _toggleLanSharing(settings, vpn, value),
            ),
            Divider(
              height: AppMetrics.space1,
              thickness: 1,
              color: colors.border,
            ),

            // ── ۳. امنیت بیشتر (عبور خروجی از WARP یا Psiphon پس از سرور) ──
            _ChainQuickRow(
              rowKey: const ValueKey<String>('quick-extra-security'),
              title: 'امنیت بیشتر',
              subtitle: 'وقتی به پروکسی اعتماد نداری',
              icon: Icons.shield_rounded,
              activeColor: const Color(0xFF34C759),
              active: extraOn,
              transport: chain.transport,
              enabled: enabled,
              tips: <String>[
                'IP شما را ${chain.transport.quickLabel} تعیین می کند',
                'ارائه دهنده سرور نشانی نهایی را نمی بیند',
                'مناسب افزایش حریم خصوصی در شبکه های عمومی',
                'ممکن است سرعت کمی کاهش یابد',
              ],
              onTurnOff: () => _applyChain(
                context,
                settings,
                vpn,
                toasts,
                chain.deactivate(),
              ),
              onPickTransport: (ChainTransport picked) => _applyChain(
                context,
                settings,
                vpn,
                toasts,
                chain.activateExtraSecurity(picked),
              ),
              onConfigure: onOpenChainSettings,
            ),
            Divider(
              height: AppMetrics.space1,
              thickness: 1,
              color: colors.border,
            ),

            // ── ۴. رفع فیلتر پروکسی (عبور از WARP یا Psiphon پیش از سرور) ──
            _ChainQuickRow(
              rowKey: const ValueKey<String>('quick-proxy-unblocker'),
              title: 'رفع فیلتر پروکسی',
              subtitle: 'عبور از فیلترینگ پروکسی',
              icon: Icons.account_tree_rounded,
              activeColor: const Color(0xFFFF8A3D),
              active: unblockerOn,
              transport: chain.transport,
              enabled: enabled,
              tips: <String>[
                'کمک به اتصال سرور در شبکه های محدودشده',
                'عبور از ${chain.transport.quickLabel} پیش از سرور اصلی',
                'جست وجوی خودکار نقطه اتصال تمیز فعال است',
                'سرعت اتصال ممکن است کمی کاهش یابد',
              ],
              onTurnOff: () => _applyChain(
                context,
                settings,
                vpn,
                toasts,
                chain.deactivate(),
              ),
              onPickTransport: (ChainTransport picked) => _applyChain(
                context,
                settings,
                vpn,
                toasts,
                chain.activateUnblocker(picked),
              ),
              onConfigure: onOpenChainSettings,
            ),
          ],
        ),
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < _modes.length; i++) ...<Widget>[
            if (i > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colors.border,
              ),
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
    return Material(
      color: isSelected
          ? colors.primary.withValues(alpha: 0.18)
          : Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => onSelected(mode) : null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space2),
            child: Text(
              mode.shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isSelected ? colors.primary : colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
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
    required this.enabled,
    required this.onOpenQr,
    required this.onToggle,
  });

  final bool shared;
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
          vertical: AppMetrics.space2,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'اشتراک گذاری اتصال',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Tooltip(
              message: 'کد QR',
              child: Material(
                color: shared
                    ? colors.primary.withValues(alpha: 0.16)
                    : colors.surfaceHigh.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                child: InkWell(
                  key: const ValueKey<String>('quick-lan-qr-button'),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                  onTap: onOpenQr,
                  child: SizedBox(
                    width: AppMetrics.iconBoxMd,
                    height: AppMetrics.iconBoxMd,
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: AppMetrics.iconMd,
                      color: shared ? colors.primary : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: AppMetrics.space7,
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

enum _ChainMenuChoice { off, psiphon, warp, configure }

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

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String activeSubtitle = widget.active && widget.tips.isNotEmpty
        ? widget.tips[_tipIndex % widget.tips.length]
        : widget.subtitle;
    final bool isPsiphon = widget.transport == ChainTransport.psiphon;
    final String statusLabel =
        widget.active ? widget.transport.quickLabel : 'خاموش';

    return InkWell(
      key: widget.rowKey,
      onTap: !widget.enabled
          ? null
          : () {
              if (widget.active) {
                widget.onTurnOff();
              } else {
                widget.onPickTransport(ChainTransport.automatic);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space4,
          vertical: AppMetrics.space3,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              widget.icon,
              size: AppMetrics.iconLg,
              color: widget.active ? widget.activeColor : colors.textSecondary,
            ),
            const SizedBox(width: AppMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppMetrics.space1),
                  Text(
                    activeSubtitle,
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
            PopupMenuButton<_ChainMenuChoice>(
              enabled: widget.enabled,
              tooltip: widget.title,
              color: colors.surfaceHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                side: BorderSide(color: colors.border),
              ),
              onSelected: (_ChainMenuChoice choice) {
                switch (choice) {
                  case _ChainMenuChoice.off:
                    widget.onTurnOff();
                  case _ChainMenuChoice.psiphon:
                    widget.onPickTransport(ChainTransport.psiphon);
                  case _ChainMenuChoice.warp:
                    widget.onPickTransport(ChainTransport.automatic);
                  case _ChainMenuChoice.configure:
                    widget.onConfigure?.call();
                }
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<_ChainMenuChoice>>[
                PopupMenuItem<_ChainMenuChoice>(
                  value: _ChainMenuChoice.off,
                  child: _menuRow(
                    icon: Icons.block_rounded,
                    iconColor: colors.textSecondary,
                    label: 'غیرفعال',
                    checked: !widget.active,
                    colors: colors,
                  ),
                ),
                PopupMenuItem<_ChainMenuChoice>(
                  value: _ChainMenuChoice.psiphon,
                  child: _menuRow(
                    icon: Icons.local_parking_rounded,
                    iconColor: const Color(0xFFE53935),
                    label: 'Psiphon',
                    checked: widget.active && isPsiphon,
                    colors: colors,
                  ),
                ),
                PopupMenuItem<_ChainMenuChoice>(
                  value: _ChainMenuChoice.warp,
                  child: _menuRow(
                    icon: Icons.cloud_rounded,
                    iconColor: const Color(0xFFF6821F),
                    label: 'WARP',
                    checked: widget.active && !isPsiphon,
                    colors: colors,
                  ),
                ),
                if (widget.onConfigure != null) ...<PopupMenuEntry<_ChainMenuChoice>>[
                  const PopupMenuDivider(),
                  PopupMenuItem<_ChainMenuChoice>(
                    value: _ChainMenuChoice.configure,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'پیکربندی',
                            style: TextStyle(color: colors.textPrimary),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: AppMetrics.iconSm,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.space3,
                  vertical: AppMetrics.space1,
                ),
                decoration: BoxDecoration(
                  color: widget.active
                      ? widget.activeColor.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: widget.active
                                ? widget.activeColor
                                : colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(width: AppMetrics.space1),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: AppMetrics.iconMd,
                      color: widget.active
                          ? widget.activeColor
                          : colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool checked,
    required UmbrellaColors colors,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: AppMetrics.iconSm, color: iconColor),
        const SizedBox(width: AppMetrics.space2),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        if (checked)
          Icon(
            Icons.check_rounded,
            size: AppMetrics.iconSm,
            color: colors.primary,
          ),
      ],
    );
  }
}
