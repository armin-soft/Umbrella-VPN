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

/// کنترل محتوا؛ دقیقاً هماهنگ با ربات تلگرام شامل دسته بندی ها و دامنه های سفارشی
/// با ذخیره، همگام سازی و اعمال خودکار روی اتصال فعال.
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

  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _domainFocus = FocusNode();
  String? _domainError;
  String _searchQuery = '';
  bool _showAllDomains = false;
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
    _domainController.dispose();
    _searchController.dispose();
    _domainFocus.dispose();
    super.dispose();
  }

  Future<bool> _applyAndSave(
    AuthController auth,
    ToastController toasts,
    FilterSettings next,
  ) async {
    final bool ok = await auth.saveFilter(next);
    if (!mounted) {
      return false;
    }
    if (!ok && auth.error.isNotEmpty) {
      toasts.error('ذخیره کنترل محتوا ناموفق بود', auth.error);
    }
    return ok;
  }

  Future<void> _onToggleMaster(
    AuthController auth,
    ToastController toasts,
    bool value,
  ) async {
    final FilterSettings current = auth.filter;
    if (value && !current.hasConfiguredRules) {
      toasts.info(
        'یک دسته را انتخاب کنید یا دامنه سفارشی اضافه کنید',
        'کنترل محتوا',
      );
      return;
    }
    await _applyAndSave(
      auth,
      toasts,
      current.copyWith(
        enabled: value,
        categories: current.activeBotCategories,
        customDomains: current.normalizedCustomDomains,
      ),
    );
  }

  Future<void> _onToggleCategory(
    AuthController auth,
    ToastController toasts,
    String key,
  ) async {
    await _applyAndSave(auth, toasts, auth.filter.toggleCategory(key));
  }

  Future<void> _onAddDomains(
    AuthController auth,
    ToastController toasts,
  ) async {
    final String raw = _domainController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _domainError = 'نام دامنه یا نشانی سایت را وارد کنید (مانند example.com)';
      });
      _domainFocus.requestFocus();
      return;
    }

    final ({List<String> valid, List<String> invalid}) parsed =
        FilterSettings.parseDomainInputs(raw);
    if (parsed.valid.isEmpty) {
      setState(() {
        _domainError =
            'دامنه معتبر نیست؛ نمونه درست: example.com یا https://site.org';
      });
      _domainFocus.requestFocus();
      return;
    }

    final ({
      FilterSettings settings,
      List<String> added,
      List<String> duplicates,
      List<String> skippedLimit,
    }) result = auth.filter.addCustomDomains(parsed.valid);

    if (result.added.isEmpty) {
      setState(() {
        _domainError = result.skippedLimit.isNotEmpty
            ? Fa.num(
                'ظرفیت ${FilterSettings.maxCustomDomains} دامنه سفارشی پر شده است',
              )
            : 'این دامنه از قبل در فهرست مسدودسازی ثبت شده است';
      });
      return;
    }

    setState(() => _domainError = null);
    final bool ok = await _applyAndSave(auth, toasts, result.settings);
    if (!mounted || !ok) {
      return;
    }
    _domainController.clear();
    final String addedMsg = result.added.length == 1
        ? 'دامنه ${result.added.first} به فهرست مسدودسازی اضافه شد'
        : Fa.num('${result.added.length} دامنه به فهرست مسدودسازی اضافه شد');
    if (parsed.invalid.isNotEmpty || result.skippedLimit.isNotEmpty) {
      toasts.warning(
        addedMsg,
        Fa.num(
          '${parsed.invalid.length + result.skippedLimit.length} مورد نامعتبر یا مازاد نادیده گرفته شد',
        ),
      );
    } else {
      toasts.success(addedMsg);
    }
  }

  Future<void> _onRemoveDomain(
    AuthController auth,
    ToastController toasts,
    String domain,
  ) async {
    final FilterSettings next = auth.filter.removeCustomDomain(domain);
    final bool ok = await _applyAndSave(auth, toasts, next);
    if (!mounted || !ok) {
      return;
    }
    toasts.info('دامنه $domain از فهرست مسدودسازی حذف شد', 'کنترل محتوا');
  }

  Future<void> _onClearAllDomains(
    AuthController auth,
    ToastController toasts,
    int count,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final UmbrellaColors colors = dialogContext.colors;
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
            side: BorderSide(color: colors.border),
          ),
          title: Text(
            'حذف همه دامنه های سفارشی',
            style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          content: Text(
            Fa.num(
              'آیا مطمئن هستید تمام $count دامنه سفارشی حذف شوند؟ '
              'این تغییر بلافاصله با ربات تلگرام و اتصال فعال همگام می شود.',
            ),
            style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.danger,
                foregroundColor: colors.onPrimary,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('حذف همه'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final bool ok =
        await _applyAndSave(auth, toasts, auth.filter.clearCustomDomains());
    if (!mounted || !ok) {
      return;
    }
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _showAllDomains = false;
    });
    toasts.info('تمام دامنه های سفارشی حذف شدند', 'کنترل محتوا');
  }

  String _statusBadgeLabel(
    FilterSettings filter,
    int activeCategoryCount,
    int domainCount,
  ) {
    if (!filter.hasActiveRules) {
      return 'خاموش';
    }
    final List<String> parts = <String>[
      if (activeCategoryCount > 0) '${Fa.num(activeCategoryCount)} دسته',
      if (domainCount > 0) '${Fa.num(domainCount)} دامنه',
    ];
    return parts.isEmpty ? 'روشن' : 'روشن (${parts.join(' · ')})';
  }

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    final AuthController auth = context.watch<AuthController>();
    final ToastController toasts = context.read<ToastController>();
    final FilterSettings filter = auth.filter;
    final bool busy = auth.savingFilter;
    final bool canEdit = auth.signedIn && !busy;
    final List<String> activeCategories = filter.activeBotCategories;
    final List<String> customDomains = filter.normalizedCustomDomains;
    final List<MapEntry<String, String>> entries =
        FilterSettings.categoryLabels.entries.toList(growable: false);
    final int activeCatCount = filter.enabled ? activeCategories.length : 0;
    final int activeDomCount = filter.enabled ? customDomains.length : 0;
    final bool active = filter.hasActiveRules;

    final String trimmedSearch = _searchQuery.trim().toLowerCase();
    final List<String> filteredDomains = trimmedSearch.isEmpty
        ? customDomains
        : customDomains
            .where((String d) => d.contains(trimmedSearch))
            .toList(growable: false);
    const int collapsedLimit = 12;
    final bool canCollapse =
        trimmedSearch.isEmpty && filteredDomains.length > collapsedLimit;
    final List<String> visibleDomains = canCollapse && !_showAllDomains
        ? filteredDomains.take(collapsedLimit).toList(growable: false)
        : filteredDomains;

    return GlassCard(
      padding: AppMetrics.cardPadding,
      radius: AppMetrics.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            icon: Icons.gpp_good_rounded,
            title: 'کنترل محتوا',
            subtitle: auth.signedIn
                ? 'هر تغییر به صورت خودکار ذخیره و بی درنگ روی اتصال و ربات تلگرام اعمال می شود'
                : 'برای مدیریت و همگام سازی کنترل محتوا ابتدا وارد حساب کاربری خود شوید',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Pill(
                  label: _statusBadgeLabel(
                    filter,
                    activeCatCount,
                    activeDomCount,
                  ),
                  color: active ? colors.success : colors.textSecondary,
                  icon: active
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  dense: true,
                ),
                const SizedBox(width: AppMetrics.space2),
                Switch.adaptive(
                  key: const ValueKey<String>('content-filter-master-switch'),
                  value: active,
                  onChanged: !canEdit
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
                            busy: !canEdit,
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
                                  busy: !canEdit,
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
                      busy: !canEdit,
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
          const Divider(height: AppMetrics.space5),

          // ── مدیریت دامنه های سفارشی (افزودن، جست وجو، حذف تکی و حذف همه) ──
          Row(
            children: <Widget>[
              IconSquare(
                icon: Icons.language_rounded,
                color: customDomains.isNotEmpty
                    ? colors.primary
                    : colors.textSecondary,
                size: AppMetrics.iconBoxSm,
                radius: AppMetrics.radiusSm,
              ),
              const SizedBox(width: AppMetrics.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'دامنه های سفارشی مسدودشده',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      Fa.num(
                        'هر دامنه به همراه تمام زیردامنه های آن مسدود و با ربات تلگرام همگام می شود '
                        '(${customDomains.length} از ${FilterSettings.maxCustomDomains})',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              if (customDomains.length > 1) ...<Widget>[
                const SizedBox(width: AppMetrics.space2),
                SizedBox(
                  height: AppMetrics.controlHeightSmall,
                  child: TextButton.icon(
                    key: const ValueKey<String>('content-filter-clear-domains'),
                    onPressed: !canEdit
                        ? null
                        : () => _onClearAllDomains(
                              auth,
                              toasts,
                              customDomains.length,
                            ),
                    icon: Icon(
                      Icons.delete_sweep_rounded,
                      size: AppMetrics.iconSm,
                      color: canEdit ? colors.danger : colors.textSecondary,
                    ),
                    label: Text(
                      'حذف همه',
                      style: TextStyle(
                        color: canEdit ? colors.danger : colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppMetrics.space3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    key: const ValueKey<String>('content-filter-domain-input'),
                    controller: _domainController,
                    focusNode: _domainFocus,
                    enabled: canEdit,
                    textAlign: TextAlign.left,
                    onChanged: (_) {
                      if (_domainError != null) {
                        setState(() => _domainError = null);
                      }
                    },
                    onSubmitted: (_) {
                      if (canEdit) {
                        unawaited(_onAddDomains(auth, toasts));
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'example.com, site.org',
                      hintTextDirection: TextDirection.ltr,
                      isDense: true,
                      prefixIcon: const Icon(
                        Icons.block_rounded,
                        size: AppMetrics.iconSm,
                      ),
                      errorText: _domainError,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppMetrics.space2),
              SizedBox(
                height: AppMetrics.controlHeight,
                child: FilledButton.icon(
                  key: const ValueKey<String>('content-filter-add-domain'),
                  onPressed:
                      !canEdit ? null : () => _onAddDomains(auth, toasts),
                  icon: const Icon(Icons.add_rounded, size: AppMetrics.iconSm),
                  label: const Text('افزودن'),
                ),
              ),
            ],
          ),
          if (customDomains.length > 8) ...<Widget>[
            const SizedBox(height: AppMetrics.space3),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                key: const ValueKey<String>('content-filter-search-domain'),
                controller: _searchController,
                textAlign: TextAlign.left,
                onChanged: (String v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'جست وجوی دامنه...',
                  isDense: true,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: AppMetrics.iconSm,
                  ),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'پاک کردن جست وجو',
                          icon: const Icon(
                            Icons.close_rounded,
                            size: AppMetrics.iconSm,
                          ),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          }),
                        ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppMetrics.space3),
          if (customDomains.isEmpty)
            Text(
              'هنوز دامنه سفارشی ثبت نشده است. می توانید یک یا چند دامنه (جداشده با ویرگول یا فاصله) وارد کنید.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            )
          else if (visibleDomains.isEmpty)
            Text(
              'دامنه ای مطابق عبارت جست وجو پیدا نشد.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            )
          else ...<Widget>[
            if (!filter.enabled)
              Padding(
                padding: const EdgeInsets.only(bottom: AppMetrics.space2),
                child: Text(
                  'کنترل محتوا خاموش است؛ برای اعمال این دامنه ها روی اتصال، کلید بالا را روشن کنید.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.warning,
                      ),
                ),
              ),
            Wrap(
              spacing: AppMetrics.space2,
              runSpacing: AppMetrics.space2,
              children: <Widget>[
                for (final String domain in visibleDomains)
                  _CustomDomainChip(
                    domain: domain,
                    active: filter.enabled,
                    enabled: canEdit,
                    colors: colors,
                    onDelete: () => _onRemoveDomain(auth, toasts, domain),
                  ),
              ],
            ),
            if (canCollapse) ...<Widget>[
              const SizedBox(height: AppMetrics.space2),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showAllDomains = !_showAllDomains),
                  icon: Icon(
                    _showAllDomains
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: AppMetrics.iconSm,
                  ),
                  label: Text(
                    _showAllDomains
                        ? 'نمایش خلاصه'
                        : Fa.num(
                            'نمایش همه ${filteredDomains.length} دامنه',
                          ),
                  ),
                ),
              ),
            ],
          ],
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

class _CustomDomainChip extends StatelessWidget {
  const _CustomDomainChip({
    required this.domain,
    required this.active,
    required this.enabled,
    required this.colors,
    required this.onDelete,
  });

  final String domain;
  final bool active;
  final bool enabled;
  final UmbrellaColors colors;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final Color accent = active ? colors.primary : colors.textSecondary;
    return Container(
      key: ValueKey<String>('custom-domain-$domain'),
      padding: const EdgeInsetsDirectional.only(
        start: AppMetrics.space3,
        end: AppMetrics.space1,
        top: AppMetrics.space1,
        bottom: AppMetrics.space1,
      ),
      decoration: BoxDecoration(
        color: active
            ? colors.primary.withValues(alpha: 0.10)
            : colors.surfaceHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        border: Border.all(
          color: active ? colors.primary.withValues(alpha: 0.5) : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.public_off_rounded, size: AppMetrics.iconXs, color: accent),
          const SizedBox(width: AppMetrics.space2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(width: AppMetrics.space1),
          Tooltip(
            message: 'حذف دامنه',
            child: InkWell(
              key: ValueKey<String>('delete-domain-$domain'),
              customBorder: const CircleBorder(),
              onTap: enabled ? onDelete : null,
              child: Padding(
                padding: const EdgeInsets.all(AppMetrics.space1),
                child: Icon(
                  Icons.close_rounded,
                  size: AppMetrics.iconSm,
                  color: enabled ? colors.textSecondary : colors.border,
                ),
              ),
            ),
          ),
        ],
      ),
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
