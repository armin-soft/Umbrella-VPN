import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../platform/services.dart';
import '../../platform/encrypted_report.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
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
  bool _exporting = false;

  /// شماره خطوطی که جزئیاتشان باز است.
  ///
  /// کلید از زمان و پیام ساخته می شود، چون فهرست با هر گزارش تازه دوباره
  /// ساخته می شود و شماره ردیف عوض می شود.
  final Set<String> _open = <String>{};

  static String _keyOf(LogLine line) =>
      '${line.time.microsecondsSinceEpoch}|${line.level}|${line.message}';

  /// فقط خطاها و هشدارها؛ برای دکمه «باز کردن همه خطاها».
  static bool _hasDetail(LogLine line) => line.hasDetails;

  static const List<(String, String, IconData)> _levels =
      <(String, String, IconData)>[
    ('', 'همه', Icons.list_alt_rounded),
    ('error', 'خطا', Icons.error_outline_rounded),
    ('warning', 'هشدار', Icons.warning_amber_rounded),
    ('info', 'اطلاع', Icons.info_outline_rounded),
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

  Future<void> _exportEncrypted(ToastController toasts) async {
    if (_exporting) return;
    final String? password = await showDialog<String>(
      context: context, builder: (_) => const _ReportPasswordDialog(),
    );
    if (password == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final String path = await EncryptedReport.save(AppLogger.instance.exportText(), password);
      toasts.success('گزارش رمزگذاری شده ذخیره شد', path);
    } catch (_) {
      toasts.error('ذخیره گزارش رمزگذاری شده ناموفق بود', 'فضای ذخیره و رمز را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final ToastController toasts = context.read<ToastController>();

    final Widget headingAndFilters = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
          PageHeader(
            title: 'گزارش ها',
            eyebrow: 'گزارش و عیب یابی',
            premium: true,
            subtitle: 'گزارش اتصال، حساب، پرداخت، تنظیمات و به روز رسانی با تاریخ و ساعت.',
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
              IconAction(
                icon: Icons.save_alt_rounded,
                tooltip: 'ذخیره فایل گزارش',
                size: AppMetrics.iconButton,
                onTap: () async {
                  final String path = await AppLogger.instance.saveToFile();
                  toasts.success('فایل گزارش ذخیره شد', path);
                },
              ),
              IconAction(
                icon: Icons.lock_outline_rounded,
                tooltip: _exporting ? 'در حال رمزگذاری' : 'ذخیره گزارش رمزگذاری شده',
                size: AppMetrics.iconButton,
                onTap: () => _exportEncrypted(toasts),
              ),
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
                  return IconAction(
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
                  );
                },
              ),
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
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space2,
                children: <Widget>[
                  for (final (String value, String label, IconData icon) item
                      in _levels)
                    ChoiceChip(
                      avatar: Icon(
                        item.$3,
                        size: AppMetrics.iconSm,
                        color: _level == item.$1
                            ? colors.primary
                            : colors.textSecondary,
                      ),
                      label: Text(
                        Fa.num(
                          item.$1.isEmpty
                              ? item.$2
                              : '${item.$2} (${Fa.num(AppLogger.instance.countOf(item.$1))})',
                        ),
                      ),
                      selected: _level == item.$1,
                      onSelected: (_) {
                        playUiClick(context);
                        setState(() => _level = item.$1);
                      },
                    ),
                  const _DiagnosticSessionChip(),
                ],
              );
            },
          ),
      ],
    );
    return Padding(
      padding: AppMetrics.responsivePagePadding(context),
      child: LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
        final compactHeight = constraints.maxHeight < 500 * scale;
        return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (compactHeight)
            Flexible(child: SingleChildScrollView(child: headingAndFilters))
          else
            headingAndFilters,
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
                    return SingleChildScrollView(
                      child: EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: all.isEmpty
                          ? 'هنوز گزارشی ثبت نشده است'
                          : 'در این سطح گزارشی نیست',
                      message: all.isEmpty
                          ? 'از زمان اجرای برنامه، گزارش های اتصال و خطاهای ثبت شده سایر بخش ها اینجا نمایش داده می شوند.'
                          : 'یکی از سطح های دیگر را انتخاب کنید.',
                      ),
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
                      final Widget badge = Container(
                        margin: const EdgeInsets.only(top: AppMetrics.space1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppMetrics.space2,
                          vertical: AppMetrics.space1,
                        ),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.14),
                          borderRadius:
                              BorderRadius.circular(AppMetrics.radiusXs),
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
                      );
                      final Widget messageBody = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                onPressed: withUiClick(context, () => _toggle(key)),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppMetrics.space2,
                                    vertical: AppMetrics.space1,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
                      );
                      final bool compactLogRow = constraints.maxWidth < 460;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppMetrics.space2,
                          horizontal: AppMetrics.space2,
                        ),
                        child: compactLogRow
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      badge,
                                      const SizedBox(width: AppMetrics.space2),
                                      Expanded(
                                        child: Text(
                                          '${Fa.num(Fa.date(line.time))} • ${Fa.clock(line.time)}',
                                          style: TextStyle(
                                            fontFamily: AppTheme.fontFamily,
                                            fontSize: AppMetrics.fontCaption,
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppMetrics.space1),
                                  messageBody,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                  badge,
                                  const SizedBox(width: AppMetrics.space3),
                                  Expanded(child: messageBody),
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
        );
      }),
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
                onPressed: withUiClick(context, () => onCopy()),
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

