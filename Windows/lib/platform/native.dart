import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/services.dart';

import '../core/utils.dart';
import '../models/models.dart';

/// پاسخ درخواست HTTP بومی ویندوز (WinHTTP + Schannel).
class NativeHttpResponse {
  const NativeHttpResponse({
    required this.ok,
    required this.statusCode,
    required this.bodyBytes,
    this.contentType = '',
    this.winError = 0,
    this.error = '',
  });

  final bool ok;
  final int statusCode;
  final Uint8List bodyBytes;
  final String contentType;
  final int winError;
  final String error;
}

/// وضعیت سبک برق ویندوز؛ مقدار نامشخص هرگز به معنی باتری فرض نمی شود.
class BatteryPowerState {
  const BatteryPowerState({required this.hasBattery, required this.onBattery,
    required this.energySaver, this.isLaptop, this.powerKnown = true});
  final bool hasBattery;
  final bool onBattery;
  final bool energySaver;
  final bool? isLaptop;
  final bool powerKnown;
  bool get shouldOptimize => isLaptop == true && powerKnown && hasBattery &&
      (onBattery || energySaver);
}

/// پل ارتباط با لایه بومی ویندوز (پلاگین umbrella_native).
///
/// هر متد در صورت نبود پلاگین مقدار امن برمی گرداند تا رابط کاربری هرگز
/// از کار نیفتد؛ مثلا در حالت اجرای آزمایشی روی ماشین بدون دسترسی مدیر.
class NativeBridge {
  NativeBridge();

  static const MethodChannel _channel = MethodChannel('ir.umbrella.app/native');
  static const EventChannel _trayChannel = EventChannel('ir.umbrella.app/tray');

  bool _available = true;
  bool get available => _available;

