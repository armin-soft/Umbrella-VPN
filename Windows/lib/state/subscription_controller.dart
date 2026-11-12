import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../data/parsers.dart';
import '../data/subscription_endpoints.dart';
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

  /// کد پاسخ آخرین دریافت؛ صفر یعنی درخواستی فرستاده نشده است.
  int lastStatus = 0;
  bool get unauthorized =>
      lastStatus == 401 || lastStatus == 403 || lastStatus == 404;
  DateTime? checkedAt;

  String get title => source.title;
  bool get personal => source.personal;
}

/// دانلود و خواندن اشتراک ها.
///
/// همه چیز خودکار است: سرور پایه اشتراک هر کاربر را می دهد، برنامه همان پایه
/// را به پنج نشانی استاندارد پنل (ایکس ری، کلش متا، وایرگارد، آمنزیا، میرو)
/// تبدیل می کند و خودش می خواند. هیچ نشانی دستی وارد نمی شود.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({
    required VpnController vpn,
    required AuthController auth,
    http.Client? client,
  })  : _vpn = vpn,
        _auth = auth,
        _client = client ?? _directClient() {
    _sources = AppConfig.subscriptionSources
        .map((SubscriptionSource source) => SourceState(source: source))
        .toList();
    _rebuildSources();
    _auth.addListener(_onAccountChanged);
  }

  /// کلاینت بدون پروکسی: نشانی ها ایرانی هستند و پروکسی بازمانده یک برنامه
  /// دیگر نباید دریافت اشتراک را بشکند.
  static http.Client _directClient() {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    inner.findProxy = (Uri _) => 'DIRECT';
    return IOClient(inner);
  }

  final VpnController _vpn;
  final AuthController _auth;
  final http.Client _client;
  final AppLogger _log = AppLogger.instance;

  late List<SourceState> _sources;
  String _signature = '';
  String _personalFetchedFor = '';
  bool _disposed = false;

  /// وقتی نشانی های سرور پاسخ نمی دهند، منابع عمومی جای آن ها را می گیرند.
  bool _fallbackActive = false;

  /// نشانی های اشتراک بدون ورود به حساب در دسترس نیستند (کد ۴۰۱/۴۰۳/۴۰۴).
  bool _needsLogin = false;
  bool get needsLogin => _needsLogin;

  List<SourceState> get sources => List<SourceState>.unmodifiable(_sources);

  /// همه منابع اشتراک این کاربر که از سرور ساخته شده اند.
  List<SourceState> get personalSources =>
      _sources.where((SourceState item) => item.personal).toList();

  /// منبع اصلی (ایکس ری) برای نمایش خلاصه در حساب کاربری.
  SourceState? get personalState {
    for (final SourceState state in personalSources) {
      if (state.source.format == SubscriptionFormat.xray) {
        return state;
      }
    }
    return personalSources.isEmpty ? null : personalSources.first;
  }

  bool get hasPersonal => personalSources.isNotEmpty;

  String get personalUrl => personalState?.source.url ?? '';

  int get personalNodeCount =>
      personalSources.fold<int>(0, (int sum, SourceState item) => sum + item.count);

  bool get personalLoading =>
      personalSources.any((SourceState item) => item.loading);

  bool get personalLoaded =>
      personalSources.any((SourceState item) => item.loaded);

  List<String> get personalErrors => <String>[
        for (final SourceState item in personalSources)
          if (item.error.isNotEmpty) item.error,
      ];

  DateTime? get personalCheckedAt {
    DateTime? latest;
    for (final SourceState item in personalSources) {
      final DateTime? at = item.checkedAt;
      if (at == null) {
        continue;
      }
      if (latest == null || at.isAfter(latest)) {
        latest = at;
      }
    }
    return latest;
  }

  bool _loadingAll = false;
  bool get loadingAll => _loadingAll;

  double _progress = 0;
  double get progress => _progress;

  int get totalNodes =>
      _sources.fold<int>(0, (int sum, SourceState item) => sum + item.count);

  int get okSources => _sources.where((SourceState item) => item.loaded).length;

  /// منابع اشتراک را از داده حساب بازسازی می کند و می گوید فهرست عوض شد یا نه.
  bool _rebuildSources() {
    final List<SubscriptionSource> personal = SubscriptionEndpoints.build(
      subscriptionUrl: _auth.account.subscriptionUrl,
      accountBase: _auth.account.accountBase,
      uuid: _auth.account.uuid,
    );
    final List<SubscriptionSource> next = <SubscriptionSource>[
      ...personal,
      if (personal.isEmpty) ...AppConfig.subscriptionSources,
    ];
    final String signature =
        next.map((SubscriptionSource item) => '${item.id}|${item.url}').join('\n');
    if (signature == _signature && _sources.isNotEmpty) {
      return false;
    }
    _signature = signature;
    _fallbackActive = false;
    _needsLogin = false;
    _personalFetchedFor = '';
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
    if (!hasPersonal || personalLoading) {
      return;
    }
    // هر مجموعه نشانی تازه یک بار به صورت خودکار خوانده می شود.
    final String signature = personalSources
        .map((SourceState item) => item.source.url)
        .join('|');
    if (_personalFetchedFor == signature) {
      return;
    }
    _personalFetchedFor = signature;
    unawaited(syncPersonal());
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

  /// اشتراک شخصی را از سرور می گیرد. اگر سرور هنوز داده کافی نداده باشد، یک بار
  /// حساب به روز می شود و دوباره تلاش می کند. هیچ ورودی دستی وجود ندارد.
  Future<void> syncPersonal() async {
    if (!_auth.signedIn) {
      return;
    }
    if (!hasPersonal) {
      await _auth.refreshAccount(silent: true);
      final bool changed = _rebuildSources();
      if (changed) {
        notifyListeners();
      }
    }
    final List<SourceState> personal = personalSources;
    if (personal.isEmpty) {
      _log.add(
        'سرور برای این حساب نشانی اشتراک نداد؛ منابع عمومی استفاده می شود.',
        level: 'warning',
      );
      return;
    }
    final List<VpnNode> fetched = <VpnNode>[];
    for (final SourceState state in personal) {
      final ParseReport? report = await _fetch(state);
      if (report != null) {
        fetched.addAll(report.nodes);
      }
    }
    if (fetched.isEmpty) {
      _needsLogin = personal.every((SourceState item) => item.unauthorized);
      if (_needsLogin) {
        _log.add(
          'نشانی های اشتراک بدون ورود به حساب پاسخ نمی دهند (کد '
          '${Fa.num(personal.isEmpty ? 0 : personal.first.lastStatus)})؛ '
          'ابتدا وارد حساب شوید.',
          level: 'warning',
        );
      }
      await _activateFallbackSources();
      return;
    }
    _fallbackActive = false;
    _needsLogin = false;
    await _applyNodes(fetched);
    if (!_disposed) {
      notifyListeners();
    }
    _log.add(
      'اشتراک کاربر از سرور خوانده شد: ${Fa.num(fetched.length)} سرور از '
      '${Fa.num(personal.where((SourceState item) => item.loaded).length)} '
      'منبع از ${Fa.num(personal.length)}.',
    );
  }

  /// اگر نشانی هایی که سرور داد پاسخ ندادند، منابع عمومی خود برنامه امتحان
  /// می شوند تا کاربر بدون سرور نماند. نشانی هر خطا کامل در گزارش ها ثبت شده
  /// است تا معلوم شود کدام مسیر اشتباه است.
  Future<void> _activateFallbackSources() async {
    if (_fallbackActive) {
      return;
    }
    _fallbackActive = true;
    _sources = AppConfig.subscriptionSources
        .map((SubscriptionSource source) => SourceState(source: source))
        .toList();
    notifyListeners();
    _log.add(
      'نشانی های اشتراک سرور پاسخ ندادند؛ منابع عمومی برنامه امتحان می شوند.',
      level: 'warning',
    );
    final List<VpnNode> nodes = <VpnNode>[];
    for (final SourceState state in _sources) {
      final ParseReport? report = await _fetch(state);
      if (report != null) {
        nodes.addAll(report.nodes);
      }
    }
    if (nodes.isEmpty) {
      _log.add('منابع عمومی هم سروری ندادند.', level: 'error');
      return;
    }
    await _applyNodes(nodes);
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> fetchAll() async {
    if (_loadingAll) {
      return;
    }
    _loadingAll = true;
    _progress = 0;
    notifyListeners();
    final List<SourceState> order = <SourceState>[
      ...personalSources,
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
      _progress = order.isEmpty ? 1 : done / order.length;
      notifyListeners();
    }

    await _applyNodes(all);
    _loadingAll = false;
    _progress = 1;
    notifyListeners();
  }

  Future<void> refreshOne(SourceState state) async {
    final ParseReport? report = await _fetch(state);
    if (report != null) {
      await _applyNodes(report.nodes);
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// گره های تازه را با گره های منابع دیگر جمع می کند و به کنترلر اتصال می دهد.
  Future<void> _applyNodes(List<VpnNode> fetched) async {
    final Set<String> currentIds =
        _sources.map((SourceState item) => item.source.id).toSet();
    final Set<String> fetchedIds =
        fetched.map((VpnNode node) => node.id).toSet();
    final List<VpnNode> keep = _vpn.nodes
        .where((VpnNode node) =>
            currentIds.contains(node.sourceId) && !fetchedIds.contains(node.id))
        .toList();
    final Map<String, VpnNode> unique = <String, VpnNode>{};
    for (final VpnNode node in <VpnNode>[...keep, ...fetched]) {
      unique[node.id] = node;
    }
    if (unique.isEmpty) {
      _log.add('هیچ سروری از اشتراک ها خوانده نشد.', level: 'warning');
      return;
    }
    await _vpn.applyNodes(unique.values.toList());
  }

  /// آیا میزبان این نشانی قابل اعتماد است؟ نشانی اشتراک از خود سرور می آید،
  /// بنابراین میزبان درگاه یا میزبان پایه حساب هم پذیرفته می شود.
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

  /// یک درخواست با یک تلاش دوباره؛ اگر شبکه هنگام اتصال لحظه ای قطع شود،
  /// دریافت اشتراک بدون دخالت کاربر تکرار می شود.
  Future<http.Response> _getWithRetry(Uri uri) async {
    final Map<String, String> headers = <String, String>{
      'Accept': '*/*',
      'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
    };
    try {
      return await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    } on Exception {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      return await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    }
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
      final http.Response response = await _getWithRetry(uri);
      state.lastStatus = response.statusCode;
      if (response.statusCode >= 300) {
        state.error = 'پاسخ سرور: کد ${response.statusCode}';
        _log.add(
          'دریافت اشتراک ناموفق (کد ${response.statusCode}): $uri',
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
        ..error = report.nodes.isEmpty
            ? report.problems.take(2).join(' | ')
            : '';
      notifyListeners();
      return report;
    } on Exception catch (error) {
      state
        ..loading = false
        ..error = 'دریافت اشتراک ناموفق بود: $error';
      _log.add('دریافت اشتراک ناموفق بود: $error | $uri', level: 'error');
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
