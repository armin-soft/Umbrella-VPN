import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/settings_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';
import '../widgets/flag_view.dart';
import '../widgets/live_clock.dart';

/// وضعیت اتصال: یک نگاه کوتاه به این که تونل زنده است یا نه.
///
/// چیدمان پیشین یک لیست بلند `InfoRow` بود که همه چیز را هم وزن نشان می داد.
/// حالا بالای صفحه یک هدر وضعیت با آیکون بزرگ و رنگ روشن است، بعد چهار کارت
/// آماری (پینگ، مدت، دریافتی، ارسالی) و در پایان دو کارت «سرور» و «برنامه».
class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final AuthController auth = context.watch<AuthController>();
    final SettingsController settings = context.watch<SettingsController>();
    final UmbrellaColors colors = context.colors;
    final VpnStatus status = vpn.status;
    final Color tone = VpnVisuals.color(context, status);
    final bool connected = status == VpnStatus.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
            title: 'وضعیت اتصال',
            subtitle: 'تونل، سرعت و عبور واقعی ترافیک در یک نگاه.',
            icon: Icons.monitor_heart_rounded,
          ),
          const SizedBox(height: 16),
          _StatusHero(
            status: status,
            tone: tone,
            connected: connected,
            flagCode: connected ? _flagCode(vpn) : '',
            countryName: connected ? _countryName(vpn) : '',
            pingMs: vpn.activePingMs,
            verified: vpn.tunnelVerified,
            colors: colors,
          ),
          const SizedBox(height: 16),

          // ── چهار عدد اصلی ──────────────────────────────────────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // در پنجره باریک دو به دو، در پهن هر چهار تا کنار هم.
              final int perRow = constraints.maxWidth < 720 ? 2 : 4;
              final List<Widget> tiles = <Widget>[
                StatTile(
                  label: 'پینگ زنده',
                  value: vpn.activePingMs > 0
                      ? Fa.ms(vpn.activePingMs)
                      : 'در حال سنجش',
                  icon: Icons.speed_rounded,
                  accent: connected ? colors.success : colors.textSecondary,
                  compact: perRow == 4,
                ),
                StatTile(
                  label: 'مدت اتصال',
                  value: connected
                      ? Fa.duration(vpn.stats.connectedFor)
                      : '—',
                  icon: Icons.timer_outlined,
                  accent: colors.info,
                  compact: perRow == 4,
                ),
                StatTile(
                  label: 'دریافتی',
                  value: vpn.stats.available ? Fa.bytes(vpn.stats.rx) : '—',
                  icon: Icons.south_rounded,
                  accent: colors.primary,
                  compact: perRow == 4,
                ),
                StatTile(
                  label: 'ارسالی',
                  value: vpn.stats.available ? Fa.bytes(vpn.stats.tx) : '—',
                  icon: Icons.north_rounded,
                  accent: colors.warning,
                  compact: perRow == 4,
                ),
              ];
              return _TileGrid(tiles: tiles, perRow: perRow);
            },
          ),
          const SizedBox(height: 16),

          // ── سرور و برنامه ─────────────────────────────────────────
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget server =
                  _ServerCard(vpn: vpn, settings: settings, colors: colors);
              final Widget app = _AppCard(auth: auth, colors: colors);
              if (constraints.maxWidth < 700) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[server, const SizedBox(height: 16), app],
                );
              }
              // دو کارت هم ارتفاع می شوند تا لبه پایین یکی نباشد.
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: server),
                    const SizedBox(width: 16),
                    Expanded(child: app),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Center(
            child: LiveDateTimeLine(
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// شبکه کارت های آماری با تعداد ستون مشخص.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, required this.perRow});

  final List<Widget> tiles;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += perRow) {
      final List<Widget> row = tiles.sublist(
        i,
        i + perRow > tiles.length ? tiles.length : i + perRow,
      );
      rows.add(
        // ارتفاع کارت ها برابر می شود؛ بدون IntrinsicHeight، stretch در
        // Column بی نهایت (اسکرول) خطا می داد.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int j = 0; j < perRow; j++) ...<Widget>[
                if (j < row.length)
                  Expanded(child: row[j])
                else
                  const Spacer(),
                if (j < perRow - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      );
      if (i + perRow < tiles.length) {
        rows.add(const SizedBox(height: 12));
      }
    }
    return Column(children: rows);
  }
}

/// پرچم کشور سرور متصل: اول از خود گره، بعد از کشور واقعی خروجی.
String _flagCode(VpnController vpn) {
  final String fromNode = vpn.activeNode?.flagCode ?? '';
  if (fromNode.isNotEmpty) {
    return fromNode;
  }
  return vpn.geo.flagCode;
}

String _countryName(VpnController vpn) => CountryNames.fa(_flagCode(vpn));

