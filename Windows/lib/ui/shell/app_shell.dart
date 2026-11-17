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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _appVisible = true;
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
    _appVisible = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final NativeBridge native = context.read<NativeBridge>();
    _traySub = native.trayEvents.listen(_handleTrayEvent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _traySub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool visible = state == AppLifecycleState.resumed;
    if (_appVisible != visible && mounted) {
      setState(() => _appVisible = visible);
    }
  }

  Future<void> _handleTrayEvent(String event) async {
    final VpnController vpn = context.read<VpnController>();
    switch (event) {
      case 'show':
        await widget.windowService.show();
        break;
      case 'servers':
        await widget.windowService.show();
        setState(() => _index = 0);
        break;
      case 'settings':
        await widget.windowService.show();
        setState(() => _index = 3);
        break;
      case 'toggle':
        if (vpn.status.active) {
          await vpn.disconnect();
        } else {
          await vpn.connect();
        }
        break;
      case 'quit':
        await vpn.disconnect(silent: true);
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

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final UpdateController updates = context.watch<UpdateController>();
    final SettingsController settings = context.watch<SettingsController>();
    final UmbrellaColors colors = context.colors;

    final List<Widget> pages = <Widget>[
      const ConnectPage(),
      const DevicePage(),
      const AccountPage(),
      const SettingsPage(),
      const LogsPage(),
      const AboutPage(),
      const UpdatesPage(),
    ];

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: <Widget>[
          TitleBar(
            status: vpn.status,
            onDragStart: widget.windowService.startDragging,
            onMinimize: widget.windowService.minimize,
            onMaximize: widget.windowService.toggleMaximize,
            onClose: () => widget.windowService.onWindowClose(),
            unread: auth.unreadCount,
            onNotifications: _openNotifications,
            onToggleTheme: settings.toggleTheme,
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
                  onSelect: (int value) => setState(() => _index = value),
                  status: vpn.status,
                  onStatusTap: () => setState(() => _index = 0),
                  updateAvailable: updates.available != null,
                ),
                Expanded(
                  // در پنجره های بسیار پهن (مثلا روی مانیتور ۲۷ اینچ) خط متن بی
                  // اندازه بلند می شد و منو ها از هم فاصله می گرفتند. محتوا حالا
                  // حداکثر به [AppMetrics.maxContentWidth] پهن می شود و در
                  // وسط پنجره می ایستد؛ نوار کناری همچنان لبه راست پنجره است.
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppMetrics.maxContentWidth,
                      ),
                      child: IndexedStack(
                        index: _index,
                        children: <Widget>[
                          for (int i = 0; i < pages.length; i++)
                            TickerMode(enabled: _appVisible && i == _index, child: pages[i]),
                        ],
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

/// مرکز اعلان ها: فهرست زمان بندی شده، فیلتر «خوانده نشده»، و شمارش.
///
/// نسخه پیشین یک لیست ساده بود. اینجا هر اعلان سرصفحه رنگی بر اساس سطح،
/// زمان نسبی و نقطه «خوانده نشده» دارد، و بالای صفحه شمارنده و دکمه
/// «همه خوانده شد» هست.
class _NotificationsDialogState extends State<_NotificationsDialog> {
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.auth.fetchNotifications();
    });
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
                              Fa.num(
                                unread > 0
                                    ? '${Fa.num(unread)} اعلان خوانده نشده از '
                                        '${Fa.num(all.length)}'
                                    : 'همه ${Fa.num(all.length)} اعلان خوانده '
                                        'شده است',
                              ),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconAction(
                        icon: Icons.close_rounded,
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

                  // ── فهرست ───────────────────────────────────────────
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
                                ? 'همه اعلان ها خوانده شده اند.'
                                : 'اعلان های حساب، اشتراک و اتصال اینجا نمایش '
                                    'داده می شوند.',
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder:
                                (BuildContext context, int index) =>
                                    const SizedBox(height: AppMetrics.space2),
                            itemBuilder: (BuildContext context, int index) {
                              final AppNotification item = items[index];
                              final Color tone = _tone(colors, item.level);
                              return GlassCard(
                                padding: const EdgeInsets.all(AppMetrics.space3),
                                radius: AppMetrics.radiusMd,
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
                                                  width: AppMetrics.space1,
                                                  height: AppMetrics.space1,
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
                                                  Fa.num(item.title),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight: !item.read
                                                            ? FontWeight.w900
                                                            : FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(width: AppMetrics.space2),
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
                                          if (item.body.isNotEmpty) ...<Widget>[
                                            const SizedBox(
                                              height: AppMetrics.space1,
                                            ),
                                            Text(
                                              Fa.num(item.body),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.textSecondary,
                                                    height: 1.5,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
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
