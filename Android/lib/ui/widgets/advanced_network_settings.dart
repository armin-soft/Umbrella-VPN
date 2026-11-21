import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/settings_controller.dart';
import 'common.dart';

class AdvancedNetworkSettings extends StatelessWidget {
  const AdvancedNetworkSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final AppSettings settings = controller.settings;
    final UmbrellaColors colors = context.colors;
    final bool hasRules = settings.appRoutes.isNotEmpty;

    final Widget routesCard = _FeatureCard(
      icon: Icons.apps_rounded,
      accent: hasRules ? colors.info : colors.primary,
      title: 'مسیریابی برنامه های ویندوز',
      badge: hasRules
          ? Fa.num('${settings.appRoutes.length} قانون')
          : 'همه از تونل',
      badgeActive: hasRules,
      subtitle:
          'تعیین مسیر مستقیم، تونل یا مسدود برای هر فایل اجرایی ویندوز در حالت تونل',
      actionLabel: 'افزودن برنامه',
      actionIcon: Icons.add_rounded,
      onAction: settings.appRoutes.length >= 64
          ? null
          : () => _editRule(context, controller),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
                        Icons.terminal_rounded,
                        size: AppMetrics.iconSm,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: AppMetrics.space2),
                      Text(
                        Fa.num(settings.appRoutes[i].process),
                        textDirection: TextDirection.ltr,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
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
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                        onChanged: (bool enabled) => _saveRules(
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
                      IconButton(
                        tooltip: 'ویرایش قانون',
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: AppMetrics.iconSm,
                        ),
                        onPressed: () =>
                            _editRule(context, controller, index: i),
                      ),
                      IconButton(
                        tooltip: 'اولویت بالاتر',
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: AppMetrics.iconSm,
                        ),
                        onPressed: i == 0
                            ? null
                            : () {
                                final List<AppRouteRule> rules =
                                    List<AppRouteRule>.of(settings.appRoutes);
                                final AppRouteRule rule = rules.removeAt(i);
                                rules.insert(i - 1, rule);
                                _saveRules(context, controller, rules);
                              },
                      ),
                      IconButton(
                        tooltip: 'حذف قانون',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: AppMetrics.iconSm,
                        ),
                        onPressed: () => _saveRules(
                          context,
                          controller,
                          List<AppRouteRule>.of(settings.appRoutes)
                            ..removeAt(i),
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
          color: badgeActive
              ? accent.withValues(alpha: 0.4)
              : colors.border,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppMetrics.space1),
                    Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
              onPressed: onAction,
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
        scrollable: true,
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
                  labelText: 'نام برنامه یا مسیر کامل فایل اجرایی',
                  hintText: 'نام برنامه ویندوز',
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
                items: <DropdownMenuItem<AppRouteAction>>[
                  for (final AppRouteAction value in AppRouteAction.values)
                    DropdownMenuItem<AppRouteAction>(
                      value: value,
                      child: Text(value.label),
                    ),
                ],
                onChanged: (AppRouteAction? value) {
                  if (value != null) setState(() => action = value);
                },
              ),
              const SizedBox(height: AppMetrics.space3),
              Text(
                'نام برنامه همه پردازش های هم نام را شامل می شود؛ برای تطبیق دقیق، مسیر کامل فایل اجرایی را وارد کنید.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            child: const Text('ذخیره قانون'),
            onPressed: () {
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
            },
          ),
        ],
      );
}
