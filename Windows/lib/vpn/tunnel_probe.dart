import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// آزمون واقعی تونل.
///
/// باز شدن پورت محلی هسته هیچ تضمینی نیست که ترافیک از سرور رد می شود؛
/// هسته پورت را باز می کند حتی وقتی خروجی خراب است. اینجا یک درخواست
/// کوچک واقعی از مسیر تونل فرستاده می شود و فقط اگر جواب بیاید اتصال
/// «برقرار» اعلام می شود.
class TunnelProbe {
  const TunnelProbe._();

  /// نشانی اصلی سنجش؛ سبک و بدون تغییر مسیر.
  static const String probeUrl = 'http://cp.cloudflare.com/generate_204';

  static const List<String> _endpoints = <String>[
    'http://cp.cloudflare.com/generate_204',
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://www.msftconnecttest.com/connecttest.txt',
  ];

  /// بررسی عبور ترافیک.
  ///
  /// [proxyPort] بزرگ تر از صفر: درخواست از پروکسی محلی هسته رد می شود.
  /// صفر: مسیر عادی سیستم (حالت تونل کارت شبکه مجازی).
  static Future<bool> check({
    int proxyPort = 0,
    int attempts = 1,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    for (int attempt = 0; attempt < attempts; attempt++) {
      if (await _race(proxyPort, timeout)) {
        return true;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return false;
  }

  /// همه نشانی ها با هم امتحان می شوند؛ اولین جواب موفق کافی است. این طور
  /// وصل شدن معطل یک سرور کند نمی شود.
  static Future<bool> _race(int proxyPort, Duration timeout) {
    final Completer<bool> done = Completer<bool>();
    int pending = _endpoints.length;
    for (final String url in _endpoints) {
      final Future<bool> probe = proxyPort > 0
          ? _viaProxy(proxyPort, url, timeout)
          : _direct(url, timeout);
      unawaited(
        probe.then<void>(
          (bool ok) {
            if (ok && !done.isCompleted) {
              done.complete(true);
            }
          },
          onError: (Object _) {},
        ).whenComplete(() {
          pending--;
          if (pending == 0 && !done.isCompleted) {
            done.complete(false);
          }
        }),
      );
    }
    return done.future.timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () => false,
    );
  }

  /// اندازه گیری تاخیر واقعی از طریق پروکسی محلی (یا مستقیم از تونل وقتی
  /// `proxyPort == 0`)؛ میلی ثانیه یا -۱.
  static Future<int> latency({
    required int proxyPort,
    Duration timeout = const Duration(seconds: 6),
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    final Completer<int> done = Completer<int>();
    int pending = _endpoints.length;
    for (final String url in _endpoints) {
      final Future<int> probe = proxyPort > 0
          ? _timedViaProxy(
              proxyPort,
              url,
              timeout,
              proxyUser: proxyUser,
              proxyPassword: proxyPassword,
            )
          : _timedDirect(url, timeout);
      unawaited(
        probe.then<void>(
          (int ms) {
            if (ms > 0 && !done.isCompleted) {
              done.complete(ms);
            }
          },
          onError: (Object _) {},
        ).whenComplete(() {
          pending--;
          if (pending == 0 && !done.isCompleted) {
            done.complete(-1);
          }
        }),
      );
    }
    return done.future.timeout(
      timeout + const Duration(seconds: 1),
      onTimeout: () => -1,
    );
  }

  static Future<int> _timedDirect(String url, Duration timeout) async {
    final Uri uri = Uri.parse(url);
    final HttpClient client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (Uri _) => 'DIRECT';
    final Stopwatch watch = Stopwatch()..start();
    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      watch.stop();
      await response.drain<void>().timeout(
            const Duration(milliseconds: 300),
            onTimeout: () {},
          );
      return response.statusCode >= 200 && response.statusCode < 400
          ? watch.elapsedMilliseconds
          : -1;
    } catch (_) {
      return -1;
    } finally {
      client.close(force: true);
    }
  }

  static Future<int> _timedViaProxy(
    int port,
    String url,
    Duration timeout, {
    String proxyUser = '',
    String proxyPassword = '',
  }) async {
    final Uri uri = Uri.parse(url);
    final String authHeader =
        proxyUser.isNotEmpty && proxyPassword.isNotEmpty
            ? 'Proxy-Authorization: Basic '
                '${base64Encode(utf8.encode('$proxyUser:$proxyPassword'))}\r\n'
            : '';
    Socket? socket;
    final Stopwatch watch = Stopwatch()..start();
    try {
      socket = await Socket.connect('127.0.0.1', port, timeout: timeout);
      socket.add(
        utf8.encode(
          'GET $url HTTP/1.1\r\n'
          'Host: ${uri.host}\r\n'
          '$authHeader'
          'User-Agent: UmbrellaVPN/1.0\r\n'
          'Accept: */*\r\n'
          'Connection: close\r\n\r\n',
        ),
      );
      await socket.flush();
      final String head = await _readHead(socket, timeout);
      watch.stop();
      if (!_statusOk(head)) {
        return -1;
      }
      return watch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      socket?.destroy();
    }
  }

  /// اتصال زنده به تونل: یک اتصال پایدار به هسته که برای سنجش پینگ و سرعت
  /// دوباره و دوباره استفاده می شود.
  ///
  /// اندازه گیری هر بار با اتصال تازه TCP، عدد پینگ را چند برابر واقعیت نشان
  /// می دهد (سه مرحله دست دادن)؛ همان کاری که کلاینت رسمی هسته می کند: اتصال
  /// باز می ماند و زمان خواندن سرور روی همان اتصال سنجیده می شود.
  static Future<ProxyLink?> openLink(int port, {int timeoutSeconds = 6}) async {
    if (port <= 0) {
      return null;
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: Duration(seconds: timeoutSeconds),
      );
      return ProxyLink._(socket);
    } catch (_) {
      socket?.destroy();
      return null;
    }
  }

  static Future<bool> _viaProxy(
    int port,
    String url,
    Duration timeout,
  ) async {
    final Uri uri = Uri.parse(url);
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: timeout,
      );
      // درخواست به شکل مطلق برای پروکسی HTTP.
      socket.add(
        utf8.encode(
          'GET $url HTTP/1.1\r\n'
          'Host: ${uri.host}\r\n'
          'User-Agent: UmbrellaVPN/1.0\r\n'
          'Accept: */*\r\n'
          'Connection: close\r\n\r\n',
        ),
      );
      await socket.flush();
      final String head = await _readHead(socket, timeout);
      return _statusOk(head);
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<bool> _direct(String url, Duration timeout) async {
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest request = await client
          .getUrl(Uri.parse(url))
          .timeout(timeout);
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout, onTimeout: () {});
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// خواندن سرآیند پاسخ (تا رسیدن خط خالی) با سقف حجم و زمان.
  static Future<String> _readHead(Socket socket, Duration timeout) async {
    final List<int> data = <int>[];
    final Completer<String> done = Completer<String>();
    late final StreamSubscription<List<int>> sub;
    final Timer timer = Timer(timeout, () {
      if (!done.isCompleted) {
        done.complete(latin1.decode(data, allowInvalid: true));
      }
    });
    sub = socket.listen(
      (List<int> chunk) {
        data.addAll(chunk);
        final String text = latin1.decode(data, allowInvalid: true);
        if (text.contains('\r\n\r\n') || data.length > 4096) {
          if (!done.isCompleted) {
            done.complete(text);
          }
        }
      },
      onError: (Object _) {
        if (!done.isCompleted) {
          done.complete(latin1.decode(data, allowInvalid: true));
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete(latin1.decode(data, allowInvalid: true));
        }
      },
      cancelOnError: true,
    );
    final String result = await done.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  static bool _statusOk(String head) {
    if (head.isEmpty) {
      return false;
    }
    final int space = head.indexOf(' ');
    if (space < 0) {
      return false;
    }
    final String rest = head.substring(space + 1);
    final int end = rest.indexOf(' ');
    final String codeText = end > 0 ? rest.substring(0, end) : rest;
    final int? code = int.tryParse(codeText.trim());
    if (code == null) {
      return false;
    }
    return code >= 200 && code < 400;
  }
}

/// اتصال باز به پروکسی محلی هسته؛ برای سنجش پینگ و سرعت زنده.
class ProxyLink {
  ProxyLink._(this._socket) {
    _socket.listen(_onData, onError: (Object _) => _closePending(),
        onDone: _closePending, cancelOnError: false);
  }

  final Socket _socket;
  Completer<int>? _pending;
  Stopwatch? _watch;
  int _headerMatch = 0;
  int _headerBytes = 0;
  bool _closed = false;

  bool get alive => !_closed;

  void _onData(List<int> chunk) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    const marker = <int>[13, 10, 13, 10];
    for (final byte in chunk) {
      _headerBytes++;
      if (_headerBytes > 65536) {
        close();
        return;
      }
      if (byte == marker[_headerMatch]) {
        _headerMatch++;
        if (_headerMatch == marker.length) {
          pending.complete(_watch!.elapsedMilliseconds);
          return;
        }
      } else {
        _headerMatch = byte == marker[0] ? 1 : 0;
      }
    }
  }

  /// یک درخواست در هر لحظه؛ پاسخ با رویداد سوکت، بدون polling دریافت می شود.
  Future<int> fetch(String url) async {
    if (_closed || _pending != null) return -1;
    final pending = Completer<int>();
    _pending = pending;
    _watch = Stopwatch()..start();
    _headerMatch = 0;
    _headerBytes = 0;
    try {
      final uri = Uri.parse(url);
      _socket.add(utf8.encode(
        'GET $url HTTP/1.1\r\n'
        'Host: ${uri.host}\r\n'
        'User-Agent: UmbrellaVPN/1.0\r\n'
        'Accept: */*\r\n\r\n',
      ));
      await _socket.flush().timeout(const Duration(seconds: 3));
      final result = await pending.future.timeout(const Duration(seconds: 5));
      return result > 0 ? result : -1;
    } catch (_) {
      // A late response cannot be mistaken for the next request.
      close();
      return -1;
    } finally {
      if (identical(_pending, pending)) _pending = null;
      _watch = null;
    }
  }

  void _closePending() {
    _closed = true;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(-1);
  }

  void close() {
    _closePending();
    _socket.destroy();
  }
}
