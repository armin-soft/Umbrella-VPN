import 'dart:convert';
import 'dart:io';

import '../platform/native.dart';
import '../umbrella_core/client_identity.dart';
import '../umbrella_core/core_client.dart';
import '../umbrella_core/core_messages.dart';
import '../umbrella_core/mtls_credentials.dart';
import '../umbrella_core/start_coordinator.dart';
import 'mobile_session.dart';

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
/// must prove traffic crossed the Android TUN; a direct request from this app
/// is not sufficient because the app itself is excluded from the VPN.
class UmbrellaMobileBackend implements MobileVpnBackend {
  UmbrellaMobileBackend({
    required this.native,
    required this.settingsJson,
    required this.configContent,
    required this.verifyTunTraffic,
    this.grpcPort = 17078,
  });

  final NativeBridge native;
  final String settingsJson;
  final String configContent;
  final Future<bool> Function() verifyTunTraffic;
  final int grpcPort;
  UmbrellaCoreConnection? _connection;
  bool _nativeStartAttempted = false;

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
    final dirs = await native.coreDirectories();
    final base = dirs['baseDir'];
    final working = dirs['workingDir'];
    final temp = dirs['tempDir'];
    if (base == null || working == null || temp == null ||
        base.isEmpty || working.isEmpty || temp.isEmpty) {
      throw StateError('Private core directories are unavailable');
    }
    final identity = await CoreClientIdentity.loadOrCreate(Directory(base));
    _nativeStartAttempted = true;
    final started = await native.startService(
      baseDir: base, workingDir: working, tempDir: temp, grpcPort: grpcPort,
    );
    if (!started) throw StateError('VPN service setup failed');
    final certificate = await native.coreServerCertificate();
    if (certificate == null || certificate.isEmpty) {
      throw StateError('VPN core server certificate unavailable');
    }
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
      final response = await client.changeHiddifySettings(
        ChangeHiddifySettingsRequest(hiddifySettingsJson: settingsJson),
      ).timeout(const Duration(seconds: 15));
      if (response.messageType != MessageType.empty) {
        throw StateError('Core rejected settings');
      }
    } catch (_) {
      throw const MobileVpnFailure('ارتباط امن با هسته یا تنظیمات VPN ناموفق بود.');
    }
    final String parsedContent;
    try {
      final parsed = await client.parse(ParseRequest(content: configContent))
          .timeout(const Duration(seconds: 30));
      parsedContent = validatedParsedProfile(parsed);
    } catch (_) {
      throw const MobileVpnFailure('پردازش تنظیمات سرور ناموفق بود.');
    }
    try {
      await CoreStartCoordinator.start(
        statuses: client.coreInfoListener(),
        sendStart: () => client.start(StartRequest(configContent: parsedContent)),
      );
    } catch (_) {
      throw const MobileVpnFailure('شروع تونل در هسته ناموفق بود.');
    }
  }

  @override
  Future<bool> verifyTraffic() => verifyTunTraffic();

  @override
  Future<void> stopService() async {
    final connection = _connection;
    _connection = null;
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
