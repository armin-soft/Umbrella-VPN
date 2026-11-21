import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';

/// کارت شیشه ای پایه همه بخش ها.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = AppMetrics.cardPadding,
    this.radius = AppMetrics.radiusXxl,
    this.onTap,
    this.gradient,
    this.borderColor,
    this.tint,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;
  final Color? tint;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ??
            LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                tint ?? colors.surface,
                Color.alphaBlend(
                  (tint ?? colors.surface).withValues(alpha: 0.65),
                  colors.backgroundAlt,
                ),
              ],
            ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? colors.border),
        boxShadow: elevated
            ? <BoxShadow>[
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap == null) {
      return content;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}

/// دکمه اصلی با گرادیان برند.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expand = true,
    this.height = AppMetrics.controlHeight,
    this.tone,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final double height;
  final Color? tone;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool active = enabled && !loading && onPressed != null;
    final Color base = tone ?? colors.primary;
    final Color end = Color.lerp(base, Colors.black, 0.35)!;
    final Color foreground = AppTheme.gradientForeground(base, end);
    final Widget child = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: active
              ? <Color>[base, end]
              : <Color>[colors.surfaceHigh, colors.surfaceHigh],
        ),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: base.withValues(alpha: 0.35),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          if (loading)
            SizedBox(
              width: AppMetrics.iconMd,
              height: AppMetrics.iconMd,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: active ? colors.onPrimary : colors.textSecondary,
              ),
            )
          else if (icon != null)
            Icon(
              icon,
              size: AppMetrics.iconMd,
              color: !active
                  ? colors.textSecondary
                  : foreground,
            ),
          if (loading || icon != null) const SizedBox(width: AppMetrics.space3),
          Flexible(
            child: Text(
            Fa.num(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  // دکمه کم رنگ (tone) رنگ روشن دارد؛ متن سفید روی آن
                  // خوانده نمی شود.
                  color: !active
                      ? colors.textSecondary
                      : foreground,
                  fontWeight: FontWeight.w800,
                ),
            ),
          ),
        ],
      ),
    );

    final Widget button = MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: active ? onPressed : null,
        child: expand ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.65,
      child: button,
    );
  }
}

