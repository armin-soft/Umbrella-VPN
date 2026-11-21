// کلاینت gRPC هسته موبایل. کنترل هسته به گواهی مشتری و TLS نیاز دارد؛
// loopback اندروید بین برنامه ها مشترک است و نباید بدون احراز هویت باز بماند.

import 'dart:async';

import 'package:grpc/grpc.dart' as $grpc;

import 'hcore_messages.dart';
import 'mtls_credentials.dart';

/// کلاینت RPC های هسته؛ یک کانال برای همه فراخوانی ها.
class HcoreClient extends $grpc.Client {
  HcoreClient(super.channel, {super.options});

  static final _$changeHiddifySettings = $grpc.ClientMethod<
      ChangeHiddifySettingsRequest, CoreInfoResponse>(
    '/hcore.Core/ChangeHiddifySettings',
    (ChangeHiddifySettingsRequest value) => value.writeToBuffer(),
    (List<int> value) => CoreInfoResponse.fromBuffer(value),
  );
  static final _$parse =
      $grpc.ClientMethod<ParseRequest, ParseResponse>(
    '/hcore.Core/Parse',
    (ParseRequest value) => value.writeToBuffer(),
    (List<int> value) => ParseResponse.fromBuffer(value),
  );
  static final _$coreInfoListener = $grpc.ClientMethod<HEmpty, CoreInfoResponse>(
    '/hcore.Core/CoreInfoListener',
    (HEmpty value) => value.writeToBuffer(),
    (List<int> value) => CoreInfoResponse.fromBuffer(value),
  );
  static final _$start = $grpc.ClientMethod<StartRequest, CoreInfoResponse>(
    '/hcore.Core/Start',
    (StartRequest value) => value.writeToBuffer(),
    (List<int> value) => CoreInfoResponse.fromBuffer(value),
  );
  static final _$stop = $grpc.ClientMethod<HEmpty, CoreInfoResponse>(
    '/hcore.Core/Stop',
    (HEmpty value) => value.writeToBuffer(),
    (List<int> value) => CoreInfoResponse.fromBuffer(value),
  );
  static final _$getSystemInfo = $grpc.ClientMethod<HEmpty, SystemInfo>(
    '/hcore.Core/GetSystemInfo',
    (HEmpty value) => value.writeToBuffer(),
    (List<int> value) => SystemInfo.fromBuffer(value),
  );

  Future<CoreInfoResponse> changeHiddifySettings(
    ChangeHiddifySettingsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(
      _$changeHiddifySettings,
      request,
      options: options,
    );
  }

  Future<ParseResponse> parse(
    ParseRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(
      _$parse,
      request,
      options: options,
    );
  }

  /// Start returns before the core is ready; observe this stream for its result.
  $grpc.ResponseStream<CoreInfoResponse> coreInfoListener({
    $grpc.CallOptions? options,
  }) => $createStreamingCall(_$coreInfoListener, Stream.value(HEmpty.create()),
      options: options);

  Future<CoreInfoResponse> start(
    StartRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(
      _$start,
      request,
      options: options,
    );
  }

  Future<CoreInfoResponse> stop({
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(
      _$stop,
      HEmpty.create(),
      options: options,
    );
  }

  Future<SystemInfo> getSystemInfo({
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(
      _$getSystemInfo,
      HEmpty.create(),
      options: options,
    );
  }
}

/// مدیریت کانال gRPC هسته: ساخت یک باره، بستن هنگام خروج.
///
/// The core must be started in its mTLS mode before the channel is used.
class HcoreConnection {
  HcoreConnection({required this.credentials, this.port = 17078});

  final CoreMtlsCredentials credentials;
  final int port;

  $grpc.ClientChannel? _channel;
  HcoreClient? _client;

  HcoreClient get client {
    _channel ??= $grpc.ClientChannel(
      '127.0.0.1',
      port: port,
      options: $grpc.ChannelOptions(credentials: credentials),
    );
    return _client ??= HcoreClient(_channel!);
  }

  bool get isConnected => _channel != null;

  Future<void> shutdown() async {
    final $grpc.ClientChannel? channel = _channel;
    _channel = null;
    _client = null;
    if (channel != null) {
      await channel.shutdown();
    }
  }
}
