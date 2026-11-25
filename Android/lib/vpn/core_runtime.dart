import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/native.dart';

/// اعتبارسنجی و آماده سازی پیکربندی برای موتور اندروید (`hiddify-core.aar`).
///
/// در اندروید خود هسته داخل سرویس بومی اجرا می شود (`Mobile.setup` + `StartService`)
/// و نیازی به اجرای زیرفرایند جداگانه نیست؛ این کلاس پیش از ارسال پیکربندی به
/// سرویس بومی، لینک ها را از طریق gRPC `Parse` به JSON ساختاریافته تبدیل می کند.
class CoreRuntime {
  const CoreRuntime._();

  static const String cacheSchemaVersion = 'umbrella-android-runtime-v8';

  static Future<File> compile({
    required String runDir,
    required String linksPath,
    required String settingsPath,
    required bool Function() cancelled,
    NativeBridge? native,
    int? clashApiPort,
    int stickyMinutes = 15,
    @visibleForTesting bool? forceAndroidPlatform,
  }) async {
    final String sep = Platform.pathSeparator;
    await Directory('$runDir${sep}data').create(recursive: true);
    if (cancelled()) {
      throw const FormatException('Core preparation cancelled');
    }

    final File linksFile = File(linksPath);
    final String rawLinks = await linksFile.readAsString();
    final NativeBridge bridge = native ?? NativeBridge();

    if ((forceAndroidPlatform ?? Platform.isAndroid) && bridge.available) {
      final ({bool ok, String content, String message}) parsed =
          await bridge.parseConfig(
        content: rawLinks,
        tempPath: '$runDir${sep}tmp',
      );
      if (cancelled()) {
        throw const FormatException('Core preparation cancelled');
      }
      if (!parsed.ok) {
        throw FormatException(
          parsed.message.isNotEmpty
              ? parsed.message
              : 'پیکربندی هسته معتبر نبود.',
        );
      }
      if (parsed.content.isEmpty) {
        throw const FormatException('خروجی پیکربندی هسته خالی بود.');
      }
      final File parsedFile = File('$runDir${sep}parsed.json');
      await parsedFile.writeAsString(parsed.content, flush: true);
      return parsedFile;
    }

    return linksFile;
  }
}
