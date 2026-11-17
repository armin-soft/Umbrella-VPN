import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/common.dart';
import '../widgets/flag_view.dart';
import '../widgets/live_clock.dart';

/// صفحه اتصال: یک نگاه، یک دکمه.
///
/// کارت اتصال تمام ارتفاع صفحه را می گیرد و دکمه بزرگ در مرکز آن است. انتخاب
/// هسته و حالت انتخاب سرور به شکل چیپ های کوچک زیر دکمه هستند و هر کدام یک
/// منوی کوچک باز می کنند؛ هیچ فهرست بلندی در صفحه نیست.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  /// آی پی دستگاه برای نمایش در نوار بالا.
  ///
  /// وقتی تونل وصل است، آی پی خروجی نشان داده می شود. وقتی قطع است، آی پی
  /// واقعی همین دستگاه؛ و اگر خواندن آن از اینترنت هنوز تمام نشده باشد، آی پی
  /// داخلی کارت شبکه. هیچ حالتی «نامشخص» یا خط تیره نمی دهد.
  String _deviceIp(VpnController vpn) {
    if (vpn.status == VpnStatus.connected && vpn.exitIp.isNotEmpty) {
      return vpn.exitIp;
    }
    if (vpn.realIp.isNotEmpty) {
      return vpn.realIp;
    }
    if (vpn.geo.ip.isNotEmpty) {
      return vpn.geo.ip;
    }
    final String local = vpn.device.localIp;
    return local.isEmpty ? 'در حال خواندن' : local;
  }

  /// پرچم مناسب همان آی پی که نشان می دهیم.
  ///
  /// • آی پی داخلی (`192.168.x.x`، `10.x`، `172.16-31.x`) پرچم ندارد؛
  ///   آی پی داخلی کشور ندارد و ایران نشان دادنش گمراه کننده است.
  /// • متصل: پرچم کشور سرور متصل از نام یا پارامترهای همان گره.
  /// • قطع: پرچم کشور واقعی دستگاه از `geo`.
  static String _flagForIp(VpnController vpn, bool connected, String ip) {
    if (connected) {
      // اگر سرویس جغرافیایی همین IP را تشخیص داده، همان دقیق ترین منبع است.
      if (vpn.geo.ip.isNotEmpty && vpn.geo.ip == ip && vpn.geo.flagCode.isNotEmpty) {
        return vpn.geo.flagCode;
      }
      // در نبود داده منطبق با IP، از شناسه کشور خود گره استفاده می کنیم.
      final String fromNode = vpn.activeNode?.flagCode ?? '';
      if (fromNode.isNotEmpty) {
        return fromNode;
      }
      final String fromGeo = vpn.geo.flagCode;
      if (fromGeo.isNotEmpty && !_isPrivateIp(ip)) {
        return fromGeo;
      }
      return '';
    }
    if (_isPrivateIp(ip) || ip == 'در حال خواندن') {
      return '';
    }
    // آی پی خروجی تونل: پرچم از داده جغرافیایی همان آی پی.
    if (vpn.geo.ip.isNotEmpty && vpn.geo.ip == ip) {
      return vpn.geo.flagCode;
    }
    return '';
  }

  /// آی پی داخلی است؟ (بدون پرچم، بدون کشور)
  static bool _isPrivateIp(String ip) {
    final String value = ip.trim();
    if (value.isEmpty) {
      return false;
    }
    if (value.startsWith('10.') ||
        value.startsWith('192.168.') ||
        value.startsWith('127.') ||
        value.startsWith('169.254.')) {
      return true;
    }
    if (value.startsWith('172.')) {
      final int? second =
          int.tryParse(value.split('.').elementAt(1));
      if (second != null && second >= 16 && second <= 31) {
        return true;
      }
    }
    // IPv6 محلی
    return value.toLowerCase().startsWith('fe80') ||
        value == '::1';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final SubscriptionController subs = context.read<SubscriptionController>();
      final VpnController vpn = context.read<VpnController>();
      await OccasionService.instance.load();
      if (!mounted) {
        return;
      }
      setState(() {});
      if (subs.totalNodes == 0 && !subs.loadingAll) {
        await subs.fetchAll();
      }
      if (!vpn.measuring &&
          vpn.nodes.isNotEmpty &&
          vpn.nodes.every((VpnNode node) => !node.hasPing)) {
        unawaited(vpn.refreshPings());
      }
    });
  }

  static String _regionLabel(String code) {
    if (code == 'all' || code.isEmpty) return 'همه';
    if (code == 'unknown') return 'نامشخص';
    return CountryNames.fa(code).isEmpty ? code.toUpperCase() : CountryNames.fa(code);
  }

  /// خط دوم اعلان اتصال، بدون نام سرور: فقط پینگ و حالت.
  ///
  /// کاربر خواست پس از اتصال هیچ جا نام سرور نمایش داده نشود؛ فقط «به آمبرلا
  /// متصل شد». جزئیات سرور در گزارش ها می ماند.
  static String _connectedNote(VpnController vpn) {
    final int ping = vpn.activePingMs;
    if (ping > 0) {
      return 'پینگ ${Fa.ms(ping)}';
    }
    return 'اتصال امن برقرار است';
  }

  /// آیکون مناسب همان سلام ساعت روز (صبح، ظهر، عصر، شب).
  static IconData _greetingIcon() {
    switch (Fa.greetingKey()) {
      case 'morning':
        return Icons.wb_twilight_rounded;
      case 'noon':
        return Icons.wb_sunny_rounded;
      case 'evening':
        return Icons.nights_stay_rounded;
      default:
        return Icons.bedtime_rounded;
    }
  }

  /// لغو اتصال در حال ساخت (دکمه «لغو اتصال»).
  Future<void> _cancelConnection(
    VpnController vpn,
    ToastController toasts,
  ) async {
    await vpn.cancel();
    if (!mounted) {
      return;
    }
    toasts.info('اتصال لغو شد');
  }

  Future<void> _toggleConnection(
    VpnController vpn,
    ToastController toasts,
  ) async {
    if (vpn.status.busy) {
      return;
    }
    if (vpn.status.active) {
      await vpn.disconnect();
      toasts.info('اتصال قطع شد');
      return;
    }
    final AuthController auth = context.read<AuthController>();
    if (!auth.account.canConnect) {
      toasts.error('اجازه اتصال نیست', auth.account.accessReason);
      return;
    }
    if (vpn.nodes.isEmpty) {
      toasts.error('سروری موجود نیست', 'اول اشتراک باید خوانده شود.');
      return;
    }
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      // نام سرور اینجا نمی آید: کاربر خواست پس از اتصال هیچ جا نام سرور
      // دیده نشود و همه جزئیات فقط در گزارش ها باشد.
      toasts.success('به آمبرلا متصل شد', _connectedNote(vpn));
    } else if (!outcome.cancelled) {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  /// انتخاب حالت اتصال (تونل کامل / پروکسی سیستمی) از منوی کوچک؛ سپس اتصال
  /// خودکار به پایدارترین سرور.
  ///
  /// هسته یکی است (موتور هسته)؛ این منو فقط تعیین می کند ترافیک با تونل
  /// کامل رد شود یا با پروکسی سیستمی.
  Future<void> _pickConnectionMode(
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    final CorePreference? picked = await showDialog<CorePreference>(
      context: context,
      builder: (BuildContext context) => _ConnectionModeDialog(
        current: settings.settings.corePreference,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    await settings.setCorePreference(picked);
    toasts.info('حالت اتصال: ${picked.faName}');
    if (vpn.status.busy) {
      return;
    }
    if (vpn.status.active) {
      await vpn.disconnect();
    }
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      toasts.success('به آمبرلا متصل شد', _connectedNote(vpn));
    } else {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  /// انتخاب حالت انتخاب سرور از منوی کوچک؛ حالت واقعا اعمال می شود.
  Future<void> _pickMode(
    VpnController vpn,
    SettingsController settings,
    ToastController toasts,
  ) async {
    final SelectionMode? picked = await showDialog<SelectionMode>(
      context: context,
      builder: (BuildContext context) => _ModeDialog(
        current: settings.settings.selectionMode,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    if (picked == settings.settings.selectionMode) {
      return;
    }
    await settings.setSelectionMode(picked);
    toasts.info('حالت انتخاب سرور: ${picked.faName}');
    if (vpn.status.busy || !vpn.status.active) {
      return;
    }
    await vpn.disconnect();
    final ConnectOutcome outcome = await vpn.connect();
    if (outcome.ok) {
      toasts.success(
        'با حالت ${picked.faName} دوباره وصل شد',
        _connectedNote(vpn),
      );
    } else {
      toasts.error('اتصال برقرار نشد', outcome.message);
    }
  }

  Future<void> _pickServerRegion(
    VpnController vpn,
    SubscriptionController subscriptions,
    SettingsController settings,
    ToastController toasts,
  ) async {
    final String previousRegion = settings.settings.serverRegionCode;
    final String previousNode = settings.settings.lastNodeId;
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _RegionProxyDialog(
        selectedRegion: previousRegion,
        onRefresh: subscriptions.fetchAll,
        onTogglePin: vpn.toggleFavorite,
        onPrefer: (VpnNode node) async {
          await settings.rememberNode(node.id);
        },
      ),
    );
    if (picked == null || !mounted) return;
    if (picked != previousRegion) {
      await settings.setServerRegion(picked);
    }
    final bool preferenceChanged = settings.settings.lastNodeId != previousNode;
    if (picked == previousRegion && !preferenceChanged) return;
    if (picked != previousRegion) {
      toasts.info('منطقه سرور: ${_regionLabel(picked)}');
    } else if (preferenceChanged) {
      toasts.info('سرور به عنوان گزینه ترجیحی ثبت شد.');
    }
    if (vpn.status.active && !vpn.status.busy) {
      await vpn.disconnect();
      final ConnectOutcome outcome = await vpn.connect();
      if (!outcome.ok) toasts.error('اتصال دوباره برقرار نشد', outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final SettingsController settings = context.watch<SettingsController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;
    final VpnStatus status = vpn.status;
    final Color tone = VpnVisuals.color(context, status);
    final bool connected = status == VpnStatus.connected;
    final Account account = auth.account;

    // پرچم: پیش از اتصال، کشور خودِ دستگاه؛ پس از اتصال، کشور سرور متصل.
    //
    // **اشکالی که در تصویر کاربر دیده شد:** آی پی `192.168.1.2` (آی پی
    // داخلی) با پرچم ایران نمایش داده می شد، چون پرچم از `geo` گرفته می شد
    // که وقتی آی پی خوانده نشود به آی پی داخلی برمی گردد. پرچم باید مال
    // همان جایی باشد که آی پی از آن آمده.
    final String shownIp = _deviceIp(vpn);
    final String flagCode = _flagForIp(vpn, connected, shownIp);
    // نام کشور همیشه از همان کدی می آید که پرچم از آن ساخته شد؛ وگرنه پرچم
    // آلمان با نام «آمبرلا» یا رشته خالی کنار هم می نشستند.
    final String countryName = CountryNames.fa(flagCode);

    // ارتفاع صفحه کامل استفاده می شود؛ هیچ نیمه خالی نمی ماند.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double orb = constraints.maxHeight < 650
            ? 210
            : (constraints.maxHeight < 780 ? 250 : 288);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppMetrics.space7, AppMetrics.space5, AppMetrics.space7, AppMetrics.space6),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 42,
            ),
            child: GlassCard(
              radius: AppMetrics.radiusHuge,
              padding: const EdgeInsets.fromLTRB(AppMetrics.space6, AppMetrics.space5, AppMetrics.space6, AppMetrics.space5),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  tone.withValues(alpha: 0.10),
                  colors.surface,
                  colors.backgroundAlt,
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── نوار بالا: سلام و آی پی و پرچم ────────────────────
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Icon(
                                  _greetingIcon(),
                                  size: AppMetrics.iconSm,
                                  color: colors.warning,
                                ),
                                const SizedBox(width: AppMetrics.space2),
                                Flexible(
                                  child: Text(
                                    Fa.num(
                                      'سلام ${account.displayName} '
                                      '${Fa.greeting()}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppMetrics.space1),
                            // تاریخ شمسی با روز هفته و ساعت زنده.
                            LiveDateTimeLine(
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (subs.needsLogin)
                        Pill(
                          label: 'برای اشتراک وارد شو',
                          icon: Icons.login_rounded,
                          color: colors.warning,
                        ),
                      const SizedBox(width: AppMetrics.space2),
                      _IpChip(
                        ip: shownIp,
                        flagCode: flagCode,
                        country: connected ? countryName : '',
                        connected: connected,
                        onRefresh: () => vpn.refreshIp(),
                      ),
                    ],
                  ),
                  if (!account.canConnect)
                    Padding(
                      padding: const EdgeInsets.only(top: AppMetrics.space3),
                      child: _AccessBanner(
                        title: account.enable
                            ? 'اشتراک شما اجازه اتصال ندارد'
                            : 'حساب شما مسدود شده است',
                        message: account.accessReason,
                      ),
                    ),
                  if (OccasionService.instance.active != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppMetrics.space3),
                      child: OccasionBanner(
                        occasion: OccasionService.instance.active,
                        enabled: settings.settings.occasionEffects,
                      ),
                    ),

                  // ── گنبد و دکمه اتصال در وسط ──────────────────────────
                  Column(
                    children: <Widget>[
                      Semantics(
                        button: true,
                        label: status.busy
                            ? 'لغو اتصال'
                            : (status.active ? 'قطع اتصال' : 'اتصال'),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          // زدن گنبد وسط در حال ساخت تونل هم اتصال را لغو
                          // می کند؛ نه فقط دکمه پایین.
                          onTap: status == VpnStatus.disconnecting
                              ? null
                              : (status.busy
                                  ? () => _cancelConnection(vpn, toasts)
                                  : () => _toggleConnection(vpn, toasts)),
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              StatusOrb(
                                image: status.image,
                                color: tone,
                                size: orb,
                                active: status.busy,
                              ),
                              if (!status.busy)
                                Container(
                                  width: orb * 0.28,
                                  height: orb * 0.28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (status.active
                                            ? colors.danger
                                            : colors.primary)
                                        .withValues(alpha: 0.94),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: (status.active
                                                ? colors.danger
                                                : colors.primary)
                                            .withValues(alpha: 0.38),
                                        blurRadius: 24,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.power_settings_new_rounded,
                                    size: orb * 0.14,
                                    color: colors.onPrimary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppMetrics.space3),
                      // وضعیت و پرچم کنار هم: کاربر می خواست وقتی وصل شد،
                      // پرچم سرور متصل کنار «متصل» دیده شود.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (connected && flagCode.isNotEmpty) ...<Widget>[
                            FlagView(code: flagCode, width: AppMetrics.flagWidth),
                            const SizedBox(width: AppMetrics.space2),
                          ],
                          Flexible(
                            child: Text(
                              Fa.num(
                                connected
                                    ? 'به آمبرلا متصل شد'
                                    : status.label,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: tone,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppMetrics.space1),
                      // پینگ سرور متصل، همان چیزی که کاربر خواست زیر وضعیت
                      // دیده شود. نام سرور اینجا نمی آید؛ فقط گزارش ها.
                      if (connected)
                        _PingLine(pingMs: vpn.activePingMs)
                      else
                        Text(
                          Fa.num(vpn.message),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      // فاصله بیشتر تا دکمه ها: کاربر خواست دکمه ها به گنبد
                      // نچسبند و پایین تر و مرتب تر باشند.
                      const SizedBox(height: AppMetrics.space6),
                      SizedBox(
                        width: AppMetrics.controlMaxWidth,
                        child: status.busy
                            // هنگام ساخت تونل، دکمه به «لغو اتصال» تبدیل می شود؛
                            // تا پیش از این کاربر هیچ راهی برای پشیمان شدن نداشت.
                            ? GradientButton(
                                label: status == VpnStatus.disconnecting
                                    ? 'در حال لغو...'
                                    : 'لغو اتصال',
                                icon: Icons.cancel_rounded,
                                height: AppMetrics.controlHeightLarge,
                                tone: colors.warning,
                                loading: status == VpnStatus.disconnecting,
                                onPressed: status == VpnStatus.disconnecting
                                    ? null
                                    : () => _cancelConnection(vpn, toasts),
                              )
                            : GradientButton(
                                label: status.active ? 'قطع اتصال' : 'اتصال',
                                icon: Icons.power_settings_new_rounded,
                                height: AppMetrics.controlHeightLarge,
                                tone: status.active
                                    ? colors.danger
                                    : colors.primary,
                                onPressed: () => _toggleConnection(vpn, toasts),
                              ),
                      ),
                      if (!account.canConnect)
                        Padding(
                          padding: const EdgeInsets.only(top: AppMetrics.space2),
                          child: Text(
                            Fa.num('اتصال تا تمدید یا رفع مسدودی اشتراک ممکن نیست.'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: colors.danger),
                          ),
                        ),
                      const SizedBox(height: AppMetrics.space6),

                      // ── دو منوی کوچک: حالت اتصال و حالت انتخاب سرور ──
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: <Widget>[
                          _PickerChip(
                            label: 'حالت اتصال',
                            value: settings.settings.corePreference.faName,
                            icon: settings.settings.corePreference.icon,
                            enabled: !status.busy,
                            onTap: () => _pickConnectionMode(
                              vpn,
                              settings,
                              toasts,
                            ),
                          ),
                          _PickerChip(
                            label: 'حالت انتخاب سرور',
                            value: settings.settings.selectionMode.faName,
                            icon: settings.settings.selectionMode.icon,
                            enabled: !status.busy,
                            onTap: () => _pickMode(vpn, settings, toasts),
                          ),
                          _PickerChip(
                            label: 'منطقه و سرورها',
                            value: _regionLabel(settings.settings.serverRegionCode),
                            icon: Icons.public_rounded,
                            enabled: !status.busy,
                            onTap: () => _pickServerRegion(
                              vpn,
                              subs,
                              settings,
                              toasts,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // آمار اتصال به همین صفحه منتقل شده و منوی جداگانه حذف است.
                  _ConnectionStats(vpn: vpn, connected: connected),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// آمار زنده اتصال که قبلا در صفحه جداگانه وضعیت اتصال نمایش داده می شد.
class _ConnectionStats extends StatelessWidget {
  const _ConnectionStats({required this.vpn, required this.connected});

  final VpnController vpn;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final List<(String, String, IconData, Color)> values = <(String, String, IconData, Color)>[
      ('پینگ', vpn.activePingMs > 0 ? Fa.ms(vpn.activePingMs) : '—', Icons.speed_rounded, context.colors.success),
      ('مدت اتصال', connected ? Fa.duration(vpn.stats.connectedFor) : '—', Icons.timer_outlined, context.colors.info),
      ('دریافتی', vpn.stats.available ? Fa.bytes(vpn.stats.rx) : '—', Icons.south_rounded, context.colors.primary),
      ('ارسالی', vpn.stats.available ? Fa.bytes(vpn.stats.tx) : '—', Icons.north_rounded, context.colors.warning),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 760;
        final double tileWidth = narrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: values.map((value) => SizedBox(
            width: tileWidth,
            child: _ConnectionStatTile(
              label: value.$1,
              value: value.$2,
              icon: value.$3,
              accent: value.$4,
            ),
          )).toList(),
        );
      },
    );
  }
}

class _ConnectionStatTile extends StatelessWidget {
  const _ConnectionStatTile({required this.label, required this.value, required this.icon, required this.accent});

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppMetrics.space3,
        vertical: AppMetrics.space2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: AppMetrics.iconMd, color: accent),
          const SizedBox(width: AppMetrics.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(Fa.num(label), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.textSecondary)),
                const SizedBox(height: AppMetrics.space1),
                Text(Fa.num(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// پینگ سرور متصل، زیر وضعیت اتصال.
///
/// کاربر خواست وقتی وصل می شود پینگ همان لحظه زیرش دیده شود. عدد زنده تونل
/// اگر آماده باشد می آید، وگرنه پینگ شبکه همان سرور؛ تا وقتی هیچ عددی
/// نرسیده باشد «در حال اندازه گیری» نوشته می شود، نه صفر.
class _PingLine extends StatelessWidget {
  const _PingLine({required this.pingMs});

  final int pingMs;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final bool known = pingMs > 0;
    // رنگ بر اساس کیفیت: سبز زیر ۸۰، کهربایی زیر ۱۸۰، قرمز بالاتر.
    final Color tone = !known
        ? colors.textSecondary
        : (pingMs < 80
            ? colors.success
            : (pingMs < 180 ? colors.warning : colors.danger));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.speed_rounded, size: AppMetrics.iconSm, color: tone),
        const SizedBox(width: AppMetrics.space2),
        Text(
          Fa.num(known ? 'پینگ ${Fa.ms(pingMs)}' : 'پینگ در حال اندازه گیری'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

/// هشدار دسترسی: اشتراک منقضی، مسدود یا تمام شده.
class _AccessBanner extends StatelessWidget {
  const _AccessBanner({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space4, vertical: AppMetrics.space3),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.lock_rounded, size: AppMetrics.iconMd, color: colors.danger),
          const SizedBox(width: AppMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Fa.num(title),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.danger,
                      ),
                ),
                Text(
                  Fa.num(message),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// نشان آی پی با پرچم کشور.
class _IpChip extends StatelessWidget {
  const _IpChip({
    required this.ip,
    required this.flagCode,
    required this.country,
    required this.connected,
    required this.onRefresh,
  });

  final String ip;
  final String flagCode;
  final String country;
  final bool connected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onRefresh,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space3, vertical: AppMetrics.space2),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (flagCode.isNotEmpty) ...<Widget>[
                FlagView(code: flagCode, width: AppMetrics.flagWidth),
                const SizedBox(width: AppMetrics.space2),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Fa.num(connected ? 'آی پی اتصال' : 'آی پی دستگاه'),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                  Text(
                    Fa.num(ip),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (country.isNotEmpty)
                    Text(
                      Fa.num(country),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: colors.info),
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

/// چیپ کوچک انتخاب: عنوان + مقدار فعلی + فلش منو.
class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppMetrics.space3, AppMetrics.space2, AppMetrics.space3, AppMetrics.space2),
          decoration: BoxDecoration(
            color: colors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon ?? Icons.tune_rounded, size: AppMetrics.iconSm,
                  color: colors.textSecondary),
              const SizedBox(width: AppMetrics.space2),
              Text(
                Fa.num(label),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(width: AppMetrics.space2),
              Text(
                Fa.num(value),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
              ),
              const SizedBox(width: AppMetrics.space1),
              Icon(Icons.expand_more_rounded, size: AppMetrics.iconSm,
                  color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// پنجره منطقه و پروکسی ها: کشور را محدود کنید، داده cached را فوری ببینید
/// و با نگه داشتن یک ردیف آن گره را پین/آزاد کنید.
class _RegionProxyDialog extends StatefulWidget {
  const _RegionProxyDialog({
    required this.selectedRegion,
    required this.onRefresh,
    required this.onTogglePin,
    required this.onPrefer,
  });

  final String selectedRegion;
  final Future<void> Function() onRefresh;
  final Future<void> Function(VpnNode node) onTogglePin;
  final Future<void> Function(VpnNode node) onPrefer;

  @override
  State<_RegionProxyDialog> createState() => _RegionProxyDialogState();
}

class _RegionProxyDialogState extends State<_RegionProxyDialog> {
  late String _region = widget.selectedRegion;
  bool _refreshing = false;
  String _refreshError = '';

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _refreshError = '';
    });
    try {
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          _refreshError =
              'تازه سازی انجام نشد؛ سرورهای cache شده همچنان قابل استفاده اند.';
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _togglePin(VpnNode node) async {
    await widget.onTogglePin(node);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(AppMetrics.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconSquare(icon: Icons.public_rounded, color: colors.primary),
                  const SizedBox(width: AppMetrics.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'منطقه و سرورها',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'فهرست cache شده فوری نمایش داده می شود.',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'تازه سازی اشتراک',
                    onPressed: _refreshing ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox(
                            width: AppMetrics.iconMd,
                            height: AppMetrics.iconMd,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'بستن',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppMetrics.space3),
              Container(
                padding: const EdgeInsets.all(AppMetrics.space3),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  'آمبرلا تا ۸ سرور کم تاخیر را فعال نگه می دارد. سرورهای پین شده '
                  'در انتخاب خودکار و تلاش های جایگزین اولویت می گیرند.',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.textSecondary, height: 1.6),
                ),
              ),
              const SizedBox(height: AppMetrics.space3),
              Consumer<VpnController>(
                builder: (BuildContext context, VpnController vpn, Widget? child) {
                  final List<String> regions = _regionCodes(vpn.nodes);
                  if (_region != 'all' && !regions.contains(_region)) {
                    regions.add(_region);
                  }
                  final List<DropdownMenuItem<String>> items =
                      <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('همه کشورها'),
                    ),
                    for (final String code in regions)
                      DropdownMenuItem<String>(
                        value: code,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (code != 'unknown') ...<Widget>[
                              FlagView(code: code, width: AppMetrics.flagWidthSmall),
                              const SizedBox(width: AppMetrics.space2),
                            ],
                            Text(
                              code == 'unknown'
                                  ? 'کشور نامشخص'
                                  : _countryLabel(code),
                            ),
                          ],
                        ),
                      ),
                  ];
                  return DropdownButtonFormField<String>(
                    initialValue: _region,
                    decoration: const InputDecoration(
                      labelText: 'فیلتر کشور',
                      isDense: true,
                    ),
                    items: items,
                    onChanged: (String? value) {
                      if (value != null) setState(() => _region = value);
                    },
                  );
                },
              ),
              if (_refreshError.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppMetrics.space2),
                Text(
                  _refreshError,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.warning),
                ),
              ],
              const SizedBox(height: AppMetrics.space2),
              Expanded(
                child: Consumer<VpnController>(
                  builder: (BuildContext context, VpnController vpn, Widget? child) {
                    final List<VpnNode> nodes = vpn.nodes.where((VpnNode node) {
                      if (_region == 'all') return true;
                      final String code = node.flagCode.toLowerCase();
                      return _region == 'unknown' ? code.isEmpty : code == _region;
                    }).toList()
                      ..sort((VpnNode a, VpnNode b) {
                        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
                        if (a.hasPing != b.hasPing) return a.hasPing ? -1 : 1;
                        return a.pingMs.compareTo(b.pingMs);
                      });
                    if (nodes.isEmpty) {
                      return Center(
                        child: Text(
                          'در این منطقه سروری در cache نیست.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: nodes.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
                      itemBuilder: (BuildContext context, int index) {
                        final VpnNode node = nodes[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                          onTap: () async {
                            await widget.onPrefer(node);
                            if (context.mounted) Navigator.of(context).pop(_region);
                          },
                          onLongPress: () => _togglePin(node),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppMetrics.space2,
                              vertical: AppMetrics.space2,
                            ),
                            child: Row(
                              children: <Widget>[
                                if (node.flagCode.isNotEmpty) ...<Widget>[
                                  FlagView(code: node.flagCode, width: AppMetrics.flagWidthSmall),
                                  const SizedBox(width: AppMetrics.space3),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        Fa.num(node.name),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: AppMetrics.space1),
                                      Text(
                                        Fa.num(
                                          '${node.protocol.name.toUpperCase()} · '
                                          '${node.hasPing ? Fa.ms(node.pingMs) : 'در انتظار سنجش'}',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: node.favorite
                                      ? 'برداشتن پین'
                                      : 'پین کردن برای اولویت اتصال',
                                  onPressed: () => _togglePin(node),
                                  icon: Icon(
                                    node.favorite
                                        ? Icons.push_pin_rounded
                                        : Icons.push_pin_outlined,
                                    color: node.favorite
                                        ? colors.primary
                                        : colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppMetrics.space2),
              Text(
                'برای انتخاب ترجیحی یک بار بزنید؛ برای پین، ردیف را نگه دارید '
                'یا آیکون پین را بزنید.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppMetrics.space2),
              GradientButton(
                label: 'اعمال منطقه انتخاب شده',
                icon: Icons.check_rounded,
                height: AppMetrics.controlHeightSmall,
                onPressed: () => Navigator.of(context).pop(_region),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<String> _regionCodes(List<VpnNode> nodes) {
    final Set<String> codes = <String>{
      for (final VpnNode node in nodes)
        if (node.flagCode.isNotEmpty) node.flagCode.toLowerCase(),
    };
    final List<String> sorted = codes.toList()
      ..sort((String a, String b) => _countryLabel(a).compareTo(_countryLabel(b)));
    if (nodes.any((VpnNode node) => node.flagCode.isEmpty)) sorted.add('unknown');
    return sorted;
  }

  static String _countryLabel(String code) =>
      CountryNames.fa(code).isEmpty ? code.toUpperCase() : CountryNames.fa(code);
}

/// منوی کوچک انتخاب حالت اتصال (توضیح هر حالت زیر نامش می آید).
class _ConnectionModeDialog extends StatelessWidget {
  const _ConnectionModeDialog({required this.current});

  final CorePreference current;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: AppMetrics.space10, bottom: AppMetrics.space6, left: AppMetrics.space6, right: AppMetrics.space6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppMetrics.space4, AppMetrics.space4, AppMetrics.space4, AppMetrics.space2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: AppMetrics.space2,
                  right: AppMetrics.space2,
                  bottom: AppMetrics.space2,
                ),
                child: Text(
                  Fa.num('حالت اتصال'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              for (final CorePreference pref in CorePreference.values)
                _MenuTile(
                  selected: pref == current,
                  enabled: pref.available,
                  title: pref.faName,
                  subtitle: pref.description,
                  leading: Icon(
                    pref.icon,
                    size: AppMetrics.iconMd,
                    color: pref == current ? colors.primary : colors.textSecondary,
                  ),
                  onTap: () => Navigator.of(context).pop(pref),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// منوی کوچک حالت انتخاب سرور (مثل منوی کلاسیک: تیک کنار گزینه فعال).
class _ModeDialog extends StatelessWidget {
  const _ModeDialog({required this.current});

  final SelectionMode current;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: AppMetrics.space10, bottom: AppMetrics.space6, left: AppMetrics.space6, right: AppMetrics.space6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppMetrics.space4, AppMetrics.space4, AppMetrics.space4, AppMetrics.space2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: AppMetrics.space2,
                  right: AppMetrics.space2,
                  bottom: AppMetrics.space2,
                ),
                child: Text(
                  Fa.num('حالت انتخاب سرور'),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              for (final SelectionMode mode in SelectionModeList.visible)
                _MenuTile(
                  selected: mode == current,
                  title: mode.faName,
                  subtitle: mode.description,
                  leading: Icon(
                    mode.icon,
                    size: AppMetrics.iconMd,
                    color: context.colors.textSecondary,
                  ),
                  onTap: () => Navigator.of(context).pop(mode),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.selected,
    required this.title,
    required this.onTap,
    required this.leading,
    this.subtitle = '',
    this.enabled = true,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final Widget leading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: enabled ? onTap : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppMetrics.space1),
          padding: const EdgeInsets.symmetric(horizontal: AppMetrics.space3, vertical: AppMetrics.space2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            color: selected
                ? colors.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(width: AppMetrics.space7, child: Center(child: leading)),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      Fa.num(title),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selected ? colors.primary : null,
                          ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        Fa.num(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: AppMetrics.iconSm, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
