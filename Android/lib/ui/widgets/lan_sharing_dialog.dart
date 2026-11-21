import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../core/ui_formatters.dart';
import '../../models/models.dart';
import '../../state/settings_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import 'common.dart';

/// پنجره اشتراک گذاری اتصال (کد QR، نشانی IP شبکه محلی، ویرایش پورت، مدیریت
/// رمز پروکسی و کپی لینک کامل یا لینک تلگرام).
class LanSharingDialog extends StatefulWidget {
  const LanSharingDialog({super.key, this.initialOtherDevices = true});

  final bool initialOtherDevices;

  static Future<void> show(
    BuildContext context, {
    bool initialOtherDevices = true,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          LanSharingDialog(initialOtherDevices: initialOtherDevices),
    );
  }

  /// ویرایش، ساخت رمز تصادفی یا حذف رمز پروکسی.
  static Future<void> editPassword(
    BuildContext context,
    SettingsController settings,
    VpnController vpn,
  ) async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _PasswordEditorDialog(
        initialSecret: settings.settings.lanSharingPassword,
      ),
    );
    if (result == null || !context.mounted) {
      return;
    }
    if (result == settings.settings.lanSharingPassword) {
      return;
    }
    await settings.setLanSharingPassword(result);
    vpn.scheduleLiveReload();
  }

  @override
  State<LanSharingDialog> createState() => _LanSharingDialogState();
}

