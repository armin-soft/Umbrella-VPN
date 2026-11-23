import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../platform/native.dart';

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

/// دریافت مستقیم اشتراک از مسیر داخلی هسته بومی (`hiddify-core.aar` / FetchUrl)
/// با امضای TLS مرورگر کروم برای عبور از محدودیت های دست دادن شبکه.
class CoreFetchClient {
  const CoreFetchClient._();

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
        final String text =
            utf8.decode(slice.sublist(start, end), allowMalformed: true);
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

  static Future<CoreFetchResult?> fetchUrl({
    required Uri uri,
    String userAgent = 'Umbrella-Android',
    Duration timeout = const Duration(seconds: 20),
    NativeBridge? native,
  }) async {
    final NativeBridge bridge = native ?? NativeBridge();
    final CoreFetchNativeResult? res = await bridge.fetchUrlWithCore(
      url: uri.toString(),
      userAgent: userAgent,
      timeoutMs: timeout.inMilliseconds,
    );
    if (res == null) return null;
    return CoreFetchResult(
      statusCode: res.statusCode,
      headers: res.headers,
      bodyBytes: res.bodyBytes,
      fetchError: _mapErrorName(res.error),
      errorDetail: res.errorDetail,
    );
  }

  static int _mapErrorName(String name) => switch (name) {
        'FETCH_URL_ERROR_NONE' || '' => 0,
        'FETCH_URL_ERROR_TIMEOUT' => 1,
        'FETCH_URL_ERROR_DNS' => 2,
        'FETCH_URL_ERROR_REFUSED' => 3,
        'FETCH_URL_ERROR_RESET' => 4,
        'FETCH_URL_ERROR_UNREACHABLE' => 5,
        'FETCH_URL_ERROR_TLS' => 6,
        'FETCH_URL_ERROR_CERTIFICATE' => 7,
        'FETCH_URL_ERROR_TOO_LARGE' => 9,
        _ => 8,
      };

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
}
