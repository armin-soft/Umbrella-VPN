import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/utils.dart';
import '../data/parsers.dart';
import '../models/models.dart';
import '../platform/services.dart';
import 'auth_controller.dart';
import '../vpn/vpn_controller.dart';

class SourceState {
  SourceState({required this.source});

  final SubscriptionSource source;
  bool loading = false;
  bool loaded = false;
  String error = '';
  int count = 0;
  DateTime? checkedAt;

  String get title => source.title;
  bool get personal => source.personal;
}

/// دانلود و خواندن اشتراک ها.
///
/// قاعده اصلی: اشتراک شخصی کاربر از سرور خوانده می شود (پاسخ
/// `account/refresh`) و هیچ نشانی از کاربر گرفته نمی شود. منابع عمومی برنامه
/// فقط پشتیبان هستند تا پیش از ورود هم سروری برای نمایش وجود داشته باشد.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({
    required VpnController vpn,
    required AuthController auth,
    http.Client? client,
  })  : _vpn = vpn,
        _auth = auth,
        _client = client ?? http.Client() {
    _sources = AppConfig.subscriptionSources
        .map((SubscriptionSource source) => SourceState(source: source))
        .toList();
    _rebuildSources();
    _auth.addListener(_onAccountChanged);
  }

  final VpnController _vpn;
  final AuthController _auth;
  final http.Client _client;
  final AppLogger _log = AppLogger.instance;

  late List<SourceState> _sources;
  String _signature = '';
  String _personalFetchedFor = '';
  bool _disposed = false;

  List<SourceState> get sources => List<SourceState>.unmodifiable(_sources);

  /// اشتراک شخصی همین کاربر که سرور داده است (اگر سرور داده باشد).
  SourceState? get personalState {
    for (final SourceState state in _sources) {
      if (state.personal) {
        return state;
      }
    }
    return null;
  }

  bool get hasPersonal => personalState != null;

  String get personalUrl => personalState?.source.url ?? '';

  bool _loadingAll = false;
  bool get loadingAll => _loadingAll;

  double _progress = 0;
  double get progress => _progress;

  int get totalNodes =>
      _sources.fold<int>(0, (int sum, SourceState item) => sum + item.count);

  int get okSources => _sources.where((SourceState item) => item.loaded).length;

  /// اشتراک شخصی را از فهرست منبع ها بازسازی می کند و می گوید فهرست عوض شد یا
  /// نه. با هر تغییر حساب (ورود، خروج، به روز شدن پروفایل) صدا زده می شود.
  bool _rebuildSources() {
    final String url = _auth.account.subscriptionUrl.trim();
    final List<SubscriptionSource> next = <SubscriptionSource>[
      if (url.isNotEmpty)
        SubscriptionSource(
          id: AppConfig.personalSourceId,
          title: 'اشتراک من',
          url: url,
          format: SubscriptionFormat.xray,
          icon: 'user',
          personal: true,
        ),
      ...AppConfig.subscriptionSources,
    ];
    final String signature =
        next.map((SubscriptionSource item) => '${item.id}|${item.url}').join('\n');
    if (signature == _signature && _sources.isNotEmpty) {
      return false;
    }
    _signature = signature;
    final Map<String, SourceState> previous = <String, SourceState>{
      for (final SourceState item in _sources) item.source.id: item,
    };
    _sources = next.map((SubscriptionSource source) {
      final SourceState? old = previous[source.id];
      if (old != null && old.source.url == source.url) {
        return old;
      }
      return SourceState(source: source);
    }).toList();
    return true;
  }

  void _onAccountChanged() {
    if (_disposed) {
      return;
    }
    final bool changed = _rebuildSources();
    if (changed) {
      notifyListeners();
    }
    final SourceState? personal = personalState;
    if (personal == null || personal.loading) {
      return;
    }
    // هر نشانی تازه یک بار به صورت خودکار خوانده می شود.
    if (_personalFetchedFor == personal.source.url) {
      return;
    }
    _personalFetchedFor = personal.source.url;
    unawaited(refreshOne(personal));
  }

  Future<void> loadCached() async {
    await _vpn.bootstrap();
    if (_vpn.nodes.isNotEmpty) {
      for (final SourceState state in _sources) {
        final int count = _vpn.nodes
            .where((VpnNode node) => node.sourceId == state.source.id)
            .length;
        state.count = count;
        state.loaded = count > 0;
      }
      notifyListeners();
    }
  }

  /// اشتراک شخصی را از سرور می گیرد. اگر سرور هنوز نشانی نداده باشد، یک بار
  /// حساب به روز می شود و دوباره تلاش می کند. هیچ ورودی دستی وجود ندارد.
  Future<void> syncPersonal() async {
    if (!_auth.signedIn) {
      return;
    }
    if (_auth.account.subscriptionUrl.trim().isEmpty) {
      await _auth.refreshAccount(silent: true);
    }
    final bool changed = _rebuildSources();
    if (changed) {
      notifyListeners();
    }
    final SourceState? personal = personalState;
    if (personal == null) {
      _log.add(
        'سرور برای این حساب نشانی اشتراک برنگرداند؛ منابع عمومی استفاده می شود.',
        level: 'warning',
      );
      return;
    }
    _personalFetchedFor = personal.source.url;
    await refreshOne(personal);
  }

  Future<void> fetchAll() async {
    if (_loadingAll) {
      return;
    }
    _loadingAll = true;
    _progress = 0;
    notifyListeners();
    final List<SourceState> order = <SourceState>[
      if (personalState != null) personalState!,
      ..._sources.where((SourceState item) => !item.personal),
    ];
    final List<VpnNode> all = <VpnNode>[];
    int done = 0;
    for (final SourceState state in order) {
      final ParseReport? report = await _fetch(state);
      if (report != null) {
        all.addAll(report.nodes);
      }
      done++;
      _progress = done / order.length;
      notifyListeners();
    }

    final Map<String, VpnNode> unique = <String, VpnNode>{};
    for (final VpnNode node in all) {
      unique[node.id] = node;
    }
    if (unique.isNotEmpty) {
      await _vpn.applyNodes(unique.values.toList());
    }
    _loadingAll = false;
    _progress = 1;
    notifyListeners();
    _log.add(
      'اشتراک ها به روز شد: ${Fa.num(unique.length)} سرور از ${Fa.num(okSources)} منبع.',
    );
  }

  Future<void> refreshOne(SourceState state) async {
    await _fetch(state);
    final List<VpnNode> all = <VpnNode>[
      for (final SourceState item in _sources)
        ..._vpn.nodes.where((VpnNode node) => node.sourceId == item.source.id),
    ];
    if (all.isNotEmpty) {
      await _vpn.applyNodes(all);
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// آیا میزبان این نشانی قابل اعتماد است؟ نشانی اشتراک شخصی از خود سرور
  /// می آید، بنابراین میزبان درگاه یا میزبان پایه حساب هم پذیرفته می شود.
  bool _hostAllowed(Uri uri, {required bool personal}) {
    final String host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return false;
    }
    if (AppConfig.allowedSubscriptionHosts.contains(host)) {
      return true;
    }
    if (!personal) {
      return false;
    }
    final String gateway =
        Uri.tryParse(_auth.gatewayBase)?.host.toLowerCase() ?? '';
    final String base =
        Uri.tryParse(_auth.account.accountBase)?.host.toLowerCase() ?? '';
    return host == gateway || (base.isNotEmpty && host == base);
  }

  Future<ParseReport?> _fetch(SourceState state) async {
    state.loading = true;
    state.error = '';
    notifyListeners();
    try {
      final Uri uri = Uri.parse(state.source.url);
      if (!_hostAllowed(uri, personal: state.source.personal)) {
        state.error = 'نشانی اشتراک از طرف سرور مجاز نیست.';
        _log.add(
          'منبع ${uri.host} در فهرست مجاز نیست؛ اشتراک خوانده نشد.',
          level: 'error',
        );
        state.loading = false;
        notifyListeners();
        return null;
      }
      final http.Response response = await _client.get(
        uri,
        headers: <String, String>{
          'Accept': '*/*',
          'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
        },
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode >= 300) {
        state.error = 'پاسخ سرور: کد ${response.statusCode}';
        _log.add(
          'دریافت اشتراک ${uri.host} ناموفق: کد ${response.statusCode}',
          level: 'error',
        );
        state.loading = false;
        notifyListeners();
        return null;
      }
      final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final ParseReport report = state.source.personal
          ? SubscriptionParser.parseAuto(body, state.source.id)
          : SubscriptionParser.parse(body, state.source);
      state
        ..loading = false
        ..loaded = report.nodes.isNotEmpty
        ..count = report.count
        ..checkedAt = DateTime.now()
        ..error = report.problems.take(2).join(' | ');
      if (state.source.personal) {
        _log.add(
          report.nodes.isEmpty
              ? 'اشتراک شخصی از سرور خوانده شد اما سروری نداشت: '
                  '${report.problems.take(2).join(' | ')}'
              : 'اشتراک شخصی از سرور خوانده شد: '
                  '${Fa.num(report.count)} سرور.',
          level: report.nodes.isEmpty ? 'warning' : 'info',
        );
      }
      notifyListeners();
      return report;
    } on Exception catch (error) {
      state
        ..loading = false
        ..error = 'دریافت اشتراک ناموفق بود: $error';
      _log.add('دریافت اشتراک ناموفق بود: $error', level: 'error');
      notifyListeners();
      return null;
    }
  }

  Future<void> close() async {
    _client.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAccountChanged);
    unawaited(close());
    super.dispose();
  }
}
