import 'package:flutter/material.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';

/// پرچم کشورها به صورت تصویر واقعی (assets/flags/<code>.png) با نام فارسی.
class FlagView extends StatelessWidget {
  const FlagView({
    super.key,
    required this.code,
    this.width = AppMetrics.flagWidth,
    this.radius = AppMetrics.radiusXs,
  });

  final String code;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String normalized = code.trim().toLowerCase();
    if (normalized.length != 2) {
      return SizedBox(width: width, height: width * 0.72);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: width * 0.72,
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: TickerMode(
          enabled: true,
          child: Image.asset(
            'assets/flags/$normalized.png',
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                Center(
              child: Icon(
                Icons.public_rounded,
                size: width * 0.52,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// پرچم به همراه نام کشور به فارسی.
class FlagLabel extends StatelessWidget {
  const FlagLabel({
    super.key,
    required this.code,
    this.showName = true,
    this.width = AppMetrics.flagWidth,
  });

  final String code;
  final bool showName;
  final double width;

  @override
  Widget build(BuildContext context) {
    final String name = CountryNames.fa(code);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FlagView(code: code, width: width),
        if (showName && name.isNotEmpty) ...<Widget>[
          const SizedBox(width: AppMetrics.space2),
          Text(
            Fa.num(name),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// نام فارسی کشورها برای نمایش کنار پرچم.
class CountryNames {
  const CountryNames._();

  static String fa(String code) => countryNameFa(code);
}
