import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart' show GrpcError;

import '../platform/native.dart';
import '../umbrella_core/client_identity.dart';
import '../umbrella_core/core_client.dart';
import '../umbrella_core/core_messages.dart';
import '../umbrella_core/mtls_credentials.dart';
import '../umbrella_core/start_coordinator.dart';
import 'mobile_session.dart';
import 'mobile_core_settings.dart';
import 'mobile_monitor_logs.dart';
export 'mobile_monitor_logs.dart' show classifyMonitorFailure;

/// Parse converts subscription links into the sing-box profile expected by
/// the core's non-raw Start. Never pass through errors or an empty profile.
String validatedParsedProfile(ParseResponse response) {
  if (response.responseCode != 0 || response.content.trim().isEmpty) {
    throw StateError('VPN profile parsing failed');
  }
  final profile = jsonDecode(response.content);
  if (profile is! Map<String, dynamic>) {
    throw const FormatException('Invalid parsed VPN profile');
  }
  return response.content;
}

/// Connects the mobile engine over pinned mutual TLS. The injected verifier
/// must prove traffic crossed the Android TUN; native verification explicitly
/// binds the request to this app's VPN network rather than the default network.
class UmbrellaMobileBackend implements MobileVpnBackend {
  UmbrellaMobileBackend({
    required this.native,
    required this.settingsJson,
    required this.configContent,
    required this.verifyTunTraffic,
    this.grpcPort = 17078,
    this.onTrace,
  });

  final NativeBridge native;
  final String settingsJson;
  final String configContent;
  final Future<bool> Function() verifyTunTraffic;
  final int grpcPort;
  final void Function(String)? onTrace;
  void _trace(String stage) => onTrace?.call(stage);
  void _traceError(String stage, Object error) {
    // Only numeric gRPC codes and fixed exception categories; raw errors can
    // contain server addresses, subscription links or credentials.
    final kind = error is GrpcError ? 'grpc_${error.code}' :
        error is TimeoutException ? 'timeout' :
        error is FormatException ? 'format' : 'other';
    _trace('$stage.failed.$kind');
  }
  UmbrellaCoreConnection? _connection;
  String? _workingDirectory;
  bool _nativeStartAttempted = false;
  StreamSubscription<CoreLogMessage>? _coreLogs;
  MobileMonitorLogs? _monitorLogs;
  final Set<String> _loggedFailures = <String>{};

  @override
  Future<bool> requestPermission() => native.requestVpnPermission();

  void _validateConfiguration() {
    if (configContent.trim().isEmpty) throw StateError('VPN profile is empty');
    final decoded = jsonDecode(settingsJson);
    if (decoded is! Map || decoded['enable-tun'] != true ||
        decoded['set-system-proxy'] == true) {
      throw const FormatException('Core settings do not enable Android VPN');
    }
  }

  @override
  Future<void> startService() async {
    _validateConfiguration();
    if (_connection != null) throw StateError('Core is already initialized');
    _trace('directories.request');
    final dirs = await native.coreDirectories();
    final base = dirs['baseDir'];
    final working = dirs['workingDir'];
    final temp = dirs['tempDir'];
    if (base == null || working == null || temp == null ||
        base.isEmpty || working.isEmpty || temp.isEmpty) {
      throw StateError('Private core directories are unavailable');
    }
    _workingDirectory = working;
    _trace('identity.prepare');
    final identity = await CoreClientIdentity.loadOrCreate(Directory(base));
    _nativeStartAttempted = true;
    final started = await native.startService(
      baseDir: base, workingDir: working, tempDir: temp, grpcPort: grpcPort,
    );
    if (!started) {
      const knownCodes = {'CORE_ACTIVE', 'CORE_NOT_READY', 'CORE_START_FAILED', 'CORE_BUSY', 'MISSING_PLUGIN'};
      final code = knownCodes.contains(native.lastErrorCode) ? native.lastErrorCode : 'UNKNOWN';
      const knownKinds = {'SECURITY', 'ARGUMENT', 'STATE', 'IO', 'LINKAGE', 'OTHER'};
      final kind = knownKinds.contains(native.lastErrorKind) ? native.lastErrorKind : 'UNKNOWN';
      _trace('native.start.failed.${code}_$kind');
      throw StateError('VPN service setup failed');
    }
    _trace('native.start.ok');
    final certificate = await native.coreServerCertificate();
    if (certificate == null || certificate.isEmpty) {
      throw StateError('VPN core server certificate unavailable');
    }
    _trace('certificate.received');
    _connection = UmbrellaCoreConnection(
      port: grpcPort,
      credentials: CoreMtlsCredentials(
        serverCertificatePem: utf8.decode(certificate),
        clientCertificatePem: identity.certificate,
        clientPrivateKeyPem: identity.privateKey,
      ),
    );
  }

