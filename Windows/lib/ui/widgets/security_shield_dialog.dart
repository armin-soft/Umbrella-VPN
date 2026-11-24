import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/security_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// نشان همیشه فعال وضعیت سپر امنیتی آمبرلا در نوار بالای صفحات اتصال و تنظیمات.
class SecurityStatusBadge extends StatelessWidget {
  const SecurityStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final SecurityScannerController? security =
        context.watch<SecurityScannerController?>();
    if (security == null) {
      return const SizedBox.shrink();
    }
    final UmbrellaColors c = context.colors;
    final bool danger = security.hasThreats;
    final bool scanning = security.scanning && !security.hasCompletedInitialScan;
    final Color fg = danger
        ? c.danger
        : (scanning ? c.primary : c.success);
    final Color bg = danger
        ? c.danger.withValues(alpha: 0.14)
        : (scanning ? c.primarySoft : c.success.withValues(alpha: 0.14));

    return Tooltip(
      message: danger
          ? 'تهدید یا فیلترشکن ناسازگار شناسایی شد؛ برای حذف کلیک کنید'
          : 'سپر امنیتی آمبرلا همیشه فعال است؛ برای اسکن و جزئیات کلیک کنید',
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                    width: 13,
                    height: 13,
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
                    size: 15,
                    color: fg,
                  ),
                const SizedBox(width: 6),
                Text(
                  security.shortBadgeLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
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

/// پنجره سپر امنیتی آمبرلا: نمایش نتیجه اسکن بلادرنگ، مسدودیت ها و حذف یا توقف تهدیدها.
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
        context.watch<SecurityScannerController?>();
    final ToastController? toasts = context.read<ToastController?>();
    final UmbrellaColors c = context.colors;
    final bool danger = security?.hasThreats ?? false;
    final Color accent = danger ? c.danger : c.success;
    final SecurityScanResult report =
        security?.lastResult ?? const SecurityScanResult();

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: danger ? c.danger.withValues(alpha: 0.45) : c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: danger
                          ? c.danger.withValues(alpha: 0.14)
                          : c.success.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      danger
                          ? Icons.gpp_bad_rounded
                          : Icons.verified_user_rounded,
                      color: accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'سپر امنیتی همیشه فعال آمبرلا',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          danger
                              ? 'برای امنیت اتصال، اجرای هم زمان بدافزارها و فیلترشکن های ناسازگار مسدود است.'
                              : 'دستگاه در برابر بدافزارها، JumpJump و فیلترشکن های ناسازگار (مانند Psiphon) ایمن است.',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
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
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _StatChip(
                    icon: Icons.memory_rounded,
                    label: 'پردازش های اسکن شده: ${Fa.num(report.scannedProcesses)}',
                  ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    Fa.num(security.lastMessage),
                    style: TextStyle(fontSize: 12, color: c.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: !danger
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.shield_rounded,
                              size: 52,
                              color: c.success,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'هیچ بدافزار یا وی پی ان ناسازگاری یافت نشد',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'پایش لحظه ای پردازش ها، استارتاپ و پوشه های سیستم به طور خودکار در پس زمینه فعال است.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: report.threats.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext ctx, int index) {
                          final SecurityThreat item = report.threats[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: c.danger.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: c.danger.withValues(alpha: 0.42),
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
                                      color: c.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.danger.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item.categoryLabelFa,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: c.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.detail,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textSecondary,
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
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    FilledButton.icon(
                                      key: ValueKey<String>(
                                        'security-remediate-${item.key}',
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: c.danger,
                                        foregroundColor: c.onPrimary,
                                      ),
                                      icon: const Icon(
                                        Icons.delete_forever_rounded,
                                        size: 17,
                                      ),
                                      label: Text(
                                        item.uninstallCmd.isNotEmpty
                                            ? 'توقف و حذف برنامه'
                                            : 'توقف و حذف فوری',
                                      ),
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
                                                    'پاکسازی نیاز به تکمیل دارد',
                                                    res.message,
                                                  );
                                                }
                                              }
                                            },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const ValueKey<String>('security-rescan-button'),
                    icon: const Icon(Icons.radar_rounded, size: 17),
                    label: Text(
                      security?.scanning ?? false
                          ? 'در حال اسکن...'
                          : 'اسکن فوری اکنون',
                    ),
                    onPressed: security == null || security.scanning
                        ? null
                        : () => security.scanNow(silent: false),
                  ),
                  const Spacer(),
                  if (danger && security != null) ...<Widget>[
                    FilledButton.icon(
                      key: const ValueKey<String>('security-remediate-all-button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.danger,
                        foregroundColor: c.onPrimary,
                      ),
                      icon: const Icon(Icons.cleaning_services_rounded, size: 17),
                      label: const Text('پاکسازی همه موارد'),
                      onPressed: security.remediating
                          ? null
                          : () async {
                              final SecurityScanResult after =
                                  await security.remediateAll();
                              if (toasts != null) {
                                if (after.clean) {
                                  toasts.success(
                                    'سیستم پاکسازی شد',
                                    'اکنون می توانید با خیال راحت به آمبرلا متصل شوید.',
                                  );
                                } else {
                                  toasts.warning(
                                    'برخی موارد باقی ماندند',
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
    final UmbrellaColors c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: c.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