class _LanSharingDialogState extends State<LanSharingDialog> {
  late bool _otherDevices;
  bool _loadingIp = true;
  List<String> _lanIps = const <String>[];
  int _selectedIpIndex = 0;
  bool _showPassword = false;
  String? _copiedField;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _otherDevices = widget.initialOtherDevices;
    unawaited(_loadLanIps());
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLanIps() async {
    final VpnController vpn = context.read<VpnController>();
    final List<String> ips = await LanSharing.detectLanIps(
      fallbackIp: vpn.device.localIp,
    ).timeout(
      const Duration(seconds: 6),
      onTimeout: () => const <String>[],
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _lanIps = ips;
      _selectedIpIndex = 0;
      _loadingIp = false;
    });
  }

  void _copyValue(String field, String value) {
    Clipboard.setData(ClipboardData(text: value));
    _copiedTimer?.cancel();
    setState(() => _copiedField = field);
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _copiedField = null);
      }
    });
  }

  Future<void> _editPort({
    required int currentPort,
    required int forbiddenPort,
    required Future<void> Function(int) onSave,
    required VpnController vpn,
  }) async {
    final int? next = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => _PortEditorDialog(
        initialPort: currentPort,
        forbiddenPort: forbiddenPort,
      ),
    );
    if (next == null || next == currentPort || !mounted) {
      return;
    }
    try {
      await onSave(next);
      vpn.scheduleLiveReload();
    } on FormatException catch (error) {
      if (mounted) {
        context.read<ToastController>().error(error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final SettingsController settings = context.watch<SettingsController>();
    final VpnController vpn = context.read<VpnController>();
    final AppSettings cfg = settings.settings;
    final bool isVpnMode = cfg.serviceMode == InboundServiceMode.vpn;
    final bool showLan = isVpnMode || _otherDevices;

    final String? lanHost = _lanIps.isEmpty
        ? null
        : _lanIps[_selectedIpIndex.clamp(0, _lanIps.length - 1)];
    final String activeHost = showLan ? (lanHost ?? '127.0.0.1') : '127.0.0.1';
    final int activePort = showLan ? cfg.lanSharingPort : cfg.mixedPort;
    final String secret = cfg.lanSharingPassword.trim();
    final bool localAuthActive = cfg.localProxyAuth &&
        cfg.serviceMode != InboundServiceMode.systemProxy;
    final String effectiveSecret =
        showLan ? secret : (localAuthActive ? secret : '');
    final bool shared = cfg.allowConnectionFromLan;

    final bool hasValidLink = showLan ? (shared && lanHost != null) : true;
    final String profileName =
        showLan ? LanSharing.lanProfileName : LanSharing.localProfileName;
    final String? fullLink = hasValidLink || (!shared && lanHost != null)
        ? LanSharing.socksLink(
            host: activeHost,
            port: activePort,
            password: effectiveSecret,
            profileName: profileName,
          )
        : null;
    final String? qrData = showLan && lanHost != null
        ? LanSharing.qrPayload(
            host: lanHost,
            port: activePort,
            password: effectiveSecret,
            profileName: profileName,
          )
        : null;
    final String? tgLink = hasValidLink
        ? LanSharing.telegramLink(
            host: activeHost,
            port: activePort,
            password: effectiveSecret,
          )
        : null;

    final Widget lanBody = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ShareQrBox(
          data: qrData,
          loading: _loadingIp,
          colors: colors,
        ),
        const SizedBox(height: AppMetrics.space3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.lan_rounded,
              size: AppMetrics.iconXs,
              color: colors.textSecondary,
            ),
            const SizedBox(width: AppMetrics.space1),
            Flexible(child: Text(
              Fa.num('پروکسی ساکس ۵ · فقط همان شبکه'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            )),
            if (_lanIps.length > 1) ...<Widget>[
              const SizedBox(width: AppMetrics.space2),
              InkWell(
                borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                onTap: () => setState(
                  () => _selectedIpIndex =
                      (_selectedIpIndex + 1) % _lanIps.length,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.space2,
                    vertical: AppMetrics.space1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: AppMetrics.iconXs,
                        color: colors.primary,
                      ),
                      const SizedBox(width: AppMetrics.space1),
                      Text(
                        Fa.num('${_selectedIpIndex + 1}/${_lanIps.length}'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppMetrics.space4),
        _buildAddressAndPortRow(
          context: context,
          colors: colors,
          hostLabel: 'نشانی آی پی',
          hostValue: _loadingIp ? '...' : activeHost,
          canCopyHost: !_loadingIp && lanHost != null,
          portValue: activePort,
          onEditPort: () => _editPort(
            currentPort: cfg.lanSharingPort,
            forbiddenPort: cfg.mixedPort,
            onSave: settings.setLanSharingPort,
            vpn: vpn,
          ),
        ),
        const SizedBox(height: AppMetrics.space2),
        _buildPasswordTile(
          context: context,
          colors: colors,
          secret: effectiveSecret,
          onSetQuickPassword: () async {
            await settings.setLanSharingPassword(LanSharing.generateSecret());
            vpn.scheduleLiveReload();
          },
          onEditPassword: () =>
              LanSharingDialog.editPassword(context, settings, vpn),
        ),
      ],
    );

    final Widget localBody = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppMetrics.space3),
          decoration: BoxDecoration(
            color: colors.surfaceHigh.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String step in const <String>[
                '۱. تنظیمات پروکسی برنامه مورد نظر را باز کنید',
                '۲. نوع پروکسی را روی ساکس ۵ یا وب بگذارید',
                '۳. نشانی و پورت زیر را وارد کنید (با کلیک کپی می شود)',
                '۴. اتصال آمبرلا را روشن نگه دارید',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppMetrics.space1,
                  ),
                  child: Text(
                    Fa.num(step),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppMetrics.space4),
        _buildAddressAndPortRow(
          context: context,
          colors: colors,
          hostLabel: 'سرور',
          hostValue: activeHost,
          canCopyHost: true,
          portValue: activePort,
          onEditPort: () => _editPort(
            currentPort: cfg.mixedPort,
            forbiddenPort: cfg.lanSharingPort,
            onSave: settings.setMixedPort,
            vpn: vpn,
          ),
        ),
        const SizedBox(height: AppMetrics.space2),
        _buildPasswordTile(
          context: context,
          colors: colors,
          secret: effectiveSecret,
          onSetQuickPassword: () async {
            if (secret.isEmpty) {
              await settings
                  .setLanSharingPassword(LanSharing.generateSecret());
            }
            await settings.setLocalProxyAuth(true);
            vpn.scheduleLiveReload();
          },
          onEditPassword: () =>
              LanSharingDialog.editPassword(context, settings, vpn),
        ),
      ],
    );

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
                    icon: Icons.wifi_tethering_rounded,
                    color: colors.primary,
                    size: AppMetrics.iconBoxSm,
                    radius: AppMetrics.radiusSm,
                  ),
                  const SizedBox(width: AppMetrics.space3),
                  Expanded(
                    child: Text(
                      Fa.num('اشتراک گذاری اتصال'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
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
              if (!isVpnMode) ...<Widget>[
                _DialogModeSwitch(
                  otherDevices: _otherDevices,
                  onChanged: (bool next) =>
                      setState(() => _otherDevices = next),
                ),
                const SizedBox(height: AppMetrics.space4),
              ],
              if (!showLan)
                localBody
              else if (shared)
                lanBody
              else
                Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Opacity(
                      opacity: 0.24,
                      child: IgnorePointer(child: lanBody),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppMetrics.space5,
                          vertical: AppMetrics.space3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppMetrics.radiusPill),
                        ),
                      ),
                      onPressed: () async {
                        await settings.setAllowConnectionFromLan(true);
                        vpn.scheduleLiveReload();
                      },
                      icon: const Icon(
                        Icons.power_settings_new_rounded,
                        size: AppMetrics.iconMd,
                      ),
                      label: const Text('روشن کردن اشتراک گذاری'),
                    ),
                  ],
                ),
              const SizedBox(height: AppMetrics.space3),
              Row(
                children: <Widget>[
                  if (hasValidLink && fullLink != null && tgLink != null)
                    _CopyLinkMenuButton(
                      copied: _copiedField == 'link',
                      tgLink: tgLink,
                      fullLink: fullLink,
                      onSelect: (String value) => _copyValue('link', value),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
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

  Widget _buildAddressAndPortRow({
    required BuildContext context,
    required UmbrellaColors colors,
    required String hostLabel,
    required String hostValue,
    required bool canCopyHost,
    required int portValue,
    required VoidCallback onEditPort,
  }) {
    final bool hostCopied = _copiedField == 'host';
    final bool portCopied = _copiedField == 'port';

    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Material(
            color: colors.surfaceHigh.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
              onTap: canCopyHost ? () => _copyValue('host', hostValue) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.space3,
                  vertical: AppMetrics.space2,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          hostCopied
                              ? Icons.check_rounded
                              : Icons.dns_rounded,
                          size: AppMetrics.iconXs,
                          color: hostCopied
                              ? colors.success
                              : colors.textSecondary,
                        ),
                        const SizedBox(width: AppMetrics.space1),
                        Expanded(
                          child: Text(
                            hostCopied ? 'کپی شد' : hostLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: hostCopied
                                      ? colors.success
                                      : colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      hostValue,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppMetrics.space2),
        Expanded(
          flex: 2,
          child: Material(
            color: colors.surfaceHigh.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
              onTap: () => _copyValue('port', '$portValue'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.space3,
                  vertical: AppMetrics.space2,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                portCopied
                                    ? Icons.check_rounded
                                    : Icons.tag_rounded,
                                size: AppMetrics.iconXs,
                                color: portCopied
                                    ? colors.success
                                    : colors.textSecondary,
                              ),
                              const SizedBox(width: AppMetrics.space1),
                              Expanded(
                                child: Text(
                                  portCopied ? 'کپی شد' : 'پورت',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: portCopied
                                            ? colors.success
                                            : colors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppMetrics.space1),
                          Text(
                            Fa.num('$portValue'),
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius:
                          BorderRadius.circular(AppMetrics.radiusPill),
                      onTap: onEditPort,
                      child: Padding(
                        padding: const EdgeInsets.all(AppMetrics.space1),
                        child: Icon(
                          Icons.edit_rounded,
                          size: AppMetrics.iconSm,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordTile({
    required BuildContext context,
    required UmbrellaColors colors,
    required String secret,
    required VoidCallback onSetQuickPassword,
    required VoidCallback onEditPassword,
  }) {
    if (secret.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space3,
          vertical: AppMetrics.space2,
        ),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          border: Border.all(color: colors.danger.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'رمز تنظیم نشده',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.danger,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
              onTap: onSetQuickPassword,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppMetrics.space2,
                  vertical: AppMetrics.space1,
                ),
                child: Text(
                  'گذاشتن رمز',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final bool secretCopied = _copiedField == 'secret';
    final String masked = '••••••••';
    return Material(
      color: colors.surfaceHigh.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: () => _copyValue('secret', secret),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.space3,
            vertical: AppMetrics.space2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          secretCopied
                              ? Icons.check_rounded
                              : Icons.lock_rounded,
                          size: AppMetrics.iconXs,
                          color: secretCopied
                              ? colors.success
                              : colors.textSecondary,
                        ),
                        const SizedBox(width: AppMetrics.space1),
                        Expanded(
                          child: Text(
                            secretCopied ? 'کپی شد' : 'رمز عبور',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: secretCopied
                                      ? colors.success
                                      : colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      _showPassword ? Fa.num(secret) : masked,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                onTap: () => setState(() => _showPassword = !_showPassword),
                child: Padding(
                  padding: const EdgeInsets.all(AppMetrics.space1),
                  child: Icon(
                    _showPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppMetrics.space1),
              InkWell(
                borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                onTap: onEditPassword,
                child: Padding(
                  padding: const EdgeInsets.all(AppMetrics.space1),
                  child: Icon(
                    Icons.edit_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.textSecondary,
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

class _ShareQrBox extends StatelessWidget {
  const _ShareQrBox({
    required this.data,
    required this.loading,
    required this.colors,
  });

  final String? data;
  final bool loading;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Center(
        child: Container(
          width: AppMetrics.qrCodeSize,
          height: AppMetrics.qrCodeSize,
          padding: const EdgeInsets.all(AppMetrics.space4),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: loading
              ? CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.wifi_off_rounded,
                      size: AppMetrics.iconXl,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(height: AppMetrics.space2),
                    Text(
                      'شبکه محلی پیدا نشد',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
        ),
      );
    }

    return Center(
      child: Container(
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
              data: data!,
              padding: EdgeInsets.zero,
              errorCorrectionLevel: QrErrorCorrectLevel.Q,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: colors.primary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
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
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: ClipOval(
                child: Image.asset(
                  BrandAssets.logo,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogModeSwitch extends StatelessWidget {
  const _DialogModeSwitch({
    required this.otherDevices,
    required this.onChanged,
  });

  final bool otherDevices;
  final ValueChanged<bool> onChanged;

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
            icon: Icons.computer_rounded,
            label: 'این دستگاه',
            active: !otherDevices,
            onTap: () => onChanged(false),
          ),
          _tab(
            context,
            colors,
            icon: Icons.devices_rounded,
            label: 'دستگاه های دیگر',
            active: otherDevices,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    UmbrellaColors colors, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final Color fg = active ? colors.primary : colors.textSecondary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        onTap: onTap,
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
                child: Text(
                  Fa.num(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
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

class _CopyLinkMenuButton extends StatelessWidget {
  const _CopyLinkMenuButton({
    required this.copied,
    required this.tgLink,
    required this.fullLink,
    required this.onSelect,
  });

  final bool copied;
  final String tgLink;
  final String fullLink;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final MenuController controller = MenuController();

    Widget item({
      required IconData icon,
      required Color iconColor,
      required String label,
      required String value,
    }) {
      return SizedBox(
        width: AppMetrics.buttonMaxWidth - (AppMetrics.space2 * 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            onTap: () {
              controller.close();
              onSelect(value);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.space3,
                vertical: AppMetrics.space2,
              ),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: AppMetrics.iconSm, color: iconColor),
                  const SizedBox(width: AppMetrics.space3),
                  Expanded(
                    child: Text(
                      Fa.num(label),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Icon(
                    Icons.content_copy_rounded,
                    size: AppMetrics.iconXs,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MenuAnchor(
      controller: controller,
      alignmentOffset: const Offset(0, AppMetrics.space1),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(colors.surface),
        surfaceTintColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
        shadowColor: WidgetStatePropertyAll<Color>(colors.shadow),
        elevation: const WidgetStatePropertyAll<double>(14),
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(AppMetrics.buttonMaxWidth, 0),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.all(AppMetrics.space2),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            side: BorderSide(color: colors.border),
          ),
        ),
      ),
      menuChildren: <Widget>[
        item(
          icon: Icons.send_rounded,
          iconColor: colors.info,
          label: 'لینک تلگرام',
          value: tgLink,
        ),
        const SizedBox(height: AppMetrics.space1),
        item(
          icon: Icons.link_rounded,
          iconColor: colors.primary,
          label: 'لینک کامل',
          value: fullLink,
        ),
      ],
      builder: (
        BuildContext context,
        MenuController menuController,
        Widget? child,
      ) {
        final bool open = menuController.isOpen;
        final Color fg = copied ? colors.success : colors.primary;
        return Material(
          color: fg.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            onTap: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.space3,
                vertical: AppMetrics.space2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    copied ? Icons.check_rounded : Icons.content_copy_rounded,
                    size: AppMetrics.iconSm,
                    color: fg,
                  ),
                  const SizedBox(width: AppMetrics.space1),
                  Text(
                    copied ? 'کپی شد' : 'کپی لینک',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: AppMetrics.space1),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: AppMetrics.iconSm,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PortEditorDialog extends StatefulWidget {
  const _PortEditorDialog({
    required this.initialPort,
    required this.forbiddenPort,
  });

  final int initialPort;
  final int forbiddenPort;

  @override
  State<_PortEditorDialog> createState() => _PortEditorDialogState();
}

class _PortEditorDialogState extends State<_PortEditorDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: Fa.num('${widget.initialPort}'));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final int? parsed = int.tryParse(Fa.toEn(_ctrl.text.trim()));
    if (parsed == null ||
        !LanSharing.isValidPort(parsed, forbiddenPort: widget.forbiddenPort)) {
      setState(() {
        _error = parsed == widget.forbiddenPort
            ? 'این پورت در حال استفاده است؛ عدد دیگری وارد کنید'
            : 'پورتی بین ۱۰۲۴ تا ۶۵۵۳۵ وارد کنید';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
        side: BorderSide(color: colors.border),
      ),
      title: const Text('ویرایش پورت'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹]')),
          const PersianDigitsFormatter(),
          LengthLimitingTextInputFormatter(5),
        ],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'پورت',
          hintText: '۱۲۳۳۸',
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

class _PasswordEditorDialog extends StatefulWidget {
  const _PasswordEditorDialog({required this.initialSecret});

  final String initialSecret;

  @override
  State<_PasswordEditorDialog> createState() => _PasswordEditorDialogState();
}

class _PasswordEditorDialogState extends State<_PasswordEditorDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: Fa.num(widget.initialSecret));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = Fa.toEn(_ctrl.text.trim());
    if (!LanSharing.isValidPassword(value)) {
      setState(() => _error = 'حداقل ۴ نویسه وارد کنید');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
        side: BorderSide(color: colors.border),
      ),
      title: const Text('رمز پروکسی'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _ctrl,
            autofocus: true,
            textDirection: TextDirection.ltr,
            inputFormatters: const <TextInputFormatter>[
              PersianDigitsFormatter(),
            ],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'رمز عبور',
              hintText: 'خالی گذاشتن برابر با بدون رمز',
              errorText: _error,
            ),
          ),
          const SizedBox(height: AppMetrics.space2),
          Wrap(
            spacing: AppMetrics.space2,
            children: <Widget>[
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _ctrl.text = Fa.num(LanSharing.generateSecret());
                    _error = null;
                  });
                },
                icon: const Icon(Icons.casino_rounded, size: AppMetrics.iconSm),
                label: const Text('ساخت رمز تازه'),
              ),
              if (_ctrl.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(''),
                  icon: Icon(
                    Icons.no_encryption_gmailerrorred_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.danger,
                  ),
                  label: Text(
                    'برداشتن رمز',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}
