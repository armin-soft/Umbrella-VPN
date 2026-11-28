import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/safe_url_launcher.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/toast_controller.dart';
import '../../state/update_controller.dart';
import 'common.dart';

enum ShareTargetPlatform { android, windows }

/// پنجره یکسان اشتراک گذاری برنامه: نمایش بارکد (QR) و لینک مستقیم دانلود
/// برای نسخه های اندروید و ویندوز با امکان کپی فوری و باز کردن لینک.
class ShareAppDialog extends StatefulWidget {
  const ShareAppDialog({
    super.key,
    this.initialPlatform = ShareTargetPlatform.windows,
  });

  final ShareTargetPlatform initialPlatform;

  static Future<void> show(
    BuildContext context, {
    ShareTargetPlatform initialPlatform = ShareTargetPlatform.windows,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          ShareAppDialog(initialPlatform: initialPlatform),
    );
  }

  static String resolveShareVersion(UpdateController? updates) {
    String best = AppConfig.version;
    if (updates == null) {
      return best;
    }
    final List<UpdateInfo> candidates = <UpdateInfo>[
      if (updates.available != null) updates.available!,
      ...updates.releases,
    ];
    for (final UpdateInfo item in candidates) {
      if (item.preRelease || item.version.trim().isEmpty) {
        continue;
      }
      if (UpdateInfo.compareVersions(item.version, best) > 0) {
        best = item.version.trim();
      }
    }
    return best;
  }

  static String directUrlFor(
    ShareTargetPlatform platform, {
    UpdateController? updates,
  }) {
    final String version = resolveShareVersion(updates);
    return switch (platform) {
      ShareTargetPlatform.android => AppConfig.directAndroidDownloadUrl(version),
      ShareTargetPlatform.windows => AppConfig.directWindowsDownloadUrl(version),
    };
  }

  static String fileNameFor(
    ShareTargetPlatform platform, {
    UpdateController? updates,
  }) {
    final String version = resolveShareVersion(updates);
    return switch (platform) {
      ShareTargetPlatform.android => 'UmbrellaVPN-$version-universal.apk',
      ShareTargetPlatform.windows => 'UmbrellaVPN-Setup-$version-x64.exe',
    };
  }

  @override
  State<ShareAppDialog> createState() => _ShareAppDialogState();
}

class _ShareAppDialogState extends State<ShareAppDialog> {
  late ShareTargetPlatform _platform;
  bool _copied = false;
  Timer? _copiedResetTimer;

