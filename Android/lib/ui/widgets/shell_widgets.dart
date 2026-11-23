import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import 'common.dart';

/// اعلان های شناور بالای وسط صفحه با رنگ و آیکون مناسب.
class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key, required this.controller});

  final ToastController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final List<ToastMessage> items = controller.items;
        return Positioned(
          top: AppMetrics.space4,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: items.isEmpty,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final ToastMessage item in items)
                  _ToastCard(
                    key: ValueKey<int>(item.id),
                    message: item,
                    onClose: () => controller.dismiss(item.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.message, required this.onClose});

  final ToastMessage message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone;
    final IconData icon;
    switch (message.kind) {
      case ToastKind.success:
        tone = colors.success;
        icon = message.icon ?? Icons.check_circle_rounded;
        break;
      case ToastKind.warning:
        tone = colors.warning;
        icon = message.icon ?? Icons.warning_amber_rounded;
        break;
      case ToastKind.error:
        tone = colors.danger;
        icon = message.icon ?? Icons.error_rounded;
        break;
      case ToastKind.info:
        tone = colors.info;
        icon = message.icon ?? Icons.info_rounded;
        break;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, -AppMetrics.space4 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppMetrics.space3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppMetrics.dialogMaxWidth,
          ),
          child: Material(
            color: Colors.transparent,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.space4,
                    vertical: AppMetrics.space3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
                    border: Border.all(color: tone.withValues(alpha: 0.5)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: tone.withValues(alpha: 0.18),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconSquare(
                        icon: icon,
                        color: tone,
                        size: AppMetrics.iconBoxSm,
                      ),
                      const SizedBox(width: AppMetrics.space3),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              Fa.num(message.title),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (message.message.isNotEmpty) ...<Widget>[
                              const SizedBox(height: AppMetrics.space1),
                              Text(
                                Fa.num(message.message),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: colors.textSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppMetrics.space2),
                      Icon(
                        Icons.close_rounded,
                        size: AppMetrics.iconSm,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// نوار بالای اندروید: لوگو، وضعیت زنده و دکمه های اعلان و تغییر تم.
class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    this.onDragStart,
    this.onMinimize,
    this.onMaximize,
    this.onClose,
    this.status,
    this.unread = 0,
    this.onNotifications,
    this.onToggleTheme,
    this.darkTheme = true,
  });

  final VpnStatus? status;
  final VoidCallback? onDragStart;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final VoidCallback? onClose;
  final int unread;
  final VoidCallback? onNotifications;
  final VoidCallback? onToggleTheme;
  final bool darkTheme;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final VpnStatus? current = status;
    final Color tone =
        current == null ? colors.primary : VpnVisuals.color(context, current);

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundAlt.withValues(alpha: 0.78),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppMetrics.space4,
                  end: AppMetrics.space2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ClipOval(
                      child: Image.asset(
                        BrandAssets.logo,
                        width: AppMetrics.iconLg,
                        height: AppMetrics.iconLg,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? stack,
                        ) =>
                            Icon(
                          Icons.shield_rounded,
                          size: AppMetrics.iconMd,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppMetrics.space2),
                    Text(
                      Fa.num(AppConfig.appName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: current == null
                      ? const SizedBox.shrink()
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppMetrics.space3,
                            vertical: AppMetrics.space1,
                          ),
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: tone.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: AppMetrics.space2,
                                height: AppMetrics.space2,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tone,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: tone.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppMetrics.space2),
                              Flexible(
                                child: Text(
                                  Fa.num(current.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: tone,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              if (onNotifications != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppMetrics.space1),
                  child: _HeaderIconButton(
                    icon: Icons.notifications_none_rounded,
                    filledIcon: Icons.notifications_rounded,
                    badge: unread,
                    tooltip: 'اعلان ها',
                    onTap: onNotifications!,
                  ),
                ),
              if (onToggleTheme != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppMetrics.space1,
                    end: AppMetrics.space3,
                  ),
                  child: _HeaderIconButton(
                    icon: darkTheme
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    tooltip: darkTheme ? 'تم روشن' : 'تم تاریک',
                    onTap: onToggleTheme!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// دکمه گرد و مدرن نوار بالا (اعلان و تم) با عدد نشان.
class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filledIcon,
    this.badge = 0,
  });

  final IconData icon;
  final IconData? filledIcon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool hasBadge = widget.badge > 0;
    return Tooltip(
      message: Fa.num(widget.tooltip),
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (bool value) {
            if (_hover != value) {
              setState(() => _hover = value);
            }
          },
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: AppMetrics.iconButton,
                height: AppMetrics.iconButton,
                decoration: BoxDecoration(
                  color: _hover ? colors.surfaceHigh : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  border: Border.all(
                    color: _hover ? colors.border : Colors.transparent,
                  ),
                ),
                child: Icon(
                  hasBadge
                      ? (widget.filledIcon ?? widget.icon)
                      : widget.icon,
                  size: AppMetrics.iconSm,
                  color: hasBadge ? colors.primary : colors.textSecondary,
                ),
              ),
              if (hasBadge)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppMetrics.space1,
                      vertical: AppMetrics.space1,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: AppMetrics.badgeMinWidth,
                    ),
                    decoration: BoxDecoration(
                      color: colors.danger,
                      borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                      border: Border.all(color: colors.backgroundAlt, width: 1.5),
                    ),
                    child: Text(
                      Fa.num(widget.badge > 99 ? '99+' : widget.badge),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppMetrics.fontMicro,
                        height: 1.1,
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w900,
                        fontFamily: AppTheme.fontFamily,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// نوار کنار (سمت راست) با فهرست بخش ها.
class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.destinations,
    required this.index,
    required this.onSelect,
    required this.status,
    this.onStatusTap,
    this.updateAvailable = false,
  });

  final List<NavDestination> destinations;
  final int index;
  final ValueChanged<int> onSelect;
  final VpnStatus status;
  final VoidCallback? onStatusTap;
  final bool updateAvailable;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // ریسپانسیو: در پنجره باریک نوار کناری جمع و جور می شود و متن منوها در
        // Tooltip می آید؛ در پنجره متوسط و پهن نام هر منو خوانا و مرتب می نشیند.
        final double windowWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final double width = windowWidth < AppMetrics.breakpointNav
            ? AppMetrics.navWidthCompact
            : (windowWidth < AppMetrics.breakpointNavWide
                ? AppMetrics.navWidthMedium
                : AppMetrics.navWidthWide);
        final bool compact = width < AppMetrics.navWidthMedium;
        final Color statusTone = VpnVisuals.color(context, status);
        return Container(
          width: width,
          decoration: BoxDecoration(
            color: colors.backgroundAlt,
            border: BorderDirectional(
              end: BorderSide(color: colors.border),
            ),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: AppMetrics.space3),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? AppMetrics.space3 : AppMetrics.space4,
                  ),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < destinations.length; i++)
                        _NavItem(
                          destination: destinations[i],
                          selected: i == index,
                          compact: compact,
                          showDot: updateAvailable &&
                              i == destinations.length - 1,
                          onTap: () => onSelect(i),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(
                  compact ? AppMetrics.space3 : AppMetrics.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!compact)
                      GlassCard(
                        onTap: onStatusTap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppMetrics.space3,
                          vertical: AppMetrics.space3,
                        ),
                        radius: AppMetrics.radiusLg,
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: AppMetrics.space2,
                              height: AppMetrics.space2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusTone,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: statusTone.withValues(alpha: 0.55),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppMetrics.space2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    Fa.num('اتصال'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: colors.textSecondary),
                                  ),
                                  Text(
                                    Fa.num(status.label),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: statusTone,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (index != 0)
                              Icon(
                                Icons.chevron_left_rounded,
                                size: AppMetrics.iconSm,
                                color: colors.textSecondary,
                              ),
                          ],
                        ),
                      )
                    else
                      Center(
                        child: Tooltip(
                          message: Fa.num(status.label),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onStatusTap,
                            child: Padding(
                              padding: const EdgeInsets.all(AppMetrics.space2),
                              child: Container(
                                width: AppMetrics.space3,
                                height: AppMetrics.space3,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusTone,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: AppMetrics.space3),
                    // پایین منوی کناری فقط شماره نسخه می آید، به شکل ساده
                    // `1.0.18` — بدون کلمه «نسخه» و بدون نام سازنده.
                    if (compact)
                      Center(
                        child: Tooltip(
                          message: Fa.num(AppConfig.versionLabel),
                          child: Text(
                            Fa.num(AppConfig.versionLabel),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.textSecondary,
                                  fontSize: AppMetrics.fontMicro,
                                ),
                          ),
                        ),
                      )
                    else
                      Row(
                        children: <Widget>[
                          Text(
                            Fa.num(AppConfig.versionLabel),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colors.textSecondary),
                          ),
                          const Spacer(),
                          if (updateAvailable)
                            Pill(
                              label: 'به روز رسانی',
                              icon: Icons.system_update_rounded,
                              color: colors.warning,
                              dense: true,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.showDot = false,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  /// در پنجره باریک فقط آیکون نشان داده می شود و متن در Tooltip می آید.
  final bool compact;
  final bool showDot;


  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool highlight = widget.selected || _hover;
    final Widget tile = Semantics(
      selected: widget.selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hover = value),
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          child: Container(
          constraints: const BoxConstraints(
            minHeight: AppMetrics.navItemHeight,
          ),
          margin: const EdgeInsets.only(bottom: AppMetrics.space2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? AppMetrics.space2 : AppMetrics.space3,
            vertical: AppMetrics.space3,
          ),
          decoration: BoxDecoration(
            gradient: widget.selected
                ? LinearGradient(
                    colors: <Color>[
                      colors.primary.withValues(alpha: 0.22),
                      colors.primary.withValues(alpha: 0.05),
                    ],
                  )
                : null,
            color: widget.selected
                ? null
                : (_hover ? colors.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(
              color: widget.selected
                  ? colors.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              if (!widget.compact) ...<Widget>[
                Container(
                  width: AppMetrics.space1,
                  height: AppMetrics.iconSm,
                  decoration: BoxDecoration(
                    color:
                        widget.selected ? colors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppMetrics.radiusXs),
                  ),
                ),
                const SizedBox(width: AppMetrics.space3),
              ],
              Icon(
                widget.selected
                    ? widget.destination.activeIcon
                    : widget.destination.icon,
                size: AppMetrics.iconMd,
                color: widget.selected
                    ? colors.primary
                    : (highlight ? colors.textPrimary : colors.textSecondary),
              ),
              if (!widget.compact) ...<Widget>[
                const SizedBox(width: AppMetrics.space3),
                Expanded(
                  child: Text(
                    Fa.num(widget.destination.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: widget.selected
                              ? colors.textPrimary
                              : (highlight
                                  ? colors.textPrimary
                                  : colors.textSecondary),
                          fontWeight: widget.selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                  ),
                ),
                if (widget.showDot) ...<Widget>[
                  const SizedBox(width: AppMetrics.space1),
                  Container(
                    width: AppMetrics.space2,
                    height: AppMetrics.space2,
                    decoration: BoxDecoration(
                      color: colors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ],
          ),
          ),
        ),
      ),
    );
    if (!widget.compact) {
      return tile;
    }
    return Tooltip(
      message: Fa.num(widget.destination.label),
      waitDuration: const Duration(milliseconds: 400),
      child: tile,
    );
  }
}