/// پس زمینه مشترک صفحه های مدیریتی؛ اتصال عمداً ظاهر مستقل خود را دارد.
class MenuPageBackdrop extends StatelessWidget {
  const MenuPageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          top: -AppMetrics.space10 * 3,
          right: -AppMetrics.space10 * 2,
          width: 540,
          height: 540,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      colors.primary.withValues(alpha: 0.11),
                      colors.primary.withValues(alpha: 0),
                    ],
                    stops: const <double>[0, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -AppMetrics.space10 * 4,
          left: -AppMetrics.space10 * 3,
          width: 620,
          height: 620,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      colors.info.withValues(alpha: 0.055),
                      colors.info.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// سربرگ یکدست و حرفه ای منوها: نشان صفحه، مسیر، عنوان، توضیح و عملیات.
///
/// اتصال از قاب هویتی خودش استفاده می کند؛ این قطعه فقط برای منوهای مدیریتی
/// به کار می رود تا همه آن ها وزن بصری، فاصله و سلسله مراتب یکسان داشته باشند.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const <Widget>[],
    this.eyebrow = 'مرکز مدیریت آمبرلا',
    this.premium = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final String eyebrow;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    if (!premium) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final bool narrow = constraints.maxWidth <
              math.max(AppMetrics.breakpointCompact, 620 * textScale);
          final Widget text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fa.num(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: AppMetrics.space1),
                Text(
                  Fa.num(subtitle!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.7,
                      ),
                ),
              ],
            ],
          );
          final Widget mark = icon == null
              ? const SizedBox.shrink()
              : Container(
                  width: AppMetrics.iconBoxXl,
                  height: AppMetrics.iconBoxXl,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
                    color: colors.primary.withValues(alpha: 0.14),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Icon(icon, size: AppMetrics.iconLg, color: colors.primary),
                );
          final Widget heading = Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                mark,
                const SizedBox(width: AppMetrics.space4),
              ],
              Expanded(child: text),
            ],
          );
          if (actions.isEmpty) {
            return ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppMetrics.controlHeight,
              ),
              child: heading,
            );
          }
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                heading,
                const SizedBox(height: AppMetrics.space3),
                Wrap(
                  spacing: AppMetrics.space3,
                  runSpacing: AppMetrics.space3,
                  children: actions,
                ),
              ],
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppMetrics.controlHeight,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: heading),
                const SizedBox(width: AppMetrics.space3),
                ...actions,
              ],
            ),
          );
        },
      );
    }
    final Widget content = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool narrow = constraints.maxWidth <
            math.max(AppMetrics.breakpointCompact, 620 * textScale);
        final Widget text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: AppMetrics.space2,
                  height: AppMetrics.space2,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.38),
                        blurRadius: AppMetrics.space3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppMetrics.space2),
                Flexible(child: Text(
                  Fa.num(eyebrow),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.35,
                      ),
                )),
              ],
            ),
            const SizedBox(height: AppMetrics.space1),
            Text(
              Fa.num(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppMetrics.space1),
              Text(
                Fa.num(subtitle!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.65,
                    ),
              ),
            ],
          ],
        );
        final Widget mark = icon == null
            ? const SizedBox.shrink()
            : Container(
                width: AppMetrics.iconBoxHero,
                height: AppMetrics.iconBoxHero,
                decoration: BoxDecoration(
                  gradient: context.brandGradient,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.2),
                      blurRadius: AppMetrics.space5,
                      offset: const Offset(0, AppMetrics.space2),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: AppMetrics.iconXl,
                  color: colors.onPrimary,
                ),
              );
        final Widget heading = Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              mark,
              const SizedBox(width: AppMetrics.space4),
            ],
            Expanded(child: text),
          ],
        );
        if (actions.isEmpty) {
          return ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppMetrics.iconBoxHero,
            ),
            child: heading,
          );
        }
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              heading,
              const SizedBox(height: AppMetrics.space3),
              Wrap(
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space2,
                children: actions,
              ),
            ],
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppMetrics.iconBoxHero,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: heading),
              const SizedBox(width: AppMetrics.space3),
              ...actions,
            ],
          ),
        );
      },
    );

    return GlassCard(
      padding: EdgeInsets.zero,
      radius: AppMetrics.radiusXl,
      borderColor: colors.primary.withValues(alpha: 0.24),
      gradient: LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: <Color>[
          Color.alphaBlend(
            colors.primary.withValues(alpha: 0.085),
            colors.surface,
          ),
          colors.surface,
        ],
      ),
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            start: 0,
            top: AppMetrics.space4,
            bottom: AppMetrics.space4,
            child: Container(
              width: AppMetrics.space1,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppMetrics.space4),
            child: content,
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          IconSquare(
            icon: icon!,
            color: accent ?? colors.primary,
            size: AppMetrics.iconBoxLg,
            radius: AppMetrics.radiusMd,
          ),
          const SizedBox(width: AppMetrics.space3),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fa.num(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppMetrics.space1),
                Text(
                  Fa.num(subtitle!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(height: AppMetrics.space2),
          trailing!,
        ],
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone = color ?? colors.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppMetrics.space2 : AppMetrics.space3,
        vertical: AppMetrics.space1,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: dense ? AppMetrics.fontSmall : AppMetrics.iconXs,
              color: tone,
            ),
            const SizedBox(width: AppMetrics.space1),
          ],
          Flexible(child: Text(
            Fa.num(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: dense ? AppMetrics.fontCaption : AppMetrics.fontSmall,
              fontWeight: FontWeight.w700,
              color: tone,
              fontFamily: AppTheme.fontFamily,
            ),
          )),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.hint,
    this.compact = false,
    this.ltr = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final String? hint;
  final bool compact;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone = accent ?? colors.primary;
    return GlassCard(
      padding: EdgeInsets.all(
        compact ? AppMetrics.space4 : AppMetrics.space5,
      ),
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: icon,
                color: tone,
                size: AppMetrics.iconBoxMd,
                radius: AppMetrics.radiusMd,
              ),
              const SizedBox(width: AppMetrics.space3),
              Expanded(
                child: Text(
                  Fa.num(label),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? AppMetrics.space2 : AppMetrics.space3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              Fa.num(value),
              textDirection: ltr ? TextDirection.ltr : null,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: compact
                        ? AppMetrics.fontButton
                        : AppMetrics.fontEmphasis,
                  ),
            ),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: AppMetrics.space1),
            Text(
              Fa.num(hint!),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class IconSquare extends StatelessWidget {
  const IconSquare({
    super.key,
    required this.icon,
    required this.color,
    this.size = AppMetrics.iconBoxMd,
    this.radius,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(radius ?? (size * 0.32)),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.valueColor,
    this.trailing,
    this.ltr = false,
    this.technicalValue = false,
    this.tooltip = false,
    this.stacked = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? valueColor;
  final Widget? trailing;
  final bool ltr;

  /// Keeps copyable addresses and identifiers byte-for-byte unchanged.
  final bool technicalValue;
  final bool tooltip;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String display = technicalValue ? value : Fa.num(value);
    Widget valueText = Text(
      display,
      textDirection: ltr ? TextDirection.ltr : null,
      textAlign: ltr
          ? TextAlign.left
          : (stacked ? TextAlign.start : TextAlign.end),
      maxLines: stacked ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: valueColor ?? colors.textPrimary,
            fontWeight: FontWeight.w700,
            height: stacked ? 1.5 : null,
          ),
    );
    if ((tooltip || stacked) && display.isNotEmpty) {
      valueText = Tooltip(message: display, child: valueText);
    }

    final Widget rowContent;
    if (stacked) {
      rowContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AppMetrics.space1),
            child: Icon(
              icon,
              size: AppMetrics.iconSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        Fa.num(label),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                      ),
                    ),
                    if (trailing != null) ...<Widget>[
                      const SizedBox(width: AppMetrics.space2),
                      trailing!,
                    ],
                    if (onTap != null) ...<Widget>[
                      const SizedBox(width: AppMetrics.space2),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: AppMetrics.iconXs,
                        color: colors.textSecondary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppMetrics.space1),
                Align(
                  alignment: ltr
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: valueText,
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      rowContent = Row(
        children: <Widget>[
          Icon(icon, size: AppMetrics.iconSm, color: colors.textSecondary),
          const SizedBox(width: AppMetrics.space3),
          Flexible(
            child: Text(
              Fa.num(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          const SizedBox(width: AppMetrics.space3),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: valueText,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppMetrics.space2),
            trailing!,
          ],
          if (onTap != null) ...<Widget>[
            const SizedBox(width: AppMetrics.space2),
            Icon(
              Icons.open_in_new_rounded,
              size: AppMetrics.iconXs,
              color: colors.textSecondary,
            ),
          ],
        ],
      );
    }

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space2,
        vertical: AppMetrics.space3,
      ),
      child: rowContent,
    );
    if (onTap == null) {
      return row;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// حلقه مصرف با گرادیان برند.
class UsageRing extends StatelessWidget {
  const UsageRing({
    super.key,
    required this.percent,
    required this.centerLabel,
    this.centerValue = '',
    this.size = 168,
    this.color,
    this.thickness = 12,
  });

  final double percent;
  final String centerLabel;
  final String centerValue;
  final double size;
  final Color? color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone = color ?? colors.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          percent: (percent / 100).clamp(0.0, 1.0),
          color: tone,
          track: colors.surfaceHigh,
          thickness: thickness,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fa.num(centerValue),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppMetrics.space1),
              Text(
                Fa.num(centerLabel),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percent,
    required this.color,
    required this.track,
    required this.thickness,
  });

  final double percent;
  final Color color;
  final Color track;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.shortestSide - thickness) / 2;
    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness + 6
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: <Color>[
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.35),
        ],
      ).createShader(rect);
    final Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: <Color>[color.withValues(alpha: 0.55), color],
      ).createShader(rect);

    final double sweep = 2 * math.pi * percent;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glowPaint);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.percent != percent || old.color != color;
}

