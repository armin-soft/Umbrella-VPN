import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/security_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// نشان همیشه فعال وضعیت سپر امنیتی آمبرلا در نوار بالای صفحات اتصال و تنظیمات.
class SecurityStatusBadge extends StatelessWidget {
  const SecurityStatusBadge({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final SecurityScannerController? security =
        context.maybeWatch<SecurityScannerController>();
    if (security == null) {
      return const SizedBox.shrink();
    }
    final UmbrellaColors colors = context.colors;
    final bool danger = security.hasThreats;
    final bool scanning = security.scanning && !security.hasCompletedInitialScan;
    final Color fg = danger
        ? colors.danger
        : (scanning ? colors.primary : colors.success);
    final Color bg = danger
        ? colors.danger.withValues(alpha: 0.14)
        : (scanning ? colors.primarySoft : colors.success.withValues(alpha: 0.14));

    return Tooltip(
      message: danger
          ? 'تهدید یا فیلترشکن ناسازگار شناسایی شد؛ برای حذف ضربه بزنید'
          : 'سپر امنیتی آمبرلا همیشه فعال است؛ برای اسکن و جزئیات ضربه بزنید',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey<String>('security-status-badge'),
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            playUiClick(context);
            unawaited(SecurityShieldDialog.show(context));
          },
          child: Ink(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 8 : 10,
              vertical: dense ? 4 : 5,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: fg.withValues(alpha: 0.42)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (scanning || security.remediating)
                  SizedBox(
                    width: dense ? 11 : 13,
                    height: dense ? 11 : 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: fg,
                    ),
                  )
                else
                  Icon(
                    danger
                        ? Icons.gpp_bad_rounded
                        : Icons.verified_user_rounded,
                    size: dense ? 13 : 15,
                    color: fg,
                  ),
                SizedBox(width: dense ? 4 : 6),
                Flexible(
                  child: Text(
                    security.shortBadgeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 10.5 : 11.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// پنجره سپر امنیتی آمبرلا در اندروید: نمایش نتیجه اسکن بلادرنگ، مسدودیت ها و حذف یا توقف تهدیدها.
class SecurityShieldDialog extends StatelessWidget {
  const SecurityShieldDialog({super.key});

  static bool _isOpen = false;

  static Future<void> show(BuildContext context) async {
    if (_isOpen || !context.mounted) return;
    _isOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => const SecurityShieldDialog(),
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final SecurityScannerController? security =
        context.maybeWatch<SecurityScannerController>();
    final ToastController? toasts = context.maybeRead<ToastController>();
    final UmbrellaColors colors = context.colors;
    final bool danger = security?.hasThreats ?? false;
    final Color accent = danger ? colors.danger : colors.success;
    final SecurityScanResult report =
        security?.lastResult ?? const SecurityScanResult();

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: danger ? colors.danger.withValues(alpha: 0.45) : colors.border,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: danger
                          ? colors.danger.withValues(alpha: 0.14)
                          : colors.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      danger
                          ? Icons.gpp_bad_rounded
                          : Icons.verified_user_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'سپر امنیتی همیشه فعال آمبرلا',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          danger
                              ? 'برای امنیت اتصال، اجرای هم زمان بدافزارها و فیلترشکن های ناسازگار مسدود است.'
                              : 'دستگاه در برابر بدافزارها، JumpJump و فیلترشکن های ناسازگار (مانند Psiphon) ایمن است.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'بستن',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  _StatChip(
                    icon: Icons.apps_rounded,
                    label: 'برنامه های بررسی شده: ${Fa.num(report.scannedApps)}',
                  ),
                  _StatChip(
                    icon: Icons.folder_open_rounded,
                    label: 'فایل های بررسی شده: ${Fa.num(report.scannedFiles)}',
                  ),
                ],
              ),
              if (security != null && security.lastMessage.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    Fa.num(security.lastMessage),
                    style: TextStyle(fontSize: 12, color: colors.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: !danger
                    ? Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.shield_rounded,
                                size: 48,
                                color: colors.success,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'هیچ بدافزار یا وی پی ان ناسازگاری یافت نشد',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'پایش لحظه ای برنامه های نصب شده و تونل های فعال دستگاه به طور خودکار در پس زمینه فعال است.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: report.threats.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext ctx, int index) {
                          final SecurityThreat item = report.threats[index];
                          final String btnLabel =
                              item.remediationKind == 'vpn_settings'
                                  ? 'باز کردن تنظیمات VPN سیستم'
                                  : (item.packageName.isNotEmpty
                                      ? 'حذف برنامه از دستگاه'
                                      : 'حذف فوری فایل');
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.danger.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: colors.danger.withValues(alpha: 0.42),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Icon(
                                      item.isConflictingVpn
                                          ? Icons.vpn_lock_rounded
                                          : Icons.bug_report_rounded,
                                      size: 18,
                                      color: colors.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.danger.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item.categoryLabelFa,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: colors.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.detail,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                if (item.target.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 6),
                                  Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Text(
                                      item.target,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontFamily: 'monospace',
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: FilledButton.icon(
                                    key: ValueKey<String>(
                                      'security-remediate-${item.key}',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colors.danger,
                                      foregroundColor: colors.onPrimary,
                                    ),
                                    icon: Icon(
                                      item.remediationKind == 'vpn_settings'
                                          ? Icons.settings_ethernet_rounded
                                          : Icons.delete_forever_rounded,
                                      size: 16,
                                    ),
                                    label: Text(btnLabel),
                                    onPressed: security == null ||
                                            security.remediating
                                        ? null
                                        : () async {
                                            final RemediationResult res =
                                                await security.remediateThreat(
                                              item,
                                            );
                                            if (toasts != null) {
                                              if (res.ok) {
                                                toasts.success(
                                                  'تهدید برطرف شد',
                                                  res.message,
                                                );
                                              } else {
                                                toasts.warning(
                                                  'تکمیل حذف در سیستم عامل',
                                                  res.message,
                                                );
                                              }
                                            }
                                          },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const ValueKey<String>('security-rescan-button'),
                    icon: const Icon(Icons.radar_rounded, size: 16),
                    label: Text(
                      security?.scanning ?? false
                          ? 'در حال اسکن...'
                          : 'اسکن فوری',
                    ),
                    onPressed: security == null || security.scanning
                        ? null
                        : () => security.scanNow(silent: false),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (danger && security != null) ...<Widget>[
                        FilledButton.icon(
                          key: const ValueKey<String>(
                            'security-remediate-all-button',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.danger,
                            foregroundColor: colors.onPrimary,
                          ),
                          icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                          label: const Text('پاکسازی همه'),
                          onPressed: security.remediating
                              ? null
                              : () async {
                                  final SecurityScanResult after =
                                      await security.remediateAll();
                                  if (toasts != null) {
                                    if (after.clean) {
                                      toasts.success(
                                        'دستگاه پاکسازی شد',
                                        'اکنون می توانید با خیال راحت به آمبرلا متصل شوید.',
                                      );
                                    } else {
                                      toasts.warning(
                                        'نیاز به تایید حذف',
                                        security.lastMessage,
                                      );
                                    }
                                  }
                                },
                        ),
                        const SizedBox(width: 8),
                      ],
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('بستن'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