  @override
  Future<void> configureAndStart() async {
    _validateConfiguration();
    final client = _connection?.client;
    if (client == null) throw StateError('VPN core is not initialized');
    try {
      _trace('settings.rpc');
      final response = await client.changeHiddifySettings(
        ChangeHiddifySettingsRequest(hiddifySettingsJson: settingsJson),
      ).timeout(const Duration(seconds: 15));
      if (response.messageType != MessageType.empty) {
        _trace('settings.rejected.code_${response.messageType}');
        throw StateError('Core rejected settings');
      }
      _trace('settings.ok');
    } catch (error) {
      _traceError('settings', error);
      throw const MobileVpnFailure('ارتباط امن با هسته یا تنظیمات VPN ناموفق بود.');
    }
    final String parsedContent;
    try {
      _trace('profile.parse');
      final parsed = await client.parse(ParseRequest(content: configContent))
          .timeout(const Duration(seconds: 30));
      _trace('profile.response.code_${parsed.responseCode}');
      parsedContent = validatedParsedProfile(parsed);
      _trace('profile.ok');
    } catch (error) {
      _traceError('profile', error);
      throw const MobileVpnFailure('پردازش تنظیمات سرور ناموفق بود.');
    }
    // Subscribe before Start so early probe failures are not lost. Raw logs
    // stay in memory only; each fixed category is emitted at most once.
    _coreLogs = client.logListener().listen((entry) {
      final category = classifyMonitorFailure(entry.message);
      if (category != null && _loggedFailures.add(category)) {
        _trace('monitor.failure_$category');
      }
    }, onError: (Object error) => _traceError('monitor.listener', error));
    try {
      _trace('core.start');
      final state = await CoreStartCoordinator.start(
        statuses: client.coreInfoListener(),
        onState: (state, message) => _trace('core.event_${state}_message_$message'),
        sendStart: () => client.start(StartRequest(configContent: parsedContent)),
      );
      _trace('core.state_${state.coreState}.message_${state.messageType}');
      // The core stores its built configuration under the app-private working
      // directory before it announces WAITING. Do not log its contents.
      final working = _workingDirectory;
      if (working == null || !mobileRuntimeMonitoringMatches(
          await File('$working/data/current-config.json').readAsString(), settingsJson)) {
        _trace('monitor.config_mismatch');
        throw StateError('Mobile monitor or control API was not safely configured');
      }
      _trace('monitor.config_verified');
      final settings = jsonDecode(settingsJson) as Map<String, dynamic>;
      final logs = MobileMonitorLogs(
        port: settings['clash-api-port'] as int,
        secret: settings['web-secret'] as String,
        onCategory: (category) {
          if (_loggedFailures.add(category)) _trace('monitor.failure_$category');
        },
        onStatus: (status) => _trace('monitor.clash_$status'),
      );
      _monitorLogs = logs;
      // The core's LogListener does not forward sing-box service logs in
      // non-debug mode. Subscribe to the authenticated local log stream instead.
      await logs.start();
    } catch (error) {
      _traceError('core.start', error);
      throw const MobileVpnFailure('شروع تونل در هسته ناموفق بود.');
    }
  }

  @override
  Future<bool> verifyTraffic() async {
    final client = _connection?.client;
    StreamSubscription<CoreInfoResponse>? subscription;
    int? latestState;
    if (client != null) {
      int? lastState;
      int? lastMessage;
      subscription = client.coreInfoListener().listen((info) {
        latestState = info.coreState;
        if (lastState != info.coreState || lastMessage != info.messageType) {
          lastState = info.coreState;
          lastMessage = info.messageType;
          _trace('verify.core_event_${info.coreState}_message_${info.messageType}');
        }
      }, onError: (Object error) { _traceError('verify.core_listener', error); });
    }
    try {
      final verified = await verifyTunTraffic();
      if (!verified && latestState == CoreStates.noAvailableProxies) {
        _trace('verify.no_available_proxies');
        throw const MobileVpnFailure('هسته هیچ مسیر قابل استفاده‌ای در آزمون اولیه پیدا نکرد؛ سرور، شبکه و دسترسی به نشانی آزمون را بررسی کنید.');
      }
      return verified;
    } finally {
      await subscription?.cancel();
    }
  }

  @override
  Future<void> stopService() async {
    _monitorLogs?.close();
    _monitorLogs = null;
    final connection = _connection;
    _connection = null;
    _workingDirectory = null;
    final logs = _coreLogs;
    _coreLogs = null;
    try {
      await logs?.cancel();
    } catch (error) {
      // A failed diagnostic stream must never prevent VPN teardown.
      _traceError('monitor.cancel', error);
    }
    // Native close stops the engine before releasing the TUN; still close the
    // client channel if native teardown fails.
    try {
      if (_nativeStartAttempted) {
        if (!await native.stopService()) throw StateError('VPN service cleanup failed');
        _nativeStartAttempted = false;
      }
    } finally {
      await connection?.shutdown();
    }
  }
}
