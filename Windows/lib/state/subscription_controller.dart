import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/utils.dart';
import '../data/parsers.dart';
import '../models/models.dart';
import '../platform/services.dart';
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
}

/// دانلود و خواندن اشتراک ها. تنها منابع تعریف شده در برنامه مجاز هستند.
class SubscriptionController extends ChangeNotifier {
  SubscriptionController({
    required VpnController vpn,
    http.Client? client,
  })  : _vpn = vpn,
        _client = client ?? http.Client() {
    _sources = AppConfig.subscriptionSources
        .map((SubscriptionSource source) => SourceState(source: source))
        .toList();
  }

  final VpnController _vpn;
  final http.Client _client;
  late List<SourceState> _sources;
  final AppLogger _log = AppLogger.instance;

  List<SourceState> get sources => List<SourceState>.unmodifiable(_sources);

  bool _loadingAll = false;
  bool get loadingAll => _loadingAll;

  double _progress = 0;
  double get progress => _progress;

  int get totalNodes =>
      _sources.fold<int>(0, (int sum, SourceState item) => sum + item.count);

  int get okSources => _sources.where((SourceState item) => item.loaded).length;

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

  Future<void> fetchAll() async {
    if (_loadingAll) {
      return;
    }
    _loadingAll = true;
    _progress = 0;
    notifyListeners();
    final List<VpnNode> all = <VpnNode>[];
    int done = 0;
    for (final SourceState state in _sources) {
      final ParseReport? report = await _fetch(state);
      if (report != null) {
        all.addAll(report.nodes);
      }
      done++;
      _progress = done / _sources.length;
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
    notifyListeners();
  }

  Future<ParseReport?> _fetch(SourceState state) async {
    state.loading = true;
    state.error = '';
    notifyListeners();
    try {
      final Uri uri = Uri.parse(state.source.url);
      if (!AppConfig.allowedSubscriptionHosts
          .contains(uri.host.toLowerCase())) {
        state.error = 'این منبع در فهرست مجاز برنامه نیست.';
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
      final ParseReport report =
          SubscriptionParser.parse(body, state.source);
      state
        ..loading = false
        ..loaded = report.nodes.isNotEmpty
        ..count = report.count
        ..checkedAt = DateTime.now()
        ..error = report.problems.take(2).join(' | ');
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
}