  @override
  void initState() {
    super.initState();
    _platform = widget.initialPlatform;
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  T? _readOptional<T>(BuildContext context, {bool listen = false}) {
    try {
      return Provider.of<T>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    _copiedResetTimer?.cancel();
    setState(() => _copied = true);
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
    _readOptional<ToastController>(context)?.success(
      'لینک مستقیم دانلود کپی شد',
      'می توانید لینک را برای دوستان خود ارسال کنید.',
    );
  }

  Future<void> _openLink(String url) async {
    final bool opened = await SafeUrlLauncher.open(url);
    if (!mounted) {
      return;
    }
    if (!opened) {
      _readOptional<ToastController>(context)?.error(
        'باز کردن لینک انجام نشد',
        'لینک را کپی کرده و در مرورگر باز کنید.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final UpdateController? updates =
        _readOptional<UpdateController>(context, listen: true);
    final String shareVersion = ShareAppDialog.resolveShareVersion(updates);
    final String directUrl =
        ShareAppDialog.directUrlFor(_platform, updates: updates);
    final String fileName =
        ShareAppDialog.fileNameFor(_platform, updates: updates);
    final String platformLabel =
        _platform == ShareTargetPlatform.android ? 'اندروید' : 'ویندوز';

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusXxl),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMetrics.qrDialogWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.space5,
            AppMetrics.space5,
            AppMetrics.space5,
            AppMetrics.space4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconSquare(
                    icon: Icons.share_rounded,
                    color: colors.primary,
                    size: AppMetrics.iconBoxSm,
                    radius: AppMetrics.radiusSm,
                  ),
                  const SizedBox(width: AppMetrics.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'اشتراک گذاری برنامه',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          'بارکد و لینک مستقیم دانلود نسخه رسمی',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconAction(
                    icon: Icons.close_rounded,
                    tooltip: 'بستن',
                    size: AppMetrics.iconBoxSm,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppMetrics.space4),
              _SharePlatformSwitch(
                platform: _platform,
                onChanged: (ShareTargetPlatform next) {
                  if (_platform == next) {
                    return;
                  }
                  setState(() {
                    _platform = next;
                    _copied = false;
                  });
                },
              ),
              const SizedBox(height: AppMetrics.space4),
              _AppQrBox(
                data: directUrl,
                colors: colors,
              ),
              const SizedBox(height: AppMetrics.space3),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppMetrics.space1,
                runSpacing: AppMetrics.space1,
                children: <Widget>[
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    size: AppMetrics.iconXs,
                    color: colors.textSecondary,
                  ),
                  Text(
                    Fa.num(
                      'اسکن بارکد برای دانلود مستقیم نسخه $platformLabel ($shareVersion)',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppMetrics.space4),
              Material(
                key: const ValueKey<String>('share-app-direct-link-card'),
                color: colors.surfaceHigh.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  onTap: withUiClick(context, () => _copyLink(directUrl)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppMetrics.space3,
                      vertical: AppMetrics.space3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                      border: Border.all(
                        color: _copied ? colors.success : colors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              _copied ? Icons.check_rounded : Icons.link_rounded,
                              size: AppMetrics.iconXs,
                              color:
                                  _copied ? colors.success : colors.textSecondary,
                            ),
                            const SizedBox(width: AppMetrics.space1),
                            Expanded(
                              child: Text(
                                _copied
                                    ? 'لینک مستقیم کپی شد'
                                    : Fa.num('لینک مستقیم دانلود · $fileName'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: _copied
                                          ? colors.success
                                          : colors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppMetrics.space2),
                        Text(
                          directUrl,
                          textDirection: TextDirection.ltr,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppMetrics.space4),
              Wrap(
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space2,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  FilledButton.icon(
                    key: const ValueKey<String>('share-app-copy-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _copied ? colors.success : colors.primary,
                      foregroundColor: colors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppMetrics.space4,
                        vertical: AppMetrics.space2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppMetrics.radiusPill),
                      ),
                    ),
                    onPressed:
                        withUiClick(context, () => _copyLink(directUrl)),
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: AppMetrics.iconXs,
                    ),
                    label: Text(_copied ? 'کپی شد' : 'کپی لینک'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('share-app-open-button'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppMetrics.space3,
                        vertical: AppMetrics.space2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppMetrics.radiusPill),
                      ),
                    ),
                    onPressed:
                        withUiClick(context, () => _openLink(directUrl)),
                    icon: const Icon(
                      Icons.open_in_new_rounded,
                      size: AppMetrics.iconXs,
                    ),
                    label: const Text('باز کردن لینک'),
                  ),
                  TextButton.icon(
                    onPressed:
                        withUiClick(context, () => Navigator.of(context).pop()),
                    icon: Icon(
                      Icons.check_rounded,
                      size: AppMetrics.iconSm,
                      color: colors.primary,
                    ),
                    label: Text(
                      'بستن',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
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

class _SharePlatformSwitch extends StatelessWidget {
  const _SharePlatformSwitch({
    required this.platform,
    required this.onChanged,
  });

  final ShareTargetPlatform platform;
  final ValueChanged<ShareTargetPlatform> onChanged;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          _tab(
            context,
            colors,
            key: const ValueKey<String>('share-platform-android'),
            icon: Icons.android_rounded,
            label: 'اندروید',
            active: platform == ShareTargetPlatform.android,
            onTap: () => onChanged(ShareTargetPlatform.android),
          ),
          _tab(
            context,
            colors,
            key: const ValueKey<String>('share-platform-windows'),
            icon: Icons.laptop_windows_rounded,
            label: 'ویندوز',
            active: platform == ShareTargetPlatform.windows,
            onTap: () => onChanged(ShareTargetPlatform.windows),
          ),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    UmbrellaColors colors, {
    required Key key,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final Color fg = active ? colors.primary : colors.textSecondary;
    return Expanded(
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        onTap: withUiClick(context, onTap),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppMetrics.space2),
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: AppMetrics.iconXs, color: fg),
              const SizedBox(width: AppMetrics.space1),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    Fa.num(label),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: fg,
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppQrBox extends StatelessWidget {
  const _AppQrBox({
    required this.data,
    required this.colors,
  });

  final String data;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const ValueKey<String>('share-app-qr-box'),
        width: AppMetrics.qrCodeSize,
        height: AppMetrics.qrCodeSize,
        padding: const EdgeInsets.all(AppMetrics.space3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          border: Border.all(color: colors.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            QrImageView(
              data: data,
              padding: EdgeInsets.zero,
              errorCorrectionLevel: QrErrorCorrectLevel.Q,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: colors.primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleStyle.square,
                color: Color(0xFF151822),
              ),
            ),
            Container(
              width: AppMetrics.controlHeightSmall,
              height: AppMetrics.controlHeightSmall,
              padding: const EdgeInsets.all(AppMetrics.space1),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white),
              ),
              child: ClipOval(
                child: Image.asset(
                  BrandAssets.logo,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stack,
                  ) =>
                      Icon(
                    Icons.shield_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
