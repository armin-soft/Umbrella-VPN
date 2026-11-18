import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import '../shell/app_shell.dart';
import 'common.dart';

/// کنترل محتوا؛ دقیقاً مطابق ربات تلگرام با ذخیره و اعمال کاملاً خودکار.
class ContentControlCard extends StatefulWidget {
  const ContentControlCard({super.key});

  @override
  State<ContentControlCard> createState() => _ContentControlCardState();
}

class _ContentControlCardState extends State<ContentControlCard> {
  static const Map<String, IconData> _categoryIcons = <String, IconData>{
    'adult': Icons.no_adult_content_rounded,
    'gambling': Icons.casino_rounded,
    'ads': Icons.ad_units_rounded,
    'dating': Icons.person_off_rounded,
  };

  Timer? _autoPollTimer;
  bool _wasTabActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollSilently());
    _autoPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted ||
          !AppShell.isLifecycleVisible(
            WidgetsBinding.instance.lifecycleState,
          ) ||
          !TickerMode.of(context)) {
        return;
      }
      _pollSilently();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool active = TickerMode.of(context);
    if (active && !_wasTabActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pollSilently());
    }
    _wasTabActive = active;
  }

  void _pollSilently() {
    if (!mounted) {
      return;
    }
    final AuthController auth = context.read<AuthController>();
    if (auth.signedIn) {
      unawaited(auth.syncFilter());
    }
  }

  @override
  void dispose() {
    _autoPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _applyAndSave(
    AuthController auth,
    ToastController toasts,
    FilterSettings next,
  ) async {
    final bool ok = await auth.saveFilter(next);
    if (!mounted) {
      return;
    }
    if (!ok && auth.error.isNotEmpty) {
      toasts.error('ذخیره کنترل محتوا ناموفق بود', auth.error);
    }
  }

  Future<void> _onToggleMaster(
    AuthController auth,
    ToastController toasts,
    bool value,
  ) async {
    final FilterSettings current = auth.filter;
    final List<String> cats = current.activeBotCategories.toList();
    await _applyAndSave(
      auth,
      toasts,
      current.copyWith(enabled: value, categories: cats),
    );
  }

  Future<void> _onToggleCategory(
    AuthController auth,
    ToastController toasts,
    String key,
  ) async {
    await _applyAndSave(auth, toasts, auth.filter.toggleCategory(key));
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final AuthController auth = context.watch<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    final FilterSettings filter = auth.filter;
    final bool busy = auth.savingFilter;
    final List<String> activeCategories = filter.activeBotCategories;
    final List<MapEntry<String, String>> entries =
        FilterSettings.categoryLabels.entries.toList(growable: false);
    final int activeCount = filter.enabled ? activeCategories.length : 0;

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.gpp_good_rounded,
            title: 'کنترل محتوا',
            subtitle:
                'هر تغییر به صورت کاملاً خودکار ذخیره و بی درنگ روی اتصال و ربات اعمال می شود',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Pill(
                  label: filter.enabled
                      ? (activeCount > 0
                          ? 'روشن (${Fa.num(activeCount)} دسته)'
                          : 'روشن')
                      : 'خاموش',
                  color: filter.enabled ? colors.success : colors.textSecondary,
                  icon: filter.enabled
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  dense: true,
                ),
                const SizedBox(width: AppMetrics.space2),
                Switch.adaptive(
                  value: filter.enabled,
                  onChanged: busy || !auth.signedIn
                      ? null
                      : (bool value) => _onToggleMaster(auth, toasts, value),
                ),
              ],
            ),
          ),
          const Divider(height: AppMetrics.space5),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool twoCols =
                  constraints.maxWidth >= AppMetrics.breakpointCompact;
              final List<Widget> rows = <Widget>[];
              if (twoCols) {
                for (int i = 0; i < entries.length; i += 2) {
                  final MapEntry<String, String> first = entries[i];
                  final MapEntry<String, String>? second =
                      i + 1 < entries.length ? entries[i + 1] : null;
                  if (i > 0) {
                    rows.add(const SizedBox(height: AppMetrics.space3));
                  }
                  rows.add(
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _buildTile(
                            entry: first,
                            filter: filter,
                            busy: busy || !auth.signedIn,
                            colors: colors,
                            onTap: () =>
                                _onToggleCategory(auth, toasts, first.key),
                          ),
                        ),
                        const SizedBox(width: AppMetrics.space3),
                        Expanded(
                          child: second != null
                              ? _buildTile(
                                  entry: second,
                                  filter: filter,
                                  busy: busy || !auth.signedIn,
                                  colors: colors,
                                  onTap: () => _onToggleCategory(
                                    auth,
                                    toasts,
                                    second.key,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  );
                }
              } else {
                for (int i = 0; i < entries.length; i++) {
                  if (i > 0) {
                    rows.add(const SizedBox(height: AppMetrics.space2));
                  }
                  final MapEntry<String, String> entry = entries[i];
                  rows.add(
                    _buildTile(
                      entry: entry,
                      filter: filter,
                      busy: busy || !auth.signedIn,
                      colors: colors,
                      onTap: () => _onToggleCategory(auth, toasts, entry.key),
                    ),
                  );
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required MapEntry<String, String> entry,
    required FilterSettings filter,
    required bool busy,
    required UmbrellaColors colors,
    required VoidCallback onTap,
  }) {
    final bool selected =
        filter.enabled && filter.activeBotCategories.contains(entry.key);
    return _CategoryTile(
      icon: _categoryIcons[entry.key] ?? Icons.shield_outlined,
      label: entry.value,
      hint: FilterSettings.categorySubtitles[entry.key] ??
          'مسدودسازی خودکار این دسته',
      selected: selected,
      busy: busy,
      colors: colors,
      onTap: onTap,
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.busy,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final bool busy;
  final UmbrellaColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.65 : 1,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : colors.surfaceHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          onTap: busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.space4,
              vertical: AppMetrics.space3,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
              border: Border.all(
                color: selected ? colors.primary : colors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                IconSquare(
                  icon: icon,
                  color: selected ? colors.primary : colors.textSecondary,
                  size: AppMetrics.iconBoxMd,
                  radius: AppMetrics.radiusMd,
                ),
                const SizedBox(width: AppMetrics.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        Fa.num(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppMetrics.space1),
                      Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppMetrics.space2),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: AppMetrics.iconMd,
                  color: selected ? colors.primary : colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
