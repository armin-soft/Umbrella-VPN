import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/update_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../pages/about_page.dart';
import '../pages/account_page.dart';
import '../pages/connect_page.dart';
import '../pages/logs_page.dart';
import '../pages/device_page.dart';
import '../pages/settings_page.dart';
import '../pages/updates_page.dart';
import '../widgets/common.dart';
import '../widgets/shell_widgets.dart';

/// پوسته برنامه: نوار عنوان، نوار کنار و بخش ها.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.windowService});

  final WindowService windowService;

  /// پنجره روی دسکتاپ ویندوز وقتی تمرکز را از دست بدهد (مثلاً کلیک روی نوار
  /// وظیفه، دیالوگ سیستم یا پنجره دیگر) وارد وضعیت `inactive` می شود ولی
  /// همچنان کاملاً مقابل چشم کاربر است. فقط در `hidden`/`paused`/`detached`
  /// واقعاً پنهان است؛ خاموش کردن تیکرها در `inactive` بارگذاری تصویر وضعیت
  /// (لوگوی وسط صفحه اتصال) و انیمیشن تغییر رنگ کارت/دکمه را متوقف می کرد.
  static bool isLifecycleVisible(AppLifecycleState? state) {
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _appVisible = true;
  bool _assetsPrecached = false;
  StreamSubscription<String>? _traySub;

  static const List<NavDestination> _destinations = <NavDestination>[
    NavDestination(label: 'اتصال', icon: Icons.shield_outlined, activeIcon: Icons.shield_rounded),
    NavDestination(label: 'دستگاه من', icon: Icons.computer_outlined, activeIcon: Icons.computer_rounded),
    NavDestination(label: 'حساب من', icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded),
    NavDestination(label: 'تنظیمات', icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded),
    NavDestination(label: 'گزارش ها', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded),
    NavDestination(label: 'درباره', icon: Icons.info_outline_rounded, activeIcon: Icons.info_rounded),
    // به روزرسانی همیشه آخر فهرست می ماند.
    NavDestination(label: 'به روز رسانی', icon: Icons.system_update_outlined, activeIcon: Icons.system_update_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appVisible = AppShell.isLifecycleVisible(
      WidgetsBinding.instance.lifecycleState,
    );
    final NativeBridge native = context.read<NativeBridge>();
    _traySub = native.trayEvents.listen(_handleTrayEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assetsPrecached) {
      return;
    }
    _assetsPrecached = true;
    // پیش بارگذاری لوگو و تصویرهای وضعیت تا هنگام جابه جایی بین «قطع»،
    // «در حال اتصال»، «متصل» و «خطا» هیچ فریم خالی دیده نشود.
    for (final String asset in <String>[
      BrandAssets.logo,
      ...BrandAssets.all,
    ]) {
      unawaited(
        precacheImage(AssetImage(asset), context).catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _traySub?.cancel();
    super.dispose();
  }

  void _triggerAutoSync() {
    if (!mounted) {
      return;
    }
    final AuthController auth = context.read<AuthController>();
    final SubscriptionController subs = context.read<SubscriptionController>();
    final VpnController vpn = context.read<VpnController>();
    if (auth.signedIn) {
      unawaited(auth.autoSync());
      if (!subs.personalLoading && !subs.loadingAll) {
        unawaited(subs.syncPersonal());
      }
    }
    unawaited(vpn.refreshIp());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool visible = AppShell.isLifecycleVisible(state);
    if (_appVisible != visible && mounted) {
      setState(() => _appVisible = visible);
    }
    if (state == AppLifecycleState.resumed) {
      _triggerAutoSync();
    }
  }

  Future<void> _handleTrayEvent(String event) async {
    final VpnController vpn = context.read<VpnController>();
    switch (event) {
      case 'show':
        await widget.windowService.show();
        if (mounted && !_appVisible) {
          setState(() => _appVisible = true);
        }
        _triggerAutoSync();
        break;
      case 'servers':
        await widget.windowService.show();
        if (mounted) {
          setState(() {
            _appVisible = true;
            _index = 0;
          });
        }
        break;
      case 'settings':
        await widget.windowService.show();
        if (mounted) {
          setState(() {
            _appVisible = true;
            _index = 3;
          });
        }
        break;
      case 'toggle':
        if (vpn.status.active) {
          await vpn.disconnect();
        } else {
          await vpn.connect();
        }
        break;
      case 'quit':
        await vpn.shutdownForExit();
        await widget.windowService.quit();
        break;
      default:
        break;
    }
  }

  void _openNotifications() {
    final AuthController auth = context.read<AuthController>();
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _NotificationsDialog(auth: auth);
      },
    );
  }

  Widget _buildActivePage(int index) {
    switch (index) {
      case 1:
        return const DevicePage();
      case 2:
        return const AccountPage();
      case 3:
        return const SettingsPage();
      case 4:
        return const LogsPage();
      case 5:
        return const AboutPage();
      case 6:
        return const UpdatesPage();
      case 0:
      default:
        return const ConnectPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final VpnStatus vpnStatus = context.select<VpnController, VpnStatus>(
      (VpnController v) => v.status,
    );
    final int unreadCount = context.select<AuthController, int>(
      (AuthController a) => a.unreadCount,
    );
    final bool hasUpdate = context.select<UpdateController, bool>(
      (UpdateController u) => u.available != null,
    );
    final SettingsController settings = context.read<SettingsController>();
    final UmbrellaColors colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: <Widget>[
          TitleBar(
            status: vpnStatus,
            onDragStart: widget.windowService.startDragging,
            onMinimize: widget.windowService.minimize,
            onMaximize: widget.windowService.toggleMaximize,
            onClose: () => widget.windowService.onWindowClose(),
            unread: unreadCount,
            onNotifications: _openNotifications,
            onToggleTheme: () => settings.toggleTheme(
              effectiveBrightness: Theme.of(context).brightness,
            ),
            darkTheme: Theme.of(context).brightness == Brightness.dark,
          ),
          Expanded(
            // در چیدمان راست به چپ، فرزند اول سمت راست می نشیند؛ پس نوار کنار
            // اول می آید تا در لبه راست پنجره باشد.
            child: Row(
              children: <Widget>[
                SideNav(
                  destinations: _destinations,
                  index: _index,
                  onSelect: (int value) {
                    if (_index != value) {
                      setState(() => _index = value);
                    }
                  },
                  status: vpnStatus,
                  onStatusTap: () {
                    if (_index != 0) {
                      setState(() => _index = 0);
                    }
                  },
                  updateAvailable: hasUpdate,
                ),
                Expanded(
                  // همه صفحات با `SizedBox.expand` تمام ارتفاع ناحیه محتوا را
                  // پر می کنند تا صفحات کوتاه تر (مثل «دستگاه من» و «درباره»)
                  // به وسط پنجره نیفتند و سربرگ تمام منوها دقیقاً از یک خط بالا
                  // با فاصله یکسان شروع شود.
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppMetrics.maxContentWidth,
                      ),
                      child: SizedBox.expand(
                        child: RepaintBoundary(
                          child: TickerMode(
                            enabled: _appVisible,
                            child: _buildActivePage(_index),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsDialog extends StatefulWidget {
  const _NotificationsDialog({required this.auth});

  final AuthController auth;

  @override
  State<_NotificationsDialog> createState() => _NotificationsDialogState();
}

/// مرکز اعلان ها: نمایش اعلان های تازه و تمام اعلان های قبلی به ترتیب زمان،
/// همراه با فیلتر «همه / خوانده نشده»، باز کردن متن کامل و به روز رسانی.
class _NotificationsDialogState extends State<_NotificationsDialog> {
  bool _unreadOnly = false;
  final Set<String> _expandedKeys = <String>{};
  Timer? _autoPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.auth.fetchNotifications(includeHistory: true));
    });
    _autoPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && widget.auth.signedIn) {
        unawaited(widget.auth.fetchNotifications(includeHistory: true));
      }
    });
  }

  @override
  void dispose() {
    _autoPollTimer?.cancel();
    super.dispose();
  }

  static Color _tone(UmbrellaColors colors, String level) {
    switch (level.toLowerCase()) {
      case 'error':
      case 'danger':
        return colors.danger;
      case 'warning':
        return colors.warning;
      case 'success':
        return colors.success;
      default:
        return colors.info;
    }
  }

  static IconData _icon(String level) {
    switch (level.toLowerCase()) {
      case 'error':
      case 'danger':
        return Icons.error_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'success':
        return Icons.check_circle_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  void _onTapItem(AppNotification item) {
    final String key = item.identityKey;
    widget.auth.markNotificationRead(item);
    setState(() {
      if (!_expandedKeys.remove(key)) {
        _expandedKeys.add(key);
      }
    });
  }

  static String _headerSubtitle(int total, int unread) {
    if (total == 0) {
      return 'هنوز اعلانی ثبت نشده است';
    }
    if (unread > 0) {
      return '${Fa.num(unread)} اعلان خوانده نشده از ${Fa.num(total)} اعلان';
    }
    return '${Fa.num(total)} اعلان ثبت شده (همه خوانده شده)';
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppMetrics.space7),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppMetrics.dialogMaxWidth,
          maxHeight: AppMetrics.dialogMaxHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.space5,
            AppMetrics.space5,
            AppMetrics.space5,
            AppMetrics.space4,
          ),
          child: ListenableBuilder(
            listenable: widget.auth,
            builder: (BuildContext context, Widget? child) {
              final List<AppNotification> all = widget.auth.notifications;
              final int unread = widget.auth.unreadCount;
              final bool loading = widget.auth.loadingNotifications;
              final List<AppNotification> items = _unreadOnly
                  ? all.where((AppNotification n) => !n.read).toList()
                  : all;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── سرصفحه ──────────────────────────────────────────
                  Row(
                    children: <Widget>[
                      IconSquare(
                        icon: Icons.notifications_active_rounded,
                        color: colors.primary,
                        size: AppMetrics.iconBoxLg,
                      ),
                      const SizedBox(width: AppMetrics.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              Fa.num('اعلان ها'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              Fa.num(_headerSubtitle(all.length, unread)),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppMetrics.space2,
                          ),
                          child: SizedBox(
                            width: AppMetrics.iconSm,
                            height: AppMetrics.iconSm,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      const SizedBox(width: AppMetrics.space2),
                      IconAction(
                        icon: Icons.close_rounded,
                        tooltip: 'بستن',
                        size: AppMetrics.iconBoxSm,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppMetrics.space3),

                  // ── فیلترها ─────────────────────────────────────────
                  Row(
                    children: <Widget>[
                      _FilterChip(
                        label: 'همه',
                        count: all.length,
                        selected: !_unreadOnly,
                        onTap: () => setState(() => _unreadOnly = false),
                      ),
                      const SizedBox(width: AppMetrics.space2),
                      _FilterChip(
                        label: 'خوانده نشده',
                        count: unread,
                        selected: _unreadOnly,
                        onTap: () => setState(() => _unreadOnly = true),
                      ),
                      const Spacer(),
                      if (unread > 0)
                        TextButton.icon(
                          onPressed: widget.auth.markNotificationsRead,
                          icon: const Icon(
                            Icons.done_all_rounded,
                            size: AppMetrics.iconSm,
                          ),
                          label: Text(Fa.num('همه خوانده شد')),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppMetrics.space3),
                  const Divider(height: AppMetrics.space1),
                  const SizedBox(height: AppMetrics.space3),

                  // ── فهرست اعلان های تازه و قبلی ─────────────────────
                  Expanded(
                    child: items.isEmpty
                        ? EmptyState(
                            icon: _unreadOnly
                                ? Icons.mark_email_read_rounded
                                : Icons.notifications_off_rounded,
                            title: _unreadOnly
                                ? 'اعلان خوانده نشده ای نیست'
                                : 'اعلانی وجود ندارد',
                            message: _unreadOnly
                                ? 'برای مشاهده اعلان های قبلی روی بخش «همه» بزنید.'
                                : 'اعلان های تازه و قبلی حساب و اشتراک شما اینجا نگهداری و نمایش داده می شوند.',
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder:
                                (BuildContext context, int index) =>
                                    const SizedBox(height: AppMetrics.space2),
                            itemBuilder: (BuildContext context, int index) {
                              final AppNotification item = items[index];
                              final Color tone = _tone(colors, item.level);
                              final bool expanded =
                                  _expandedKeys.contains(item.identityKey);
                              return GlassCard(
                                onTap: () => _onTapItem(item),
                                padding: const EdgeInsets.all(AppMetrics.space3),
                                radius: AppMetrics.radiusMd,
                                borderColor: !item.read
                                    ? colors.primary.withValues(alpha: 0.4)
                                    : colors.border,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    IconSquare(
                                      icon: _icon(item.level),
                                      color: tone,
                                      size: AppMetrics.iconBoxSm,
                                    ),
                                    const SizedBox(width: AppMetrics.space3),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Row(
                                            children: <Widget>[
                                              if (!item.read) ...<Widget>[
                                                Container(
                                                  width: AppMetrics.space2,
                                                  height: AppMetrics.space2,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: colors.primary,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: AppMetrics.space2,
                                                ),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  Fa.num(item.compactTitle),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        color:
                                                            colors.textPrimary,
                                                        fontWeight: !item.read
                                                            ? FontWeight.w800
                                                            : FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(
                                                width: AppMetrics.space2,
                                              ),
                                              Text(
                                                Fa.num(
                                                  Fa.relative(item.sentAt),
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          colors.textSecondary,
                                                      fontSize:
                                                          AppMetrics.fontMicro,
                                                    ),
                                              ),
                                            ],
                                          ),
                                          if (item.compactBody.isNotEmpty) ...<
                                              Widget>[
                                            const SizedBox(
                                              height: AppMetrics.space1,
                                            ),
                                            Text(
                                              Fa.num(item.compactBody),
                                              maxLines: expanded ? 4 : 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.textSecondary,
                                                    height: 1.5,
                                                  ),
                                            ),
                                          ],
                                          if (expanded &&
                                              item.sentAt != null) ...<Widget>[
                                            const SizedBox(
                                              height: AppMetrics.space2,
                                            ),
                                            Text(
                                              Fa.num(
                                                Fa.dateTime(item.sentAt),
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.textSecondary,
                                                    fontSize:
                                                        AppMetrics.fontMicro,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: AppMetrics.space3),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.check_rounded,
                      size: AppMetrics.iconSm,
                    ),
                    label: Text(Fa.num('بستن')),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// چیپ فیلتر اعلان ها با شمارنده.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.space3,
          vertical: AppMetrics.space2,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.16)
              : colors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              Fa.num(label),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    color: selected ? colors.primary : colors.textSecondary,
                  ),
            ),
            const SizedBox(width: AppMetrics.space1),
            Text(
              Fa.num(count),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? colors.primary : colors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
