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

/// تنظیمات سریع اتصال، به صورت مستقیم و بدون باز کردن زیرمنو نمایش داده می شوند:
/// حالت سرویس، اشتراک گذاری شبکه محلی، و انتخاب وارپ یا سایفون.
class QuickConnectionPanel extends StatelessWidget {
  const QuickConnectionPanel({
    super.key,
    required this.enabled,
    this.onOpenChainSettings,
  });

  final bool enabled;
  final VoidCallback? onOpenChainSettings;

  Future<void> _selectServiceMode(
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    InboundServiceMode mode,
  ) async {
    if (settings.settings.serviceMode == mode) return;
    if (mode == InboundServiceMode.vpn && !settings.elevated) {
      toasts.info(
        'برای حالت تونل کامل برنامه را با دسترسی مدیر اجرا کنید',
        'حالت سرویس',
      );
    }
    await settings.setServiceMode(mode);
    if (vpn.status.active) vpn.scheduleLiveReload();
  }

  Future<void> _toggleLanSharing(
    SettingsController settings,
    VpnController vpn,
    bool value,
  ) async {
    await settings.setAllowConnectionFromLan(value);
    if (vpn.status.active) vpn.scheduleLiveReload();
  }

  Future<void> _applyChain(
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    ChainSettings next,
  ) async {
    try {
      await settings.setChain(next);
      if (vpn.status.active) vpn.scheduleLiveReload();
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
      child: GlassCard(
        padding: EdgeInsets.zero,
        radius: AppMetrics.radiusXl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.space4,
                AppMetrics.space3,
                AppMetrics.space2,
                AppMetrics.space3,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SectionHeader(
                      icon: Icons.tune_rounded,
                      title: 'تنظیمات اتصال',
                      subtitle: 'گزینه ها مستقیم و یک جا در همین صفحه هستند',
                    ),
                  ),
                  if (onOpenChainSettings != null)
                    IconButton(
                      key: const ValueKey<String>('quick-chain-settings'),
                      tooltip: Fa.num('تنظیمات پیشرفته زنجیره'),
                      onPressed:
                          enabled ? onOpenChainSettings : null,
                      icon: const Icon(Icons.settings_suggest_rounded),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.space4,
                AppMetrics.space3,
                AppMetrics.space4,
                AppMetrics.space3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppMetrics.space2),
                  _ServiceModeSegmentedBar(
                    selected: cfg.serviceMode,
                    enabled: enabled,
                    onSelected: (InboundServiceMode mode) =>
                        _selectServiceMode(settings, vpn, toasts, mode),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            _LanSharingRow(
              shared: cfg.allowConnectionFromLan,
              port: cfg.lanSharingPort,
              enabled: enabled,
              onOpenQr: () => LanSharingDialog.show(context),
              onToggle: (bool value) =>
                  _toggleLanSharing(settings, vpn, value),
            ),
            Divider(height: 1, color: colors.border),
            _ChainQuickRow(
              rowKey: const ValueKey<String>('quick-extra-security'),
              title: 'امنیت بیشتر',
              subtitle: 'پس از سرور اصلی از وارپ یا سایفون عبور کنید',
              icon: Icons.verified_user_rounded,
              activeColor: colors.success,
              active: extraOn,
              transport: chain.transport,
              enabled: enabled,
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
            ),
            Divider(height: 1, color: colors.border),
            _ChainQuickRow(
              rowKey: const ValueKey<String>('quick-proxy-unblocker'),
              title: 'رفع فیلتر پروکسی',
              subtitle: 'پیش از سرور اصلی از وارپ یا سایفون عبور کنید',
              icon: Icons.account_tree_rounded,
              activeColor: colors.warning,
              active: unblockerOn,
              transport: chain.transport,
              enabled: enabled,
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

class _ChainQuickRow extends StatelessWidget {
  const _ChainQuickRow({
    required this.rowKey,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.activeColor,
    required this.active,
    required this.transport,
    required this.enabled,
    required this.onTurnOff,
    required this.onPickTransport,
  });

  final Key rowKey;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color activeColor;
  final bool active;
  final ChainTransport transport;
  final bool enabled;
  final VoidCallback onTurnOff;
  final ValueChanged<ChainTransport> onPickTransport;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool isPsiphon = transport == ChainTransport.psiphon;
    final Color tone = active ? activeColor : colors.textSecondary;
    return Container(
      key: rowKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space4,
        vertical: AppMetrics.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: icon,
                color: tone,
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
                      Fa.num(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      Fa.num(subtitle),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppMetrics.space2),
              Pill(
                label: active ? transport.quickLabel : 'خاموش',
                icon: active
                    ? transport.quickIcon
                    : Icons.power_settings_new_rounded,
                color: tone,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space2),
          Wrap(
            spacing: AppMetrics.space2,
            runSpacing: AppMetrics.space1,
            children: <Widget>[
              _chainChoice(
                context,
                label: 'خاموش',
                icon: Icons.power_settings_new_rounded,
                selected: !active,
                enabled: enabled && active,
                onPressed: onTurnOff,
              ),
              _chainChoice(
                context,
                label: 'وارپ',
                icon: Icons.cloud_done_rounded,
                selected: active && !isPsiphon,
                enabled: enabled,
                onPressed: () => onPickTransport(ChainTransport.automatic),
              ),
              _chainChoice(
                context,
                label: 'سایفون',
                icon: Icons.language_rounded,
                selected: active && isPsiphon,
                enabled: enabled,
                onPressed: () => onPickTransport(ChainTransport.psiphon),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chainChoice(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final UmbrellaColors colors = context.colors;
    return ChoiceChip(
      label: Text(Fa.num(label)),
      avatar: Icon(icon, size: AppMetrics.iconXs),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected ? colors.primary : colors.textSecondary,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
      selectedColor: colors.primary.withValues(alpha: 0.13),
      side: BorderSide(
        color: selected ? colors.primary.withValues(alpha: 0.4) : colors.border,
      ),
      onSelected: enabled ? (_) => onPressed() : null,
    );
  }
}
