import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import 'common.dart';
import 'content_control.dart';
import 'lan_sharing_dialog.dart';

/// تنظیمات اتصال در یک پنل کوتاه و مستقل؛ الگوی SegmentedButton و ListTile
/// همان ساختار آشنای تنظیمات سریع Hiddify را دنبال می کند.
class QuickConnectionPanel extends StatelessWidget {
  const QuickConnectionPanel({
    super.key,
    required this.enabled,
    this.onClose,
  });

  final bool enabled;
  final VoidCallback? onClose;

  Future<void> _selectServiceMode(
    SettingsController settings,
    VpnController vpn,
    ToastController toasts,
    InboundServiceMode mode,
  ) async {
    if (settings.settings.serviceMode == mode) return;
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

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final SettingsController settings = context.watch<SettingsController>();
    final AuthController? auth = context.watch<AuthController?>();
    final VpnController vpn = context.read<VpnController>();
    final ToastController toasts = context.read<ToastController>();
    final AppSettings cfg = settings.settings;
    final InboundServiceMode uiMode = cfg.serviceMode == InboundServiceMode.proxy
        ? InboundServiceMode.proxy
        : InboundServiceMode.vpn;
    final Color explanationTone = colors.info;
    final String explanation = uiMode.description;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.space4,
              AppMetrics.space2,
              AppMetrics.space2,
              AppMetrics.space3,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SectionHeader(
                    icon: Icons.tune_rounded,
                    title: 'تنظیمات اتصال',
                    subtitle: auth != null
                        ? 'حالت سرویس، اشتراک گذاری شبکه محلی و کنترل محتوا'
                        : 'حالت سرویس و اشتراک گذاری شبکه محلی',
                    trailing: Pill(
                      label: cfg.serviceMode.shortLabel,
                      icon: cfg.serviceMode.icon,
                      color: colors.primary,
                      dense: true,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    key: const ValueKey<String>('quick-settings-close'),
                    tooltip: Fa.num('بستن تنظیمات اتصال'),
                    onPressed: withUiClick(context, onClose),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.space4,
              AppMetrics.space4,
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppMetrics.space2),
                _ServiceModeSegmentedBar(
                  selected: uiMode,
                  enabled: enabled,
                  onSelected: (InboundServiceMode mode) =>
                      _selectServiceMode(settings, vpn, toasts, mode),
                ),
                const SizedBox(height: AppMetrics.space3),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (Widget child, Animation<double> animation) =>
                      SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Container(
                    key: ValueKey<String>(uiMode.name),
                    padding: const EdgeInsets.all(AppMetrics.space3),
                    decoration: BoxDecoration(
                      color: explanationTone.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                      border: Border.all(
                        color: explanationTone.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          uiMode.icon,
                          size: AppMetrics.iconSm,
                          color: explanationTone,
                        ),
                        const SizedBox(width: AppMetrics.space2),
                        Expanded(
                          child: Text(
                            Fa.num(explanation),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  height: 1.5,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (cfg.chain.position != ChainPosition.off &&
              cfg.chain.transport == ChainTransport.psiphon) ...<Widget>[
            Divider(height: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppMetrics.space4),
              child: AnchoredSelectField<String>(
                key: const ValueKey<String>('quick-psiphon-country'),
                label: 'کشور سایفون',
                value: cfg.chain.psiphonRegion,
                enabled: enabled && !vpn.status.busy,
                leadingIcon: Icons.public_rounded,
                options: <SelectOption<String>>[
                  for (final String region in ChainSettings.regions)
                    SelectOption<String>(value: region, label: ChainSettings.regionLabel(region)),
                ],
                onChanged: (String region) async {
                  if (region == settings.settings.chain.psiphonRegion) return;
                  try {
                    await settings.setChain(settings.settings.chain.copyWith(psiphonRegion: region));
                    if (vpn.status.active) vpn.scheduleLiveReload();
                  } catch (_) {
                    toasts.error('تغییر کشور سایفون ناموفق بود');
                  }
                },
              ),
            ),
          ],
          Divider(height: 1, color: colors.border),
          _LanSharingRow(
            shared: cfg.allowConnectionFromLan,
            port: cfg.lanSharingPort,
            enabled: enabled,
            onOpenQr: () => LanSharingDialog.show(context),
            onToggle: (bool value) =>
                _toggleLanSharing(settings, vpn, value),
          ),
          if (auth != null) ...<Widget>[
            Divider(height: 1, color: colors.border),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppMetrics.space3,
                AppMetrics.space2,
                AppMetrics.space3,
                AppMetrics.space2,
              ),
              child: ContentControlCard(),
            ),
          ],
          const SizedBox(height: AppMetrics.space2),
        ],
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
    InboundServiceMode.vpn,
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<InboundServiceMode>(
      showSelectedIcon: false,
      segments: <ButtonSegment<InboundServiceMode>>[
        for (final InboundServiceMode mode in _modes)
          ButtonSegment<InboundServiceMode>(
            value: mode,
            tooltip: Fa.num(mode.description),
            icon: Icon(mode.icon, size: AppMetrics.iconXs),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppMetrics.space2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Fa.num(mode.shortLabel),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
      selected: <InboundServiceMode>{selected},
      onSelectionChanged: enabled
          ? (Set<InboundServiceMode> value) {
              playUiClick(context);
              onSelected(value.first);
            }
          : null,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppMetrics.space3,
        AppMetrics.space2,
        AppMetrics.space3,
        AppMetrics.space2,
      ),
      child: Material(
        color: colors.surfaceHigh.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: const ValueKey<String>('quick-lan-row'),
          contentPadding: const EdgeInsetsDirectional.only(
            start: AppMetrics.space3,
            end: AppMetrics.space2,
          ),
          leading: IconSquare(
            icon: Icons.wifi_tethering_rounded,
            color: shared ? colors.primary : colors.textSecondary,
            size: AppMetrics.iconBoxSm,
            radius: AppMetrics.radiusSm,
          ),
          title: Text(
            Fa.num('اشتراک گذاری اتصال'),
          ),
          subtitle: Text(
            shared
                ? 'فعال روی پورت ${Fa.num(port)} در شبکه محلی'
                : 'اشتراک اینترنت با دستگاه های هم شبکه',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: shared ? colors.primary : colors.textSecondary,
                ),
          ),
          onTap: withUiClick(context, onOpenQr),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Material(
                color: shared
                    ? colors.primary.withValues(alpha: 0.16)
                    : colors.surfaceHigh.withValues(alpha: 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  side: BorderSide(
                    color: shared
                        ? colors.primary.withValues(alpha: 0.35)
                        : colors.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  key: const ValueKey<String>('quick-lan-qr-button'),
                  tooltip: Fa.num('رمزینه تصویری اشتراک گذاری'),
                  onPressed: withUiClick(context, onOpenQr),
                  icon: Icon(
                    Icons.qr_code_2_rounded,
                    color: shared ? colors.primary : colors.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                height: AppMetrics.space6,
                child: VerticalDivider(
                  width: AppMetrics.space3,
                  color: colors.border,
                ),
              ),
              Switch.adaptive(
                key: const ValueKey<String>('quick-lan-switch'),
                value: shared,
                onChanged: enabled ? withUiClickValue(context, onToggle) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
