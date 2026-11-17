import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'runtime_config.dart';

/// Compile once and cache by SHA-256 fingerprint of engine + links + settings,
/// so warm connects and background-prewarmed sessions launch `srun` in <2 ms
/// without spawning redundant `parse`/`build` subprocesses (matching Hiddify's
/// pre-validated profile launch path).
class CoreRuntime {
  const CoreRuntime._();

  /// Bump whenever [RuntimeConfig.finalize] semantics change so cached
  /// `runtime.json` files from older app versions rebuild automatically.
  static const String cacheSchemaVersion = 'umbrella-runtime-v2';

  static int _nonce = 0;

  static Future<File> compile({
    required String executable,
    required String workDir,
    required String runDir,
    required String linksPath,
    required String settingsPath,
    required bool Function() cancelled,
    void Function(Process)? onStarted,
    void Function(Process)? onFinished,
    int? clashApiPort,
    bool useCache = true,
  }) async {
    // `build` enables data/clash.db, but srun does not perform hcore.Setup's
    // directory creation. A fresh installation must work without old files.
    final String sep = Platform.pathSeparator;
    await Directory('$runDir${sep}data').create(recursive: true);
    if (cancelled()) throw const FormatException('Core preparation cancelled');

    final File parsedFile = File('$runDir${sep}parsed.json');
    final File parsedStampFile = File('$runDir${sep}parsed.cache.sha256');
    final File runtimeFile = File('$runDir${sep}runtime.json');
    final File runtimeStampFile = File('$runDir${sep}runtime.cache.sha256');

    final String engineStamp = await _engineStamp(executable, workDir);
    final List<int> linkBytes = await File(linksPath).readAsBytes();
    final List<int> settingsBytes = await File(settingsPath).readAsBytes();
    final String parsedKey = _sha256(<List<int>>[
      utf8.encode('$cacheSchemaVersion|parse|$engineStamp|'),
      linkBytes,
    ]);
    final String runtimeKey = _sha256(<List<int>>[
      utf8.encode(
        '$cacheSchemaVersion|runtime|$parsedKey|clash=${clashApiPort ?? 'default'}|',
      ),
      _canonicalSettingsBytes(settingsBytes),
    ]);

    // Fast path (Level 2): identical engine, links and effective settings ->
    // launch `srun` immediately without spawning `parse` or `build`.
    if (useCache &&
        await _stampMatches(runtimeStampFile, runtimeKey) &&
        await _validRuntimeFile(runtimeFile, clashApiPort: clashApiPort)) {
      if (cancelled()) throw const FormatException('Core preparation cancelled');
      return runtimeFile;
    }

    final int buildId = ++_nonce;

    Future<File> command(List<String> args, String output) async {
      final File file = File('$runDir$sep$output');
      if (await file.exists()) await file.delete();
      if (cancelled()) throw const FormatException('Core preparation cancelled');
      final Process process = await Process.start(
        executable,
        <String>[...args, '-D', runDir],
        workingDirectory: workDir,
        runInShell: false,
      );
      onStarted?.call(process);
      // Do not retain parser output: it can contain subscription credentials.
      final Future<void> stdout = process.stdout.drain<void>();
      final Future<void> stderr = process.stderr.drain<void>();
      try {
        if (cancelled()) process.kill();
        final int code =
            await process.exitCode.timeout(const Duration(seconds: 30));
        await Future.wait(<Future<void>>[stdout, stderr]);
        if (cancelled()) {
          throw const FormatException('Core preparation cancelled');
        }
        if (code != 0 || !await file.exists()) {
          throw FormatException(
            'Core ${args.first} did not produce a configuration (exit $code)',
          );
        }
        return file;
      } finally {
        process.kill();
        await process.exitCode
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);
        onFinished?.call(process);
      }
    }

    // Level 1 cache: if only settings changed (e.g. TUN <-> Proxy or DNS),
    // reuse validated `parsed.json` and skip the `parse` subprocess entirely.
    Set<String>? tags;
    if (useCache && await _stampMatches(parsedStampFile, parsedKey)) {
      tags = await _readProfileTags(parsedFile);
    }
    if (tags == null) {
      final String tempParsedName = 'parsed.$buildId.tmp.json';
      final File tempParsed = await command(
        <String>['parse', linksPath, '-o', tempParsedName],
        tempParsedName,
      );
      try {
        final Set<String>? extracted = await _readProfileTags(tempParsed);
        if (extracted == null) {
          throw const FormatException('Parsed profile has no outbound list');
        }
        await _replaceFile(tempParsed, parsedFile);
        if (useCache) {
          await _writeTextSafe(parsedStampFile, parsedKey);
        }
        tags = extracted;
      } finally {
        await _deleteSafe(tempParsed);
      }
    }

