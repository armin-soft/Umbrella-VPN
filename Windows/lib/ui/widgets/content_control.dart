import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// کارت کنترل محتوا با ساختار کاملاً یکدست با کارت های تنظیمات.
class ContentControlCard extends StatefulWidget {
  const ContentControlCard({super.key});

  @override
  State<ContentControlCard> createState() => _ContentControlCardState();
}

class _ContentControlCardState extends State<ContentControlCard> {
  List<String> _categories = <String>[];
  bool _enabled = false;
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final FilterSettings filter = context.read<AuthController>().filter;
      _categories = List<String>.of(filter.categories);
      _enabled = filter.enabled;
      _initialized = true;
    }
  }

  Future<void> _save() async {
    final AuthController auth = context.read<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    setState(() => _saving = true);
    final bool ok = await auth.saveFilter(
      auth.filter.copyWith(enabled: _enabled, categories: _categories),
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (ok) {
      toasts.success('تنظیمات کنترل محتوا ذخیره شد');
    } else {
      toasts.error('ذخیره نشد', auth.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.block_rounded,
            title: 'کنترل محتوا',
            subtitle: 'مسدودسازی دسته های انتخابی روی حساب شما',
            trailing: Switch.adaptive(
              value: _enabled,
              onChanged: (bool value) => setState(() => _enabled = value),
            ),
          ),
          const Divider(height: AppMetrics.space5),
          Wrap(
            spacing: AppMetrics.space2,
            runSpacing: AppMetrics.space2,
            children: <Widget>[
              for (final MapEntry<String, String> entry
                  in FilterSettings.categoryLabels.entries)
                _CategoryChip(
                  label: entry.value,
                  selected: _categories.contains(entry.key),
                  enabled: _enabled,
                  colors: colors,
                  onTap: () => setState(() {
                    if (_categories.contains(entry.key)) {
                      _categories.remove(entry.key);
                    } else {
                      _categories.add(entry.key);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppMetrics.space4),
          SizedBox(
            height: AppMetrics.controlHeightSmall,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: AppMetrics.iconXs,
                      height: AppMetrics.iconXs,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: AppMetrics.iconSm),
              label: const Text('ذخیره کنترل محتوا'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final UmbrellaColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.space3,
              vertical: AppMetrics.space2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
              border: Border.all(
                color: selected ? colors.primary : colors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: AppMetrics.iconSm,
                  color: selected ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: AppMetrics.space2),
                Text(
                  Fa.num(label),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
