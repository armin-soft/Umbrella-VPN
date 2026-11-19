import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../platform/services.dart';
import '../../state/toast_controller.dart';
import '../widgets/common.dart';

/// گزارش دقیق برنامه: هر خطا، هشدار و رویداد با تاریخ شمسی و ساعت تهران.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  /// فیلتر سطح گزارش؛ خالی یعنی همه.
  String _level = '';

  /// شماره خطوطی که جزئیاتشان باز است.
  ///
  /// کلید از زمان و پیام ساخته می شود، چون فهرست با هر گزارش تازه دوباره
  /// ساخته می شود و شماره ردیف عوض می شود.
  final Set<String> _open = <String>{};

  static String _keyOf(LogLine line) =>
      '${line.time.microsecondsSinceEpoch}|${line.level}|${line.message}';

  /// فقط خطاها و هشدارها؛ برای دکمه «باز کردن همه خطاها».
  static bool _hasDetail(LogLine line) => line.hasDetails;

  static const List<(String, String)> _levels = <(String, String)>[
    ('', 'همه'),
    ('error', 'خطا'),
    ('warning', 'هشدار'),
    ('info', 'اطلاع'),
  ];

  void _toggle(String key) {
    setState(() {
      if (!_open.remove(key)) {
        _open.add(key);
      }
    });
  }

  /// متن کامل یک خط با همه جزئیاتش، برای کپی جداگانه.
  static String _detailText(LogLine line) => AppLogger.lineDetailText(line);

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final ToastController toasts = context.read<ToastController>();

    return Padding(
      padding: AppMetrics.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'گزارش ها',
            subtitle: 'همه رویدادها، خطاها و هشدارها با تاریخ و ساعت؛ برای پیگیری مشکل اتصال.',
            icon: Icons.receipt_long_rounded,
            actions: <Widget>[
              IconAction(
                icon: Icons.copy_all_rounded,
                tooltip: 'کپی همه',
                size: AppMetrics.iconButton,
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: AppLogger.instance.exportText()),
                  );
                  toasts.success('گزارش ها کپی شد');
                },
              ),
              const SizedBox(width: AppMetrics.space3),
              IconAction(
                icon: Icons.save_alt_rounded,
                tooltip: 'ذخیره فایل گزارش',
                size: AppMetrics.iconButton,
                onTap: () async {
                  final String path = await AppLogger.instance.saveToFile();
                  toasts.success('فایل گزارش ذخیره شد', path);
                },
              ),
              const SizedBox(width: AppMetrics.space3),
              // باز کردن همه خطاها با یک کلیک؛ برای وقتی که کاربر می خواهد
              // همه چیز را یک جا ببیند و بفرستد.
              ListenableBuilder(
                listenable: AppLogger.instance,
                builder: (BuildContext context, Widget? child) {
                  final List<LogLine> withDetails = AppLogger.instance.lines
                      .where(_hasDetail)
                      .toList();
                  final bool allOpen = withDetails.isNotEmpty &&
                      withDetails.every(
                        (LogLine line) => _open.contains(_keyOf(line)),
                      );
                  if (withDetails.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(left: AppMetrics.space3),
                    child: IconAction(
                      icon: allOpen
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      tooltip: allOpen
                          ? 'بستن جزئیات همه'
                          : 'باز کردن جزئیات همه خطاها '
                              '(${Fa.num(withDetails.length)})',
                      size: AppMetrics.iconButton,
                      onTap: () {
                        setState(() {
                          if (allOpen) {
                            _open.clear();
                          } else {
                            _open
                              ..clear()
                              ..addAll(withDetails.map(_keyOf));
                          }
                        });
                      },
                    ),
                  );
                },
              ),
              const SizedBox(width: AppMetrics.space3),
              IconAction(
                icon: Icons.delete_sweep_rounded,
                tooltip: 'پاک کردن',
                size: AppMetrics.iconButton,
                onTap: () {
                  AppLogger.instance.clear();
                  toasts.info('گزارش ها پاک شد');
                },
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          ListenableBuilder(
            listenable: AppLogger.instance,
            builder: (BuildContext context, Widget? child) {
              return Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final (String value, String label) item in _levels)
                    ChoiceChip(
                      label: Text(
                        Fa.num(
                          item.$1.isEmpty
                              ? item.$2
                              : '${item.$2} (${Fa.num(AppLogger.instance.countOf(item.$1))})',
                        ),
                      ),
                      selected: _level == item.$1,
                      onSelected: (_) => setState(() => _level = item.$1),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppMetrics.space3),
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space2, vertical: AppMetrics.space2),
              child: ListenableBuilder(
                listenable: AppLogger.instance,
                builder: (BuildContext context, Widget? child) {
                  final List<LogLine> all = AppLogger.instance.lines;
                  final List<LogLine> lines = _level.isEmpty
                      ? all
                      : all
                          .where((LogLine line) => line.level == _level)
                          .toList();
                  if (lines.isEmpty) {
                    return EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: all.isEmpty
                          ? 'هنوز گزارشی ثبت نشده است'
                          : 'در این سطح گزارشی نیست',
                      message: all.isEmpty
                          ? 'از لحظه اجرا، هر رویداد اتصال و خطا اینجا ثبت می شود.'
                          : 'یکی از سطح های دیگر را انتخاب کنید.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: AppMetrics.space2),
                    itemCount: lines.length,
                    itemBuilder: (BuildContext context, int index) {
                      final LogLine line = lines[index];
                      final String key = _keyOf(line);
                      final bool open = _open.contains(key);
                      final Color tone = switch (line.level) {
                        'error' => colors.danger,
                        'warning' => colors.warning,
                        _ => colors.info,
                      };
                      final String levelLabel = switch (line.level) {
                        'error' => 'خطا',
                        'warning' => 'هشدار',
                        _ => 'اطلاع',
                      };
                      final int sections = line.details
                          .where((LogDetail d) => d.text.trim().isNotEmpty)
                          .length;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppMetrics.space2,
                          horizontal: AppMetrics.space2,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      Fa.num(Fa.date(line.time)),
                                      style: TextStyle(
                                        fontFamily: AppTheme.fontFamily,
                                        fontSize: AppMetrics.fontMicro,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      Fa.clock(line.time),
                                      style: TextStyle(
                                        fontFamily: AppTheme.fontFamily,
                                        fontSize: AppMetrics.fontCaption,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: AppMetrics.space3),
                                Container(
                                  margin: const EdgeInsets.only(top: AppMetrics.space1),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppMetrics.space2,
                                    vertical: AppMetrics.space1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tone.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(AppMetrics.radiusXs),
                                  ),
                                  child: Text(
                                    Fa.num(levelLabel),
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontFamily,
                                      fontSize: AppMetrics.fontMicro,
                                      fontWeight: FontWeight.w700,
                                      color: tone,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppMetrics.space3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      SelectableText(
                                        Fa.num(line.message) +
                                            (line.repeat > 1
                                                ? '  ×${Fa.num(line.repeat)}'
                                                : ''),
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontFamily,
                                          fontSize: AppMetrics.fontSmall,
                                          height: 1.7,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      // دکمه «جزئیات کامل» فقط وقتی که واقعا
                                      // چیزی برای نشان دادن باشد.
                                      if (line.hasDetails)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: AppMetrics.space1),
                                          child: TextButton.icon(
                                            onPressed: () => _toggle(key),
                                            icon: Icon(
                                              open
                                                  ? Icons.unfold_less_rounded
                                                  : Icons.unfold_more_rounded,
                                              size: AppMetrics.iconSm,
                                            ),
                                            label: Text(
                                              Fa.num(
                                                open
                                                    ? 'بستن جزئیات'
                                                    : 'جزئیات کامل '
                                                        '(${Fa.num(sections)} بخش)',
                                              ),
                                              style: const TextStyle(
                                                fontSize: AppMetrics.fontCaption,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: AppMetrics.space2,
                                                vertical: AppMetrics.space1,
                                              ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              foregroundColor: tone,
                                            ),
                                          ),
                                        ),
                                      if (open)
                                        _DetailPanel(
                                          line: line,
                                          colors: colors,
                                          onCopy: () async {
                                            await Clipboard.setData(
                                              ClipboardData(
                                                text: _detailText(line),
                                              ),
                                            );
                                            toasts.success(
                                              'جزئیات این خطا کپی شد',
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppMetrics.space3),
          Text(
            Fa.num(
              'گزارش ها برای پشتیبانی مفید است | ${AppConfig.appName} ${AppConfig.version}',
            ),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// پنل جزئیات یک خطا: هر بخش با عنوان و متن کامل و قابل انتخاب، به اضافه
/// دکمه کپی همان بخش. کاربر نباید برای خواندن خروجی هسته به جای دیگری برود.
class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.line,
    required this.colors,
    required this.onCopy,
  });

  final LogLine line;
  final UmbrellaColors colors;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final List<LogDetail> shown = line.details
        .where((LogDetail detail) => detail.text.trim().isNotEmpty)
        .toList();
    return Container(
      margin: const EdgeInsets.only(top: AppMetrics.space2, bottom: AppMetrics.space1),
      padding: const EdgeInsets.all(AppMetrics.space3),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.bug_report_outlined, size: AppMetrics.iconSm, color: colors.textSecondary),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Text(
                  Fa.num('جزئیات کامل برای عیب یابی'),
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: AppMetrics.fontCaption,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => onCopy(),
                icon: const Icon(Icons.copy_all_rounded, size: AppMetrics.iconSm),
                label: Text(
                  Fa.num('کپی جزئیات'),
                  style: const TextStyle(fontSize: AppMetrics.fontCaption),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space2, vertical: AppMetrics.space1),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: colors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space2),
          for (final LogDetail detail in shown) ...<Widget>[
            if (detail.title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppMetrics.space3, bottom: AppMetrics.space1),
                child: Text(
                  Fa.num(detail.title),
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: AppMetrics.fontCaption,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppMetrics.space3),
              decoration: BoxDecoration(
                color: colors.background.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
              ),
              // متن خام هسته لاتین است و شماره سطر ندارد که فارسی شود؛ فقط
              // همان طور که هست، انتخاب پذیر و کامل نشان داده می شود.
              child: SelectableText(
                Fa.num(detail.text.trim()),
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: AppMetrics.fontCaption,
                  height: 1.5,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