    final String tempRuntimeName = 'runtime.$buildId.tmp.json';
    final File tempBuilt = await command(
      <String>[
        'build', '-c', parsedFile.path, '-d', settingsPath, '-o', tempRuntimeName,
      ],
      tempRuntimeName,
    );
    try {
      final Map<String, dynamic> config =
          jsonDecode(await tempBuilt.readAsString()) as Map<String, dynamic>;
      RuntimeConfig.finalize(
        config,
        profileTags: tags,
        clashApiPort: clashApiPort,
      );
      if (cancelled()) {
        throw const FormatException('Core preparation cancelled');
      }
      await tempBuilt.writeAsString(jsonEncode(config), flush: true);
      await _replaceFile(tempBuilt, runtimeFile);
      if (useCache) {
        await _writeTextSafe(runtimeStampFile, runtimeKey);
      }
      return runtimeFile;
    } finally {
      await _deleteSafe(tempBuilt);
    }
  }

  /// Strips `log-file` from the cache digest because [RuntimeConfig.finalize]
  /// always removes `log.output` from the built runtime JSON.
  static List<int> _canonicalSettingsBytes(List<int> raw) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(raw));
      if (decoded is Map<String, dynamic>) {
        final Map<String, dynamic> copy = Map<String, dynamic>.of(decoded)
          ..remove('log-file');
        final List<String> keys = copy.keys.toList()..sort();
        return utf8.encode(
          jsonEncode(<String, dynamic>{
            for (final String k in keys) k: copy[k],
          }),
        );
      }
    } on Object {
      // Fall back to raw bytes.
    }
    return raw;
  }

  static Future<String> _engineStamp(String executable, String workDir) async {
    final StringBuffer buffer = StringBuffer(executable);
    final String sep = Platform.pathSeparator;
    for (final String path in <String>[
      executable,
      '$workDir${sep}UmbrellaCore.dll',
      '$workDir${sep}cores${sep}umbrella${sep}UmbrellaCore.dll',
    ]) {
      try {
        final FileStat stat = await File(path).stat();
        if (stat.type == FileSystemEntityType.file) {
          buffer.write(
            '|$path:${stat.size}:${stat.modified.millisecondsSinceEpoch}',
          );
        }
      } on FileSystemException {
        // Non-existent candidate path is simply omitted.
      }
    }
    return buffer.toString();
  }

  static String _sha256(List<List<int>> chunks) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    for (final List<int> chunk in chunks) {
      builder.add(chunk);
    }
    return sha256.convert(builder.takeBytes()).toString();
  }

  static Future<bool> _stampMatches(File stampFile, String expected) async {
    try {
      if (!await stampFile.exists()) return false;
      return (await stampFile.readAsString()).trim() == expected;
    } on FileSystemException {
      return false;
    }
  }

  static Future<Set<String>?> _readProfileTags(File parsed) async {
    try {
      if (!await parsed.exists()) return null;
      final Object? decoded = jsonDecode(await parsed.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['outbounds'] is! List) {
        return null;
      }
      return <String>{
        for (final dynamic outbound in decoded['outbounds'] as List<dynamic>)
          if (outbound is Map && outbound['tag'] is String)
            outbound['tag'] as String,
      };
    } on Object {
      return null;
    }
  }

  static Future<bool> _validRuntimeFile(
    File runtime, {
    required int? clashApiPort,
  }) async {
    try {
      if (!await runtime.exists()) return false;
      final Object? decoded = jsonDecode(await runtime.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      final Object? outbounds = decoded['outbounds'];
      final Object? experimental = decoded['experimental'];
      if (outbounds is! List || outbounds.isEmpty || experimental is! Map) {
        return false;
      }
      if (experimental['monitoring'] is! Map) return false;
      if (clashApiPort != null && clashApiPort <= 0) {
        return !experimental.containsKey('clash_api');
      }
      return true;
    } on Object {
      return false;
    }
  }

  static Future<void> _replaceFile(File source, File target) async {
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await _deleteSafe(source);
    }
  }

  static Future<void> _writeTextSafe(File file, String content) async {
    try {
      await file.writeAsString(content, flush: true);
    } on FileSystemException {
      // Cache metadata failure must never abort a connection.
    }
  }

  static Future<void> _deleteSafe(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best-effort cleanup of temporary compile artifacts.
    }
  }
}
