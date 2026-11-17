import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// استودیوی پیشرفته و خوانای کنترل محتوا در بخش تنظیمات.
class ContentControlCard extends StatefulWidget {
  const ContentControlCard({super.key});

  @override
  State<ContentControlCard> createState() => _ContentControlCardState();
}

class _ContentControlCardState extends State<ContentControlCard> {
  static const Map<String, IconData> _categoryIcons = <String, IconData>{
    'adult': Icons.no_adult_content_rounded,
    'social': Icons.public_off_rounded,
    'gambling': Icons.casino_rounded,
    'ads': Icons.ad_units_rounded,
    'streaming': Icons.ondemand_video_rounded,
    'dating': Icons.person_off_rounded,
    'violence': Icons.gpp_bad_rounded,
    'messaging': Icons.speaker_notes_off_rounded,
  };

  static const Map<String, String> _categoryHints = <String, String>{
    'adult': 'مسدودسازی سایت ها و دامنه های نامناسب بزرگسال',
    'social': 'محدودسازی دسترسی به شبکه های اجتماعی',
    'gambling': 'جلوگیری از باز شدن سایت های شرط بندی',
    'ads': 'حذف تبلیغات مزاحم و ردیاب های تبلیغاتی',
    'streaming': 'مدیریت دسترسی به سرویس های پخش ویدیو',
    'dating': 'مسدودسازی پلتفرم های دوستیابی',
    'violence': 'فیلتر محتوای خشونت آمیز و آسیب زا',
    'messaging': 'محدودسازی پیام رسان ها روی این حساب',
  };

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

  void _toggleCategory(String key) {
    setState(() {
      if (_categories.contains(key)) {
        _categories.remove(key);
      } else {
        _categories.add(key);
      }
    });
  }

  void _toggleAll() {
    final List<String> allKeys = FilterSettings.categoryLabels.keys.toList();
    setState(() {
      if (_categories.length == allKeys.length) {
        _categories.clear();
      } else {
        _categories = allKeys;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final List<MapEntry<String, String>> entries =
        FilterSettings.categoryLabels.entries.toList(growable: false);
    final bool allSelected = _categories.length == entries.length;

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.gpp_good_rounded,
            title: 'کنترل محتوا و فیلتر خانواده',
            subtitle:
                'دسته های دلخواه را انتخاب کنید تا به صورت خودکار روی حساب شما مسدود شوند',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                StatusBadge(
                  label: _enabled
                      ? '${Fa.num(_categories.length)} دسته فعال'
                      : 'غیرفعال',
                  color: _enabled ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: AppMetrics.space2),
                Switch.adaptive(
                  value: _enabled,
                  onChanged: (bool value) => setState(() => _enabled = value),
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
                        Expanded(child: _buildTile(first, colors)),
                        const SizedBox(width: AppMetrics.space3),
                        Expanded(
                          child: second != null
                              ? _buildTile(second, colors)
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
                  rows.add(_buildTile(entries[i], colors));
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              );
            },
          ),
          const Divider(height: AppMetrics.space6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppMetrics.space3,
            runSpacing: AppMetrics.space2,
            children: <Widget>[
              SizedBox(
                height: AppMetrics.controlHeightSmall,
                child: OutlinedButton.icon(
                  onPressed: _enabled ? _toggleAll : null,
                  icon: Icon(
                    allSelected
                        ? Icons.deselect_rounded
                        : Icons.done_all_rounded,
                    size: AppMetrics.iconSm,
                  ),
                  label: Text(
                    allSelected ? 'پاک کردن همه انتخاب ها' : 'انتخاب همه دسته ها',
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppMetrics.buttonMaxWidth,
                ),
                child: GradientButton(
                  label: _saving ? 'در حال ذخیره...' : 'ذخیره کنترل محتوا',
                  icon: Icons.save_rounded,
                  loading: _saving,
                  height: AppMetrics.controlHeightSmall,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTile(MapEntry<String, String> entry, UmbrellaColors colors) {
    final bool selected = _categories.contains(entry.key);
    return _CategoryTile(
      icon: _categoryIcons[entry.key] ?? Icons.shield_outlined,
      label: entry.value,
      hint: _categoryHints[entry.key] ?? 'مدیریت دسترسی این دسته',
      selected: selected,
      enabled: _enabled,
      colors: colors,
      onTap: () => _toggleCategory(entry.key),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final bool enabled;
  final UmbrellaColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool activeHighlight = enabled && selected;
    return Opacity(
      opacity: enabled ? 1 : 0.52,
      child: Material(
        color: activeHighlight
            ? colors.primary.withValues(alpha: 0.1)
            : colors.surfaceHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.space4,
              vertical: AppMetrics.space3,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
              border: Border.all(
                color: activeHighlight ? colors.primary : colors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                IconSquare(
                  icon: icon,
                  color: activeHighlight ? colors.primary : colors.textSecondary,
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
                  color: activeHighlight ? colors.primary : colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