/// لوگوی وضعیت اتصال با هاله تنفس.
class StatusOrb extends StatefulWidget {
  const StatusOrb({
    super.key,
    required this.image,
    required this.color,
    this.size = 220,
    this.active = false,
  });

  final String image;
  final Color color;
  final double size;
  final bool active;

  @override
  State<StatusOrb> createState() => _StatusOrbState();
}

class _StatusOrbState extends State<StatusOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: widget.size * (0.86 + 0.1 * t),
                height: widget.size * (0.86 + 0.1 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      widget.color.withValues(alpha: 0.30 - 0.12 * t),
                      widget.color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              Container(
                width: widget.size * 0.74,
                height: widget.size * 0.74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.35 + 0.25 * t),
                    width: 1.4,
                  ),
                ),
              ),
              if (widget.active)
                SizedBox(
                  width: widget.size * 0.82,
                  height: widget.size * 0.82,
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 2,
                    color: widget.color.withValues(alpha: 0.18 + 0.2 * t),
                  ),
                ),
              ClipOval(
                // بارگذاری تصویر وضعیت هرگز نباید با خاموش شدن تیکر پس زمینه
                // متوقف شود (حتی اگر وضعیت در حالت کوچک شده در سینی عوض شود).
                child: TickerMode(
                  enabled: true,
                  child: Image.asset(
                    widget.image,
                    width: widget.size * 0.66,
                    height: widget.size * 0.66,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stack,
                    ) =>
                        Image.asset(
                      BrandAssets.logo,
                      width: widget.size * 0.66,
                      height: widget.size * 0.66,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (
                        BuildContext context,
                        Object fallbackError,
                        StackTrace? fallbackStack,
                      ) =>
                          Container(
                        width: widget.size * 0.66,
                        height: widget.size * 0.66,
                        color: colors.surfaceHigh,
                        child: Icon(
                          Icons.shield_outlined,
                          size: widget.size * 0.28,
                          color: widget.color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppMetrics.space7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconSquare(
              icon: icon,
              color: colors.textSecondary,
              size: AppMetrics.iconBoxHero,
            ),
            const SizedBox(height: AppMetrics.space4),
            Text(
              Fa.num(title),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            if (message.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppMetrics.space2),
              Text(
                Fa.num(message),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: AppMetrics.space5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class SelectionCard extends StatelessWidget {
  const SelectionCard({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppMetrics.space4),
      radius: AppMetrics.radiusLg,
      borderColor: selected ? colors.primary : colors.border,
      tint: selected ? colors.primarySoft : colors.surface,
      child: Row(
        children: <Widget>[
          IconSquare(
            icon: icon ?? Icons.tune_rounded,
            color: selected ? colors.primary : colors.textSecondary,
            size: AppMetrics.iconBoxMd,
          ),
          const SizedBox(width: AppMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Fa.num(title),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: selected ? colors.textPrimary : colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppMetrics.space1),
                Text(
                  Fa.num(description),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.6,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppMetrics.space2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: AppMetrics.iconMd,
            height: AppMetrics.iconMd,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.primary : Colors.transparent,
              border: Border.all(
                color: selected ? colors.primary : colors.border,
                width: 1.6,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    size: AppMetrics.iconXs,
                    color: colors.onPrimary,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone =
        value ? (accent ?? colors.primary) : colors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.space2,
            vertical: AppMetrics.space3,
          ),
          child: Row(
            children: <Widget>[
              IconSquare(
                icon: icon,
                color: tone,
                size: AppMetrics.iconBoxMd,
                radius: AppMetrics.radiusMd,
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
                    if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        Fa.num(subtitle!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.55,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppMetrics.space3),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// گزینه استاندارد فهرست بازشوی دسکتاپ.
class SelectOption<T> {
  const SelectOption({
    required this.value,
    required this.label,
    this.subtitle = '',
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String subtitle;
  final IconData? icon;
  final bool enabled;
}

/// کنترل انتخاب بازشوی استاندارد ویندوز (متصل به خود فیلد، بدون پنجره وسط صفحه).
class AnchoredSelectField<T> extends StatefulWidget {
  const AnchoredSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.leadingIcon,
  });

  final String label;
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final IconData? leadingIcon;

  @override
  State<AnchoredSelectField<T>> createState() => _AnchoredSelectFieldState<T>();
}

class _AnchoredSelectFieldState<T> extends State<AnchoredSelectField<T>> {
  final MenuController _menuController = MenuController();
  bool _hovered = false;

  SelectOption<T> get _selected {
    for (final SelectOption<T> option in widget.options) {
      if (option.value == widget.value) {
        return option;
      }
    }
    return widget.options.first;
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final SelectOption<T> active = _selected;
    final IconData? icon = active.icon ?? widget.leadingIcon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppMetrics.space1,
            bottom: AppMetrics.space1,
          ),
          child: Text(
            Fa.num(widget.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double menuWidth = constraints.maxWidth > AppMetrics.buttonMaxWidth
                ? constraints.maxWidth
                : AppMetrics.buttonMaxWidth;
            final double itemWidth = menuWidth - (AppMetrics.space2 * 2);
            return MenuAnchor(
              controller: _menuController,
              alignmentOffset: const Offset(0, AppMetrics.space1),
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll<Color>(colors.surface),
                surfaceTintColor:
                    const WidgetStatePropertyAll<Color>(Colors.transparent),
                shadowColor: WidgetStatePropertyAll<Color>(colors.shadow),
                elevation: const WidgetStatePropertyAll<double>(14),
                minimumSize: WidgetStatePropertyAll<Size>(
                  Size(menuWidth, 0),
                ),
                maximumSize: WidgetStatePropertyAll<Size>(
                  Size(menuWidth, AppMetrics.dialogMaxHeight),
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
                for (int i = 0; i < widget.options.length; i++)
                  _SelectMenuItem<T>(
                    option: widget.options[i],
                    width: itemWidth,
                    isLast: i == widget.options.length - 1,
                    selected: widget.options[i].value == widget.value,
                    onSelect: () {
                      final T next = widget.options[i].value;
                      _menuController.close();
                      if (next != widget.value) {
                        widget.onChanged(next);
                      }
                    },
                  ),
              ],
              builder: (
                BuildContext context,
                MenuController controller,
                Widget? child,
              ) {
                final bool open = controller.isOpen;
                final Color borderColor = !widget.enabled
                    ? colors.border
                    : (open
                        ? colors.primary
                        : (_hovered
                            ? colors.textSecondary.withValues(alpha: 0.55)
                            : colors.border));
                return Opacity(
                  opacity: widget.enabled ? 1 : 0.55,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppMetrics.radiusMd),
                        onTap: !widget.enabled
                            ? null
                            : () {
                                if (controller.isOpen) {
                                  controller.close();
                                } else {
                                  controller.open();
                                }
                              },
                        child: Container(
                          height: AppMetrics.controlHeightSmall,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppMetrics.space3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceHigh,
                            borderRadius:
                                BorderRadius.circular(AppMetrics.radiusMd),
                            border: Border.all(
                              color: borderColor,
                              width: open ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              if (icon != null) ...<Widget>[
                                Icon(
                                  icon,
                                  size: AppMetrics.iconSm,
                                  color: open
                                      ? colors.primary
                                      : colors.textSecondary,
                                ),
                                const SizedBox(width: AppMetrics.space2),
                              ],
                              Expanded(
                                child: Text(
                                  Fa.num(active.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: colors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              const SizedBox(width: AppMetrics.space2),
                              AnimatedRotation(
                                turns: open ? 0.5 : 0,
                                duration: const Duration(milliseconds: 160),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: AppMetrics.iconMd,
                                  color: open
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
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _SelectMenuItem<T> extends StatelessWidget {
  const _SelectMenuItem({
    required this.option,
    required this.width,
    required this.isLast,
    required this.selected,
    required this.onSelect,
  });

  final SelectOption<T> option;
  final double width;
  final bool isLast;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return SizedBox(
      width: width,
      child: Padding(
        padding: isLast
            ? EdgeInsets.zero
            : const EdgeInsets.only(bottom: AppMetrics.space1),
        child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          onTap: option.enabled ? onSelect : null,
          child: Opacity(
            opacity: option.enabled ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.space3,
                vertical: AppMetrics.space2,
              ),
              child: Row(
                children: <Widget>[
                  if (option.icon != null) ...<Widget>[
                    Icon(
                      option.icon,
                      size: AppMetrics.iconSm,
                      color: selected ? colors.primary : colors.textSecondary,
                    ),
                    const SizedBox(width: AppMetrics.space3),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          Fa.num(option.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                  ),
                        ),
                        if (option.subtitle.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppMetrics.space1),
                          Text(
                            Fa.num(option.subtitle),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppMetrics.space2),
                  SizedBox(
                    width: AppMetrics.iconMd,
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: AppMetrics.iconSm,
                            color: colors.primary,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.color,
    this.height = 8,
    this.label,
  });

  final double value;
  final Color? color;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  Fa.num(label!),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ),
              Text(
                Fa.percent(value * 100),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space2),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: height,
            backgroundColor: colors.surfaceHigh,
            valueColor: AlwaysStoppedAnimation<Color>(color ?? colors.primary),
          ),
        ),
      ],
    );
  }
}

class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.size = AppMetrics.iconButton,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, size: size * 0.5, color: color ?? colors.textSecondary),
        ),
      ),
    );
    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: Fa.num(tooltip!), child: button);
  }
}

/// دو ستون که در پنجره باریک زیر هم می روند.
///
/// صفحه های دستگاه، حساب و تنظیمات همه یک `Row` با دو `Expanded` داشتند؛ در
/// پنجره باریک یا بزرگ شده ویندوز، ستون ها آن قدر تنگ می شدند که متن ها روی
/// هم می افتادند. این ویجت با `LayoutBuilder` عرض واقعی را می سنجد و زیر
/// [breakpoint] چیدمان را عمودی می کند.
class ResponsiveColumns extends StatelessWidget {
  const ResponsiveColumns({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 3,
    this.rightFlex = 2,
    this.spacing = AppMetrics.space4,
    this.breakpoint = AppMetrics.breakpointColumns,
  });

  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double spacing;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
        if (constraints.maxWidth < breakpoint * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[left, SizedBox(height: spacing), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: leftFlex, child: left),
            SizedBox(width: spacing),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }
}
