import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'runtime_config.dart';

/// Compile once, then run the exact inspected JSON, not standalone's rebuild.
class CoreRuntime {
  const CoreRuntime._();

  static Future<File> compile({
    required String executable,
    required String workDir,
    required String runDir,
    required String linksPath,
    required String settingsPath,
    required bool Function() cancelled,
    required void Function(Process) onStarted,
    required void Function(Process) onFinished,
  }) async {
    // `build` enables data/clash.db, but srun does not perform hcore.Setup's
    // directory creation. A fresh installation must work without old files.
    await Directory('$runDir${Platform.pathSeparator}data').create(recursive: true);
    Future<File> command(List<String> args, String output) async {
      final File file = File('$runDir${Platform.pathSeparator}$output');
      if (await file.exists()) await file.delete();
      if (cancelled()) throw const FormatException('Core preparation cancelled');
      final Process process = await Process.start(executable, <String>[...args, '-D', runDir],
          workingDirectory: workDir, runInShell: false);
      onStarted(process);
      // Do not retain parser output: it can contain subscription credentials.
      final Future<void> stdout = process.stdout.drain<void>();
      final Future<void> stderr = process.stderr.drain<void>();
      try {
        if (cancelled()) process.kill();
        final int code = await process.exitCode.timeout(const Duration(seconds: 30));
        await Future.wait(<Future<void>>[stdout, stderr]);
        if (cancelled()) throw const FormatException('Core preparation cancelled');
        if (code != 0 || !await file.exists()) {
          throw FormatException('Core ${args.first} did not produce a configuration (exit $code)');
        }
        return file;
      } finally {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
        onFinished(process);
      }
    }

    final File parsed = await command(<String>['parse', linksPath, '-o', 'parsed.json'], 'parsed.json');
    final Map<String, dynamic> profile = jsonDecode(await parsed.readAsString()) as Map<String, dynamic>;
    if (profile['outbounds'] is! List) throw const FormatException('Parsed profile has no outbound list');
    final Set<String> tags = <String>{
      for (final dynamic outbound in profile['outbounds'] as List<dynamic>)
        if (outbound['tag'] is String) outbound['tag'] as String,
    };
    final File built = await command(<String>[
      'build', '-c', parsed.path, '-d', settingsPath, '-o', 'runtime.json',
    ], 'runtime.json');
    final Map<String, dynamic> config = jsonDecode(await built.readAsString()) as Map<String, dynamic>;
    RuntimeConfig.finalize(config, profileTags: tags);
    if (cancelled()) throw const FormatException('Core preparation cancelled');
    await built.writeAsString(jsonEncode(config), flush: true);
    return built;
  }
}
