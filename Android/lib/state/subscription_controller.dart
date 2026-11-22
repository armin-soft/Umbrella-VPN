import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/app_config.dart';
import '../core/utils.dart';
import '../data/parsers.dart';
import '../data/emergency_feeds.dart';
import '../data/subscription_endpoints.dart';
import '../models/models.dart';
import '../platform/native.dart';
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

/// دانلود و به روز رسانی اشتراک اختصاصی کاربر.
///
/// هیچ منبع عمومی، رایگان یا اشتراکی در برنامه استفاده نمی شود: فقط نشانی
/// اختصاصی `/sub/` حساب کاربر واردشده از مسیر بومی ویندوز (WinHTTP + Schannel)،
/// مسیر پشتیبان کلاینت و در صورت محدودیت شبکه از درگاه امن حساب دریافت می شود.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({
    required VpnController vpn,
    required AuthController auth,
    http.Client? client,
    bool? enableNativeTransport,
  })  : _vpn = vpn,
        _auth = auth,
        _injectedClient = client != null,
        _enableNativeTransport =
            enableNativeTransport ?? (client == null && Platform.isAndroid),
        _client = client ?? _createClient(direct: true),
        _proxyClient = client == null ? _createClient(direct: false) : null {
    _sources = <SourceState>[];
    _rebuildSources();
    _auth.addListener(_onAccountChanged);
    scheduleMicrotask(_syncEmergencyFlag);
  }

  static http.Client _createClient({required bool direct}) {
    final HttpClient inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 15);
    inner.findProxy =
        direct ? (Uri _) => 'DIRECT' : HttpClient.findProxyFromEnvironment;
    return IOClient(inner);
  }

  final VpnController _vpn;
  final AuthController _auth;
  final bool _injectedClient;
  final bool _enableNativeTransport;
  final http.Client _client;
  final http.Client? _proxyClient;
  final AppLogger _log = AppLogger.instance;

  late List<SourceState> _sources;
  String _signature = '';
  String _personalFetchedFor = '';
  String _lastLoggedNodesSignature = '';
  Future<void>? _syncInFlight;
  bool _disposed = false;
  bool _emergencyEnabled = false;
  bool _emergencyLoading = false;
  int _emergencyGeneration = 0;
  String _emergencyError = '';
  int _emergencyUnavailableSources = 0;
  bool get emergencyEnabled => _auth.signedIn && _auth.account.emergencyEnabled;
  bool get emergencyLoading => _emergencyLoading;
  String get emergencyError => _emergencyError;
  int get emergencyUnavailableSources => _emergencyUnavailableSources;
  List<VpnNode> get emergencyNodes => _vpn.emergencyNodes;

  void _syncEmergencyFlag() {
    if (_disposed) return;
    final bool enabled = emergencyEnabled;
    if (enabled == _emergencyEnabled) return;
    _emergencyEnabled = enabled;
    _emergencyGeneration++;
    _emergencyError = '';
    _emergencyUnavailableSources = 0;
    if (!enabled) {
      _emergencyLoading = false;
      _vpn.setEmergencyNodes(const <VpnNode>[], enabled: false);
      notifyListeners();
      return;
    }
    unawaited(refreshEmergency());
  }

  Future<void> refreshEmergency() async {
    if (_disposed || !emergencyEnabled || _emergencyLoading) return;
    final int generation = ++_emergencyGeneration;
    _emergencyLoading = true;
    notifyListeners();
    final results = await Future.wait(<Future<EmergencyFeedResult>>[
      for (int i = 0; i < EmergencyFeeds.urls.length; i++) EmergencyFeeds.fetch(_client, i),
    ]);
    if (_disposed || generation != _emergencyGeneration || !emergencyEnabled) return;
    final nodes = <VpnNode>[
      for (final result in results) ...result.nodes,
    ].take(400).toList();
    _emergencyLoading = false;
    _emergencyUnavailableSources = results.where((result) => result.error.isNotEmpty).length;
    _emergencyError = nodes.isEmpty ? 'هیچ مسیر اضطراری سازگاری دریافت نشد.' : '';
    _vpn.setEmergencyNodes(nodes, enabled: true);
    notifyListeners();
  }

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

  /// فقط منبع اشتراک اختصاصی حساب واردشده را می سازد؛ هیچ منبع عمومی یا رایگان
  /// هرگز اضافه نمی شود.
  bool _rebuildSources() {
    final List<SubscriptionSource> next = _auth.signedIn
        ? SubscriptionEndpoints.build(
            subscriptionUrl: _auth.account.subscriptionUrl,
            accountBase: _auth.account.accountBase,
            uuid: _auth.account.uuid,
          )
        : const <SubscriptionSource>[];
    final String signature = next
        .map((SubscriptionSource item) => '${item.id}|${item.url}')
        .join('\n');
    if (signature == _signature && _sources.length == next.length) {
      return false;
    }
    _signature = signature;
    _needsLogin = false;
    _personalFetchedFor = '';
    _lastLoggedNodesSignature = '';
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
    _syncEmergencyFlag();
    if (!_auth.signedIn) {
      if (_vpn.nodes.isNotEmpty) {
        unawaited(_vpn.applyNodes(<VpnNode>[], measure: false));
      }
      if (changed) {
        notifyListeners();
      }
      return;
    }
    if (changed) {
      notifyListeners();
    }
    if (!hasPersonal || personalLoading) {
      return;
    }
    // هر نشانی تازه اشتراک شخصی یک بار به صورت خودکار خوانده می شود.
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
    if (!_auth.signedIn) {
      // بدون ورود به حساب هیچ سرور ذخیره شده یا عمومی نگه داشته نمی شود.
      if (_vpn.nodes.isNotEmpty) {
        await _vpn.applyNodes(<VpnNode>[], measure: false);
      }
      return;
    }
    if (_vpn.nodes.isNotEmpty) {
      // فقط گره های اشتراک اختصاصی کاربر (`user-sub`) نگه داشته می شوند؛ هر
      // گره بازمانده از منابع عمومی یا پیش فرض نسخه های قبلی بی درنگ حذف می شود.
      final Set<String> allowedIds =
          personalSources.map((SourceState item) => item.source.id).toSet();
      final List<VpnNode> cleaned = _vpn.nodes
          .where((VpnNode node) => allowedIds.contains(node.sourceId))
          .map((VpnNode node) =>
              node.disabled ? node.copyWith(disabled: false) : node)
          .toList();
      if (cleaned.length != _vpn.nodes.length ||
          _vpn.nodes.any((VpnNode node) => node.disabled)) {
        await _vpn.applyNodes(cleaned, measure: false);
      }
      for (final SourceState state in personalSources) {
        final int count = _vpn.nodes
            .where((VpnNode node) => node.sourceId == state.source.id)
            .length;
        state.count = count;
        state.loaded = count > 0;
      }
      notifyListeners();
    }
  }

  /// اشتراک اختصاصی کاربر را از سرور دریافت و به روز می کند (تک پروازی تا چند
  /// فراخوانی هم زمان با هم تداخل نکنند و گزارش خطای تکراری ثبت نشود).
  Future<void> syncPersonal() {
    final Future<void>? active = _syncInFlight;
    if (active != null) {
      return active;
    }
    final Future<void> run = _performSyncPersonal();
    _syncInFlight = run;
    return run.whenComplete(() {
      if (identical(_syncInFlight, run)) {
        _syncInFlight = null;
      }
    });
  }

  Future<void> _performSyncPersonal() async {
    if (!_auth.signedIn || _disposed) {
      return;
    }
    bool refreshedAccount = false;
    if (!hasPersonal) {
      await _auth.refreshAccount(silent: true);
      refreshedAccount = true;
      if (_rebuildSources() && !_disposed) {
        notifyListeners();
      }
    }
    List<SourceState> personal = personalSources;
    if (personal.isEmpty) {
      _log.add(
        'برای این حساب هنوز نشانی اشتراک اختصاصی ثبت نشده است.',
        level: 'warning',
      );
      return;
    }

    _personalFetchedFor =
        personal.map((SourceState item) => item.source.url).join('|');
    _BatchFetch batch = await _fetchMany(personal, logErrors: false);
    List<VpnNode> fetched = batch.nodes;

    // اگر دسترسی مستقیم به دامنه پنل اشتراک محدود بود یا پاسخی نرسید، اشتراک
    // اختصاصی همین کاربر از درگاه امن حساب (armin-soft.ir) خوانده می شود.
    if (fetched.isEmpty && _auth.signedIn && !_disposed) {
      final SourceState primary = personal.first;
      final List<VpnNode> viaGateway = await _tryFetchViaGateway(primary);
      if (viaGateway.isNotEmpty) {
        fetched = viaGateway;
      }
    }

    // اگر هنوز دریافت نشد و پروفایل حساب تازه نشده بود، یک بار نشانی اشتراک را
    // از درگاه به روز کن و در صورت تغییر نشانی دوباره امتحان کن.
    if (fetched.isEmpty && !refreshedAccount && _auth.signedIn && !_disposed) {
      final String previousUrl = personal.first.source.url;
      await _auth.refreshAccount(silent: true);
      _rebuildSources();
      personal = personalSources;
      if (personal.isNotEmpty && personal.first.source.url != previousUrl) {
        _personalFetchedFor =
            personal.map((SourceState item) => item.source.url).join('|');
        batch = await _fetchMany(personal, logErrors: false);
        fetched = batch.nodes;
        if (fetched.isEmpty && _auth.signedIn && !_disposed) {
          fetched = await _tryFetchViaGateway(personal.first);
        }
      }
    }

    if (fetched.isEmpty) {
      _needsLogin = personal.every((SourceState item) => item.unauthorized);
      final SourceState state = personal.first;
      if (!_auth.account.canConnect) {
        _log.add(
          'اشتراک به روز نشد: ${_auth.account.accessReason}',
          level: 'warning',
        );
      } else if (state.lastStatus == 404) {
        _log.add(
          'نشانی اشتراک این حساب در سرور پیدا نشد (کد ۴۰۴)؛ وضعیت بسته اشتراک را در حساب من بررسی کنید.',
          level: 'error',
        );
      } else if (state.lastStatus == 401 || state.lastStatus == 403) {
        _log.add(
          'دسترسی به نشانی اشتراک رد شد (کد ${Fa.num(state.lastStatus)}).',
          level: 'error',
        );
      } else if (state.lastStatus >= 200 && state.lastStatus < 300) {
        _log.add(
          'اشتراک شما هنوز سرور فعالی ندارد؛ در صورت نداشتن بسته فعال از بخش حساب من اشتراک تهیه کنید.',
          level: 'warning',
        );
      } else {
        final String detail =
            state.error.isNotEmpty ? state.error : 'سرور اشتراک پاسخ نداد.';
        _log.add(detail, level: 'error');
      }
      if (!_disposed) {
        notifyListeners();
      }
      return;
    }

    _needsLogin = false;
    final int uniqueCount = await _applyNodes(
      fetched,
      refreshedSourceIds:
          personal.map((SourceState item) => item.source.id).toSet(),
    );
    if (!_disposed) {
      notifyListeners();
    }
    if (uniqueCount > 0) {
      final List<String> ids =
          _vpn.nodes.map((VpnNode item) => item.id).toList()..sort();
      final String nodesSignature = '$uniqueCount:${ids.join(',')}';
      if (nodesSignature != _lastLoggedNodesSignature) {
        _lastLoggedNodesSignature = nodesSignature;
        _log.add(
          'اشتراک کاربر به روز شد: ${Fa.num(uniqueCount)} مسیر آماده اتصال.',
        );
      }
    }
  }

  Future<List<VpnNode>> _tryFetchViaGateway(SourceState state) async {
    state.loading = true;
    if (!_disposed) {
      notifyListeners();
    }
    try {
      final String? content = await _auth.fetchSubscriptionViaGateway();
      if (content == null || content.trim().isEmpty) {
        state.loading = false;
        return const <VpnNode>[];
      }
      final ParseReport report =
          SubscriptionParser.parseAuto(content, state.source.id);
      if (report.nodes.isEmpty) {
        state.loading = false;
        return const <VpnNode>[];
      }
      state
        ..loading = false
        ..loaded = true
        ..lastStatus = 200
        ..body = content
        ..count = report.count
        ..checkedAt = DateTime.now()
        ..error = '';
      return report.nodes;
    } on Object {
      state.loading = false;
      return const <VpnNode>[];
    }
  }

  /// فقط اشتراک شخصی کاربر واردشده را بازخوانی می کند؛ منبع عمومی وجود ندارد.
  Future<void> fetchAll() async {
    if (!_auth.signedIn || _loadingAll) {
      return;
    }
    _loadingAll = true;
    _progress = 0;
    if (!_disposed) {
      notifyListeners();
    }
    try {
      await syncPersonal();
    } finally {
      _loadingAll = false;
      _progress = 1;
      if (!_disposed) {
        notifyListeners();
      }
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
    bool logErrors = true,
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
        final ParseReport? report = await _fetch(state, logErrors: logErrors);
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

  /// آیا میزبان این نشانی قابل اعتماد است؟ فقط اشتراک شخصی کاربر از میزبان
  /// رسمی پنل، میزبان درگاه یا پایه حساب تاییدشده مجاز است.
  bool _hostAllowed(Uri uri, {required bool personal}) {
    if (!personal) {
      return false;
    }
    final String host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return false;
    }
    if (AppConfig.allowedSubscriptionHosts.contains(host)) {
      return true;
    }
    final String gateway =
        Uri.tryParse(_auth.gatewayBase)?.host.toLowerCase() ?? '';
    final String base =
        Uri.tryParse(_auth.account.accountBase)?.host.toLowerCase() ?? '';
    return host == gateway || (base.isNotEmpty && host == base);
  }

  Map<String, String> _subHeaders({String? userAgent}) => <String, String>{
        'Accept': 'text/plain, application/json, */*',
        'Cache-Control': 'no-cache',
        'User-Agent': userAgent ?? 'Umbrella-Android/${AppConfig.version}',
      };

  Future<({http.Response? response, bool tlsFailed, bool timedOut})>
      _downloadWithTransports(Uri uri, {String? userAgent}) async {
    final Map<String, String> headers = _subHeaders(userAgent: userAgent);
    if (_injectedClient) {
      try {
        final http.Response r = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
        return (response: r, tlsFailed: false, timedOut: false);
      } on TimeoutException {
        return (response: null, tlsFailed: false, timedOut: true);
      } on TlsException {
        return (response: null, tlsFailed: true, timedOut: false);
      } on Object {
        return (response: null, tlsFailed: false, timedOut: false);
      }
    }

    bool sawTls = false;
    bool sawTimeout = false;
    int attempts = 0;
    http.Response? fallbackError;

    // ۱. مسیر بومی WinHTTP + Schannel ویندوز (در حالت وصل ابتدا از تونل فعال و
    // در حالت قطع ابتدا مستقیم و سپس با پروکسی سیستم) برای سازگاری ۱۰۰ درصد با
    // تمامی نسخه های ۶۴ بیتی ویندوز ۱۰ و ۱۱.
    final bool preferProxy = _vpn.status.active;
    if (_enableNativeTransport) {
      final List<bool> proxyOrder = preferProxy
          ? const <bool>[true, false]
          : const <bool>[false, true];
      for (final bool useProxy in proxyOrder) {
        attempts++;
        final NativeHttpResponse? native =
            await NativeBridge.performHttpRequest(
          method: 'GET',
          url: uri.toString(),
          headers: headers,
          timeoutMs: 15000,
          useProxy: useProxy,
        );
        if (native == null) {
          break;
        }
        if (!native.ok || native.statusCode <= 0) {
          if (native.winError == 12175) {
            sawTls = true;
          } else if (native.winError == 12002) {
            sawTimeout = true;
          }
          continue;
        }
        final http.Response resp =
            http.Response.bytes(native.bodyBytes, native.statusCode);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return (response: resp, tlsFailed: false, timedOut: false);
        }
        fallbackError ??= resp;
        if (resp.statusCode == 401 || resp.statusCode == 404) {
          return (response: resp, tlsFailed: false, timedOut: false);
        }
      }
    }

    // ۲. مسیر پشتیبان کلاینت دارت (مستقیم و با پروکسی سیستمی).
    final http.Client? proxyClient = _proxyClient;
    final List<http.Client> dartClients = preferProxy && proxyClient != null
        ? <http.Client>[proxyClient, _client]
        : <http.Client>[
            _client,
            if (proxyClient != null) proxyClient,
          ];
    for (final http.Client client in dartClients) {
      attempts++;
      try {
        final http.Response resp = await client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 14));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return (response: resp, tlsFailed: false, timedOut: false);
        }
        fallbackError ??= resp;
        if (resp.statusCode == 401 || resp.statusCode == 404) {
          return (response: resp, tlsFailed: false, timedOut: false);
        }
      } on TimeoutException {
        sawTimeout = true;
      } on TlsException {
        sawTls = true;
      } on Object {
        // مسیر بعدی بررسی می شود.
      }
    }

    return (
      response: fallbackError,
      tlsFailed: sawTls && attempts > 0 && !sawTimeout,
      timedOut: sawTimeout,
    );
  }

  Future<ParseReport?> _fetch(
    SourceState state, {
    bool logErrors = true,
  }) async {
    state.loading = true;
    state.error = '';
    if (!_disposed) {
      notifyListeners();
    }
    try {
      final Uri uri = Uri.parse(state.source.url);
      if (!_hostAllowed(uri, personal: state.source.personal)) {
        state
          ..error = 'منبع اشتراک مجاز نیست.'
          ..loading = false;
        if (logErrors) {
          _log.add(
            'منبع اشتراک در فهرست مجاز نیست و خوانده نشد.',
            level: 'error',
          );
        }
        if (!_disposed) {
          notifyListeners();
        }
        return null;
      }

      final ({http.Response? response, bool tlsFailed, bool timedOut}) result =
          await _downloadWithTransports(uri);
      final http.Response? response = result.response;

      if (response == null) {
        final String message = result.tlsFailed
            ? 'خطای گواهی امنیتی در دریافت اشتراک؛ ساعت و تاریخ دستگاه را بررسی کنید.'
            : result.timedOut
                ? 'پاسخ سرور اشتراک دیر رسید؛ اتصال اینترنت یا محدودیت شبکه را بررسی کنید.'
                : 'دسترسی به سرور اشتراک برقرار نشد؛ اتصال اینترنت یا محدودیت شبکه را بررسی کنید.';
        state
          ..lastStatus = 0
          ..loading = false
          ..error = message;
        if (logErrors) {
          _log.add(message, level: 'error');
        }
        if (!_disposed) {
          notifyListeners();
        }
        return null;
      }

      state.lastStatus = response.statusCode;
      if (response.statusCode >= 300) {
        final String message =
            'دریافت اشتراک ناموفق بود (کد ${Fa.num(response.statusCode)}).';
        state
          ..error = message
          ..loading = false;
        if (logErrors) {
          _log.add(message, level: 'error');
        }
        if (!_disposed) {
          notifyListeners();
        }
        return null;
      }

      String body = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (SubscriptionParser.looksLikeHtml(body)) {
        final ({http.Response? response, bool tlsFailed, bool timedOut}) alt =
            await _downloadWithTransports(uri, userAgent: 'SingBox/1.10.0');
        if (alt.response != null &&
            alt.response!.statusCode >= 200 &&
            alt.response!.statusCode < 300) {
          body = utf8.decode(alt.response!.bodyBytes, allowMalformed: true);
        }
      }

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
      if (!_disposed) {
        notifyListeners();
      }
      return report;
    } on Object {
      const String message =
          'دریافت اشتراک اختصاصی ناموفق بود؛ اتصال اینترنت را بررسی کنید.';
      state
        ..loading = false
        ..error = message;
      if (logErrors) {
        _log.add(message, level: 'error');
      }
      if (!_disposed) {
        notifyListeners();
      }
      return null;
    }
  }

  Future<void> close() async {
    _client.close();
    _proxyClient?.close();
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
