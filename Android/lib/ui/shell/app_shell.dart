import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/security_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/subscription_controller.dart';
import '../../state/update_controller.dart';
import '../../vpn/clash_api.dart';
import '../../vpn/vpn_controller.dart';
import '../pages/about_page.dart';
import '../pages/account_page.dart';
import '../pages/connect_page.dart';
import '../pages/device_page.dart';
import '../pages/exit_page.dart';
import '../pages/logs_page.dart';
import '../pages/settings_page.dart';
import '../pages/updates_page.dart';
import '../widgets/common.dart';
import '../widgets/shell_widgets.dart';
import '../widgets/telegram_channel_dialog.dart';

/// پوسته اصلی برنامه: ناوبری واکنش گرا در گوشی (نوار پایین) و تبلت (نوار کنار).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.windowService});

  final WindowService windowService;

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
  bool _telegramPromptOpen = false;
  Timer? _telegramInitTimer;
  Timer? _telegramPeriodicTimer;
  AuthController? _boundAuth;

  static const List<NavDestination> _destinations = <NavDestination>[
    NavDestination(label: 'اتصال', icon: Icons.shield_outlined, activeIcon: Icons.shield_rounded),
    NavDestination(label: 'دستگاه من', icon: Icons.smartphone_outlined, activeIcon: Icons.smartphone_rounded),
    NavDestination(label: 'حساب من', icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded),
    NavDestination(label: 'تنظیمات', icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded),
    NavDestination(label: 'گزارش ها', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded),
    NavDestination(label: 'درباره', icon: Icons.info_outline_rounded, activeIcon: Icons.info_rounded),
    NavDestination(label: 'به روز رسانی', icon: Icons.system_update_outlined, activeIcon: Icons.system_update_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ActivityMonitorBuffer.instance.recordScreen(_destinations[_index].label);
    _appVisible = AppShell.isLifecycleVisible(
      WidgetsBinding.instance.lifecycleState,
    );
    _telegramInitTimer = Timer(const Duration(milliseconds: 550), () {
      unawaited(_maybeShowTelegramChannelPrompt());
    });
    _telegramPeriodicTimer = Timer.periodic(const Duration(hours: 6), (_) {
      unawaited(_maybeShowTelegramChannelPrompt());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AuthController? auth = context.maybeRead<AuthController>();
    if (!identical(_boundAuth, auth)) {
      if (_boundAuth?.onAnnouncementUpdated == _onAnnouncementUpdated) {
        _boundAuth?.onAnnouncementUpdated = null;
      }
      _boundAuth = auth;
      if (auth != null) {
        auth.onAnnouncementUpdated = _onAnnouncementUpdated;
      }
    }
    if (_assetsPrecached) {
      return;
    }
    _assetsPrecached = true;
    for (final String asset in <String>[
      BrandAssets.logo,
      ...BrandAssets.all,
    ]) {
      unawaited(
        precacheImage(AssetImage(asset), context).catchError((Object _) {}),
      );
    }
  }

  void _onAnnouncementUpdated(AppAnnouncement _) {
    unawaited(_maybeShowTelegramChannelPrompt());
  }

  @override
  void dispose() {
    if (_boundAuth?.onAnnouncementUpdated == _onAnnouncementUpdated) {
      _boundAuth?.onAnnouncementUpdated = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _telegramInitTimer?.cancel();
    _telegramPeriodicTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShowTelegramChannelPrompt() async {
    if (!mounted ||
        !_appVisible ||
        widget.windowService.isHiddenToTray ||
        _telegramPromptOpen) {
      return;
    }
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }
    _telegramPromptOpen = true;
    try {
      final AuthController? auth = context.maybeRead<AuthController>();
      if (auth != null) {
        await TelegramChannelPrompt.showAnnouncementIfDue(
          context,
          announcement: auth.announcement,
        );
      } else {
        await TelegramChannelPrompt.showIfDue(context);
      }
    } catch (_) {
      // خطای احتمالی انبار محلی هرگز نباید کار پوسته اصلی را متوقف کند.
    } finally {
      _telegramPromptOpen = false;
    }
  }

  DateTime? _lastAutoSyncAt;

  void _triggerAutoSync() {
    if (!mounted) {
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime? last = _lastAutoSyncAt;
    if (last != null &&
        now.difference(last) < const Duration(seconds: 45)) {
      return;
    }
    _lastAutoSyncAt = now;
    final AuthController auth = context.read<AuthController>();
    final SubscriptionController subs = context.read<SubscriptionController>();
    final VpnController vpn = context.read<VpnController>();
    if (auth.signedIn) {
      unawaited(auth.autoSync());
      if (!subs.personalLoading && !subs.loadingAll) {
        unawaited(subs.syncPersonal());
      }
    }
    // فقط زمانی که تونل فعال نیست آی پی واقعی سیستم را بازخوانی کن تا آی پی
    // خروجی سرور VPN جایگزین آی پی واقعی پیش از اتصال نشود.
    if (!vpn.status.active && !vpn.status.busy) {
      unawaited(vpn.refreshIp());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool visible = AppShell.isLifecycleVisible(state);
    widget.windowService.setLifecycleVisible(visible);
    if (_appVisible != visible && mounted) {
      setState(() => _appVisible = visible);
    }
    if (state == AppLifecycleState.resumed) {
      _triggerAutoSync();
      final AuthController? auth = context.maybeRead<AuthController>();
      if (auth != null) {
        unawaited(auth.syncAnnouncement());
      }
      final SecurityScannerController? security =
          context.maybeRead<SecurityScannerController>();
      if (security != null) {
        unawaited(security.scanNow(silent: true));
      }
      unawaited(_maybeShowTelegramChannelPrompt());
    }
  }

  void _selectTab(int value) {
    playUiClick(context);
    setState(() {
      if (value == 3) {
        _settingsNavVersion++;
      }
      _index = value;
    });
    if (value >= 0 && value < _destinations.length) {
      ActivityMonitorBuffer.instance.recordScreen(_destinations[value].label);
    }
  }

  void _openMoreSheet(bool hasUpdate) {
    final UmbrellaColors colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: AppMetrics.dialogMaxWidth),
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.space4,
              AppMetrics.space4,
              AppMetrics.space4,
              AppMetrics.space5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: AppMetrics.space4),
                _MoreTile(
                  icon: Icons.smartphone_rounded,
                  title: 'دستگاه من',
                  subtitle:
                      'مشخصات سخت افزار، حافظه، سیستم عامل، شبکه و شناسه این دستگاه',
                  selected: _index == 1,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _selectTab(1);
                  },
                ),
                _MoreTile(
                  icon: Icons.system_update_rounded,
                  title: 'به روز رسانی',
                  subtitle: hasUpdate
                      ? 'نسخه جدید آماده دریافت و نصب است'
                      : 'بررسی انتشارهای جدید برنامه',
                  badge: hasUpdate,
                  selected: _index == 6,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _selectTab(6);
                  },
                ),
                _MoreTile(
                  icon: Icons.info_rounded,
                  title: 'درباره',
                  subtitle:
                      'مشخصات نسخه، راه های ارتباط با پشتیبانی و بررسی دسترسی',
                  selected: _index == 5,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _selectTab(5);
                  },
                ),
                _MoreTile(
                  icon: Icons.power_settings_new_rounded,
                  title: 'خروج',
                  subtitle: 'قطع اتصال و بستن کامل برنامه',
                  danger: true,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final VpnController vpn = context.read<VpnController>();
                    await showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        insetPadding: const EdgeInsets.all(AppMetrics.space4),
                        child: ExitPage(
                          onCancelTap: () => Navigator.of(context).pop(),
                          onExit: () async {
                            Navigator.of(context).pop();
                            await vpn.disconnect(silent: true);
                            await widget.windowService.quit();
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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

  int _settingsNavVersion = 0;

  Widget _buildActivePage(int index) {
    switch (index) {
      case 1:
        return const DevicePage();
      case 2:
        return const AccountPage();
      case 3:
        return SettingsPage(key: ValueKey<int>(_settingsNavVersion));
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

  int _mobileNavIndex() {
    switch (_index) {
      case 0:
        return 0;
      case 2:
        return 1;
      case 3:
        return 2;
      case 4:
        return 3;
      default:
        return 4;
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
    final Size viewport = MediaQuery.sizeOf(context);
    final bool landscapePhone = AppMetrics.isLandscapePhone(context);
    final bool compact = viewport.width < AppMetrics.breakpointPhone && !landscapePhone;

    final Widget pageStack = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppMetrics.maxContentWidth,
        ),
        child: SizedBox.expand(
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Offstage(
                  offstage: _index != 1,
                  child: TickerMode(
                    enabled: _appVisible && _index == 1,
                    child: MenuPageBackdrop(
                      child: const DevicePage(),
                    ),
                  ),
                ),
                Offstage(
                  offstage: _index != 6,
                  child: TickerMode(
                    enabled: _appVisible && _index == 6,
                    child: MenuPageBackdrop(
                      child: const UpdatesPage(),
                    ),
                  ),
                ),
                if (_index != 1 && _index != 6)
                  TickerMode(
                    enabled: _appVisible,
                    child: _index == 0
                        ? _buildActivePage(_index)
                        : MenuPageBackdrop(
                            child: _buildActivePage(_index),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _index != 0) {
          _selectTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: Column(
          children: <Widget>[
            TitleBar(
              status: vpnStatus,
              unread: unreadCount,
              onNotifications: _openNotifications,
              onToggleTheme: () => settings.toggleTheme(
                effectiveBrightness: Theme.of(context).brightness,
              ),
              darkTheme: Theme.of(context).brightness == Brightness.dark,
            ),
            Expanded(
              child: compact
                  ? pageStack
                  : Row(
                      children: <Widget>[
                        SideNav(
                          destinations: _destinations,
                          index: _index,
                          onSelect: _selectTab,
                          status: vpnStatus,
                          onStatusTap: () {
                            if (_index != 0) {
                              _selectTab(0);
                            } else {
                              playUiClick(context);
                            }
                          },
                          updateAvailable: hasUpdate,
                        ),
                        Expanded(child: pageStack),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: compact
            ? Container(
                decoration: BoxDecoration(
                  color: colors.backgroundAlt,
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: NavigationBarTheme(
                    data: NavigationBarThemeData(
                      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
                        (Set<WidgetState> states) {
                          final bool selected =
                              states.contains(WidgetState.selected);
                          return Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontSize: AppMetrics.isCompactWidth(context)
                                    ? 10.5
                                    : 11.5,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              );
                        },
                      ),
                    ),
                    child: NavigationBar(
                    height: 64,
                    selectedIndex: _mobileNavIndex(),
                    backgroundColor: colors.backgroundAlt,
                    indicatorColor: colors.primary.withValues(alpha: 0.16),
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    onDestinationSelected: (int navIdx) {
                      switch (navIdx) {
                        case 0:
                          _selectTab(0);
                          break;
                        case 1:
                          _selectTab(2);
                          break;
                        case 2:
                          _selectTab(3);
                          break;
                        case 3:
                          _selectTab(4);
                          break;
                        case 4:
                          playUiClick(context);
                          _openMoreSheet(hasUpdate);
                          break;
                      }
                    },
                    destinations: <NavigationDestination>[
                      const NavigationDestination(
                        icon: Icon(Icons.shield_outlined),
                        selectedIcon: Icon(Icons.shield_rounded),
                        label: 'اتصال',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: 'حساب من',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: 'تنظیمات',
                      ),
                      const NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long_rounded),
                        label: 'گزارش ها',
                      ),
                      NavigationDestination(
                        icon: Badge(
                          isLabelVisible: hasUpdate,
                          child: const Icon(Icons.menu_rounded),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: hasUpdate,
                          child: const Icon(Icons.menu_open_rounded),
                        ),
                        label: 'بیشتر',
                      ),
                    ],
                  ),
                ),
                ),
              )
            : null,
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = false,
    this.selected = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool badge;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color tone = danger
        ? colors.danger
        : (selected ? colors.primary : colors.textPrimary);
    return ListTile(
      onTap: withUiClick(context, onTap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      ),
      tileColor: selected ? colors.primary.withValues(alpha: 0.1) : null,
      leading: Badge(
        isLabelVisible: badge,
        child: Icon(icon, color: tone),
      ),
      title: Text(
        Fa.num(title),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
            ),
      ),
      subtitle: Text(
        Fa.num(subtitle),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
      ),
      trailing: Icon(
        Icons.chevron_left_rounded,
        color: colors.textSecondary,
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
      insetPadding: AppMetrics.responsivePagePadding(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppMetrics.dialogMaxWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppMetrics.isCompactWidth(context) ? AppMetrics.space4 : AppMetrics.space5,
            AppMetrics.space4,
            AppMetrics.isCompactWidth(context) ? AppMetrics.space4 : AppMetrics.space5,
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
                  Wrap(
                    spacing: AppMetrics.space2,
                    runSpacing: AppMetrics.space2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _FilterChip(
                            icon: Icons.inbox_rounded,
                            label: 'همه',
                            count: all.length,
                            selected: !_unreadOnly,
                            onTap: () => setState(() => _unreadOnly = false),
                          ),
                          const SizedBox(width: AppMetrics.space2),
                          _FilterChip(
                            icon: Icons.mark_email_unread_rounded,
                            label: 'خوانده نشده',
                            count: unread,
                            selected: _unreadOnly,
                            onTap: () => setState(() => _unreadOnly = true),
                          ),
                        ],
                      ),
                      if (unread > 0)
                        TextButton.icon(
                          onPressed: withUiClick(
                            context,
                            widget.auth.markNotificationsRead,
                          ),
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
                    onPressed: withUiClick(context, () => Navigator.of(context).pop()),
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
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color fg = selected ? colors.primary : colors.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      onTap: withUiClick(context, onTap),
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
            Icon(icon, size: AppMetrics.iconXs, color: fg),
            const SizedBox(width: AppMetrics.space1),
            Text(
              Fa.num(label),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    color: fg,
                  ),
            ),
            const SizedBox(width: AppMetrics.space1),
            Text(
              Fa.num(count),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