/// هدر وضعیت: آیکون بزرگ، برچسب وضعیت و راهنمای یک خطی.
class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.status,
    required this.tone,
    required this.connected,
    required this.flagCode,
    required this.countryName,
    required this.pingMs,
    required this.verified,
    required this.colors,
  });

  final VpnStatus status;
  final Color tone;
  final bool connected;
  final String flagCode;
  final String countryName;
  final int pingMs;
  final bool verified;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      radius: 22,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: <Color>[
          tone.withValues(alpha: 0.16),
          colors.surface,
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = constraints.maxWidth < 460;
          final Widget icon = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.16),
              border: Border.all(color: tone.withValues(alpha: 0.45)),
            ),
            child: Icon(VpnVisuals.icon(status), size: 30, color: tone),
          );
          final Widget text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Fa.num(status.label),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                    ),
              ),
              if (connected && flagCode.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    FlagView(code: flagCode, width: 26),
                    if (countryName.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 7),
                      Text(
                        Fa.num(countryName),
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 3),
              Text(
                Fa.num(
                  connected
                      ? (verified
                          ? 'ترافیک واقعی از تونل عبور می کند.'
                          : 'اتصال برقرار است؛ تایید عبور ترافیک در جریان است.')
                      : _statusHint(status),
                ),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary, height: 1.6),
              ),
            ],
          );
          return Row(
            children: <Widget>[
              icon,
              SizedBox(width: narrow ? 14 : 18),
              Expanded(child: text),
              if (connected && !narrow)
                Pill(
                  label: verified ? 'تایید شد' : 'در انتظار تایید',
                  icon: verified
                      ? Icons.verified_rounded
                      : Icons.hourglass_bottom_rounded,
                  color: verified ? colors.success : colors.warning,
                  dense: true,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// سرور فعال؛ نام سرور فقط همین جا و در گزارش ها دیده می شود.
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.vpn,
    required this.settings,
    required this.colors,
  });

  final VpnController vpn;
  final SettingsController settings;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    final VpnNode? node = vpn.activeNode;
    final bool has = node != null && vpn.status.active;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'سرور و اتصال',
            subtitle: 'همان چیزی که تونل را می سازد',
          ),
          const SizedBox(height: 12),
          InfoRow(
            icon: Icons.dns_rounded,
            label: 'سرور',
            value: Fa.num(has ? node.name : 'انتخاب نشده'),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.lock_outline_rounded,
            label: 'پروتکل',
            value: Fa.num(has ? node.protocol.label : '—'),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.memory_rounded,
            label: 'هسته',
            value: 'آمبرلا',
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.wifi_tethering_rounded,
            label: 'حالت اتصال',
            value: Fa.num(
              has
                  ? (settings.settings.tunMode
                      ? 'تونل کامل (TUN)'
                      : 'پروکسی سیستمی')
                  : '—',
            ),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.public_rounded,
            label: 'کشور خروجی',
            value: Fa.num(
              vpn.geo.ip.isNotEmpty ? vpn.geo.countryLabel : 'در حال خواندن',
            ),
          ),
        ],
      ),
    );
  }
}

/// نسخه، حساب و وضعیت بررسی.
class _AppCard extends StatelessWidget {
  const _AppCard({required this.auth, required this.colors});

  final AuthController auth;
  final UmbrellaColors colors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(
            title: 'برنامه',
            subtitle: 'نسخه، حساب و بررسی ها',
          ),
          const SizedBox(height: 12),
          InfoRow(
            icon: Icons.tag_rounded,
            label: 'نسخه',
            value: Fa.num(AppConfig.versionLabel),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.person_rounded,
            label: 'حساب',
            value: Fa.num(auth.account.displayName),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.workspace_premium_rounded,
            label: 'سرویس',
            value: Fa.num(auth.account.planLabel),
          ),
          const Divider(height: 14),
          InfoRow(
            icon: Icons.window_rounded,
            label: 'سیستم',
            value: 'ویندوز ۱۰ و ۱۱ (۶۴ بیت)',
          ),
        ],
      ),
    );
  }
}

/// راهنمای یک خطی زیر برچسب وضعیت.
String _statusHint(VpnStatus status) {
  switch (status) {
    case VpnStatus.connected:
      return 'تونل فعال است.';
    case VpnStatus.connecting:
    case VpnStatus.reconnecting:
    case VpnStatus.switching:
    case VpnStatus.preparing:
      return 'در حال ساختن تونل؛ چند لحظه صبر کنید.';
    case VpnStatus.disconnecting:
      return 'در حال بستن تونل.';
    case VpnStatus.failed:
      return 'اتصال برقرار نشد؛ گزارش ها را ببینید.';
    case VpnStatus.disconnected:
      return 'برای اتصال به صفحه «اتصال» بروید.';
  }
}
