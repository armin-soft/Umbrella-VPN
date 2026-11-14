import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/utils.dart';
import '../models/models.dart';

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

  Future<bool> killPid(int pid) async {
    final bool? ok =
        await _invoke<bool>('killPid', <String, dynamic>{'pid': pid});
    if (ok == true) {
      return true;
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
    if (count != null && count > 0) {
      return count;
    }
    return _dartKillByName(name);
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

  Future<bool> setAutostart(bool enabled, {String appName = 'UmbrellaVPN'}) async =>
      await _invoke<bool>('autostart', <String, dynamic>{
        'enabled': enabled,
        'appName': appName,
      }) ??
      false;

  Future<bool> autostartEnabled({String appName = 'UmbrellaVPN'}) async =>
      await _invoke<bool>('autostartEnabled', <String, dynamic>{
        'appName': appName,
      }) ??
      false;

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