  /// آخرین خطای پل بومی؛ برای گزارش ها نگه داشته می شود.
  String _lastError = '';
  String get lastError => _lastError;

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!_available) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException catch (error) {
      // پلاگین بومی در نسخه ویندوز ثبت نشده است؛ از این پس کارهای حیاتی با
      // پیاده سازی جایگزین انجام می شوند تا اتصال از کار نیفتد.
      _available = false;
      _lastError = 'MissingPluginException: ${error.message ?? method}';
      return null;
    } on PlatformException catch (error) {
      _lastError = '${error.code}: ${error.message ?? method}';
      return null;
    }
  }

  // ── جایگزین های دارت ──────────────────────────────────────────────────
  // این توابع وقتی پلاگین بومی در دسترس نباشد اجرا می شوند تا صفحه اتصال و
  // آزمون پینگ هرگز بی صدا از کار نیفتند.

  Future<int> _dartTcpPing(String host, int port, int timeoutMs) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final Socket socket = await Socket.connect(
        host,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      socket.destroy();
      return watch.elapsedMilliseconds;
    } on Object {
      return -1;
    }
  }

  Future<int> _dartPing(String host, int timeoutMs) async {
    try {
      final ProcessResult result = await Process.run(
        'ping',
        <String>['-n', '1', '-w', '$timeoutMs', host],
        runInShell: false,
      );
      final String text = _asciiDigits('${result.stdout}\n${result.stderr}');
      // ویندوز فارسی «زمان=۱۲۰ms» و در حالت کمتر از یک میلی ثانیه
      // «زمان<1ms» می نویسد.
      final RegExpMatch? match =
          RegExp(r'(?:time|زمان)\s*[=<]\s*([0-9]+)\s*(?:ms|میلی)').firstMatch(text);
      if (match != null) {
        final int? value = int.tryParse(match.group(1) ?? '');
        if (value != null) {
          return value;
        }
      }
    } on Object {
      return -1;
    }
    return -1;
  }

  /// رقم های فارسی و عربی را به رقم لاتین تبدیل می کند تا خروجی ابزارهای
  /// ویندوز فارسی هم خوانده شود.
  static String _asciiDigits(String text) {
    const String persian = '۰۱۲۳۴۵۶۷۸۹';
    const String arabic = '٠١٢٣٤٥٦٧٨٩';
    final StringBuffer buffer = StringBuffer();
    for (final int code in text.runes) {
      final String char = String.fromCharCode(code);
      final int persianIndex = persian.indexOf(char);
      if (persianIndex >= 0) {
        buffer.write(persianIndex);
        continue;
      }
      final int arabicIndex = arabic.indexOf(char);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  static const String _inetKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  Future<bool> _reg(List<String> args) async {
    try {
      final ProcessResult result = await Process.run('reg', args, runInShell: false);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<bool> _dartSetSystemProxy(String host, int port) async {
    final bool enabled = await _reg(<String>[
      'add', _inetKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f',
    ]);
    final bool server = await _reg(<String>[
      'add', _inetKey, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '$host:$port',
      '/f',
    ]);
    await _reg(<String>[
      'add', _inetKey, '/v', 'ProxyOverride', '/t', 'REG_SZ',
      '/d', '<local>;127.0.0.1;localhost;::1', '/f',
    ]);
    return enabled && server;
  }

  Future<bool> _dartDisableSystemProxy() async {
    final bool ok = await _reg(<String>[
      'add', _inetKey, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f',
    ]);
    await _reg(<String>['delete', _inetKey, '/v', 'ProxyOverride', '/f']);
    return ok;
  }

  Future<List<String>> _taskList() async {
    try {
      final ProcessResult result = await Process.run(
        'tasklist',
        <String>['/FO', 'CSV', '/NH'],
        runInShell: false,
      );
      final String text = '${result.stdout}';
      final List<String> names = <String>[];
      for (final String line in text.split(RegExp(r'\r?\n'))) {
        final int start = line.indexOf('"');
        if (start < 0) {
          continue;
        }
        final int end = line.indexOf('"', start + 1);
        if (end <= start) {
          continue;
        }
        names.add(line.substring(start + 1, end).toLowerCase());
      }
      return names;
    } on Object {
      return <String>[];
    }
  }

  Future<int> _dartKillByName(String name) async {
    final String image = name.toLowerCase().endsWith('.exe')
        ? name.toLowerCase()
        : '${name.toLowerCase()}.exe';
    try {
      final ProcessResult result = await Process.run(
        'taskkill',
        <String>['/F', '/IM', image],
        runInShell: false,
      );
      return result.exitCode == 0 ? 1 : 0;
    } on Object {
      return 0;
    }
  }

  Stream<String> get trayEvents {
    if (!_available) {
      return const Stream<String>.empty();
    }
    return _trayChannel
        .receiveBroadcastStream()
        .map((Object? event) => event?.toString() ?? '')
        .handleError((Object error) => '');
  }

  Future<bool> isElevated() async {
    final bool? elevated = await _invoke<bool>('isElevated');
    if (elevated != null) {
      return elevated;
    }
    // «net session» فقط با دسترسی مدیر موفق می شود.
    try {
      final ProcessResult result = await Process.run(
        'net',
        <String>['session'],
        runInShell: false,
      );
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<bool> relaunchElevated() async =>
      await _invoke<bool>('relaunchElevated') ?? false;

  Future<bool> runElevated(String exe, {String args = ''}) async =>
      await _invoke<bool>('runElevated', <String, dynamic>{
        'exe': exe,
        'args': args,
      }) ??
      false;

  /// ابعاد ناحیه کاری نمایشگر اصلی در واحد منطقی، بدون نوار وظیفه.
  Future<Size?> primaryWorkArea() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('primaryWorkArea');
      final width = raw?['width'];
      final height = raw?['height'];
      if (width is! num || height is! num || !width.isFinite ||
          !height.isFinite || width <= 0 || height <= 0) return null;
      return Size(width.toDouble(), height.toDouble());
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// عدم پشتیبانی از این متد نباید کل پل بومی را از کار بیندازد.
  Future<BatteryPowerState?> powerStatus() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('powerStatus');
      if (raw == null) return null;
      final bool? laptop = raw['isLaptop'] is bool ? raw['isLaptop'] as bool : null;
      final bool known = raw['known'] == true && raw['hasBattery'] is bool &&
          raw['onBattery'] is bool && raw['energySaver'] is bool;
      if (!known && laptop == null) return null;
      return BatteryPowerState(
        isLaptop: laptop,
        powerKnown: known,
        hasBattery: known && raw['hasBattery'] == true,
        onBattery: known && raw['onBattery'] == true,
        energySaver: known && raw['energySaver'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<DeviceProfile> deviceInfo() async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('deviceInfo');
    if (raw == null || raw.isEmpty) {
      return DeviceProfile.empty;
    }
    return DeviceProfile.fromNative(Map<String, dynamic>.from(raw));
  }

  Future<String> localIp() async => await _invoke<String>('localIp') ?? '';

  Future<String> adapterName() async =>
      await _invoke<String>('adapterName') ?? '';

  /// پینگ ICMP عمدا از پلاگین بومی گرفته نمی شود: آن پیاده سازی روی رشته رابط
  /// کاربری اجرا می شد و با سنجش چند سرور، کل پنجره قفل می کرد. اجرای ping.exe
  /// با Process.run ناهمگام است و رابط را آزاد می گذارد.
  Future<int> ping(String host, {int timeoutMs = 1500}) =>
      _dartPing(host, timeoutMs);

  /// آزمون TCP با سوکت دارت؛ ناهمگام و بدون قفل کردن رابط.
  Future<int> tcpPing(String host, int port, {int timeoutMs = 1500}) =>
      _dartTcpPing(host, port, timeoutMs);

  Future<int> spawn({
    required String exe,
    String args = '',
    String workDir = '',
    bool hidden = true,
    String logPath = '',
  }) async =>
      await _invoke<int>('spawn', <String, dynamic>{
        'exe': exe,
        'args': args,
        'workDir': workDir,
        'hidden': hidden,
        'logPath': logPath,
      }) ??
      -1;

  /// متن خطای ویندوز هنگام آخرین اجرای ناموفق هسته.
  Future<String> lastSpawnError() async =>
      await _invoke<String>('lastSpawnError') ?? '';

  /// الصاق پردازش هسته به Job Object بومی ویندوز تا با بسته شدن برنامه (حتی از
  /// Task Manager) هسته و CLI بلافاصله بسته شوند.
  Future<bool> attachCoreJob(int pid) async {
    if (pid <= 0) return false;
    return await _invoke<bool>('attachCoreJob', <String, dynamic>{'pid': pid}) ??
        false;
  }

  static bool _winHttpAvailable = true;

  /// فعال سازی مجدد مسیر HTTP بومی برای آزمون واحد.
  static void resetHttpAvailabilityForTest() {
    _winHttpAvailable = true;
  }

  /// ارسال درخواست HTTPS/HTTP از مسیر بومی ویندوز (WinHTTP + Schannel).
  ///
  /// روی تمام نسخه های ۶۴ بیتی ویندوز ۱۰ و ۱۱ از مخزن گواهی خود ویندوز
  /// (همراه با دریافت خودکار گواهی ریشه و میانی)، TLS 1.2/1.3 بومی و گذار
  /// سریع از IPv6 معیوب به IPv4 استفاده می کند و روی رشته پس زمینه اجرا
  /// می شود تا رابط کاربری هرگز قفل نشود.
  static Future<NativeHttpResponse?> performHttpRequest({
    required String method,
    required String url,
    Map<String, String> headers = const <String, String>{},
    String body = '',
    int timeoutMs = 15000,
    bool useProxy = false,
  }) async {
    if (!Platform.isWindows || !_winHttpAvailable) {
      return null;
    }
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>(
        'httpRequest',
        <String, dynamic>{
          'method': method,
          'url': url,
          'headers': headers,
          'body': body,
          'timeoutMs': timeoutMs,
          'useProxy': useProxy,
        },
      ).timeout(Duration(milliseconds: timeoutMs + 3000));
      if (raw == null) {
        return null;
      }
      final Object? rawBytes = raw['bodyBytes'];
      final Uint8List bytes;
      if (rawBytes is Uint8List) {
        bytes = rawBytes;
      } else if (rawBytes is List<int>) {
        bytes = Uint8List.fromList(rawBytes);
      } else {
        bytes = Uint8List(0);
      }
      return NativeHttpResponse(
        ok: raw['ok'] == true,
        statusCode: JsonX.integer(raw['statusCode']),
        bodyBytes: bytes,
        contentType: raw['contentType']?.toString() ?? '',
        winError: JsonX.integer(raw['winError']),
        error: raw['error']?.toString() ?? '',
      );
    } on MissingPluginException {
      _winHttpAvailable = false;
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return NativeHttpResponse(
        ok: false,
        statusCode: 0,
        bodyBytes: Uint8List(0),
        winError: 12002,
        error: 'channel_timeout',
      );
    } on Object {
      return null;
    }
  }

  /// بستن قطعی همه پردازش های هسته و پنجره های CLI آمبرلا و پاک سازی پروکسی محلی.
  Future<int> shutdownCores({bool skipIfClean = false}) async {
    final int? count = await _invoke<int>(
      'shutdownCores',
      <String, dynamic>{'skipIfClean': skipIfClean},
    );
    if (count != null) {
      return count;
    }
    int killed = 0;
    for (final String name in const <String>[
      'UmbrellaCli.exe',
      'UmbrellaCoreEngine.exe',
      'UmbrellaAdmin.exe',
    ]) {
      killed += await _dartKillByName(name);
    }
    await _dartDisableSystemProxy();
    return killed;
  }

  Future<bool> killPid(int pid) async {
    if (pid <= 0) {
      return false;
    }
    final bool? ok =
        await _invoke<bool>('killPid', <String, dynamic>{'pid': pid});
    if (ok != null) {
      return ok;
    }
    try {
      final ProcessResult result = await Process.run(
        'taskkill',
        <String>['/F', '/PID', '$pid'],
        runInShell: false,
      );
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<int> killByName(String name) async {
    final int? count =
        await _invoke<int>('killByName', <String, dynamic>{'name': name});
    if (count != null) {
      return count;
    }
    return _dartKillByName(name);
  }

  /// شناسه پردازش هایی که این پورت را گرفته اند.
  ///
  /// راه اول از پل بومی می آید (`GetExtendedTcpTable`) و راه دوم `netstat`
  /// است؛ اگر هیچ کدام جواب نداد، فهرست خالی برمی گردد و برنامه دست به حدس
  /// نمی زند.
  Future<List<int>> pidsHoldingPort(int port) async {
    final List<Object?>? raw =
        await _invoke<List<Object?>>('pidsHoldingPort', <String, dynamic>{
      'port': port,
    });
    if (raw != null && raw.isNotEmpty) {
      return raw
          .map((Object? item) => int.tryParse('$item') ?? 0)
          .where((int pid) => pid > 0)
          .toList();
    }
    return _netstatPids(port);
  }

  /// خواندن صاحب پورت از `netstat` برای وقتی که پل بومی در دسترس نیست.
  Future<List<int>> _netstatPids(int port) async {
    final List<int> pids = <int>[];
    try {
      final ProcessResult result = await Process.run(
        'netstat',
        <String>['-ano', '-p', 'tcp'],
        runInShell: false,
      );
      for (final String row in '${result.stdout}'.split(RegExp(r'\r?\n'))) {
        final List<String> cols = row
            .trim()
            .split(RegExp(r'\s+'))
            .where((String part) => part.isNotEmpty)
            .toList();
        // ستون ها: پروتکل، آدرس محلی، آدرس خارجی، حالت، شناسه پردازش
        if (cols.length < 5 || !cols[0].toUpperCase().startsWith('TCP')) {
          continue;
        }
        if (!cols[1].endsWith(':$port')) {
          continue;
        }
        final int? pid = int.tryParse(cols[4]);
        if (pid != null && pid > 0 && !pids.contains(pid)) {
          pids.add(pid);
        }
      }
    } on Object {
      return <int>[];
    }
    return pids;
  }

  /// نام فایل اجرایی یک پردازش (مثلاً `Hiddify.exe`).
  Future<String> processNameOf(int pid) async {
    final String? name =
        await _invoke<String>('processNameOf', <String, dynamic>{'pid': pid});
    if (name != null && name.isNotEmpty) {
      return name;
    }
    try {
      final ProcessResult result = await Process.run(
        'tasklist',
        <String>['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
        runInShell: false,
      );
      final String out = '${result.stdout}'.trim();
      if (out.isEmpty || out.startsWith('INFO')) {
        return '';
      }
      final List<String> cols = out
          .split(',')
          .map((String part) => part.replaceAll('"', '').trim())
          .toList();
      return cols.isEmpty ? '' : cols.first;
    } on Object {
      return '';
    }
  }

  /// مسیر کامل فایل اجرایی یک پردازش؛ برای این که دوباره اشتباه نشود.
  Future<String> processPathOf(int pid) async {
    final String? path =
        await _invoke<String>('processPathOf', <String, dynamic>{'pid': pid});
    if (path != null && path.isNotEmpty) {
      return path;
    }
    try {
      final ProcessResult result = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-Process -Id $pid -ErrorAction SilentlyContinue).Path',
        ],
        runInShell: false,
      );
      return '${result.stdout}'.trim();
    } on Object {
      return '';
    }
  }

  Future<bool> isRunning(String name) async {
    final bool? running =
        await _invoke<bool>('isRunning', <String, dynamic>{'name': name});
    if (running == true) {
      return true;
    }
    final String image = name.toLowerCase().endsWith('.exe')
        ? name.toLowerCase()
        : '${name.toLowerCase()}.exe';
    final List<String> names = await _taskList();
    return names.contains(image);
  }

  Future<List<String>> runningCores() async {
    final List<Object?>? raw =
        await _invoke<List<Object?>>('runningCores');
    if (raw != null && raw.isNotEmpty) {
      return raw.map((Object? item) => item.toString()).toList();
    }
    const List<String> known = <String>[
      'xray.exe',
      'mihomo.exe',
      'clash-meta.exe',
      'v2ray.exe',
      'sing-box.exe',
      'hysteria.exe',
      'tuic.exe',
    ];
    final List<String> names = await _taskList();
    return names
        .where((String item) => known.contains(item))
        .map((String item) => item.replaceAll('.exe', ''))
        .toList();
  }

  Future<bool> setSystemProxy({
    String host = '127.0.0.1',
    required int port,
  }) async {
    final bool? ok = await _invoke<bool>('setSystemProxy', <String, dynamic>{
      'host': host,
      'port': port,
    });
    if (ok == true) {
      return true;
    }
    return _dartSetSystemProxy(host, port);
  }

  Future<bool> disableSystemProxy() async {
    final bool? ok = await _invoke<bool>('disableSystemProxy');
    if (ok == true) {
      return true;
    }
    return _dartDisableSystemProxy();
  }

  Future<bool> systemProxyEnabled() async =>
      await _invoke<bool>('systemProxyEnabled') ?? false;

  Future<bool> flushDns() => _run('ipconfig', <String>['/flushdns']);

  /// اجرای ناهمگام یک فرمان ویندوز؛ خروجی صفر یعنی موفق.
  Future<bool> _run(String exe, List<String> args) async {
    try {
      final ProcessResult result = await Process.run(exe, args, runInShell: false);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<TunnelStats> tunnelStats({String hint = 'sing-box'}) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'tunnelStats',
      <String, dynamic>{'hint': hint},
    );
    if (raw == null) {
      return TunnelStats.empty;
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
    return TunnelStats(
      rx: JsonX.integer(map['rx']),
      tx: JsonX.integer(map['tx']),
      available: JsonX.boolean(map['available']),
      adapter: JsonX.text(map['adapter']),
    );
  }

  static const String _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  Future<bool> setAutostart(
    bool enabled, {
    String appName = 'UmbrellaVPN',
  }) async {
    final bool? nativeResult = await _invoke<bool>(
      'autostart',
      <String, dynamic>{
        'enabled': enabled,
        'appName': appName,
      },
    );
    if (nativeResult == true) {
      return true;
    }
    if (!Platform.isWindows) {
      return false;
    }
    if (!enabled) {
      final bool existed = await autostartEnabled(appName: appName);
      if (!existed) {
        return true;
      }
      return _reg(<String>['delete', _runKey, '/v', appName, '/f']);
    }
    final String exe = await exePath();
    if (exe.isEmpty) {
      return false;
    }
    return _reg(<String>[
      'add',
      _runKey,
      '/v',
      appName,
      '/t',
      'REG_SZ',
      '/d',
      '"$exe" --minimized',
      '/f',
    ]);
  }

  Future<bool> autostartEnabled({String appName = 'UmbrellaVPN'}) async {
    final bool? nativeResult = await _invoke<bool>(
      'autostartEnabled',
      <String, dynamic>{'appName': appName},
    );
    if (nativeResult != null) {
      return nativeResult;
    }
    if (!Platform.isWindows) {
      return false;
    }
    return _reg(<String>['query', _runKey, '/v', appName]);
  }

  Future<String> exePath() async {
    final String? path = await _invoke<String>('exePath');
    if (path != null && path.isNotEmpty) {
      return path;
    }
    return Platform.resolvedExecutable;
  }

  Future<String> dataDir() async => await _invoke<String>('dataDir') ?? '';

  Future<bool> openPath(String path) async =>
      await _invoke<bool>('openPath', <String, dynamic>{'path': path}) ?? false;

  Future<bool> restoreNetworkDefaults() async {
    final bool proxy = await disableSystemProxy();
    await flushDns();
    return proxy;
  }

  Future<bool> trayInit() async => await _invoke<bool>('trayInit') ?? false;

  Future<bool> trayIcon(String path) async =>
      await _invoke<bool>('trayIcon', <String, dynamic>{'path': path}) ?? false;

  Future<bool> trayTooltip(String text) async =>
      await _invoke<bool>('trayTooltip', <String, dynamic>{'text': text}) ??
      false;

  Future<bool> trayMenu({
    required String connectLabel,
    required String disconnectLabel,
    required bool connected,
  }) async =>
      await _invoke<bool>('trayMenu', <String, dynamic>{
        'connectLabel': connectLabel,
        'disconnectLabel': disconnectLabel,
        'connected': connected,
      }) ??
      false;

  Future<bool> trayBalloon({
    required String title,
    required String body,
    bool warning = false,
  }) async =>
      await _invoke<bool>('trayBalloon', <String, dynamic>{
        'title': title,
        'body': body,
        'warning': warning,
      }) ??
      false;

  Future<bool> trayDestroy() async => await _invoke<bool>('trayDestroy') ?? false;
}
