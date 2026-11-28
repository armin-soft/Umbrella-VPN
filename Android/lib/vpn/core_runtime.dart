import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../platform/native.dart';
import 'runtime_config.dart';

/// اعتبارسنجی و آماده سازی پیکربندی برای موتور اندروید (`hiddify-core.aar`).
///
/// در اندروید خود هسته داخل سرویس بومی اجرا می شود (`Mobile.setup` + `StartService`)
/// و نیازی به اجرای زیرفرایند جداگانه نیست؛ این کلاس پیش از ارسال پیکربندی به
/// سرویس بومی، لینک ها را از طریق gRPC `Parse` به JSON ساختاریافته تبدیل می کند
/// و پیکربندی نهایی `runtime-android.json` را برای بوت تک مرحله ای (`enableRawConfig`)
/// کش می کند.
class CoreRuntime {
  const CoreRuntime._();

  static const String cacheSchemaVersion = 'umbrella-android-runtime-v11';

  static String runtimeCacheKey({
    required List<String> preparedLinks,
    required Map<String, dynamic> fullSettings,
    required int stickyMinutes,
    required String serviceMode,
    required bool hasBlockPage,
    bool hasHttpsFilter = false,
    bool httpsFilterBroadMode = false,
    Map<String, String>? localRuleSetPaths,
  }) {
    final Map<String, dynamic> strippedSettings =
        Map<String, dynamic>.of(fullSettings)
          ..remove('log-file')
          ..remove('log-level-until');
    final List<String> localKeys = (localRuleSetPaths ?? const <String, String>{})
        .entries
        .map((MapEntry<String, String> e) => '${e.key.trim().toLowerCase()}=${e.value.trim()}')
        .where((String s) => !s.startsWith('='))
        .toList()
      ..sort();
    final String payload = jsonEncode(<String, dynamic>{
      'v': cacheSchemaVersion,
      'mode': serviceMode,
      'sticky': stickyMinutes,
      'blockPage': hasBlockPage,
      'httpsFilter': hasHttpsFilter,
      'httpsBroad': httpsFilterBroadMode,
      'links': preparedLinks,
      'settings': _canonicalize(strippedSettings),
      'local': localKeys,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final List<String> keys =
          value.keys.map((dynamic k) => '$k').toList()..sort();
      return <String, dynamic>{
        for (final String k in keys) k: _canonicalize(value[k]),
      };
    }
    if (value is List) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  static Future<File?> loadCachedRuntime({
    required String runDir,
    required String runtimeKey,
    int? blockPagePort,
    int? httpsFilterPort,
    int? httpsFilterEgressPort,
    String? httpsFilterSecret,
    String coreLogPath = '',
    bool hasBlockPage = false,
    bool hasHttpsFilter = false,
  }) async {
    final String sep = Platform.pathSeparator;
    final File runtimeFile = File('$runDir${sep}runtime-android.json');
    final File stampFile = File('$runDir${sep}runtime-android.cache.sha256');
    try {
      if (!await stampFile.exists() || !await runtimeFile.exists()) {
        return null;
      }
      final String stamp = (await stampFile.readAsString()).trim();
      if (stamp != runtimeKey || await runtimeFile.length() < 8) {
        return null;
      }
      final Object? decoded = jsonDecode(await runtimeFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final Object? outbounds = decoded['outbounds'];
      final Object? inbounds = decoded['inbounds'];
      final Object? experimental = decoded['experimental'];
      if (outbounds is! List ||
          outbounds.isEmpty ||
          inbounds is! List ||
          inbounds.isEmpty ||
          experimental is! Map ||
          experimental['monitoring'] is! Map) {
        return null;
      }

      // Ensure every local `.srs` rule_set referenced in the cached config
      // still exists on disk before launching with `enableRawConfig: true`.
      final Object? route = decoded['route'];
      if (route is Map && route['rule_set'] is List) {
        for (final dynamic item in route['rule_set'] as List<dynamic>) {
          if (item is Map && item['type'] == 'local') {
            final String path = '${item['path'] ?? ''}'.trim();
            if (path.isEmpty || !await File(path).exists()) {
              return null;
            }
          }
        }
      }

      bool mutated = false;
      if (hasBlockPage) {
        bool foundBlockOutbound = false;
        for (final dynamic item in outbounds) {
          if (item is Map && item['tag'] == RuntimeConfig.blockPageOutboundTag) {
            foundBlockOutbound = true;
            if (blockPagePort != null &&
                blockPagePort > 0 &&
                item['server_port'] != blockPagePort) {
              item['server_port'] = blockPagePort;
              mutated = true;
            }
            break;
          }
        }
        if (!foundBlockOutbound) {
          return null;
        }
      }

      if (hasHttpsFilter) {
        bool foundHttpsOutbound = false;
        for (final dynamic item in outbounds) {
          if (item is Map &&
              item['tag'] == RuntimeConfig.httpsFilterOutboundTag) {
            foundHttpsOutbound = true;
            if (httpsFilterPort != null &&
                httpsFilterPort > 0 &&
                item['server_port'] != httpsFilterPort) {
              item['server_port'] = httpsFilterPort;
              mutated = true;
            }
            break;
          }
        }
        bool foundEgressInbound = false;
        for (final dynamic item in inbounds) {
          if (item is Map &&
              item['tag'] == RuntimeConfig.httpsFilterEgressInboundTag) {
            foundEgressInbound = true;
            if (httpsFilterEgressPort != null &&
                httpsFilterEgressPort > 0 &&
                item['listen_port'] != httpsFilterEgressPort) {
              item['listen_port'] = httpsFilterEgressPort;
              mutated = true;
            }
            if (httpsFilterSecret != null && httpsFilterSecret.isNotEmpty) {
              final List<Map<String, String>> nextUsers = <Map<String, String>>[
                <String, String>{
                  'username': 'umbrella',
                  'password': httpsFilterSecret,
                },
              ];
              item['users'] = nextUsers;
              mutated = true;
            }
            break;
          }
        }
        if (!foundHttpsOutbound || !foundEgressInbound) {
          return null;
        }
      }

      if (coreLogPath.isNotEmpty && decoded['log'] is Map) {
        final Map<dynamic, dynamic> logMap = decoded['log'] as Map<dynamic, dynamic>;
        if (logMap['output'] != coreLogPath) {
          logMap['output'] = coreLogPath;
          mutated = true;
        }
      }

      if (mutated) {
        final File tempFile = File('$runDir${sep}runtime-android.tmp.json');
        await tempFile.writeAsString(jsonEncode(decoded), flush: true);
        if (await runtimeFile.exists()) {
          await runtimeFile.delete();
        }
        await tempFile.rename(runtimeFile.path);
      }
      return runtimeFile;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRuntimeCache({
    required String runDir,
    required String runtimeKey,
    required Map<String, dynamic> config,
  }) async {
    final String sep = Platform.pathSeparator;
    final File runtimeFile = File('$runDir${sep}runtime-android.json');
    final File stampFile = File('$runDir${sep}runtime-android.cache.sha256');
    final File tempFile = File('$runDir${sep}runtime-android.save.tmp.json');
    try {
      await tempFile.writeAsString(jsonEncode(config), flush: true);
      if (await runtimeFile.exists()) {
        await runtimeFile.delete();
      }
      await tempFile.rename(runtimeFile.path);
      await stampFile.writeAsString(runtimeKey, flush: true);
    } catch (_) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  static Future<void> invalidateRuntimeCache(String runDir) async {
    final String sep = Platform.pathSeparator;
    for (final String name in const <String>[
      'runtime-android.cache.sha256',
      'runtime-android.json',
    ]) {
      try {
        final File f = File('$runDir$sep$name');
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  static Future<File> compile({
    required String runDir,
    required String linksPath,
    required String settingsPath,
    required bool Function() cancelled,
    NativeBridge? native,
    int? clashApiPort,
    int stickyMinutes = 15,
    bool useCache = true,
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
      final File parsedFile = File('$runDir${sep}parsed.json');
      final File cacheStampFile = File('$runDir${sep}parsed.cache.sha256');
      final String cacheKey = sha256
          .convert(utf8.encode('$cacheSchemaVersion|android|${rawLinks.trim()}'))
          .toString();

      if (useCache &&
          await cacheStampFile.exists() &&
          await parsedFile.exists()) {
        try {
          final String cachedStamp = (await cacheStampFile.readAsString()).trim();
          if (cachedStamp == cacheKey && await parsedFile.length() > 2) {
            final String cachedJson = await parsedFile.readAsString();
            if (cachedJson.trimLeft().startsWith('{')) {
              return parsedFile;
            }
          }
        } catch (_) {}
      }

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
      await parsedFile.writeAsString(parsed.content, flush: true);
      try {
        await cacheStampFile.writeAsString(cacheKey, flush: true);
      } catch (_) {}
      return parsedFile;
    }

    return linksFile;
  }
}
