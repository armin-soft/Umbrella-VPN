import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../platform/services.dart';
import '../../vpn/vpn_controller.dart';
import 'common.dart';

/// نشان اپراتور تلفن همراه با لوگوی رسمی خودش (همراه اول، ایرانسل، رایتل).
///
/// لوگوها همراه برنامه نصب می شوند و از اینترنت گرفته نمی شوند؛ اگر فایل لوگو
/// نبود، همان نشان دایره ای رنگی به عنوان جایگزین نمایش داده می شود.
class OperatorBadge extends StatelessWidget {
  const OperatorBadge({
    super.key,
    required this.operator,
    this.compact = false,
  });

  final MobileOperator operator;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final double height = compact ? 24 : 32;
    final Widget mark = operator.hasLogo
        ? Container(
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 9,
              vertical: compact ? 3 : 4,
            ),
            decoration: BoxDecoration(
              color: operator.chipColor,
              borderRadius: BorderRadius.circular(compact ? 8 : 10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Image.asset(
              operator.logoAsset,
              height: compact ? 18 : 24,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                  _FallbackMark(operator: operator, compact: compact),
            ),
          )
        : _FallbackMark(operator: operator, compact: compact);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        mark,
        if (!compact) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            Fa.num(operator.label),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: operator == MobileOperator.unknown
                      ? colors.textSecondary
                      : colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}

/// نشان جایگزین وقتی لوگوی اپراتور در دسترس نیست.
class _FallbackMark extends StatelessWidget {
  const _FallbackMark({required this.operator, required this.compact});

  final MobileOperator operator;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 24 : 30;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[
            operator.color,
            Color.lerp(operator.color, Colors.black, 0.35)!,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      alignment: Alignment.center,
      child: Text(
        operator.latin,
        style: TextStyle(
          fontSize: compact ? 8 : 9.5,
          fontWeight: FontWeight.w900,
          color: operator == MobileOperator.irancell
              ? const Color(0xFF1A1A1A)
              : Colors.white,
          fontFamily: AppTheme.fontFamily,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class StateChip {
  const StateChip({required this.image, required this.label, required this.status});

  final String image;
  final String label;
  final VpnStatus status;
}

/// گالری لوگوهای وضعیت اتصال با نام فارسی هر وضعیت.
class StateGallery extends StatelessWidget {
  const StateGallery({super.key, required this.current, this.compact = false});

  final VpnStatus current;
  final bool compact;

  static const List<StateChip> chips = <StateChip>[
    StateChip(image: BrandAssets.connected, label: 'متصل', status: VpnStatus.connected),
    StateChip(image: BrandAssets.connecting, label: 'در حال اتصال', status: VpnStatus.connecting),
    StateChip(image: BrandAssets.disconnected, label: 'قطع', status: VpnStatus.disconnected),
    StateChip(image: BrandAssets.reconnecting, label: 'اتصال دوباره', status: VpnStatus.reconnecting),
    StateChip(image: BrandAssets.switching, label: 'تغییر سرور', status: VpnStatus.switching),
    StateChip(image: BrandAssets.failed, label: 'خطا', status: VpnStatus.failed),
  ];

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final double size = compact ? 44 : 56;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        for (final StateChip chip in chips)
          Builder(
            builder: (BuildContext context) {
              final bool active = chip.status == current ||
                  (chip.status == VpnStatus.connecting &&
                      current == VpnStatus.preparing);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: compact ? 74 : 88,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active
                      ? colors.primary.withValues(alpha: 0.10)
                      : colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? colors.primary.withValues(alpha: 0.55) : colors.border,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ClipOval(
                      child: Image.asset(
                        chip.image,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        color: active ? null : Colors.white.withValues(alpha: 0.72),
                        colorBlendMode: active ? null : BlendMode.modulate,
                        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                            Icon(
                          Icons.shield_outlined,
                          size: size * 0.6,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      Fa.num(chip.label),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 9.5 : 10.5,
                        fontFamily: AppTheme.fontFamily,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active ? colors.textPrimary : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// بنر مناسبت فعال (یلدا، نوروز، چهارشنبه سوری و ...).
class OccasionBanner extends StatelessWidget {
  const OccasionBanner({super.key, required this.occasion, this.enabled = true});

  final Occasion? occasion;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (occasion == null || !enabled) {
      return const SizedBox.shrink();
    }
    final Occasion item = occasion!;
    final UmbrellaColors colors = context.colors;
    final Color tint = Color(item.tint);
    return Stack(
      children: <Widget>[
        GlassCard(
          padding: const EdgeInsets.all(18),
          radius: 20,
          borderColor: tint.withValues(alpha: 0.45),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: <Color>[
              tint.withValues(alpha: 0.22),
              colors.surface,
            ],
          ),
          child: Row(
            children: <Widget>[
              IconSquare(icon: _iconFor(item), color: tint, size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fa.num(item.title),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Fa.num(item.subtitle),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Pill(label: 'مناسبت', icon: Icons.auto_awesome_rounded, color: tint, dense: true),
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SparklePainter(color: tint),
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(Occasion item) {
    switch (item.icon) {
      case 'nightlight':
        return Icons.nightlight_round;
      case 'spa':
        return Icons.spa_rounded;
      case 'local_fire_department':
        return Icons.local_fire_department_rounded;
      case 'forest':
        return Icons.forest_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'dark_mode':
        return Icons.dark_mode_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random random = math.Random(7);
    final Paint paint = Paint()..color = color.withValues(alpha: 0.35);
    for (int i = 0; i < 14; i++) {
      final double x = random.nextDouble() * size.width;
      final double y = random.nextDouble() * size.height;
      final double radius = 0.8 + random.nextDouble() * 1.8;
      paint.color = color.withValues(alpha: 0.10 + random.nextDouble() * 0.25);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color;
}

/// نشان کوچک لوگو و نام برنامه.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 42, this.showTitle = true});

  final double size;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipOval(
          child: Image.asset(
            BrandAssets.logo,
            width: size,
            height: size,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                Icon(Icons.beach_access_rounded, size: size * 0.8, color: colors.primary),
          ),
        ),
        if (showTitle) ...<Widget>[
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fa.num('فیلترشکن آمبرلا'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                Fa.num('نسل جدید اتصال امن'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
