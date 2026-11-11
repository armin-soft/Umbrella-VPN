import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';

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
    (Icons.lock_rounded, 'تونل کامل ویندوز', 'همه ترافیک دستگاه از تونل امن عبور می کند، نه فقط مرورگر.'),
    (Icons.hub_rounded, 'پنج هسته اتصال', 'ایکس ری، کلش متا، وایرگارد، آمنزیا و میرو در یک برنامه.'),
    (Icons.speed_rounded, 'انتخاب خودکار سرور', 'پایدارترین سرور با کمترین پینگ، خودکار انتخاب می شود.'),
    (Icons.security_rounded, 'کیل سوییچ واقعی', 'اگر تونل قطع شود، اینترنت شما متوقف می شود تا داده لو نرود.'),
    (Icons.palette_rounded, 'رابط فارسی و راست چین', 'تم تاریک و روشن، ارقام فارسی و طراحی نسل جدید.'),
    (Icons.support_agent_rounded, 'پشتیبانی و حساب کاربری', 'مصرف، اعتبار و تمدید حساب در همان برنامه.'),
  ];

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.75, -0.85),
                  radius: 1.4,
                  colors: <Color>[
                    colors.primary.withValues(alpha: 0.22),
                    colors.background,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _CircuitPainter(color: colors.primary)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 32),
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
                          const BrandMark(size: 62),
                          const SizedBox(height: 30),
                          Text(
                            Fa.num('اینترنت آزاد،\nبا اتصالی که دوام می آورد.'),
                            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontSize: 42,
                                  height: 1.35,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            Fa.num(
                              'فیلترشکن آمبرلا با هسته های نسل جدید، تونل کامل ویندوز و انتخاب هوشمند سرور، اتصال پایدار و امن می سازد.',
                            ),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.9,
                                ),
                          ),
                          const SizedBox(height: 34),
                          Row(
                            children: <Widget>[
                              SizedBox(
                                width: 240,
                                child: GradientButton(
                                  label: 'شروع',
                                  icon: Icons.arrow_back_rounded,
                                  onPressed: widget.onStart,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Pill(
                                label: 'نسخه ۱٫۰٫۰',
                                icon: Icons.verified_rounded,
                                color: colors.success,
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
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
                  const SizedBox(width: 56),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: Column(
                        children: <Widget>[
                          for (final (IconData icon, String title, String subtitle) item
                              in _features)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassCard(
                                padding: const EdgeInsets.all(16),
                                radius: 18,
                                child: Row(
                                  children: <Widget>[
                                    IconSquare(icon: item.$1, color: colors.primary, size: 40),
                                    const SizedBox(width: 14),
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
                                          const SizedBox(height: 3),
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
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                Fa.num('${AppConfig.company} | همه حقوق محفوظ است'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary.withValues(alpha: 0.7),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  _CircuitPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random random = math.Random(11);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color.withValues(alpha: 0.10);
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
  bool shouldRepaint(covariant _CircuitPainter old) => old.color != color;
}
