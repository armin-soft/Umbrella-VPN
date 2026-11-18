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

  /// متن خام پاسخ. برای کلش مهم است: همان پیکربندی کامل پنل که mihomo اجرا
  /// می کند و پدینگ و هدرها و ALPN گره ها در آن هست.
  String body = '';

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
    final List<SubscriptionSource> next = personal.isNotEmpty
        ? personal
        : AppConfig.subscriptionSources;
    final String signature = next
        .map((SubscriptionSource item) => '${item.id}|${item.url}')
        .join('\n');
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
      // فقط گره های متعلق به تنها مسیر مجاز `/sub/` نگه داشته می شوند؛ هر کش
      // بازمانده از مسیرهای حذف شده نسخه های پیشین بی درنگ پاک می شود.
      final Set<String> allowedIds =
          _sources.map((SourceState item) => item.source.id).toSet();
      final List<VpnNode> cleaned = _vpn.nodes
          .where((VpnNode node) => allowedIds.contains(node.sourceId))
          .map((VpnNode node) =>
              node.disabled ? node.copyWith(disabled: false) : node)
          .toList();
      if (cleaned.length != _vpn.nodes.length ||
          _vpn.nodes.any((VpnNode node) => node.disabled)) {
        await _vpn.applyNodes(cleaned, measure: false);
      }
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
    final _BatchFetch batch = await _fetchMany(personal);
    final List<VpnNode> fetched = batch.nodes;
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
    // همه منبع های شخصی بازخوانی شدند؛ سرورهای حذف شده قدیمی از کش پاک می شوند
    // تا فهرست اتصال با سرورهای ازکارافتاده انباشته نشود.
    final int uniqueCount = await _applyNodes(
      fetched,
      refreshedSourceIds: personal
          .map((SourceState item) => item.source.id)
          .toSet(),
    );
    if (!_disposed) {
      notifyListeners();
    }
    _log.add(
      'اشتراک کاربر به روز شد: ${Fa.num(uniqueCount)} مسیر آماده اتصال.',
    );
  }

  /// اگر نشانی اختصاصی کاربر پاسخ نداد، منبع پشتیبان پیش فرض امتحان می شود
  /// تا کاربر بدون مسیر اتصال نماند.
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
      'اشتراک حساب پاسخ نداد؛ در حال بارگذاری پیکربندی پشتیبان برنامه.',
      level: 'warning',
    );
    final _BatchFetch batch = await _fetchMany(_sources);
    final List<VpnNode> nodes = batch.nodes;
    if (nodes.isEmpty) {
      _log.add('دریافت پیکربندی اشتراک ناموفق بود.', level: 'error');
      if (_needsLogin) {
        _log.add(
          'فهرست سرورهای قبلی پاک شد؛ پس از ورود به حساب، اشتراک دوباره '
          'خوانده می شود.',
          level: 'warning',
        );
        await _vpn.applyNodes(<VpnNode>[], measure: false);
      }
      notifyListeners();
      return;
    }
    await _applyNodes(
      nodes,
      refreshedSourceIds: _sources
          .map((SourceState item) => item.source.id)
          .toSet(),
    );
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
    final _BatchFetch batch = await _fetchMany(
      order,
      onProgress: (int done, int total) {
        _progress = total == 0 ? 1 : done / total;
        if (!_disposed) {
          notifyListeners();
        }
      },
    );

    await _applyNodes(
      batch.nodes,
      refreshedSourceIds: batch.nodes.isNotEmpty
          ? batch.settledSourceIds
          : const <String>{},
    );
    _loadingAll = false;
    _progress = 1;
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> refreshOne(SourceState state) async {
    final ParseReport? report = await _fetch(state);
    if (report != null) {
      await _applyNodes(
        report.nodes,
        refreshedSourceIds: <String>{state.source.id},
      );
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// دریافت همزمان کنترل شده (تا ۳ منبع با هم) تا بازخوانی ۸ مسیر پنل به جای
  /// ده ها ثانیه در چند ثانیه تمام شود و ترتیب منبع ها حفظ بماند.
  Future<_BatchFetch> _fetchMany(
    List<SourceState> items, {
    int concurrency = 3,
    void Function(int done, int total)? onProgress,
  }) async {
    if (items.isEmpty) {
      return const _BatchFetch(<VpnNode>[], <String>{});
    }
    final List<ParseReport?> reports =
        List<ParseReport?>.filled(items.length, null);
    final Set<String> settled = <String>{};
    int cursor = 0;
    int done = 0;
    final int workers = concurrency.clamp(1, items.length);

    Future<void> worker() async {
      while (!_disposed) {
        final int index = cursor++;
        if (index >= items.length) {
          return;
        }
        final SourceState state = items[index];
        final ParseReport? report = await _fetch(state);
        reports[index] = report;
        if (report != null ||
            (state.lastStatus >= 200 && state.lastStatus < 500)) {
          settled.add(state.source.id);
        }
        done++;
        onProgress?.call(done, items.length);
      }
    }

    await Future.wait<void>(<Future<void>>[
      for (int i = 0; i < workers; i++) worker(),
    ]);
    final List<VpnNode> combined = <VpnNode>[
      for (final ParseReport? report in reports)
        if (report != null) ...report.nodes,
    ];
    return _BatchFetch(combined, settled);
  }

  /// گره های تازه را با گره های منابع بازخوانی نشده جمع، گره های تکراری بین
  /// قالب های هم پوشان پنل (`sub/`، `all.txt`، `sub64/`، کلش و سینگ باکس) را
  /// یکی، و نتیجه تمیز را به کنترلر اتصال می دهد.
  Future<int> _applyNodes(
    List<VpnNode> fetched, {
    Set<String> refreshedSourceIds = const <String>{},
  }) async {
    final Set<String> currentIds =
        _sources.map((SourceState item) => item.source.id).toSet();
    final Set<String> fetchedIds =
        fetched.map((VpnNode node) => node.id).toSet();
    final List<VpnNode> keep = _vpn.nodes
        .where((VpnNode node) =>
            currentIds.contains(node.sourceId) &&
            !refreshedSourceIds.contains(node.sourceId) &&
            !fetchedIds.contains(node.id))
        .toList();
    // تمام آیتم های معتبر اشتراک `/sub/` به همان ترتیب اصلی حفظ می شوند و هر
    // سرور قدیمی از منابع قبلی کنار گذاشته می شود.
    final Set<String> seenIds = <String>{};
    final List<VpnNode> nextNodes = <VpnNode>[
      for (final VpnNode node in <VpnNode>[...fetched, ...keep])
        if (seenIds.add(node.id)) node,
    ];
    if (nextNodes.isEmpty) {
      _log.add('هیچ مسیر فعالی از اشتراک دریافت نشد.', level: 'warning');
      return 0;
    }
    await _vpn.applyNodes(nextNodes);
    return nextNodes.length;
  }

  /// حذف کپی های کاملاً یکسان یک سرور در قالب های مختلف پنل بدون ادغام کلاینت ها
  /// یا مسیرهای متفاوت. لینک خام اصلی (`scheme://...`) همیشه بر بازسازی کلش یا
  /// سینگ باکس اولویت دارد تا تمام پارامترهای دقیق سرور دست نخورده بماند.
  static List<VpnNode> deduplicateNodes(List<VpnNode> nodes) {
    if (nodes.length <= 1) {
      return List<VpnNode>.of(nodes);
    }
    final Map<String, int> indexByKey = <String, int>{};
    final List<VpnNode> result = <VpnNode>[];

    for (final VpnNode node in nodes) {
      final String key = endpointIdentity(node);
      final int? existingIndex = indexByKey[key];
      if (existingIndex == null) {
        indexByKey[key] = result.length;
        result.add(node);
        continue;
      }
      final VpnNode existing = result[existingIndex];
      final bool preferIncoming =
          !_hasNativeShareLink(existing) && _hasNativeShareLink(node);
      final VpnNode winner = preferIncoming ? node : existing;
      final VpnNode other = preferIncoming ? existing : node;
      final int bestPing = winner.hasPing && other.hasPing
          ? (winner.pingMs <= other.pingMs ? winner.pingMs : other.pingMs)
          : (winner.hasPing ? winner.pingMs : other.pingMs);
      result[existingIndex] = winner.copyWith(
        favorite: winner.favorite || other.favorite,
        disabled: winner.disabled && other.disabled,
        pingMs: bestPing,
      );
    }
    return result;
  }

  static bool _hasNativeShareLink(VpnNode node) =>
      node.raw.trim().contains('://');

  /// کلید یکتای بدون اتلاف برای یک نقطه اتصال؛ هر تفاوتی در شناسه کاربر، رمز،
  /// پورت، انتقال، مسیر، SNI، کلید ریلیتی یا تنظیمات XHTTP دو کلید جدا می سازد.
  static String endpointIdentity(VpnNode node) {
    final Map<String, dynamic> p = node.params;
    String norm(Object? value) => JsonX.text(value).trim();
    String normLower(Object? value) => norm(value).toLowerCase();
    String transport = normLower(p['network'] ?? p['type']);
    if (transport.isEmpty || transport == 'raw') {
      transport = 'tcp';
    } else if (transport == 'h2') {
      transport = 'http';
    } else if (transport == 'splithttp') {
      transport = 'xhttp';
    }
    String security = normLower(p['security']);
    if (security.isEmpty && JsonX.boolean(p['tls'])) {
      security = 'tls';
    }
    if (security.isEmpty && norm(p['pbk'] ?? p['publicKey']).isNotEmpty &&
        node.protocol == NodeProtocol.vless) {
      security = 'reality';
    }
    if (security.isEmpty && node.protocol == NodeProtocol.trojan) {
      security = 'tls';
    }
    final Object? rawExtra = p['extra'];
    final String extra = rawExtra == null
        ? ''
        : (rawExtra is String ? rawExtra.trim() : jsonEncode(rawExtra));
    return <String>[
      node.protocol.name,
      node.host.trim().toLowerCase(),
      '${node.port}',
      norm(p['id'] ?? p['uuid']),
      norm(p['password']),
      norm(p['username']),
      norm(p['publicKey']),
      norm(p['privateKey'] ?? p['pk'] ?? p['private_key']),
      norm(p['hostKey'] ?? p['hk']),
      normLower(p['method'] ?? p['cipher']),
      normLower(p['plugin']),
      normLower(p['obfs']),
      normLower(p['obfs-host'] ?? p['obfs_host']),
      norm(p['mport']),
      transport,
      normLower(p['mode']),
      norm(p['path'] ?? p['serviceName']),
      normLower(p['host']),
      normLower(p['headerType']),
      security,
      normLower(p['sni'] ?? p['servername']),
      norm(p['pbk']),
      norm(p['sid']),
      norm(p['spx']),
      normLower(p['flow']),
      normLower(p['alpn']),
      norm(p['encryption']),
      norm(p['fragment']),
      extra,
    ].join('\x1f');
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
      'Accept': 'text/plain, */*',
      'User-Agent': 'Umbrella-Windows/${AppConfig.version}',
    };
    try {
      final http.Response first = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      // خطای دائمی کلاینت (۴۰۱/۴۰۳/۴۰۴/۴۱۰) با تلاش دوباره درست نمی شود؛
      // خطای موقت سرور (۵xx یا ۴۲۹) یک بار دوباره امتحان می شود.
      if (first.statusCode == 429 || first.statusCode >= 500) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 12));
      }
      return first;
    } on Exception {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
    }
  }

  Future<ParseReport?> _fetch(SourceState state) async {
    state.loading = true;
    state.error = '';
    notifyListeners();
    try {
      final Uri uri = Uri.parse(state.source.url);
      if (!_hostAllowed(uri, personal: state.source.personal)) {
        state.error = 'منبع اشتراک مجاز نیست.';
        _log.add(
          'منبع اشتراک در فهرست مجاز نیست و خوانده نشد.',
          level: 'error',
        );
        state.loading = false;
        notifyListeners();
        return null;
      }
      final http.Response response = await _getWithRetry(uri);
      state.lastStatus = response.statusCode;
      if (response.statusCode >= 300) {
        state.error = 'پاسخ ناموفق اشتراک (کد ${Fa.num(response.statusCode)})';
        _log.add(
          'دریافت اشتراک ناموفق بود (کد ${Fa.num(response.statusCode)}).',
          level: 'error',
        );
        state.loading = false;
        notifyListeners();
        return null;
      }
      final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
      state.body = body;
      final ParseReport report =
          SubscriptionParser.parseAuto(body, state.source.id);
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
    } on Exception {
      state
        ..loading = false
        ..error = 'دریافت اشتراک ناموفق بود.';
      _log.add(
        'دریافت اشتراک ناموفق بود؛ اتصال اینترنت را بررسی کنید.',
        level: 'error',
      );
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

class _BatchFetch {
  const _BatchFetch(this.nodes, this.settledSourceIds);

  final List<VpnNode> nodes;
  final Set<String> settledSourceIds;
}