/// کلید حالت عیب یابی ۱۰ دقیقه ای با شمارش معکوس زنده و بازگشت خودکار.
class _DiagnosticSessionChip extends StatefulWidget {
  const _DiagnosticSessionChip();

  @override
  State<_DiagnosticSessionChip> createState() => _DiagnosticSessionChipState();
}

class _DiagnosticSessionChipState extends State<_DiagnosticSessionChip> {
  Timer? _tick;

  SettingsController? _maybeSettings(BuildContext context) {
    try {
      return Provider.of<SettingsController>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  VpnController? _maybeVpn(BuildContext context) {
    try {
      return context.read<VpnController>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _syncTicker(bool active) {
    if (active && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsController? settings = _maybeSettings(context);
    if (settings == null) {
      return const SizedBox.shrink();
    }
    final UmbrellaColors colors = context.colors;
    final bool active = settings.diagnosticActive;
    _syncTicker(active);
    final Duration remaining = settings.diagnosticRemaining;
    final String label = active
        ? 'عیب یابی فعال · ${Fa.duration(remaining)}'
        : 'عیب یابی ۱۰ دقیقه ای';
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxLabelWidth =
            (constraints.maxWidth - 76).clamp(100.0, 320.0);
        return ActionChip(
          key: const ValueKey<String>('logs-diagnostic-session-chip'),
          avatar: Icon(
            active ? Icons.bug_report_rounded : Icons.troubleshoot_rounded,
            size: AppMetrics.iconSm,
            color: active ? colors.primary : colors.textSecondary,
          ),
          label: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                Fa.num(label),
                maxLines: 1,
              ),
            ),
          ),
          backgroundColor: active ? colors.primarySoft : null,
          side: BorderSide(color: active ? colors.primary : colors.border),
          onPressed: () async {
            playUiClick(context);
            final VpnController? vpn = _maybeVpn(context);
            if (active) {
              await settings.stopDiagnosticSession();
              AppLogger.instance.add('حالت عیب یابی متوقف شد و سطح گزارش به حالت عادی بازگشت.');
            } else {
              await settings.startDiagnosticSession();
              AppLogger.instance.add('حالت گزارش عیب یابی برای ۱۰ دقیقه فعال شد.');
            }
            vpn?.scheduleLiveReload();
          },
        );
      },
    );
  }
}

/// A password is never persisted, copied, displayed in reports or sent.
class _ReportPasswordDialog extends StatefulWidget {
  const _ReportPasswordDialog();
  @override
  State<_ReportPasswordDialog> createState() => _ReportPasswordDialogState();
}

class _ReportPasswordDialogState extends State<_ReportPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('گزارش رمزگذاری شده'),
    content: SizedBox(
      width: AppMetrics.dialogMaxWidth,
      child: SingleChildScrollView(child: Form(key: _form, child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('فقط گزارش فعلی برنامه ذخیره می شود؛ فایل های خام هسته و پروفایل ها ضمیمه نمی شوند. فایل خودکار ارسال نمی شود. رمز را جداگانه و امن به پشتیبانی بدهید؛ بدون آن بازیابی ممکن نیست.'),
          const SizedBox(height: AppMetrics.space4),
          TextFormField(controller: _password, obscureText: true, autocorrect: false,
            enableSuggestions: false, maxLength: 128,
            decoration: const InputDecoration(labelText: 'رمز گزارش (حداقل ۱۲ نویسه)'),
            validator: (value) => (value ?? '').runes.length < 12 ? 'رمز باید حداقل ۱۲ نویسه باشد.' : null),
          TextFormField(controller: _confirmation, obscureText: true, autocorrect: false,
            enableSuggestions: false, maxLength: 128,
            decoration: const InputDecoration(labelText: 'تکرار رمز'),
            validator: (value) => value != _password.text ? 'رمزها یکسان نیستند.' : null),
        ],
      ))),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: withUiClick(context, () => Navigator.pop(context)),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: withUiClick(context, () {
          if (_form.currentState?.validate() ?? false) Navigator.pop(context, _password.text);
        }),
        child: const Text('رمزگذاری و ذخیره'),
      ),
    ],
  );
}
