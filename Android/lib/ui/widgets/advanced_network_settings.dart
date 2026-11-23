import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../platform/native.dart';
import '../../state/settings_controller.dart';
import '../../vpn/vpn_controller.dart';
import 'common.dart';

class AdvancedNetworkSettings extends StatelessWidget {
  const AdvancedNetworkSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final AppSettings settings = controller.settings;
    final UmbrellaColors colors = context.colors;
    final bool hasRules = settings.appRoutes.isNotEmpty;
    final String perAppMode = settings.perAppProxyMode;
    final List<String> activePackages = perAppMode == 'include'
        ? settings.perAppIncludePackages
        : (perAppMode == 'exclude'
            ? settings.perAppExcludePackages
            : const <String>[]);

    final Widget splitTunnelCard = Container(
      padding: const EdgeInsets.all(AppMetrics.space4),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(
          color: perAppMode != 'off'
              ? colors.info.withValues(alpha: 0.4)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: Icons.call_split_rounded,
                color: perAppMode != 'off' ? colors.info : colors.primary,
                size: AppMetrics.iconBoxMd,
                radius: AppMetrics.radiusMd,
              ),
              const SizedBox(width: AppMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'مسیریابی برنامه های دستگاه',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      perAppMode == 'off'
                          ? 'تمام برنامه های دستگاه از تونل عبور می کنند'
                          : perAppMode == 'include'
                              ? Fa.num(
                                  'فقط ${activePackages.length} برنامه انتخابی از تونل عبور می کنند',
                                )
                              : Fa.num(
                                  'همه برنامه ها به جز ${activePackages.length} برنامه مستثنی شده از تونل عبور می کنند',
                                ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: perAppMode != 'off'
                                ? colors.info
                                : colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space3),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'off',
                label: FittedBox(fit: BoxFit.scaleDown, child: Text('همه')),
              ),
              ButtonSegment<String>(
                value: 'include',
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('فقط انتخابی ها'),
                ),
              ),
              ButtonSegment<String>(
                value: 'exclude',
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('همه به جز'),
                ),
              ),
            ],
            selected: <String>{perAppMode},
            onSelectionChanged: (Set<String> selected) async {
              playUiClick(context);
              final String next = selected.first;
              await controller.setPerAppProxy(mode: next);
              if (!context.mounted) return;
              final VpnController vpn = context.read<VpnController>();
              if (vpn.status.active) vpn.scheduleLiveReload();
            },
          ),
          if (perAppMode != 'off') ...<Widget>[
            const SizedBox(height: AppMetrics.space3),
            SizedBox(
              height: AppMetrics.controlHeightSmall,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.apps_rounded, size: AppMetrics.iconSm),
                label: Text(
                  Fa.num(
                    'انتخاب برنامه ها (${activePackages.length})',
                  ),
                ),
                onPressed: withUiClick(
                  context,
                  () => _openInstalledAppsPicker(context, controller, perAppMode),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final Widget routesCard = _FeatureCard(
      icon: Icons.rule_rounded,
      accent: hasRules ? colors.info : colors.primary,
      title: 'مسیریابی برنامه ها',
      badge: hasRules
          ? Fa.num('${settings.appRoutes.length} قانون')
          : 'همه از تونل',
      badgeActive: hasRules,
      subtitle:
          'تعیین مسیر مستقیم، تونل یا مسدود برای هر برنامه در حالت تونل',
      actionLabel: 'افزودن برنامه',
      actionIcon: Icons.add_rounded,
      onAction: settings.appRoutes.length >= 64
          ? null
          : () => _editRule(context, controller),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        splitTunnelCard,
        const SizedBox(height: AppMetrics.space3),
        routesCard,
        if (hasRules) ...<Widget>[
          const SizedBox(height: AppMetrics.space3),
          for (int i = 0; i < settings.appRoutes.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: AppMetrics.space2),
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.space4,
                vertical: AppMetrics.space2,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceHigh.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                border: Border.all(color: colors.border),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space1,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.android_rounded,
                        size: AppMetrics.iconSm,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: AppMetrics.space2),
                      Flexible(
                        child: Text(
                          settings.appRoutes[i].process,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: AppMetrics.space2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppMetrics.space2,
                          vertical: AppMetrics.space1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(AppMetrics.radiusPill),
                        ),
                        child: Text(
                          settings.appRoutes[i].action.label,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Switch.adaptive(
                        value: settings.appRoutes[i].enabled,
                        onChanged: withUiClickValue(
                          context,
                          (bool enabled) => _saveRules(
                            context,
                            controller,
                            <AppRouteRule>[
                              for (int j = 0; j < settings.appRoutes.length; j++)
                                j == i
                                    ? AppRouteRule(
                                        process: settings.appRoutes[j].process,
                                        action: settings.appRoutes[j].action,
                                        enabled: enabled,
                                      )
                                    : settings.appRoutes[j],
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'ویرایش قانون',
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: AppMetrics.iconSm,
                        ),
                        onPressed: withUiClick(
                          context,
                          () => _editRule(context, controller, index: i),
                        ),
                      ),
                      IconButton(
                        tooltip: 'اولویت بالاتر',
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: AppMetrics.iconSm,
                        ),
                        onPressed: i == 0
                            ? null
                            : withUiClick(context, () {
                                final List<AppRouteRule> rules =
                                    List<AppRouteRule>.of(settings.appRoutes);
                                final AppRouteRule rule = rules.removeAt(i);
                                rules.insert(i - 1, rule);
                                _saveRules(context, controller, rules);
                              }),
                      ),
                      IconButton(
                        tooltip: 'حذف قانون',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: AppMetrics.iconSm,
                        ),
                        onPressed: withUiClick(
                          context,
                          () => _saveRules(
                            context,
                            controller,
                            List<AppRouteRule>.of(settings.appRoutes)
                              ..removeAt(i),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _openInstalledAppsPicker(
    BuildContext context,
    SettingsController controller,
    String mode,
  ) async {
    final NativeBridge native = context.read<NativeBridge>();
    final List<String> initialSelected = mode == 'include'
        ? controller.settings.perAppIncludePackages
        : controller.settings.perAppExcludePackages;

    final List<String>? result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) => _InstalledAppsSheet(
        native: native,
        mode: mode,
        initialSelected: initialSelected.toSet(),
      ),
    );
    if (result == null || !context.mounted) return;
    await controller.setPerAppProxy(
      mode: mode,
      includePackages: mode == 'include' ? result : null,
      excludePackages: mode == 'exclude' ? result : null,
    );
    if (!context.mounted) return;
    final VpnController vpn = context.read<VpnController>();
    if (vpn.status.active) vpn.scheduleLiveReload();
  }

  Future<void> _saveRules(
    BuildContext context,
    SettingsController controller,
    List<AppRouteRule> rules,
  ) async {
    try {
      await controller.setAppRoutes(rules);
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Fa.num(error.message))),
        );
      }
    }
  }

  Future<void> _editRule(
    BuildContext context,
    SettingsController controller, {
    int? index,
  }) async {
    final List<AppRouteRule> rules =
        List<AppRouteRule>.of(controller.settings.appRoutes);
    final AppRouteRule? result = await showDialog<AppRouteRule>(
      context: context,
      builder: (BuildContext context) =>
          AppRouteDialog(initial: index == null ? null : rules[index]),
    );
    if (result == null || !context.mounted) return;
    if (index == null) {
      rules.add(result);
    } else {
      rules[index] = result;
    }
    await _saveRules(context, controller, rules);
  }
}

class _InstalledAppsSheet extends StatefulWidget {
  const _InstalledAppsSheet({
    required this.native,
    required this.mode,
    required this.initialSelected,
  });

  final NativeBridge native;
  final String mode;
  final Set<String> initialSelected;

  @override
  State<_InstalledAppsSheet> createState() => _InstalledAppsSheetState();
}

class _InstalledAppsSheetState extends State<_InstalledAppsSheet> {
  final TextEditingController _search = TextEditingController();
  late Set<String> _selected;
  List<InstalledAppInfo> _apps = const <InstalledAppInfo>[];
  bool _loading = true;
  bool _showSystem = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.of(widget.initialSelected);
    unawaited(_loadApps());
  }

  Future<void> _loadApps() async {
    final List<InstalledAppInfo> apps = await widget.native.getInstalledApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final String q = _query.trim().toLowerCase();
    final List<InstalledAppInfo> filtered = _apps.where((InstalledAppInfo app) {
      if (!_showSystem && app.isSystem && !_selected.contains(app.packageName)) {
        return false;
      }
      if (q.isEmpty) return true;
      return app.name.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q);
    }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.space4,
            AppMetrics.space4,
            AppMetrics.space4,
            AppMetrics.space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.mode == 'include'
                          ? 'فقط برنامه های انتخابی از تونل عبور کنند'
                          : 'برنامه های مستثنی شده از تونل',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton(
                    onPressed: withUiClick(
                      context,
                      () => Navigator.of(context).pop(_selected.toList()),
                    ),
                    child: Text(Fa.num('ذخیره (${_selected.length})')),
                  ),
                ],
              ),
              const SizedBox(height: AppMetrics.space3),
              TextField(
                controller: _search,
                onChanged: (String v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'جست و جوی نام برنامه یا نام بسته...',
                ),
              ),
              const SizedBox(height: AppMetrics.space2),
              Row(
                children: <Widget>[
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('نمایش برنامه های سیستمی'),
                      value: _showSystem,
                      onChanged: withUiClickValue(
                        context,
                        (bool? v) => setState(() => _showSystem = v ?? false),
                      ),
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: withUiClick(
                        context,
                        () => setState(() => _selected.clear()),
                      ),
                      child: const Text('پاک کردن همه'),
                    ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? const Center(
                            child: Text('برنامه ای با این مشخصات پیدا نشد.'),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (BuildContext context, int i) {
                              final InstalledAppInfo app = filtered[i];
                              final bool checked =
                                  _selected.contains(app.packageName);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: withUiClickValue(context, (bool? v) {
                                  setState(() {
                                    if (v ?? false) {
                                      _selected.add(app.packageName);
                                    } else {
                                      _selected.remove(app.packageName);
                                    }
                                  });
                                }),
                                title: Text(app.name),
                                subtitle: Text(
                                  app.packageName,
                                  textDirection: TextDirection.ltr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.badge,
    required this.badgeActive,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String badge;
  final bool badgeActive;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppMetrics.space4),
      decoration: BoxDecoration(
        color: colors.surfaceHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(
          color: badgeActive ? accent.withValues(alpha: 0.4) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconSquare(
                icon: icon,
                color: accent,
                size: AppMetrics.iconBoxMd,
                radius: AppMetrics.radiusMd,
              ),
              const SizedBox(width: AppMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      badge,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: badgeActive ? accent : colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.space3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.6,
                ),
          ),
          const SizedBox(height: AppMetrics.space4),
          SizedBox(
            height: AppMetrics.controlHeightSmall,
            child: OutlinedButton.icon(
              icon: Icon(actionIcon, size: AppMetrics.iconSm),
              label: Text(actionLabel),
              onPressed: withUiClick(context, onAction),
            ),
          ),
        ],
      ),
    );
  }
}

