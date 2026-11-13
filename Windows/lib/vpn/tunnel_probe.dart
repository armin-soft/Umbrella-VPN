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

  /// اندازه گیری تاخیر واقعی از طریق پروکسی محلی؛ میلی ثانیه یا -۱.
  static Future<int> latency({
    required int proxyPort,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final Completer<int> done = Completer<int>();
    int pending = _endpoints.length;
    for (final String url in _endpoints) {
      final Future<int> probe = _timedViaProxy(proxyPort, url, timeout);
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

  static Future<int> _timedViaProxy(
    int port,
    String url,
    Duration timeout,
  ) async {
    final Uri uri = Uri.parse(url);
    Socket? socket;
    final Stopwatch watch = Stopwatch()..start();
    try {
      socket = await Socket.connect('127.0.0.1', port, timeout: timeout);
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
