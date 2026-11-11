import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../platform/services.dart';
import '../widgets/common.dart';

/// گزارش زنده برنامه برای عیب یابی اتصال.
class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
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
                      Fa.num('رویدادهای اتصال، هسته ها و شبکه'),
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
                  final String text = AppLogger.instance.lines
                      .map(
                        (LogLine line) =>
                            '${line.time.toIso8601String()} | ${line.level} | ${line.message}',
                      )
                      .join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                },
              ),
              const SizedBox(width: 10),
              IconAction(
                icon: Icons.delete_sweep_rounded,
                tooltip: 'پاک کردن',
                size: 42,
                onTap: AppLogger.instance.clear,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: ListenableBuilder(
                listenable: AppLogger.instance,
                builder: (BuildContext context, Widget? child) {
                  final List<LogLine> lines = AppLogger.instance.lines;
                  if (lines.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'هنوز گزارشی ثبت نشده است',
                      message: 'پس از اتصال، رویدادها اینجا نمایش داده می شوند.',
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
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              Fa.num(Fa.clock(line.time)),
                              style: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tone,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                Fa.num(line.message),
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
              'این گزارش ها برای پشتیبانی مفید است | ${AppConfig.appName} ${AppConfig.version}',
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
