import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../state/toast_controller.dart';
import '../../state/update_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';

/// به روز رسانی برنامه با دانلود مستقیم و درصد پیشرفت.
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final UpdateController updates = context.read<UpdateController>();
      updates.loadSkipped().then((_) => updates.check(silent: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    final UpdateController updates = context.watch<UpdateController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final bool hasUpdate = updates.available != null;

    return SingleChildScrollView(
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
                      Fa.num('به روز رسانی'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fa.num('نسخه فعلی ${AppConfig.version} | آخرین بررسی در همین صفحه'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              GradientButton(
                label: updates.checking ? 'در حال بررسی' : 'بررسی نسخه جدید',
                icon: Icons.system_update_rounded,
                expand: false,
                height: 46,
                loading: updates.checking,
                onPressed: onPressedUpdate(updates, toasts),
              ),
            ],
          ),
          const SizedBox(height: 18),
          GlassCard(
            padding: const EdgeInsets.all(24),
            radius: 24,
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                (hasUpdate ? colors.warning : colors.success).withValues(alpha: 0.14),
                colors.surface,
              ],
            ),
            child: Row(
              children: <Widget>[
                const BrandMark(size: 72, showTitle: false),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            Fa.num(hasUpdate
                                ? 'نسخه ${updates.available!.version} آماده نصب است'
                                : 'برنامه به روز است'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(width: 10),
                          Pill(
                            label: hasUpdate ? 'جدید' : 'آخرین نسخه',
                            color: hasUpdate ? colors.warning : colors.success,
                            icon: hasUpdate
                                ? Icons.new_releases_rounded
                                : Icons.check_circle_rounded,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Fa.num(
                          hasUpdate
                              ? (updates.available!.notes.isNotEmpty
                                  ? updates.available!.notes
                                  : 'بهبود پایداری اتصال، رفع خطاها و سرعت بیشتر.')
                              : 'در حال حاضر نسخه جدیدی برای ویندوز منتشر نشده است.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.8,
                            ),
                      ),
                      if (hasUpdate) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          Fa.num(
                            'حجم بسته: ${updates.available!.sizeBytes > 0 ? Fa.bytes(updates.available!.sizeBytes) : 'نامشخص'}',
                          ),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (updates.error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: colors.danger.withValues(alpha: 0.5),
              child: Row(
                children: <Widget>[
                  Icon(Icons.error_outline_rounded, size: 18, color: colors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Fa.num(updates.error),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textPrimary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasUpdate) ...<Widget>[
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(
                    title: 'دانلود و نصب',
                    subtitle: 'دانلود مستقیم از داخل برنامه با نمایش درصد و بررسی سلامت فایل',
                    trailing: Pill(
                      label: updates.downloading ? 'در حال دانلود' : 'آماده',
                      color: updates.downloading ? colors.info : colors.textSecondary,
                      dense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (updates.downloading || updates.installing)
                    ProgressLine(
                      value: updates.progress,
                      label:
                          '${updates.phase} | ${Fa.bytes(updates.received)} از ${Fa.bytes(updates.total)}',
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 260,
                        child: GradientButton(
                          label: updates.downloading
                              ? 'در حال دانلود...'
                              : 'دانلود و نصب به روز رسانی',
                          icon: Icons.download_rounded,
                          loading: updates.downloading || updates.installing,
                          onPressed: updates.downloading
                              ? null
                              : () async {
                                  final bool ok = await updates.downloadAndInstall();
                                  if (ok) {
                                    toasts.success('نصب کننده اجرا شد');
                                    await Future<void>.delayed(
                                      const Duration(seconds: 2),
                                    );
                                  } else if (updates.error.isNotEmpty) {
                                    toasts.error('به روز رسانی انجام نشد', updates.error);
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: updates.skipCurrent,
                        icon: const Icon(Icons.skip_next_rounded, size: 18),
                        label: const Text('این نسخه را رد کن'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(title: 'تاریخچه نسخه ها'),
                const SizedBox(height: 12),
                _VersionRow(
                  version: '۱٫۰٫۰',
                  date: 'انتشار اولیه',
                  notes: 'تونل کامل ویندوز، پنج هسته اتصال، کیل سوییچ، ورود پیامکی و تایید تلگرام، رابط فارسی راست چین.',
                  current: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  VoidCallback? onPressedUpdate(
    UpdateController updates,
    ToastController toasts,
  ) {
    if (updates.checking) {
      return null;
    }
    return () async {
      final bool found = await updates.check();
      if (found) {
        toasts.info('نسخه جدید پیدا شد', updates.available!.version);
      } else {
        toasts.success('برنامه به روز است');
      }
    };
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.date,
    required this.notes,
    this.current = false,
  });

  final String version;
  final String date;
  final String notes;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current ? colors.primary.withValues(alpha: 0.4) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                Fa.num('نسخه $version'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 8),
              if (current)
                Pill(label: 'نصب شده', color: colors.primary, dense: true),
              const Spacer(),
              Text(
                Fa.num(date),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Fa.num(notes),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.8,
                ),
          ),
        ],
      ),
    );
  }
}
