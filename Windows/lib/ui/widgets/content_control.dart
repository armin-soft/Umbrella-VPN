import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// کنترل محتوا: انتخاب دسته هایی که باید مسدود شوند. این بخش قبلا در صفحه
/// حساب بود و حالا در تنظیمات قرار دارد.
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'کنترل محتوا',
            subtitle: 'دسته هایی که باید مسدود شوند؛ با حساب شما همگام است.',
            trailing: Switch.adaptive(
              value: _enabled,
              onChanged: (bool value) => setState(() => _enabled = value),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final MapEntry<String, String> entry
                  in FilterSettings.categoryLabels.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: !_enabled
                      ? null
                      : () => setState(() {
                            if (_categories.contains(entry.key)) {
                              _categories.remove(entry.key);
                            } else {
                              _categories.add(entry.key);
                            }
                          }),
                  child: Opacity(
                    opacity: _enabled ? 1 : 0.5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _categories.contains(entry.key)
                            ? colors.primary.withValues(alpha: 0.14)
                            : colors.backgroundAlt,
                        border: Border.all(
                          color: _categories.contains(entry.key)
                              ? colors.primary
                              : colors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _categories.contains(entry.key)
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 15,
                            color: _categories.contains(entry.key)
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            Fa.num(entry.value),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'ذخیره تنظیمات کنترل محتوا',
            icon: Icons.save_rounded,
            height: 44,
            expand: false,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
