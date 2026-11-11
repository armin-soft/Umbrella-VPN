import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../platform/services.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import '../../state/update_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../pages/about_page.dart';
import '../pages/account_page.dart';
import '../pages/connect_page.dart';
import '../pages/logs_page.dart';
import '../pages/servers_page.dart';
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

class _AppShellState extends State<AppShell> {
  int _index = 0;
  StreamSubscription<String>? _traySub;

  static const List<NavDestination> _destinations = <NavDestination>[
    NavDestination(
      label: 'اتصال',
      icon: Icons.shield_outlined,
      activeIcon: Icons.shield_rounded,
    ),
    NavDestination(
      label: 'سرورها',
      icon: Icons.dns_outlined,
      activeIcon: Icons.dns_rounded,
    ),
    NavDestination(
      label: 'حساب من',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
    NavDestination(
      label: 'تنظیمات',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
    ),
    NavDestination(
      label: 'به روز رسانی',
      icon: Icons.system_update_outlined,
      activeIcon: Icons.system_update_rounded,
    ),
    NavDestination(
      label: 'گزارش ها',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
    ),
    NavDestination(
      label: 'درباره',
      icon: Icons.info_outline_rounded,
      activeIcon: Icons.info_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final NativeBridge native = context.read<NativeBridge>();
    _traySub = native.trayEvents.listen(_handleTrayEvent);
  }

  @override
  void dispose() {
    _traySub?.cancel();
    super.dispose();
  }

  Future<void> _handleTrayEvent(String event) async {
    final VpnController vpn = context.read<VpnController>();
    switch (event) {
      case 'show':
        await widget.windowService.show();
        break;
      case 'servers':
        await widget.windowService.show();
        setState(() => _index = 1);
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
    final UmbrellaColors colors = context.colors;

    final List<Widget> pages = <Widget>[
      ConnectPage(onOpenServers: () => setState(() => _index = 1)),
      const ServersPage(),
      AccountPage(onSignedOut: () => setState(() => _index = 0)),
      SettingsPage(onOpenAbout: () => setState(() => _index = 6)),
      const UpdatesPage(),
      const LogsPage(),
      const AboutPage(),
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
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: pages,
                  ),
                ),
                SideNav(
                  destinations: _destinations,
                  index: _index,
                  onSelect: (int value) => setState(() => _index = value),
                  status: vpn.status,
                  onStatusTap: () => setState(() => _index = 0),
                  updateAvailable: updates.available != null,
                ),
              ],
            ),
          ),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.backgroundAlt,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  vpn.killSwitchOn ? Icons.gpp_good_rounded : Icons.gpp_maybe_rounded,
                  size: 13,
                  color: vpn.killSwitchOn ? colors.success : colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  Fa.num(vpn.killSwitchOn ? 'کیل سوییچ روشن' : 'کیل سوییچ خاموش'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 10,
                      ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.hub_rounded, size: 13, color: colors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  Fa.num('${Fa.num(vpn.nodes.length)} سرور | ${vpn.settings.selectionMode.faName}'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 10,
                      ),
                ),
                const Spacer(),
                if (vpn.activeNode != null)
                  Text(
                    Fa.num(vpn.activeNode!.name),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
                  ),
                const SizedBox(width: 14),
                Text(
                  Fa.num('${AppConfig.appName} ${AppConfig.version}'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontSize: 10,
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

class _NotificationsDialogState extends State<_NotificationsDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.auth.fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconSquare(
                    icon: Icons.notifications_active_rounded,
                    color: colors.primary,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      Fa.num('اعلان ها'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconAction(
                    icon: Icons.close_rounded,
                    size: 32,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.auth,
                  builder: (BuildContext context, Widget? child) {
                    final int count = widget.auth.notifications.length;
                    if (count == 0) {
                      return const EmptyState(
                        icon: Icons.notifications_off_rounded,
                        title: 'اعلانی وجود ندارد',
                        message: 'اعلان های حساب و اتصال اینجا نمایش داده می شوند.',
                      );
                    }
                    return ListView.separated(
                      itemCount: count,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final AppNotification item = widget.auth.notifications[index];
                        return GlassCard(
                          padding: const EdgeInsets.all(14),
                          radius: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                Fa.num(item.title),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              if (item.body.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  Fa.num(item.body),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  widget.auth.markNotificationsRead();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.done_all_rounded, size: 17),
                label: const Text('خوانده شد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
