import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'umbrella_core.dart';

/// نتیجه فراخوانی `FetchUrl` از هسته با دست دادن مرورگر کروم.
class CoreFetchResult {
  const CoreFetchResult({
    this.statusCode = 0,
    this.headers = const <String, String>{},
    this.bodyBytes = const <int>[],
    this.fetchError = 0,
    this.errorDetail = '',
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  final int fetchError;
  final String errorDetail;

  bool get hasHttpResponse => statusCode > 0 && fetchError == 0;
}

/// دریافت مستقیم اشتراک از مسیر داخلی هسته (`mode 3`, HTTP/2 gRPC روی لوپ بک)
/// برای عبور از محدودیت هایی که دست دادن TLS کلاینت های غیراستاندارد را مسدود
/// می کنند. صفر وابستگی خارجی دارد و فرایند هسته بلافاصله پس از پاسخ بسته می شود.
class CoreFetchClient {
  const CoreFetchClient._();

  static final String _readyPrefix = '${UmbrellaCore.id.toUpperCase()}_CORE_READY ';
  static final String _errorPrefix = '${UmbrellaCore.id.toUpperCase()}_CORE_ERROR ';

  /// کدگذاری پیام Protobuf برای `FetchUrlRequest`.
  static Uint8List encodeRequest({
    required String url,
    required String userAgent,
    int timeoutMs = 15000,
  }) {
    final BytesBuilder out = BytesBuilder(copy: false);
    void writeString(int field, String value) {
      if (value.isEmpty) return;
      final List<int> bytes = utf8.encode(value);
      _writeVarint(out, (field << 3) | 2);
      _writeVarint(out, bytes.length);
      out.add(bytes);
    }

    writeString(1, url);
    writeString(2, userAgent);
    if (timeoutMs > 0) {
      _writeVarint(out, (3 << 3) | 0);
      _writeVarint(out, timeoutMs);
    }
    return out.takeBytes();
  }

  /// رمزگشایی پاسخ Protobuf برای `FetchUrlResponse`.
  static CoreFetchResult decodeResponse(Uint8List bytes) {
    int statusCode = 0;
    final Map<String, String> headers = <String, String>{};
    List<int> body = const <int>[];
    int fetchError = 0;
    String errorDetail = '';

    int offset = 0;
    while (offset < bytes.length) {
      final (int tag, int afterTag) = _readVarint(bytes, offset);
      offset = afterTag;
      final int field = tag >> 3;
      final int wire = tag & 0x07;
      switch (wire) {
        case 0:
          final (int value, int next) = _readVarint(bytes, offset);
          offset = next;
          if (field == 1) statusCode = value;
          if (field == 4) fetchError = value;
          break;
        case 2:
          final (int len, int start) = _readVarint(bytes, offset);
          final int end = (start + len).clamp(start, bytes.length);
          final Uint8List slice = bytes.sublist(start, end);
          offset = end;
          if (field == 2) {
            final (String k, String v) = _decodeHttpHeader(slice);
            if (k.isNotEmpty) {
              headers[k.toLowerCase()] = v;
            }
          } else if (field == 3) {
            body = slice;
          } else if (field == 5) {
            errorDetail = utf8.decode(slice, allowMalformed: true);
          }
          break;
        case 1:
          offset = (offset + 8).clamp(offset, bytes.length);
          break;
        case 5:
          offset = (offset + 4).clamp(offset, bytes.length);
          break;
        default:
          offset = bytes.length;
          break;
      }
    }
    return CoreFetchResult(
      statusCode: statusCode,
      headers: headers,
      bodyBytes: body,
      fetchError: fetchError,
      errorDetail: errorDetail,
    );
  }

  static (String, String) _decodeHttpHeader(Uint8List slice) {
    String name = '';
    String value = '';
    int offset = 0;
    while (offset < slice.length) {
      final (int tag, int afterTag) = _readVarint(slice, offset);
      offset = afterTag;
      final int field = tag >> 3;
      final int wire = tag & 0x07;
      if (wire == 2) {
        final (int len, int start) = _readVarint(slice, offset);
        final int end = (start + len).clamp(start, slice.length);
        final String text = utf8.decode(slice.sublist(start, end), allowMalformed: true);
        offset = end;
        if (field == 1) name = text;
        if (field == 2) value = text;
      } else if (wire == 0) {
        final (_, int next) = _readVarint(slice, offset);
        offset = next;
      } else {
        break;
      }
    }
    return (name, value);
  }

  /// اجرای موقت هسته در حالت gRPC محلی بدون رمزنگاری روی یک پورت آزاد و
  /// دریافت نشانی با امضای مرورگر کروم.
  static Future<CoreFetchResult?> fetchUrl({
    required String executable,
    required String workDir,
    required String dataDir,
    required Uri uri,
    String userAgent = 'Umbrella-Windows',
    Duration timeout = const Duration(seconds: 20),
    void Function(int pid)? onProcessStarted,
  }) async {
    if (!File(executable).existsSync()) return null;
    final int port = await _pickFreeLoopbackPort();
    if (port <= 0) return null;

    final Directory work = Directory('$dataDir${Platform.pathSeparator}fetch');
    await work.create(recursive: true);

    Process? process;
    try {
      process = await Process.start(
        executable,
        <String>[
          'core',
          '--mode',
          '3',
          '--base-dir',
          work.path,
          '--working-dir',
          work.path,
          '--temp-dir',
          work.path,
          '--listen',
          '127.0.0.1:$port',
          '--owner-pid',
          '$pid',
        ],
        workingDirectory: workDir,
        environment: UmbrellaCore.ownerEnvironment(),
        runInShell: false,
      );
      onProcessStarted?.call(process.pid);
      unawaited(process.stderr.drain<void>());

      final bool ready = await _waitForReadyLine(
        process,
        timeout: const Duration(seconds: 6),
      );
      if (!ready) {
        return null;
      }

      return await callGrpcFetchUrl(
        host: '127.0.0.1',
        port: port,
        uri: uri,
        userAgent: userAgent,
        timeout: timeout,
      );
    } on Object {
      return null;
    } finally {
      if (process != null) {
        try {
          await process.stdin.close();
        } on Object {
          // Stdin may already be closed.
        }
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          process.kill();
        }
      }
    }
  }

  static Future<bool> _waitForReadyLine(
    Process process, {
    required Duration timeout,
  }) async {
    final Completer<bool> completer = Completer<bool>();
    late final StreamSubscription<String> sub;
    sub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (String line) {
        if (completer.isCompleted) return;
        if (line.startsWith(_readyPrefix)) {
          completer.complete(true);
        } else if (line.startsWith(_errorPrefix)) {
          completer.complete(false);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(false);
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    unawaited(process.exitCode.then((_) {
      if (!completer.isCompleted) completer.complete(false);
    }));
    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      await sub.cancel();
    }
  }

  /// ارسال یک تماس گواهی نشده `h2c` روی سوکت لوپ بک به مسیر `/hcore.Core/FetchUrl`.
  /// قابل تست مستقل بر روی هر سرور HTTP/2 آزمایشی.
  static Future<CoreFetchResult?> callGrpcFetchUrl({
    required String host,
    required int port,
    required Uri uri,
    String userAgent = 'Umbrella-Windows',
    Duration timeout = const Duration(seconds: 18),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      socket.setOption(SocketOption.tcpNoDelay, true);

      // RFC 7540 connection preface + empty SETTINGS frame.
      socket.add(utf8.encode('PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n'));
      socket.add(_buildFrame(type: 0x04, flags: 0x00, streamId: 0, payload: Uint8List(0)));

      final Uint8List hpack = _encodeRequestHeaders(
        authority: '$host:$port',
        path: '/hcore.Core/FetchUrl',
      );
      socket.add(_buildFrame(
        type: 0x01, // HEADERS
        flags: 0x04, // END_HEADERS
        streamId: 1,
        payload: hpack,
      ));

      final Uint8List body = encodeRequest(
        url: uri.toString(),
        userAgent: userAgent,
        timeoutMs: timeout.inMilliseconds.clamp(3000, 30000),
      );
      final Uint8List grpcPayload = Uint8List(5 + body.length);
      grpcPayload[0] = 0; // uncompressed
      grpcPayload[1] = (body.length >> 24) & 0xFF;
      grpcPayload[2] = (body.length >> 16) & 0xFF;
      grpcPayload[3] = (body.length >> 8) & 0xFF;
      grpcPayload[4] = body.length & 0xFF;
      grpcPayload.setRange(5, 5 + body.length, body);

      socket.add(_buildFrame(
        type: 0x00, // DATA
        flags: 0x01, // END_STREAM
        streamId: 1,
        payload: grpcPayload,
      ));
      await socket.flush();

      final BytesBuilder buffer = BytesBuilder(copy: false);
      final BytesBuilder responseData = BytesBuilder(copy: false);
      bool streamEnded = false;
      final Completer<CoreFetchResult?> done = Completer<CoreFetchResult?>();

      final StreamSubscription<Uint8List> sub = socket.listen(
        (Uint8List chunk) {
          buffer.add(chunk);
          final Uint8List raw = buffer.toBytes();
          int pos = 0;
          while (pos + 9 <= raw.length) {
            final int length = (raw[pos] << 16) | (raw[pos + 1] << 8) | raw[pos + 2];
            if (pos + 9 + length > raw.length) break;
            final int type = raw[pos + 3];
            final int flags = raw[pos + 4];
            final int streamId = ((raw[pos + 5] & 0x7F) << 24) |
                (raw[pos + 6] << 16) |
                (raw[pos + 7] << 8) |
                raw[pos + 8];
            final Uint8List payload = raw.sublist(pos + 9, pos + 9 + length);
            pos += 9 + length;

            if (type == 0x04 && (flags & 0x01) == 0) {
              // Server SETTINGS -> ACK.
              _trySend(
                socket,
                _buildFrame(
                  type: 0x04,
                  flags: 0x01,
                  streamId: 0,
                  payload: Uint8List(0),
                ),
              );
            } else if (type == 0x06 && (flags & 0x01) == 0) {
              // Server PING -> PONG.
              _trySend(
                socket,
                _buildFrame(
                  type: 0x06,
                  flags: 0x01,
                  streamId: 0,
                  payload: payload,
                ),
              );
            } else if (streamId == 1) {
              if (type == 0x00) {
                responseData.add(payload);
                if (length > 0) {
                  final Uint8List win = Uint8List(4);
                  win[0] = (length >> 24) & 0x7F;
                  win[1] = (length >> 16) & 0xFF;
                  win[2] = (length >> 8) & 0xFF;
                  win[3] = length & 0xFF;
                  _trySend(
                    socket,
                    _buildFrame(type: 0x08, flags: 0, streamId: 0, payload: win),
                  );
                  _trySend(
                    socket,
                    _buildFrame(type: 0x08, flags: 0, streamId: 1, payload: win),
                  );
                }
              } else if (type == 0x03 || type == 0x07) {
                // RST_STREAM or GOAWAY
                if (!done.isCompleted) done.complete(null);
                return;
              }
              if ((flags & 0x01) != 0 && (type == 0x00 || type == 0x01)) {
                streamEnded = true;
              }
            } else if (type == 0x07) {
              if (!done.isCompleted) done.complete(null);
              return;
            }
          }
          buffer.clear();
          if (pos < raw.length) {
            buffer.add(raw.sublist(pos));
          }
          if (streamEnded && !done.isCompleted) {
            final Uint8List grpcBytes = responseData.takeBytes();
            if (grpcBytes.length < 5) {
              done.complete(null);
            } else {
              final int msgLen = (grpcBytes[1] << 24) |
                  (grpcBytes[2] << 16) |
                  (grpcBytes[3] << 8) |
                  grpcBytes[4];
              if (5 + msgLen > grpcBytes.length) {
                done.complete(null);
              } else {
                done.complete(decodeResponse(grpcBytes.sublist(5, 5 + msgLen)));
              }
            }
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete(null);
        },
        onError: (_) {
          if (!done.isCompleted) done.complete(null);
        },
      );

      try {
        return await done.future.timeout(timeout, onTimeout: () => null);
      } finally {
        await sub.cancel();
      }
    } on Object {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  static void _trySend(Socket? socket, Uint8List frame) {
    if (socket == null) return;
    try {
      socket.add(frame);
    } on Object catch (_) {
      return;
    }
  }

  static Uint8List _buildFrame({
    required int type,
    required int flags,
    required int streamId,
    required Uint8List payload,
  }) {
    final int len = payload.length;
    final Uint8List out = Uint8List(9 + len);
    out[0] = (len >> 16) & 0xFF;
    out[1] = (len >> 8) & 0xFF;
    out[2] = len & 0xFF;
    out[3] = type;
    out[4] = flags;
    out[5] = (streamId >> 24) & 0x7F;
    out[6] = (streamId >> 16) & 0xFF;
    out[7] = (streamId >> 8) & 0xFF;
    out[8] = streamId & 0xFF;
    out.setRange(9, 9 + len, payload);
    return out;
  }

  static Uint8List _encodeRequestHeaders({
    required String authority,
    required String path,
  }) {
    final BytesBuilder out = BytesBuilder(copy: false);
    void writeLiteralIndexedName(int index, String value) {
      out.addByte(index); // index < 15, literal without indexing
      final List<int> valBytes = utf8.encode(value);
      _writeHpackInt(out, 0x00, 7, valBytes.length);
      out.add(valBytes);
    }

    void writeLiteralNewName(String name, String value) {
      out.addByte(0x00);
      final List<int> nameBytes = utf8.encode(name);
      _writeHpackInt(out, 0x00, 7, nameBytes.length);
      out.add(nameBytes);
      final List<int> valBytes = utf8.encode(value);
      _writeHpackInt(out, 0x00, 7, valBytes.length);
      out.add(valBytes);
    }

    out.addByte(0x83); // :method POST (static index 3)
    out.addByte(0x86); // :scheme http (static index 6)
    writeLiteralIndexedName(4, path); // :path (static index 4)
    writeLiteralIndexedName(1, authority); // :authority (static index 1)
    writeLiteralNewName('content-type', 'application/grpc');
    writeLiteralNewName('te', 'trailers');
    return out.takeBytes();
  }

  static void _writeHpackInt(BytesBuilder out, int prefix, int n, int value) {
    final int mask = (1 << n) - 1;
    if (value < mask) {
      out.addByte(prefix | value);
      return;
    }
    out.addByte(prefix | mask);
    int v = value - mask;
    while (v >= 128) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  static void _writeVarint(BytesBuilder out, int value) {
    int v = value;
    while (v >= 0x80) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  static (int, int) _readVarint(Uint8List bytes, int start) {
    int result = 0;
    int shift = 0;
    int pos = start;
    while (pos < bytes.length) {
      final int b = bytes[pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return (result, pos);
  }

  static Future<int> _pickFreeLoopbackPort() async {
    ServerSocket? server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      return server.port;
    } on Object {
      return 0;
    } finally {
      await server?.close();
    }
  }
}
