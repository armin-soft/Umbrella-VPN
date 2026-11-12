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
          top: 16,
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
            offset: Offset(0, -16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: Colors.transparent,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
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
                      IconSquare(icon: icon, color: tone, size: 32),
                      const SizedBox(width: 12),
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
                              const SizedBox(height: 2),
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
                      const SizedBox(width: 10),
                      Icon(Icons.close_rounded, size: 15, color: colors.textSecondary),
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

/// نوار بالای پنجره: لوگو، وضعیت و دکمه های کوچک کردن، بزرگ کردن و بستن.
///
/// پنجره ویندوز بدون قاب پیش فرض ساخته می شود، پس این نوار روی همه صفحه ها —
/// از جمله صفحه ورود و معرفی — باید وجود داشته باشد تا کاربر بتواند پنجره را
/// جابه جا، کوچک یا بسته کند.
class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    required this.onDragStart,
    required this.onMinimize,
    required this.onMaximize,
    required this.onClose,
    this.status,
    this.unread = 0,
    this.onNotifications,
    this.onToggleTheme,
    this.darkTheme = true,
  });

  final VpnStatus? status;
  final VoidCallback onDragStart;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onClose;
  final int unread;
  final VoidCallback? onNotifications;

  /// تغییر تم روشن و تاریک از نوار بالای پنجره (نه از تنظیمات).
  final VoidCallback? onToggleTheme;
  final bool darkTheme;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final VpnStatus? current = status;
    final Color tone =
        current == null ? colors.primary : VpnVisuals.color(context, current);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.backgroundAlt.withValues(alpha: 0.6),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: <Widget>[
          // دکمه های پنجره در سمت راست، مطابق چیدمان راست چین.
          _WindowButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            danger: true,
          ),
          _WindowButton(icon: Icons.crop_square_rounded, onTap: onMaximize),
          _WindowButton(icon: Icons.remove_rounded, onTap: onMinimize),
          if (onToggleTheme != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _WindowButton(
                icon: darkTheme
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                onTap: onToggleTheme!,
              ),
            ),
          if (onNotifications != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  _WindowButton(
                    icon: Icons.notifications_none_rounded,
                    onTap: onNotifications!,
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          Fa.num(unread),
                          style: TextStyle(
                            fontSize: 9,
                            color: colors.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontFamily: AppTheme.fontFamily,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // ناحیه کشیدن پنجره با لوگو و وضعیت در سمت چپ نوار.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => onDragStart(),
              onDoubleTap: onMaximize,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (current != null) ...<Widget>[
                      Pill(
                        label: current.label,
                        icon: VpnVisuals.icon(current),
                        color: tone,
                        dense: true,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      Fa.num(AppConfig.appName),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(width: 10),
                    ClipOval(
                      child: Image.asset(
                        BrandAssets.logo,
                        width: 26,
                        height: 26,
                        errorBuilder: (BuildContext context, Object error,
                                StackTrace? stack) =>
                            Icon(
                          Icons.beach_access_rounded,
                          size: 22,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color hoverColor = widget.danger ? colors.danger : colors.surfaceHigh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 48,
          height: 52,
          color: _hover ? hoverColor : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 17,
            color: _hover && widget.danger ? colors.onPrimary : colors.textSecondary,
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
    this.version = AppConfig.versionLabel,
    this.updateAvailable = false,
  });

  final List<NavDestination> destinations;
  final int index;
  final ValueChanged<int> onSelect;
  final VpnStatus status;
  final VoidCallback? onStatusTap;
  final String version;
  final bool updateAvailable;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: colors.backgroundAlt,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < destinations.length; i++)
                  _NavItem(
                    destination: destinations[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                GlassCard(
                  onTap: onStatusTap,
                  padding: const EdgeInsets.all(14),
                  radius: 16,
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: VpnVisuals.color(context, status),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: VpnVisuals.color(context, status)
                                  .withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          Fa.num(status.label),
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(
                        Icons.chevron_left_rounded,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Text(
                      Fa.num(version),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                          ),
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
                const SizedBox(height: 6),
                Text(
                  Fa.num(AppConfig.developer),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary.withValues(alpha: 0.8),
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

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool highlight = widget.selected || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected
                  ? colors.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.selected ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                widget.selected
                    ? widget.destination.activeIcon
                    : widget.destination.icon,
                size: 19,
                color: widget.selected
                    ? colors.primary
                    : (highlight ? colors.textPrimary : colors.textSecondary),
              ),
              const SizedBox(width: 10),
              Text(
                Fa.num(widget.destination.label),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: widget.selected
                          ? colors.textPrimary
                          : (highlight ? colors.textPrimary : colors.textSecondary),
                      fontWeight:
                          widget.selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
