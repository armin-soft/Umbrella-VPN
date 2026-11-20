import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../platform/services.dart';
import '../../state/settings_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';
import '../widgets/shell_widgets.dart';

/// صفحه معرفی که فقط یک بار در اولین اجرا نمایش داده می شود.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const List<(IconData, String, String)> _features = <(IconData, String, String)>[
    (Icons.lock_rounded, 'حالت تونل ویندوز', 'امکان استفاده از تونل یا پروکسی سیستمی بر اساس تنظیمات اتصال.'),
    (Icons.hub_rounded, 'هسته اتصال آمبرلا', 'اتصال با هسته همراه برنامه و تنظیمات شبکه قابل انتخاب.'),
    (Icons.speed_rounded, 'انتخاب خودکار سرور', 'پایدارترین سرور با کمترین پینگ، خودکار انتخاب می شود.'),
    (Icons.security_rounded, 'پایش اتصال', 'وضعیت تونل و مسیر اتصال به صورت دوره ای بررسی می شود.'),
    (Icons.palette_rounded, 'رابط فارسی و راست چین', 'تم تاریک و روشن، ارقام فارسی و طراحی نسل جدید.'),
    (Icons.support_agent_rounded, 'پشتیبانی و حساب کاربری', 'مصرف، اعتبار و تمدید حساب در همان برنامه.'),
  ];

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final SettingsController settings = context.watch<SettingsController>();
    final WindowService window = context.read<WindowService>();
    final Brightness brightness = Theme.of(context).brightness;
    final bool isDark = brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: <Widget>[
          TitleBar(
            onDragStart: window.startDragging,
            onMinimize: window.minimize,
            onMaximize: window.toggleMaximize,
            onClose: window.quit,
            onToggleTheme: () => settings.toggleTheme(
              effectiveBrightness: brightness,
            ),
            darkTheme: isDark,
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.75, -0.85),
                  radius: 1.4,
                  colors: <Color>[
                    colors.primary.withValues(alpha: isDark ? 0.22 : 0.11),
                    colors.background,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _CircuitPainter(
                color: colors.primary,
                opacity: isDark ? 0.10 : 0.08,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space10, vertical: AppMetrics.space8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: FadeTransition(
                      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const BrandMark(size: AppMetrics.logoMd),
                          const SizedBox(height: AppMetrics.space8),
                          Text(
                            Fa.num('اینترنت آزاد،\nبا اتصالی که دوام می آورد.'),
                            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontSize: AppMetrics.fontHero,
                                  height: 1.35,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: AppMetrics.space5),
                          Text(
                            Fa.num(
                              'فیلترشکن آمبرلا با هسته های نسل جدید، تونل کامل ویندوز و انتخاب هوشمند سرور، اتصال پایدار و امن می سازد.',
                            ),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.9,
                                ),
                          ),
                          const SizedBox(height: AppMetrics.space8),
                          Row(
                            children: <Widget>[
                              SizedBox(
                                width: AppMetrics.buttonMaxWidth,
                                child: GradientButton(
                                  label: 'شروع',
                                  icon: Icons.arrow_back_rounded,
                                  onPressed: widget.onStart,
                                ),
                              ),
                              const SizedBox(width: AppMetrics.space4),
                              Pill(
                                label: Fa.num('نسخه ${AppConfig.versionLabel}'),
                                icon: Icons.verified_rounded,
                                color: colors.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppMetrics.space6),
                          Text(
                            Fa.num('ویندوز ۱۰ و ۱۱ نسخه ۶۴ بیت | اجرا با دسترسی مدیر'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppMetrics.space10),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: Column(
                        children: <Widget>[
                          for (final (IconData icon, String title, String subtitle) item
                              in _features)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppMetrics.space3),
                              child: GlassCard(
                                padding: const EdgeInsets.all(AppMetrics.space4),
                                radius: AppMetrics.radiusLg,
                                child: Row(
                                  children: <Widget>[
                                    IconSquare(icon: item.$1, color: colors.primary, size: AppMetrics.iconBoxLg),
                                    const SizedBox(width: AppMetrics.space4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            Fa.num(item.$2),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(fontWeight: FontWeight.w800),
                                          ),
                                          const SizedBox(height: AppMetrics.space1),
                                          Text(
                                            Fa.num(item.$3),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(color: colors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  _CircuitPainter({required this.color, this.opacity = 0.10});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random random = math.Random(11);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color.withValues(alpha: opacity);
    for (int i = 0; i < 18; i++) {
      final Offset start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final Path path = Path()..moveTo(start.dx, start.dy);
      double x = start.dx;
      double y = start.dy;
      for (int step = 0; step < 4; step++) {
        if (random.nextBool()) {
          x += (random.nextDouble() - 0.5) * 180;
        } else {
          y += (random.nextDouble() - 0.5) * 180;
        }
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
      canvas.drawCircle(start, 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter old) =>
      old.color != color || old.opacity != opacity;
}
