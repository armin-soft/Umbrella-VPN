import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
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

  static const List<(String, String)> _levels = <(String, String)>[
    ('', 'همه'),
    ('error', 'خطا'),
    ('warning', 'هشدار'),
    ('info', 'اطلاع'),
  ];

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final ToastController toasts = context.read<ToastController>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fa.num('گزارش ها'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fa.num(
                        'همه رویدادها، خطاها و هشدارها با تاریخ و ساعت؛ برای پیگیری مشکل اتصال.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              IconAction(
                icon: Icons.copy_all_rounded,
                tooltip: 'کپی همه',
                size: 42,
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: AppLogger.instance.exportText()),
                  );
                  toasts.success('گزارش ها کپی شد');
                },
              ),
              const SizedBox(width: 10),
              IconAction(
                icon: Icons.save_alt_rounded,
                tooltip: 'ذخیره فایل گزارش',
                size: 42,
                onTap: () async {
                  final String path = await AppLogger.instance.saveToFile();
                  toasts.success('فایل گزارش ذخیره شد', path);
                },
              ),
              const SizedBox(width: 10),
              IconAction(
                icon: Icons.delete_sweep_rounded,
                tooltip: 'پاک کردن',
                size: 42,
                onTap: () {
                  AppLogger.instance.clear();
                  toasts.info('گزارش ها پاک شد');
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 12),
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: lines.length,
                    itemBuilder: (BuildContext context, int index) {
                      final LogLine line = lines[index];
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
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  Fa.num(Fa.date(line.time)),
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    fontSize: 10,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                Text(
                                  Fa.clock(line.time),
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tone.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                Fa.num(levelLabel),
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: tone,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                Fa.num(line.message) +
                                    (line.repeat > 1
                                        ? '  ×${Fa.num(line.repeat)}'
                                        : ''),
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: 12,
                                  height: 1.7,
                                  color: colors.textPrimary,
                                ),
                              ),
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
          const SizedBox(height: 12),
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
