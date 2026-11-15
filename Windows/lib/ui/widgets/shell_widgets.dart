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

    // چیدمان خواسته شده: وضعیت اتصال **وسط** نوار، و اعلان و تم در **سمت
    // چپ** آن. دکمه های پنجره در لبه راست می مانند (چیدمان راست چین).
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: colors.backgroundAlt.withValues(alpha: 0.65),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: <Widget>[
          // ── راست: دکمه های پنجره ───────────────────────────────────
          _WindowButton(icon: Icons.close_rounded, onTap: onClose, danger: true),
          _WindowButton(icon: Icons.crop_square_rounded, onTap: onMaximize),
          _WindowButton(icon: Icons.remove_rounded, onTap: onMinimize),

          // ── وسط: لوگو، نام، وضعیت ────────────────────────────────
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => onDragStart(),
              onDoubleTap: onMaximize,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ClipOval(
                      child: Image.asset(
                        BrandAssets.logo,
                        width: 24,
                        height: 24,
                        errorBuilder: (BuildContext context, Object error,
                                StackTrace? stack) =>
                            Icon(
                          Icons.beach_access_rounded,
                          size: 20,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        Fa.num(AppConfig.appName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                      ),
                    ),
                    if (current != null) ...<Widget>[
                      const SizedBox(width: 10),
                      // نقطه رنگی وضعیت، در پنجره باریک فقط همین می ماند.
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tone,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: tone.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          Fa.num(current.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: tone,
                                  ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── چپ: اعلان و تم ────────────────────────────────────────
          if (onNotifications != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
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
              padding: const EdgeInsets.only(left: 3, right: 10),
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
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _hover ? colors.surfaceHigh : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: _hover ? colors.border : Colors.transparent,
                  ),
                ),
                child: Icon(
                  hasBadge
                      ? (widget.filledIcon ?? widget.icon)
                      : widget.icon,
                  size: 17,
                  color: hasBadge ? colors.primary : colors.textSecondary,
                ),
              ),
              if (hasBadge)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 14),
                    decoration: BoxDecoration(
                      color: colors.danger,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.backgroundAlt, width: 1.5),
                    ),
                    child: Text(
                      Fa.num(widget.badge > 99 ? '99+' : widget.badge),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8.5,
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
    this.updateAvailable = false,
    this.exitIndex,
  });

  final List<NavDestination> destinations;
  final int index;
  final ValueChanged<int> onSelect;
  final VpnStatus status;
  final VoidCallback? onStatusTap;
  final bool updateAvailable;

  /// اندیس گزینه «خروج» در [destinations]؛ اگر داده نشود، خروج نمایش داده
  /// نمی شود. جدا از بقیه منوها کشیده می شود تا با آن ها اشتباه نشود.
  final int? exitIndex;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // ریسپانسیو: در پنجره باریک نوار کناری باریک می شود و متن منوها
        // کوتاه می شود تا محتوا جا شود؛ هیچ گزینه ای حذف نمی شود.
        final double width = constraints.maxWidth < 820
            ? 68
            : (constraints.maxWidth < 1060 ? 186 : 232);
        final bool compact = width < 150;
        return Container(
          width: width,
          decoration: BoxDecoration(
            color: colors.backgroundAlt,
            border: BorderDirectional(
              start: BorderSide(color: colors.border),
            ),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 14,
                  ),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < destinations.length; i++)
                        _NavItem(
                          destination: destinations[i],
                          selected: i == index,
                          compact: compact,
                          onTap: () => onSelect(i),
                          // «خروج» آخرین خانه است و قرمز می ماند تا با
                          // بقیه اشتباه نشود.
                          tone: (exitIndex != null &&
                                  destinations[i] == destinations[exitIndex!])
                              ? colors.danger
                              : null,
                        ),
                      // «خروج» بخش جداگانه ای در انتهای منو است، نه ته
                      // تنظیمات. یک خط جداکننده هم مرزش را نشان می دهد.
                      // «خروج» دیگر یک خانه جداگانه نیست: خودش در فهرست
                      // `destinations` هست و بالا با آن کشیده می شود.
                      //
                      // **اشکال گزارش ۱٫۰۱۷:** اینجا یک خانه «خروج» هم دستی
                      // ساخته می شد، پس کاربر دو «خروج» می دید — یکی وسط
                      // منو و یکی پایین با خط جداکننده. تنها چیزی که اینجا
                      // لازم است همان خط جداکننده پیش از «خروج» است.
                      if (exitIndex != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Divider(height: 1, color: colors.border),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 10 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!compact)
                      GlassCard(
                        onTap: onStatusTap,
                        padding: const EdgeInsets.all(12),
                        radius: 14,
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
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                Fa.num(status.label),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Center(
                        child: Tooltip(
                          message: Fa.num(status.label),
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: VpnVisuals.color(context, status),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
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
                                  fontSize: 9,
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
    this.tone,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  /// در پنجره باریک فقط آیکون نشان داده می شود و متن در Tooltip می آید.
  final bool compact;

  /// رنگ دلخواه؛ «خروج» قرمز است تا از گزینه های معمولی جدا باشد.
  final Color? tone;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool highlight = widget.selected || _hover;
    final Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 6 : 12,
            vertical: 11,
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
                  color: widget.selected
                      ? (widget.tone ?? colors.primary)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(width: widget.compact ? 6 : 10),
              Icon(
                widget.selected
                    ? widget.destination.activeIcon
                    : widget.destination.icon,
                size: 19,
                color: widget.selected
                    ? (widget.tone ?? colors.primary)
                    : (highlight ? colors.textPrimary : colors.textSecondary),
              ),
              if (!widget.compact) ...<Widget>[
                const SizedBox(width: 10),
                Flexible(
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
              ],
            ],
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
