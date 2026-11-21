import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';

/// ساعت زنده با تاریخ شمسی.
///
/// پیش از این صفحه اتصال یک تاریخ ثابت از لحظه ساخت ویجت نشان می داد و ساعت
/// اصلا دیده نمی شد؛ کاربر خواست «تاریخ و ساعت زنده» باشد. این ویجت هر ثانیه
/// خودش را تازه می کند و در لحظه پنهان شدن صفحه تایمر را می بندد تا وقتی
/// پنجره کوچک است پردازنده بی دلیل بیدار نشود.
class LiveClock extends StatefulWidget {
  const LiveClock({
    super.key,
    this.compact = false,
    this.showDate = true,
    this.alignment = CrossAxisAlignment.start,
  });

  /// فقط ساعت، بدون تاریخ (برای نوار بالا).
  final bool compact;
  final bool showDate;
  final CrossAxisAlignment alignment;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _start();
  }

  void _start() {
    _timer?.cancel();
    // هر ثانیه، دقیقا روی مرز ثانیه، تا عقربه «بی دلیل» نلرزد.
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        return;
      }
      final DateTime next = DateTime.now();
      // اگر ویندوز دفتر را خواباند یا برنامه معلق شد، یک بار دیگر زمان
      // درست را بخوان تا ساعت عقب نماند.
      if (next.second != _now.second || next.difference(_now).inMinutes.abs() > 1) {
        setState(() => _now = next);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // وقتی پنجره کوچک یا پنهان است، تایمر لازم نیست.
    final bool visible = TickerMode.of(context);
    if (visible) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    if (widget.compact) {
      return Text(
        Fa.num(Fa.clock(_now)),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
      );
    }
    return Column(
      crossAxisAlignment: widget.alignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.schedule_rounded,
              size: AppMetrics.iconXs,
              color: colors.textSecondary,
            ),
            const SizedBox(width: AppMetrics.space1),
            Text(
              Fa.num(Fa.clock(_now)),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
            ),
          ],
        ),
        if (widget.showDate) ...<Widget>[
          const SizedBox(height: AppMetrics.space1),
          Text(
            Fa.num(Fa.fullDate(_now)),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ],
    );
  }
}

/// لیبل تاریخ کامل و ساعت زنده در یک خط: «یکشنبه ۲۴ آذر ۱۴۰۵ — ۱۲:۳۶:۰۱».
class LiveDateTimeLine extends StatelessWidget {
  const LiveDateTimeLine({super.key, this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return _LiveLine(style: style ?? Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: colors.textSecondary));
  }
}

class _LiveLine extends StatefulWidget {
  const _LiveLine({this.style});

  final TextStyle? style;

  @override
  State<_LiveLine> createState() => _LiveLineState();
}

class _LiveLineState extends State<_LiveLine> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      Fa.num(Fa.fullDateTime(_now)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}
