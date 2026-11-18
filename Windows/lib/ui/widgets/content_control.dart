import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// کنترل محتوا؛ همگام دوطرفه و آنی با ربات تلگرام آمبرلا.
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

  final TextEditingController _domainCtrl = TextEditingController();
  String _domainError = '';

  @override
  void dispose() {
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyAndSave(
    AuthController auth,
    ToastController toasts,
    FilterSettings next, {
    String? toastTitle,
  }) async {
    final bool ok = await auth.saveFilter(next);
    if (!mounted) {
      return;
    }
    if (ok) {
      if (toastTitle != null && toastTitle.isNotEmpty) {
        toasts.success(toastTitle);
      }
    } else if (auth.error.isNotEmpty) {
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
    // مشابه ربات تلگرام: روشن یا خاموش کردن کلید اصلی همان لحظه ذخیره و اعمال می شود.
    final FilterSettings next = current.copyWith(
      enabled: value,
      categories: cats,
    );
    await _applyAndSave(
      auth,
      toasts,
      next,
      toastTitle:
          value ? 'کنترل محتوا روشن شد' : 'کنترل محتوا خاموش شد',
    );
  }

  Future<void> _onToggleCategory(
    AuthController auth,
    ToastController toasts,
    String key,
  ) async {
    // دقیقاً مطابق منطق ربات تلگرام (`AppFilter::toggle`): لمس هر دسته آن را
    // روشن/خاموش می کند و اگر حداقل یک دسته یا دامنه باقی ماند فیلتر فعال می ماند.
    final FilterSettings next = auth.filter.toggleCategory(key);
    await _applyAndSave(auth, toasts, next);
  }

  Future<void> _onToggleAll(
    AuthController auth,
    ToastController toasts,
  ) async {
    final FilterSettings current = auth.filter;
    final List<String> allKeys = FilterSettings.categoryLabels.keys.toList();
    final bool clearAll =
        current.enabled && current.activeBotCategories.length == allKeys.length;
    final FilterSettings next = clearAll
        ? current.copyWith(
            enabled: current.normalizedCustomDomains.isNotEmpty,
            categories: const <String>[],
          )
        : current.copyWith(
            enabled: true,
            categories: allKeys,
          );
    await _applyAndSave(
      auth,
      toasts,
      next,
      toastTitle: clearAll
          ? 'همه دسته ها غیرفعال شدند'
          : 'همه دسته ها فعال و همگام شدند',
    );
  }

  Future<void> _onAddDomain(
    AuthController auth,
    ToastController toasts,
  ) async {
    final String? normalized =
        FilterSettings.normalizeDomainSuffix(_domainCtrl.text);
    if (normalized == null) {
      setState(() {
        _domainError = 'دامنه معتبر وارد کنید (مانند example.com).';
      });
      return;
    }
    final FilterSettings current = auth.filter;
    final List<String> domains = current.normalizedCustomDomains.toList();
    if (domains.contains(normalized)) {
      _domainCtrl.clear();
      setState(() => _domainError = '');
      return;
    }
    domains.add(normalized);
    _domainCtrl.clear();
    setState(() => _domainError = '');
    await _applyAndSave(
      auth,
      toasts,
      current.copyWith(enabled: true, customDomains: domains),
      toastTitle: 'دامنه به فهرست مسدود اضافه شد',
    );
  }

  Future<void> _onRemoveDomain(
    AuthController auth,
    ToastController toasts,
    String domain,
  ) async {
    final FilterSettings current = auth.filter;
    final List<String> domains = current.normalizedCustomDomains
        .where((String item) => item != domain)
        .toList();
    final bool stayEnabled =
        current.activeBotCategories.isNotEmpty || domains.isNotEmpty;
    await _applyAndSave(
      auth,
      toasts,
      current.copyWith(
        enabled: current.enabled && stayEnabled,
        customDomains: domains,
      ),
    );
  }

  Future<void> _onSyncFromBot(
    AuthController auth,
    ToastController toasts,
  ) async {
    final bool ok = await auth.syncFilter();
    if (!mounted) {
      return;
    }
    if (ok) {
      toasts.success('کنترل محتوا با ربات همگام شد');
    } else if (auth.error.isNotEmpty) {
      toasts.error('همگام سازی ناموفق بود', auth.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final AuthController auth = context.watch<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    final FilterSettings filter = auth.filter;
    final bool busy = auth.savingFilter || auth.syncingFilter;
    final List<String> activeCategories = filter.activeBotCategories;
    final List<String> customDomains = filter.normalizedCustomDomains;
    final List<MapEntry<String, String>> entries =
        FilterSettings.categoryLabels.entries.toList(growable: false);
    final bool allSelected =
        filter.enabled && activeCategories.length == entries.length;
    final int activeCount =
        filter.enabled ? activeCategories.length : 0;

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
                'همگام خودکار با بخش کنترل محتوا در ربات تلگرام؛ هر تغییر در ربات یا برنامه بلافاصله روی هر دو اعمال می شود',
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
          const SizedBox(height: AppMetrics.space4),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _domainCtrl,
                  enabled: !busy && auth.signedIn,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _onAddDomain(auth, toasts),
                  decoration: InputDecoration(
                    hintText: 'افزودن دامنه سفارشی برای مسدودسازی (example.com)',
                    prefixIcon: const Icon(
                      Icons.block_rounded,
                      size: AppMetrics.iconSm,
                    ),
                    errorText: _domainError.isEmpty ? null : _domainError,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppMetrics.space2),
              SizedBox(
                height: AppMetrics.controlHeightSmall,
                child: OutlinedButton.icon(
                  onPressed: busy || !auth.signedIn
                      ? null
                      : () => _onAddDomain(auth, toasts),
                  icon: const Icon(Icons.add_rounded, size: AppMetrics.iconSm),
                  label: const Text('افزودن'),
                ),
              ),
            ],
          ),
          if (customDomains.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppMetrics.space3),
            Wrap(
              spacing: AppMetrics.space2,
              runSpacing: AppMetrics.space2,
              children: customDomains.map((String domain) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppMetrics.space3,
                    vertical: AppMetrics.space1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceHigh.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        domain,
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(width: AppMetrics.space1),
                      InkWell(
                        borderRadius:
                            BorderRadius.circular(AppMetrics.radiusPill),
                        onTap: busy
                            ? null
                            : () => _onRemoveDomain(auth, toasts, domain),
                        child: Icon(
                          Icons.close_rounded,
                          size: AppMetrics.iconXs,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(growable: false),
            ),
          ],
          const Divider(height: AppMetrics.space6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppMetrics.space3,
            runSpacing: AppMetrics.space2,
            children: <Widget>[
              Pill(
                label: busy
                    ? 'در حال همگام سازی با سرور...'
                    : 'آخرین تغییر: ${filter.sourceLabel}',
                icon: Icons.sync_rounded,
                color: busy ? colors.info : colors.textSecondary,
                dense: true,
              ),
              Wrap(
                spacing: AppMetrics.space2,
                runSpacing: AppMetrics.space2,
                children: <Widget>[
                  SizedBox(
                    height: AppMetrics.controlHeightSmall,
                    child: OutlinedButton.icon(
                      onPressed: busy || !auth.signedIn
                          ? null
                          : () => _onToggleAll(auth, toasts),
                      icon: Icon(
                        allSelected
                            ? Icons.deselect_rounded
                            : Icons.done_all_rounded,
                        size: AppMetrics.iconSm,
                      ),
                      label: Text(
                        allSelected ? 'غیرفعال سازی همه' : 'انتخاب همه دسته ها',
                      ),
                    ),
                  ),
                  SizedBox(
                    height: AppMetrics.controlHeightSmall,
                    child: OutlinedButton.icon(
                      onPressed: busy || !auth.signedIn
                          ? null
                          : () => _onSyncFromBot(auth, toasts),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: AppMetrics.iconSm,
                      ),
                      label: const Text('همگام سازی با ربات'),
                    ),
                  ),
                ],
              ),
            ],
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
