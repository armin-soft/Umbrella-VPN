import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';

/// کارت شیشه ای پایه همه بخش ها.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
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
    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
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
    this.height = 54,
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
    final Widget child = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: active
              ? <Color>[base, Color.lerp(base, Colors.black, 0.35)!]
              : <Color>[colors.surfaceHigh, colors.surfaceHigh],
        ),
        borderRadius: BorderRadius.circular(18),
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
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: active ? colors.onPrimary : colors.textSecondary,
              ),
            )
          else if (icon != null)
            Icon(
              icon,
              size: 19,
              color: active ? colors.onPrimary : colors.textSecondary,
            ),
          if (loading || icon != null) const SizedBox(width: 10),
          Text(
            Fa.num(label),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: active ? colors.onPrimary : colors.textSecondary,
                  fontWeight: FontWeight.w800,
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

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                Fa.num(title),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  Fa.num(subtitle!),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
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
        horizontal: dense ? 8 : 11,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 12 : 14, color: tone),
            const SizedBox(width: 5),
          ],
          Text(
            Fa.num(label),
            style: TextStyle(
              fontSize: dense ? 10.5 : 12,
              fontWeight: FontWeight.w700,
              color: tone,
              fontFamily: AppTheme.fontFamily,
            ),
          ),
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
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final String? hint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone = accent ?? colors.primary;
    return GlassCard(
      padding: EdgeInsets.all(compact ? 14 : 18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(icon: icon, color: tone, size: compact ? 30 : 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Fa.num(label),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              Fa.num(value),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 14 : 17,
                  ),
            ),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 4),
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
    this.size = 36,
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
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 17, color: colors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  Fa.num(label),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  Fa.num(value),
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: valueColor ?? colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ],
              if (onTap != null) ...<Widget>[
                const SizedBox(width: 4),
                Icon(Icons.chevron_left_rounded, size: 18, color: colors.border),
              ],
            ],
          ),
        ),
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
              const SizedBox(height: 2),
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
                child: Image.asset(
                  widget.image,
                  width: widget.size * 0.66,
                  height: widget.size * 0.66,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconSquare(icon: icon, color: colors.textSecondary, size: 56),
            const SizedBox(height: 16),
            Text(
              Fa.num(title),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            if (message.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                Fa.num(message),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 18),
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
      padding: const EdgeInsets.all(16),
      radius: 18,
      borderColor: selected ? colors.primary : colors.border,
      tint: selected ? colors.primarySoft : colors.surface,
      child: Row(
        children: <Widget>[
          IconSquare(
            icon: icon ?? Icons.tune_rounded,
            color: selected ? colors.primary : colors.textSecondary,
            size: 34,
          ),
          const SizedBox(width: 12),
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
                const SizedBox(height: 4),
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
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.primary : Colors.transparent,
              border: Border.all(
                color: selected ? colors.primary : colors.border,
                width: 1.6,
              ),
            ),
            child: selected
                ? Icon(Icons.check_rounded, size: 14, color: colors.onPrimary)
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          IconSquare(icon: icon, color: accent ?? colors.primary, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Fa.num(title),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    Fa.num(subtitle!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
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
          const SizedBox(height: 6),
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
    this.size = 34,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
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
