import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/malicious_link_guard.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/security_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// لوگوی رسمی سپر امنیتی آمبرلا (هم سبک با سایر لوگوهای برند).
class SecurityShieldLogo extends StatelessWidget {
  const SecurityShieldLogo({
    super.key,
    required this.danger,
    required this.size,
  });

  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return ClipOval(
      child: TickerMode(
        enabled: true,
        child: Image.asset(
          danger ? BrandAssets.securityAlert : BrandAssets.securityShield,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stack,
          ) =>
              Container(
            width: size,
            height: size,
            color: danger
                ? colors.danger.withValues(alpha: 0.14)
                : colors.success.withValues(alpha: 0.14),
            child: Icon(
              danger ? Icons.gpp_bad_rounded : Icons.verified_user_rounded,
              size: size * 0.6,
              color: danger ? colors.danger : colors.success,
            ),
          ),
        ),
      ),
    );
  }
}

/// نشان همیشه فعال وضعیت سپر امنیتی آمبرلا در نوار بالای صفحات اتصال و تنظیمات.
class SecurityStatusBadge extends StatelessWidget {
  const SecurityStatusBadge({super.key});

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
          ? 'تهدید امنیتی شناسایی شد؛ برای مشاهده و حذف کلیک کنید'
          : 'سپر امنیتی همیشه فعال است؛ برای اسکن یا بررسی لینک کلیک کنید',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey<String>('security-status-badge'),
          borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          onTap: () {
            playUiClick(context);
            unawaited(SecurityShieldDialog.show(context));
          },
          child: Ink(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.space3,
              vertical: AppMetrics.space1,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
              border: Border.all(color: fg.withValues(alpha: 0.42)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (scanning || security.remediating)
                  SizedBox(
                    width: AppMetrics.iconXs,
                    height: AppMetrics.iconXs,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: fg,
                    ),
                  )
                else
                  SecurityShieldLogo(
                    danger: danger,
                    size: AppMetrics.iconMd,
                  ),
                const SizedBox(width: AppMetrics.space2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      security.shortBadgeLabel,
                      style: TextStyle(
                        fontSize: AppMetrics.fontSmall,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
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

/// پنجره مدیریت سپر امنیتی همیشه فعال، بررسی لینک، حذف فایل های دانلودی آلوده و برنامه های ناسازگار.
class SecurityShieldDialog extends StatefulWidget {
  const SecurityShieldDialog({super.key});

  static bool _isOpen = false;

  static Future<void> show(BuildContext context) async {
    if (_isOpen) return;
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
  State<SecurityShieldDialog> createState() => _SecurityShieldDialogState();
}

class _SecurityShieldDialogState extends State<SecurityShieldDialog> {
  final TextEditingController _linkController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _checkLink(
    SecurityScannerController? security,
    ToastController? toasts,
  ) async {
    final String raw = _linkController.text.trim();
    if (raw.isEmpty || security == null) return;
    final MaliciousLinkMatch? hit = await security.inspectAndBlockUrl(raw);
    if (!mounted) return;
    if (hit == null) {
      toasts?.success('لینک سالم است', 'الگوی تروجانی یا فیشینگ در این نشانی یافت نشد.');
    } else {
      toasts?.error('لینک تروجانی مسدود شد', hit.detail);
      _linkController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SecurityScannerController? security =
        context.maybeWatch<SecurityScannerController>();
    final ToastController? toasts = context.maybeRead<ToastController>();
    final UmbrellaColors c = context.colors;
    final bool danger = security?.hasThreats ?? false;
    final SecurityScanResult report =
        security?.lastResult ?? const SecurityScanResult();
    final List<NeutralizedSecurityEvent> neutralized =
        security?.neutralizedEvents ?? const <NeutralizedSecurityEvent>[];

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
        side: BorderSide(
          color: danger ? c.danger.withValues(alpha: 0.45) : c.border,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppMetrics.dialogMaxWidth,
          maxHeight: AppMetrics.dialogMaxHeight,
        ),
        child: Padding(
          padding: AppMetrics.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SecurityShieldLogo(
                    danger: danger,
                    size: AppMetrics.iconBoxLg,
                  ),
                  const SizedBox(width: AppMetrics.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'سپر امنیتی همیشه فعال آمبرلا',
                          style: TextStyle(
                            fontSize: AppMetrics.fontEmphasis,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppMetrics.space1),
                        Text(
                          danger
                              ? 'برای امنیت اتصال، اجرای هم زمان بدافزارها و فیلترشکن های ناسازگار مسدود است.'
                              : 'دستگاه در برابر بدافزارها (JumpJump)، فایل های آلوده و فیلترشکن های ناسازگار ایمن است.',
                          style: TextStyle(
                            fontSize: AppMetrics.fontSmall,
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
              const SizedBox(height: AppMetrics.space3),
              Wrap(
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space2,
                children: <Widget>[
                  _StatChip(
                    icon: Icons.memory_rounded,
                    label:
                        'پردازش های اسکن شده: ${Fa.num(report.scannedProcesses)}',
                  ),
                  _StatChip(
                    icon: Icons.apps_rounded,
                    label:
                        'برنامه های بررسی شده: ${Fa.num(report.scannedApps)}',
                  ),
                  _StatChip(
                    icon: Icons.folder_open_rounded,
                    label:
                        'فایل ها و تصاویر بررسی شده: ${Fa.num(report.scannedFiles)}',
                  ),
                ],
              ),
              if (security != null && security.lastMessage.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppMetrics.space3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.space3,
                    vertical: AppMetrics.space2,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    Fa.num(security.lastMessage),
                    style: TextStyle(
                      fontSize: AppMetrics.fontSmall,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppMetrics.space3),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (danger) ...<Widget>[
                        for (final SecurityThreat item in report.threats) ...<Widget>[
                          _ThreatCard(
                            item: item,
                            security: security,
                            toasts: toasts,
                          ),
                          const SizedBox(height: AppMetrics.space2),
                        ],
                      ],
                      Container(
                        padding: const EdgeInsets.all(AppMetrics.space3),
                        decoration: BoxDecoration(
                          color: c.surfaceHigh,
                          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              'بررسی امنیتی لینک پیش از باز کردن',
                              style: TextStyle(
                                fontSize: AppMetrics.fontSmall,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppMetrics.space2),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    key: const ValueKey<String>(
                                      'security-link-input',
                                    ),
                                    controller: _linkController,
                                    textDirection: TextDirection.ltr,
                                    decoration: const InputDecoration(
                                      hintText: 'https://example.com/...',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: AppMetrics.space3,
                                        vertical: AppMetrics.space2,
                                      ),
                                    ),
                                    onSubmitted: (_) =>
                                        unawaited(_checkLink(security, toasts)),
                                  ),
                                ),
                                const SizedBox(width: AppMetrics.space2),
                                FilledButton.icon(
                                  key: const ValueKey<String>(
                                    'security-check-link-button',
                                  ),
                                  icon: const Icon(
                                    Icons.link_rounded,
                                    size: AppMetrics.iconSm,
                                  ),
                                  label: const Text('بررسی لینک'),
                                  onPressed: security == null
                                      ? null
                                      : () => _checkLink(security, toasts),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppMetrics.space3),
                      if (!danger)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppMetrics.space3,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const SecurityShieldLogo(
                                danger: false,
                                size: AppMetrics.logoLg,
                              ),
                              const SizedBox(height: AppMetrics.space3),
                              Text(
                                'هیچ بدافزار یا وی پی ان ناسازگاری یافت نشد',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: AppMetrics.fontButton,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: AppMetrics.space2),
                              Text(
                                'پایش لحظه ای لینک های تروجانی، فایل های دانلودی و تصاویر آلوده به طور خودکار در پس زمینه فعال است.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: AppMetrics.fontSmall,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (neutralized.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppMetrics.space2),
                        Text(
                          'موارد حذف یا مسدودشده اخیر (ارسال شده به تلگرام)',
                          style: TextStyle(
                            fontSize: AppMetrics.fontSmall,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppMetrics.space2),
                        for (final NeutralizedSecurityEvent ev in neutralized.take(6)) ...<Widget>[
                          _NeutralizedCard(event: ev),
                          const SizedBox(height: AppMetrics.space2),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppMetrics.space3),
              Wrap(
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space2,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const ValueKey<String>('security-rescan-button'),
                    icon: const Icon(Icons.radar_rounded, size: AppMetrics.iconSm),
                    label: Text(
                      security?.scanning ?? false
                          ? 'در حال اسکن...'
                          : 'اسکن فوری اکنون',
                    ),
                    onPressed: security == null || security.scanning
                        ? null
                        : () => security.scanNow(silent: false),
                  ),
                  if (danger && security != null)
                    FilledButton.icon(
                      key: const ValueKey<String>('security-remediate-all-button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.danger,
                        foregroundColor: c.onPrimary,
                      ),
                      icon: const Icon(
                        Icons.cleaning_services_rounded,
                        size: AppMetrics.iconSm,
                      ),
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

class _ThreatCard extends StatelessWidget {
  const _ThreatCard({
    required this.item,
    required this.security,
    required this.toasts,
  });

  final SecurityThreat item;
  final SecurityScannerController? security;
  final ToastController? toasts;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppMetrics.space3),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
        border: Border.all(color: c.danger.withValues(alpha: 0.42)),
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
                size: AppMetrics.iconMd,
                color: c.danger,
              ),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: AppMetrics.fontBody,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppMetrics.space2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.space2,
                  vertical: AppMetrics.space1,
                ),
                decoration: BoxDecoration(
                  color: c.danger.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                ),
                child: Text(
                  item.categoryLabelFa,
                  style: TextStyle(
                    fontSize: AppMetrics.fontCaption,
                    fontWeight: FontWeight.w700,
                    color: c.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space2),
          Text(
            item.detail,
            style: TextStyle(
              fontSize: AppMetrics.fontSmall,
              color: c.textSecondary,
            ),
          ),
          if (item.target.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppMetrics.space2),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                item.target,
                style: TextStyle(
                  fontSize: AppMetrics.fontCaption,
                  fontFamily: 'monospace',
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppMetrics.space3),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: ValueKey<String>('security-remediate-${item.key}'),
              style: FilledButton.styleFrom(
                backgroundColor: c.danger,
                foregroundColor: c.onPrimary,
              ),
              icon: const Icon(
                Icons.delete_forever_rounded,
                size: AppMetrics.iconSm,
              ),
              label: Text(
                item.uninstallCmd.isNotEmpty
                    ? 'توقف و حذف برنامه'
                    : 'توقف و حذف فوری',
              ),
              onPressed: security == null || security!.remediating
                  ? null
                  : () async {
                      final RemediationResult res =
                          await security!.remediateThreat(item);
                      if (toasts != null) {
                        if (res.ok) {
                          toasts!.success('تهدید برطرف شد', res.message);
                        } else {
                          toasts!.warning(
                            'پاکسازی نیاز به تکمیل دارد',
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
  }
}

class _NeutralizedCard extends StatelessWidget {
  const _NeutralizedCard({required this.event});

  final NeutralizedSecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppMetrics.space3),
      decoration: BoxDecoration(
        color: c.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: c.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                event.action == 'blocked_connection'
                    ? Icons.link_off_rounded
                    : Icons.delete_sweep_rounded,
                size: AppMetrics.iconSm,
                color: c.success,
              ),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Text(
                  event.name,
                  style: TextStyle(
                    fontSize: AppMetrics.fontSmall,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.space2,
                  vertical: AppMetrics.space1,
                ),
                decoration: BoxDecoration(
                  color: c.success.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                ),
                child: Text(
                  event.actionLabelFa,
                  style: TextStyle(
                    fontSize: AppMetrics.fontCaption,
                    fontWeight: FontWeight.w700,
                    color: c.success,
                  ),
                ),
              ),
            ],
          ),
          if (event.target.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppMetrics.space1),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                event.target,
                style: TextStyle(
                  fontSize: AppMetrics.fontCaption,
                  fontFamily: 'monospace',
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ],
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space3,
        vertical: AppMetrics.space1,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: AppMetrics.iconXs, color: c.textSecondary),
          const SizedBox(width: AppMetrics.space2),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppMetrics.fontSmall,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
