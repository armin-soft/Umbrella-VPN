import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/toast_controller.dart';
import '../../state/update_controller.dart';
import '../shell/app_shell.dart';
import '../widgets/common.dart';

/// به روز رسانی کاملاً درون برنامه ای در دو کانال اصلی (پایدار) و بتا (آزمایشی).
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  Timer? _autoCheckTimer;
  bool _wasTabActive = false;

  @override
  void initState() {
    super.initState();
    _autoCheckTimer = Timer.periodic(UpdateController.autoCheckInterval, (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      _checkSilently();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool active = TickerMode.of(context);
    if (active && !_wasTabActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkSilently());
    }
    _wasTabActive = active;
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  void _checkSilently() {
    if (!mounted) {
      return;
    }
    final UpdateController updates = context.read<UpdateController>();
    if (updates.checking ||
        updates.downloading ||
        updates.installing ||
        !updates.autoCheckDue) {
      return;
    }
    unawaited(updates.loadSkipped().then((_) {
      if (mounted &&
          !updates.checking &&
          !updates.downloading &&
          !updates.installing &&
          updates.autoCheckDue) {
        unawaited(updates.checkIfDue(silent: true));
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final UpdateController updates = context.watch<UpdateController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final UpdateInfo? available = updates.available;
    final bool hasUpdate = available != null;
    final bool activeTransfer = updates.downloading || updates.installing;
    final List<String> changelog =
        available?.changelogItems ?? const <String>[];

    return SingleChildScrollView(
      padding: AppMetrics.responsivePagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'به روز رسانی',
            eyebrow: 'به روز رسانی برنامه',
            premium: true,
            subtitle: Fa.num(
              'نسخه نصب شده ${AppConfig.version}  •  کانال ${updates.channel.label}'
              '${updates.lastCheckedAt != null ? '  •  آخرین بررسی ${Fa.relative(updates.lastCheckedAt)}' : ''}',
            ),
            icon: Icons.system_update_rounded,
            actions: updates.checking
                ? <Widget>[
                    Pill(
                      label: 'بررسی خودکار...',
                      color: colors.primary,
                      dense: true,
                    ),
                  ]
                : const <Widget>[],
          ),
          const SizedBox(height: AppMetrics.space4),

          // ── انتخاب کانال انتشار (اصلی / بتا) ────────────────────────────
          GlassCard(
            padding: AppMetrics.responsiveCardPadding(context),
            radius: AppMetrics.radiusXl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SectionHeader(
                  icon: Icons.tune_rounded,
                  title: 'کانال دریافت نسخه',
                  subtitle:
                      'بین انتشار اصلی پایدار و نسخه بتا انتخاب کنید؛ دانلود و نصب هر دو کاملاً داخل برنامه انجام می شود',
                ),
                const SizedBox(height: AppMetrics.space4),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Widget stableTile = _ChannelOptionCard(
                      icon: Icons.verified_rounded,
                      accent: colors.primary,
                      channel: UpdateChannel.stable,
                      selected: updates.channel == UpdateChannel.stable,
                      disabled: updates.checking || activeTransfer,
                      onTap: () => _onSelectChannel(
                        updates,
                        toasts,
                        UpdateChannel.stable,
                      ),
                    );
                    final Widget betaTile = _ChannelOptionCard(
                      icon: Icons.science_rounded,
                      accent: colors.info,
                      channel: UpdateChannel.beta,
                      selected: updates.channel == UpdateChannel.beta,
                      disabled: updates.checking || activeTransfer,
                      onTap: () => _onSelectChannel(
                        updates,
                        toasts,
                        UpdateChannel.beta,
                      ),
                    );
                    if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) >= AppMetrics.breakpointCompact) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(child: stableTile),
                            const SizedBox(width: AppMetrics.space3),
                            Expanded(child: betaTile),
                          ],
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        stableTile,
                        const SizedBox(height: AppMetrics.space3),
                        betaTile,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          if (updates.error.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppMetrics.space4),
            GlassCard(
              padding: const EdgeInsets.all(AppMetrics.space4),
              radius: AppMetrics.radiusLg,
              borderColor: colors.danger.withValues(alpha: 0.5),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.danger,
                  ),
                  const SizedBox(width: AppMetrics.space3),
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

          // ── کارت دانلود و نصب درون برنامه ای ────────────────────────────
          if (hasUpdate) ...<Widget>[
            const SizedBox(height: AppMetrics.space4),
            GlassCard(
              padding: AppMetrics.responsiveCardPadding(context),
              radius: AppMetrics.radiusXl,
              borderColor: (available.preRelease ? colors.info : colors.primary)
                  .withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SectionHeader(
                    icon: Icons.download_for_offline_rounded,
                    title: Fa.num('دانلود و نصب نسخه ${available.version}'),
                    subtitle: available.publishedAt != null
                        ? Fa.num(
                            'انتشار در ${Fa.tehranDate(available.publishedAt)}  •  دریافت و نصب درون برنامه ای',
                          )
                        : 'دانلود مستقیم، بررسی اصالت فایل و نصب خودکار در برنامه',
                    trailing: Pill(
                      label: available.preRelease ? 'نسخه بتا' : 'انتشار اصلی',
                      color:
                          available.preRelease ? colors.info : colors.success,
                      dense: true,
                    ),
                  ),
                  if (changelog.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppMetrics.space4),
                    Container(
                      padding: const EdgeInsets.all(AppMetrics.space4),
                      decoration: BoxDecoration(
                        color: colors.surfaceHigh.withValues(alpha: 0.45),
                        borderRadius:
                            BorderRadius.circular(AppMetrics.radiusLg),
                        border: Border.all(color: colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'تغییرات این نسخه',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: AppMetrics.space2),
                          for (final String line in changelog)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppMetrics.space1,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '•  ',
                                    style: TextStyle(color: colors.primary),
                                  ),
                                  Expanded(
                                    child: Text(
                                      Fa.num(line),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colors.textSecondary,
                                            height: 1.6,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (activeTransfer) ...<Widget>[
                    const SizedBox(height: AppMetrics.space4),
                    ProgressLine(
                      value: updates.progress,
                      label: _progressLabel(updates),
                    ),
                  ],
                  const SizedBox(height: AppMetrics.space4),
                  Wrap(
                    spacing: AppMetrics.space3,
                    runSpacing: AppMetrics.space2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: AppMetrics.buttonMaxWidth,
                        child: GradientButton(
                          label: updates.installing
                              ? 'در حال نصب خودکار...'
                              : (updates.downloading
                                  ? Fa.num(
                                      'دریافت ${Fa.percent(updates.progress * 100)}',
                                    )
                                  : 'دانلود و نصب در برنامه'),
                          icon: Icons.system_update_alt_rounded,
                          loading: activeTransfer,
                          height: AppMetrics.controlHeightSmall,
                          onPressed: activeTransfer
                              ? null
                              : () async {
                                  final bool ok =
                                      await updates.downloadAndInstall();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  if (ok) {
                                    toasts.success(
                                      'نصب نسخه جدید آغاز شد',
                                      'بسته به روز رسانی برای نصب در سیستم آماده و باز شد.',
                                    );
                                  } else if (updates.error.isNotEmpty) {
                                    toasts.error(
                                      'به روز رسانی انجام نشد',
                                      updates.error,
                                    );
                                  }
                                },
                        ),
                      ),
                      if (updates.downloading && !updates.installing)
                        SizedBox(
                          height: AppMetrics.controlHeightSmall,
                          child: OutlinedButton.icon(
                            onPressed: withUiClick(context, updates.cancelDownload),
                            icon: const Icon(
                              Icons.close_rounded,
                              size: AppMetrics.iconSm,
                            ),
                            label: const Text('لغو دانلود'),
                          ),
                        )
                      else if (!activeTransfer && !available.mandatory)
                        SizedBox(
                          height: AppMetrics.controlHeightSmall,
                          child: OutlinedButton.icon(
                            onPressed: withUiClick(context, updates.skipCurrent),
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              size: AppMetrics.iconSm,
                            ),
                            label: const Text('نادیده گرفتن این نسخه'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppMetrics.space4),

          // ── تاریخچه انتشارها ───────────────────────────────────────────
          GlassCard(
            padding: AppMetrics.responsiveCardPadding(context),
            radius: AppMetrics.radiusXl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SectionHeader(
                  icon: Icons.history_rounded,
                  title: 'تاریخچه نسخه ها',
                  subtitle: updates.releases.isEmpty
                      ? 'اطلاعات نسخه فعال روی این دستگاه'
                      : Fa.num(
                          'آخرین انتشارهای کانال ${updates.channel.label}',
                        ),
                ),
                const SizedBox(height: AppMetrics.space3),
                if (updates.releases.isEmpty)
                  _VersionRow(
                    version: AppConfig.version,
                    date: 'نسخه فعلی',
                    notes:
                        'هسته به روز شده با مصرف پردازنده کمتر، کنترل محتوای همگام با ربات، کانال پایدار و بتا و نصب درون برنامه ای.',
                    current: true,
                    preRelease: false,
                  )
                else
                  for (final UpdateInfo item in updates.releases.take(6))
                    _VersionRow(
                      version: item.version,
                      date: item.publishedAt != null
                          ? Fa.tehranDate(item.publishedAt)
                          : (item.preRelease ? 'انتشار بتا' : 'انتشار رسمی'),
                      notes: item.changelogItems.isNotEmpty
                          ? item.changelogItems.take(3).join(' · ')
                          : 'بهبود پایداری اتصال، سرعت هسته و رفع خطاها.',
                      current: item.isCurrentVersion,
                      preRelease: item.preRelease,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _progressLabel(UpdateController updates) {
    final String sizeText = updates.total > 0
        ? '${Fa.bytes(updates.received)} از ${Fa.bytes(updates.total)}'
        : Fa.bytes(updates.received);
    final String speedText = updates.speedBytesPerSec > 0
        ? '  •  ${Fa.speed(updates.speedBytesPerSec.toDouble())}'
        : '';
    return Fa.num('${updates.phase}  |  $sizeText$speedText');
  }

  Future<void> _onSelectChannel(
    UpdateController updates,
    ToastController toasts,
    UpdateChannel next,
  ) async {
    if (updates.channel == next) {
      return;
    }
    await updates.setChannel(next);
    if (!mounted) {
      return;
    }
    if (updates.available != null) {
      toasts.info(
        Fa.num('نسخه ${updates.available!.version} آماده است'),
        'کانال ${next.label}',
      );
    } else if (updates.error.isEmpty) {
      toasts.success('کانال ${next.label} فعال شد');
    }
  }
}

class _ChannelOptionCard extends StatelessWidget {
  const _ChannelOptionCard({
    required this.icon,
    required this.accent,
    required this.channel,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final UpdateChannel channel;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Opacity(
      opacity: disabled ? 0.65 : 1,
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : colors.surfaceHigh.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          onTap: disabled ? null : withUiClick(context, onTap),
          child: Container(
            padding: const EdgeInsets.all(AppMetrics.space4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
              border: Border.all(
                color: selected ? accent : colors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                IconSquare(
                  icon: icon,
                  color: selected ? accent : colors.textSecondary,
                  size: AppMetrics.iconBoxMd,
                  radius: AppMetrics.radiusMd,
                ),
                const SizedBox(width: AppMetrics.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              Fa.num('کانال ${channel.label}'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: colors.textPrimary,
                                  ),
                            ),
                          ),
                          if (selected) ...<Widget>[
                            const SizedBox(width: AppMetrics.space2),
                            Pill(label: 'فعال', color: accent, dense: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        Fa.num(channel.subtitle),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.55,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppMetrics.space2),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: AppMetrics.iconMd,
                  color: selected ? accent : colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.date,
    required this.notes,
    this.current = false,
    this.preRelease = false,
  });

  final String version;
  final String date;
  final String notes;
  final bool current;
  final bool preRelease;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppMetrics.space4),
      margin: const EdgeInsets.only(bottom: AppMetrics.space3),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(
          color: current
              ? colors.primary.withValues(alpha: 0.4)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppMetrics.space2,
              runSpacing: AppMetrics.space1,
              children: <Widget>[
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppMetrics.space2,
                  runSpacing: AppMetrics.space1,
                  children: <Widget>[
                    Text(
                      Fa.num('نسخه $version'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Pill(
                      label: preRelease ? 'بتا' : 'پایدار',
                      color: preRelease ? colors.info : colors.success,
                      dense: true,
                    ),
                    if (current)
                      Pill(label: 'نصب شده', color: colors.primary, dense: true),
                  ],
                ),
                Text(
                  Fa.num(date),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppMetrics.space2),
          Text(
            Fa.num(notes),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.65,
                ),
          ),
        ],
      ),
    );
  }
}
