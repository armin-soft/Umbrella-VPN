// کلاینت gRPC هسته موبایل روی 127.0.0.1:17078.
//
// هسته با Mobile.setup (حالت GRPC_NORMAL_INSECURE) در سرویس پیش زمینه
// اندروید بالا می آید و سرور gRPC را روی همین پورت باز می کند. Dart از
// اینجا فقط RPC های لازم را صدا می زند؛ شروع/توقف سرویس و TUN در Kotlin است.
//
// هشدار امنیتی: loopback در اندروید بین برنامه ها مشترک است؛ اتصال بدون
// TLS و احراز هویت از هسته در برابر برنامه های دیگر محافظت نمی کند. پیش از
// انتشار باید حالت امن هسته و احراز هویت مشتری پیاده و بررسی شود.

import 'dart:async';

import 'package:grpc/grpc.dart' as $grpc;

import 'hcore_messages.dart';

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
/// کانال روی loopback بدون TLS است؛ اگر هسته هنوز بالا نیامده باشد،
/// فراخوانی ها با UNAVAILABLE برمی گردند و کنترلر اتصال دوباره تلاش می کند.
class HcoreConnection {
  HcoreConnection({this.host = '127.0.0.1', this.port = 17078});

  final String host;
  final int port;

  $grpc.ClientChannel? _channel;
  HcoreClient? _client;

  HcoreClient get client {
    _channel ??= $grpc.ClientChannel(
      host,
      port: port,
      options: const $grpc.ChannelOptions(
        credentials: $grpc.ChannelCredentials.insecure(),
      ),
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
