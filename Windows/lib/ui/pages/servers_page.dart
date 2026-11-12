import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/subscription_controller.dart';
import '../../state/toast_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../widgets/common.dart';

/// فهرست سرورها با پینگ، کیفیت و منبع.
class ServersPage extends StatefulWidget {
  const ServersPage({super.key});

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  String _sourceFilter = '';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final VpnController vpn = context.watch<VpnController>();
    final SubscriptionController subs = context.watch<SubscriptionController>();
    final ToastController toasts = context.read<ToastController>();
    final UmbrellaColors colors = context.colors;

    final List<VpnNode> nodes = vpn.nodes.where((VpnNode node) {
      final bool sourceOk = _sourceFilter.isEmpty || node.sourceId == _sourceFilter;
      final bool queryOk = _query.isEmpty ||
          node.name.contains(_query) ||
          node.host.contains(_query) ||
          node.protocol.label.contains(_query);
      return sourceOk && queryOk;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Fa.num('سرورها'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fa.num('${Fa.num(nodes.length)} سرور از ${subs.okSources} منبع | بهترین انتخاب: ${vpn.recommended?.name ?? 'نامشخص'}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (String value) => setState(() => _query = value.trim()),
                  decoration: const InputDecoration(
                    hintText: 'جستجوی سرور یا کشور',
                    prefixIcon: Icon(Icons.search_rounded, size: 19),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconAction(
                icon: Icons.refresh_rounded,
                tooltip: 'به روز رسانی اشتراک ها',
                size: 46,
                onTap: subs.loadingAll
                    ? () {}
                    : () async {
                        await subs.fetchAll();
                        toasts.success('فهرست سرورها به روز شد');
                      },
              ),
              const SizedBox(width: 10),
              IconAction(
                icon: Icons.speed_rounded,
                tooltip: 'سنجش پینگ',
                size: 46,
                onTap: vpn.measuring
                    ? () {}
                    : () async {
                        await vpn.refreshPings();
                        toasts.success('سنجش پینگ تمام شد');
                      },
              ),
            ],
          ),
          const SizedBox(height: 18),
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (vpn.measuring) ...<Widget>[
                  const SizedBox(height: 14),
                  ProgressLine(
                    value: vpn.pingProgress,
                    label: 'در حال سنجش پینگ سرورها',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _SourceChip(
                label: 'همه منابع',
                count: vpn.nodes.length,
                selected: _sourceFilter.isEmpty,
                icon: Icons.apps_rounded,
                onTap: () => setState(() => _sourceFilter = ''),
              ),
              for (final SourceState state in subs.sources)
                _SourceChip(
                  label: state.title,
                  count: state.count,
                  selected: _sourceFilter == state.source.id,
                  icon: state.personal
                      ? Icons.person_rounded
                      : Icons.public_rounded,
                  onTap: () => setState(() => _sourceFilter = state.source.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: nodes.isEmpty
                ? EmptyState(
                    icon: Icons.dns_outlined,
                    title: 'سروری پیدا نشد',
                    message: 'اشتراک شما به صورت خودکار از سرور خوانده می شود؛ اگر سروری نبود فیلتر را بردارید.',
                    action: GradientButton(
                      label: 'دریافت سرورها',
                      icon: Icons.cloud_download_rounded,
                      expand: false,
                      loading: subs.loadingAll,
                      onPressed: subs.loadingAll ? null : subs.fetchAll,
                    ),
                  )
                : ListView.separated(
                    itemCount: nodes.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final VpnNode node = nodes[index];
                      return _NodeTile(
                        node: node,
                        isActive: vpn.activeNode?.id == node.id,
                        onConnect: () async {
                          if (vpn.status.active) {
                            await vpn.switchTo(node);
                          } else {
                            await vpn.connect(requested: node);
                          }
                          if (vpn.status == VpnStatus.connected) {
                            toasts.success('به ${node.name} وصل شدید');
                          }
                        },
                        onFavorite: () => vpn.toggleFavorite(node),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? colors.primary : colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                Fa.num('$label (${Fa.num(count)})'),
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.isActive,
    required this.onConnect,
    required this.onFavorite,
  });

  final VpnNode node;
  final bool isActive;
  final VoidCallback onConnect;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final Color pingColor = !node.hasPing
        ? colors.textSecondary
        : (node.pingMs < 150
            ? colors.success
            : (node.pingMs < 320 ? colors.warning : colors.danger));
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 18,
      borderColor: isActive ? colors.primary : colors.border,
      child: Row(
        children: <Widget>[
          Container(
            width: 64,
            height: 46,
            decoration: BoxDecoration(
              color: pingColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pingColor.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  node.hasPing ? Fa.num(node.pingMs) : '—',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: pingColor,
                  ),
                ),
                Text(
                  'میلی ثانیه',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 8.5,
                    color: pingColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        Fa.num(node.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (isActive) ...<Widget>[
                      const SizedBox(width: 8),
                      Pill(label: 'فعال', color: colors.primary, dense: true),
                    ],
                    if (node.favorite) ...<Widget>[
                      const SizedBox(width: 6),
                      Icon(Icons.star_rounded, size: 15, color: colors.warning),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  Fa.num(node.quality),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconAction(
            icon: node.favorite ? Icons.star_rounded : Icons.star_border_rounded,
            onTap: onFavorite,
            tooltip: 'نشان کردن',
            color: node.favorite ? colors.warning : colors.textSecondary,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 128,
            child: GradientButton(
              label: isActive ? 'قطع' : 'اتصال',
              icon: isActive
                  ? Icons.power_settings_new_rounded
                  : Icons.play_arrow_rounded,
              height: 42,
              tone: isActive ? colors.danger : colors.primary,
              onPressed: onConnect,
            ),
          ),
        ],
      ),
    );
  }
}