class AppRouteDialog extends StatefulWidget {
  const AppRouteDialog({super.key, this.initial});
  final AppRouteRule? initial;
  @override
  State<AppRouteDialog> createState() => _AppRouteDialogState();
}

class _AppRouteDialogState extends State<AppRouteDialog> {
  late final TextEditingController process;
  late AppRouteAction action;
  String? error;

  @override
  void initState() {
    super.initState();
    process = TextEditingController(text: widget.initial?.process ?? '');
    action = widget.initial?.action ?? AppRouteAction.proxy;
  }

  @override
  void dispose() {
    process.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('قانون برنامه'),
        content: SizedBox(
          width: AppMetrics.dialogMaxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: process,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'نام بسته برنامه',
                  hintText: 'org.telegram.messenger',
                  errorText: error,
                ),
              ),
              const SizedBox(height: AppMetrics.space3),
              DropdownButtonFormField<AppRouteAction>(
                initialValue: action,
                isExpanded: true,
                dropdownColor: context.colors.surface,
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                decoration: const InputDecoration(labelText: 'عملکرد مسیر'),
                onTap: () => playUiClick(context),
                items: <DropdownMenuItem<AppRouteAction>>[
                  for (final AppRouteAction value in AppRouteAction.values)
                    DropdownMenuItem<AppRouteAction>(
                      value: value,
                      child: Text(value.label),
                    ),
                ],
                onChanged: (AppRouteAction? value) {
                  playUiClick(context);
                  if (value != null) setState(() => action = value);
                },
              ),
              const SizedBox(height: AppMetrics.space3),
              Text(
                'نام بسته برنامه برای تطبیق دقیق به کار می رود؛ برای مسیریابی ساده تر می توانید از گزینه «مسیریابی برنامه های دستگاه» در بالا استفاده کنید.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: withUiClick(context, () => Navigator.of(context).pop()),
            child: const Text('انصراف'),
          ),
          FilledButton(
            child: const Text('ذخیره قانون'),
            onPressed: withUiClick(context, () {
              final AppRouteRule rule = AppRouteRule(
                process: process.text.trim(),
                action: action,
                enabled: widget.initial?.enabled ?? true,
              );
              if (rule.validationError != null) {
                setState(() => error = rule.validationError);
                return;
              }
              Navigator.of(context).pop(rule);
            }),
          ),
        ],
      );
}
