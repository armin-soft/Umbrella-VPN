// پیام های پروتوباف هسته موبایل (hiddify-core v5.9.11) به صورت دستی.
//
// چرا دستی؟ تولید کد با protoc در زنجیره ساخت اندروید نیست و فایل های
// تولید شده آماده هم در مخزن نیست؛ پس فقط RPC هایی که اندروید لازم دارد
// با همان شماره فیلدهای فایل های .proto اصلی نوشته شده اند:
//   v2/hcore/hcore.proto و v2/hcommon/common.proto
// قالب سیم (wire format) دقیقاً همان است که سرور gRPC هسته انتظار دارد؛
// فیلدهای enum به صورت int32 خوانده/نوشته می شوند تا بدون کلاس enum کار کند.
//
// RPC های پوشش داده شده:
//   ChangeHiddifySettings, Parse, Start, Stop, GetSystemInfo
// بقیه کارها (پینگ، انتخاب خروجی، آمار ترافیک) از رابط HTTP کلش هسته
// (127.0.0.1:16756) انجام می شود که در vpn/clash_api.dart پیاده شده است.

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

// ── hcommon ────────────────────────────────────────────────────────────────

/// hcommon.Empty — پیام خالی برای RPC های بدون ورودی.
class HEmpty extends $pb.GeneratedMessage {
  @override
  HEmpty clone() => create()..mergeFromMessage(this);

  HEmpty._() : super();
  factory HEmpty.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo('Empty',
      package: const $pb.PackageName('hcommon'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static HEmpty create() => HEmpty._();
  HEmpty createEmptyInstance() => create();
  static $pb.PbList<HEmpty> createRepeated() => $pb.PbList<HEmpty>();
  static HEmpty getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HEmpty>(create);
  static HEmpty? _defaultInstance;
}

/// hcommon.Response — کد پاسخ (OK=0, FAILED=1, AUTH_NEED=2) و پیام.
class HResponse extends $pb.GeneratedMessage {
  @override
  HResponse clone() => create()..mergeFromMessage(this);

  factory HResponse({int? code, String? message}) {
    final HResponse result = create();
    if (code != null) {
      result.code = code;
    }
    if (message != null) {
      result.message = message;
    }
    return result;
  }

  HResponse._() : super();
  factory HResponse.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo('Response',
      package: const $pb.PackageName('hcommon'),
      createEmptyInstance: create)
    ..a<int>(1, 'code', $pb.PbFieldType.O3)
    ..aOS(2, 'message')
    ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static HResponse create() => HResponse._();
  HResponse createEmptyInstance() => create();
  static $pb.PbList<HResponse> createRepeated() => $pb.PbList<HResponse>();
  static HResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HResponse>(create);
  static HResponse? _defaultInstance;

  @$pb.TagNumber(1)
  int get code => $_getIZ(0);
  @$pb.TagNumber(1)
  set code(int v) {
    $_setSignedInt32(0, v);
  }

  @$pb.TagNumber(1)
  bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => clearField(1);

  @$pb.TagNumber(2)
  String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message(String v) {
    $_setString(1, v);
  }

  @$pb.TagNumber(2)
  bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => clearField(2);
}

// ── hcore ──────────────────────────────────────────────────────────────────

/// Only the log request level and response message are needed. Unknown fields
/// (including timestamp) are ignored by protobuf.
class CoreLogRequest extends $pb.GeneratedMessage {
  @override
  CoreLogRequest clone() => create()..mergeFromMessage(this);
  CoreLogRequest._() : super();
  factory CoreLogRequest({int level = 3}) => create()..level = level;
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('LogRequest',
      package: const $pb.PackageName('hcore'), createEmptyInstance: create)
    ..a<int>(1, 'level', $pb.PbFieldType.O3)
    ..hasRequiredFields = false;
  $pb.BuilderInfo get info_ => _i;
  static CoreLogRequest create() => CoreLogRequest._();
  CoreLogRequest createEmptyInstance() => create();
  static $pb.PbList<CoreLogRequest> createRepeated() => $pb.PbList<CoreLogRequest>();
  static CoreLogRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CoreLogRequest>(create);
  static CoreLogRequest? _defaultInstance;
  int get level => $_getIZ(0);
  set level(int v) => $_setSignedInt32(0, v);
}

class CoreLogMessage extends $pb.GeneratedMessage {
  @override
  CoreLogMessage clone() => create()..mergeFromMessage(this);
  CoreLogMessage._() : super();
  factory CoreLogMessage.fromBuffer(List<int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo('LogMessage',
      package: const $pb.PackageName('hcore'), createEmptyInstance: create)
    ..a<int>(1, 'level', $pb.PbFieldType.O3)
    ..a<int>(2, 'type', $pb.PbFieldType.O3)
    ..aOS(3, 'message')
    ..hasRequiredFields = false;
  $pb.BuilderInfo get info_ => _i;
  static CoreLogMessage create() => CoreLogMessage._();
  CoreLogMessage createEmptyInstance() => create();
  static $pb.PbList<CoreLogMessage> createRepeated() => $pb.PbList<CoreLogMessage>();
  static CoreLogMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CoreLogMessage>(create);
  static CoreLogMessage? _defaultInstance;
  String get message => $_getSZ(2);
}

/// hcore.CoreInfoResponse — وضعیت هسته (CoreStates) و نوع پیام.
///
/// CoreStates: STOPPED=0, STARTING=1, STARTED=2, STOPPING=3,
///   HOT_RELOADING=4, WAITING=5, NO_AVAILABLE_PROXIES=6
/// MessageType: EMPTY=0, ... ERROR_BUILDING_CONFIG=11, ...
class CoreInfoResponse extends $pb.GeneratedMessage {
  @override
  CoreInfoResponse clone() => create()..mergeFromMessage(this);

  factory CoreInfoResponse({int? coreState, int? messageType, String? message}) {
    final CoreInfoResponse result = create();
    if (coreState != null) {
      result.coreState = coreState;
    }
    if (messageType != null) {
      result.messageType = messageType;
    }
    if (message != null) {
      result.message = message;
    }
    return result;
  }

  CoreInfoResponse._() : super();
  factory CoreInfoResponse.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo('CoreInfoResponse',
      package: const $pb.PackageName('hcore'),
      createEmptyInstance: create)
    ..a<int>(1, 'coreState', $pb.PbFieldType.O3)
    ..a<int>(2, 'messageType', $pb.PbFieldType.O3)
    ..aOS(3, 'message')
    ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static CoreInfoResponse create() => CoreInfoResponse._();
  CoreInfoResponse createEmptyInstance() => create();
  static $pb.PbList<CoreInfoResponse> createRepeated() =>
      $pb.PbList<CoreInfoResponse>();
  static CoreInfoResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CoreInfoResponse>(create);
  static CoreInfoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  int get coreState => $_getIZ(0);
  @$pb.TagNumber(1)
  set coreState(int v) {
    $_setSignedInt32(0, v);
  }

  @$pb.TagNumber(1)
  bool hasCoreState() => $_has(0);
  @$pb.TagNumber(1)
  void clearCoreState() => clearField(1);

  @$pb.TagNumber(2)
  int get messageType => $_getIZ(1);
  @$pb.TagNumber(2)
  set messageType(int v) {
    $_setSignedInt32(1, v);
  }

  @$pb.TagNumber(2)
  bool hasMessageType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessageType() => clearField(2);

  @$pb.TagNumber(3)
  String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message(String v) {
    $_setString(2, v);
  }

  @$pb.TagNumber(3)
  bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => clearField(3);
}

/// hcore.StartRequest — شروع هسته با مسیر یا محتوای پروفایل.
class StartRequest extends $pb.GeneratedMessage {
  @override
  StartRequest clone() => create()..mergeFromMessage(this);

  factory StartRequest({
    String? configPath,
    String? configContent,
    bool? disableMemoryLimit,
    bool? delayStart,
    bool? enableOldCommandServer,
    bool? enableRawConfig,
    String? configName,
  }) {
    final StartRequest result = create();
    if (configPath != null) {
      result.configPath = configPath;
    }
    if (configContent != null) {
      result.configContent = configContent;
    }
    if (disableMemoryLimit != null) {
      result.disableMemoryLimit = disableMemoryLimit;
    }
    if (delayStart != null) {
      result.delayStart = delayStart;
    }
    if (enableOldCommandServer != null) {
      result.enableOldCommandServer = enableOldCommandServer;
    }
    if (enableRawConfig != null) {
      result.enableRawConfig = enableRawConfig;
    }
    if (configName != null) {
      result.configName = configName;
    }
    return result;
  }

  StartRequest._() : super();
  factory StartRequest.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo('StartRequest',
      package: const $pb.PackageName('hcore'),
      createEmptyInstance: create)
    ..aOS(1, 'configPath')
    ..aOS(2, 'configContent')
    ..aOB(3, 'disableMemoryLimit')
    ..aOB(4, 'delayStart')
    ..aOB(5, 'enableOldCommandServer')
    ..aOB(6, 'enableRawConfig')
    ..aOS(7, 'configName')
    ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static StartRequest create() => StartRequest._();
  StartRequest createEmptyInstance() => create();
  static $pb.PbList<StartRequest> createRepeated() => $pb.PbList<StartRequest>();
  static StartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartRequest>(create);
  static StartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  String get configPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set configPath(String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(1)
  bool hasConfigPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfigPath() => clearField(1);

  @$pb.TagNumber(2)
  String get configContent => $_getSZ(1);
  @$pb.TagNumber(2)
  set configContent(String v) {
    $_setString(1, v);
  }

  @$pb.TagNumber(2)
  bool hasConfigContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfigContent() => clearField(2);

  @$pb.TagNumber(3)
  bool get disableMemoryLimit => $_getBF(2);
  @$pb.TagNumber(3)
  set disableMemoryLimit(bool v) {
    $_setBool(2, v);
  }

  @$pb.TagNumber(3)
  bool hasDisableMemoryLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearDisableMemoryLimit() => clearField(3);

  @$pb.TagNumber(4)
  bool get delayStart => $_getBF(3);
  @$pb.TagNumber(4)
  set delayStart(bool v) {
    $_setBool(3, v);
  }

  @$pb.TagNumber(4)
  bool hasDelayStart() => $_has(3);
  @$pb.TagNumber(4)
  void clearDelayStart() => clearField(4);

  @$pb.TagNumber(5)
  bool get enableOldCommandServer => $_getBF(4);
  @$pb.TagNumber(5)
  set enableOldCommandServer(bool v) {
    $_setBool(4, v);
  }

  @$pb.TagNumber(5)
  bool hasEnableOldCommandServer() => $_has(4);
  @$pb.TagNumber(5)
  void clearEnableOldCommandServer() => clearField(5);

  @$pb.TagNumber(6)
  bool get enableRawConfig => $_getBF(5);
  @$pb.TagNumber(6)
  set enableRawConfig(bool v) {
    $_setBool(5, v);
  }

  @$pb.TagNumber(6)
  bool hasEnableRawConfig() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableRawConfig() => clearField(6);

  @$pb.TagNumber(7)
  String get configName => $_getSZ(6);
  @$pb.TagNumber(7)
  set configName(String v) {
    $_setString(6, v);
  }

  @$pb.TagNumber(7)
  bool hasConfigName() => $_has(6);
  @$pb.TagNumber(7)
  void clearConfigName() => clearField(7);
}

/// hcore.ParseRequest — اعتبارسنجی پروفایل بدون شروع هسته.
class ParseRequest extends $pb.GeneratedMessage {
  @override
  ParseRequest clone() => create()..mergeFromMessage(this);

  factory ParseRequest({
    String? content,
    String? configPath,
    String? tempPath,
    bool? debug,
  }) {
    final ParseRequest result = create();
    if (content != null) {
      result.content = content;
    }
    if (configPath != null) {
      result.configPath = configPath;
    }
    if (tempPath != null) {
      result.tempPath = tempPath;
    }
    if (debug != null) {
      result.debug = debug;
    }
    return result;
  }

  ParseRequest._() : super();
  factory ParseRequest.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo('ParseRequest',
      package: const $pb.PackageName('hcore'),
      createEmptyInstance: create)
    ..aOS(1, 'content')
    ..aOS(2, 'configPath')
    ..aOS(3, 'tempPath')
    ..aOB(4, 'debug')
    ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static ParseRequest create() => ParseRequest._();
  ParseRequest createEmptyInstance() => create();
  static $pb.PbList<ParseRequest> createRepeated() => $pb.PbList<ParseRequest>();
  static ParseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ParseRequest>(create);
  static ParseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  String get content => $_getSZ(0);
  @$pb.TagNumber(1)
  set content(String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(1)
  bool hasContent() => $_has(0);
  @$pb.TagNumber(1)
  void clearContent() => clearField(1);

  @$pb.TagNumber(2)
  String get configPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set configPath(String v) {
    $_setString(1, v);
  }

  @$pb.TagNumber(2)
  bool hasConfigPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfigPath() => clearField(2);

  @$pb.TagNumber(3)
  String get tempPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set tempPath(String v) {
    $_setString(2, v);
  }

  @$pb.TagNumber(3)
  bool hasTempPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearTempPath() => clearField(3);

  @$pb.TagNumber(4)
  bool get debug => $_getBF(3);
  @$pb.TagNumber(4)
  set debug(bool v) {
    $_setBool(3, v);
  }

  @$pb.TagNumber(4)
  bool hasDebug() => $_has(3);
  @$pb.TagNumber(4)
  void clearDebug() => clearField(4);
}

/// hcore.ParseResponse — نتیجه اعتبارسنجی (response_code: OK=0, FAILED=1).
class ParseResponse extends $pb.GeneratedMessage {
  @override
  ParseResponse clone() => create()..mergeFromMessage(this);

  factory ParseResponse({int? responseCode, String? content, String? message}) {
    final ParseResponse result = create();
    if (responseCode != null) {
      result.responseCode = responseCode;
    }
    if (content != null) {
      result.content = content;
    }
    if (message != null) {
      result.message = message;
    }
    return result;
  }

  ParseResponse._() : super();
  factory ParseResponse.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo('ParseResponse',
      package: const $pb.PackageName('hcore'),
      createEmptyInstance: create)
    ..a<int>(1, 'responseCode', $pb.PbFieldType.O3)
    ..aOS(2, 'content')
    ..aOS(3, 'message')
    ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static ParseResponse create() => ParseResponse._();
  ParseResponse createEmptyInstance() => create();
  static $pb.PbList<ParseResponse> createRepeated() => $pb.PbList<ParseResponse>();
  static ParseResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ParseResponse>(create);
  static ParseResponse? _defaultInstance;

  @$pb.TagNumber(1)
  int get responseCode => $_getIZ(0);
  @$pb.TagNumber(1)
  set responseCode(int v) {
    $_setSignedInt32(0, v);
  }

  @$pb.TagNumber(1)
  bool hasResponseCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearResponseCode() => clearField(1);

  @$pb.TagNumber(2)
  String get content => $_getSZ(1);
  @$pb.TagNumber(2)
  set content(String v) {
    $_setString(1, v);
  }

  @$pb.TagNumber(2)
  bool hasContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearContent() => clearField(2);

  @$pb.TagNumber(3)
  String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message(String v) {
    $_setString(2, v);
  }

  @$pb.TagNumber(3)
  bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => clearField(3);
}

/// hcore.ChangeHiddifySettingsRequest — اعمال تنظیمات هسته (JSON کامل).
///
/// هسته ابتدا HiddifyOptions را به پیش فرض برمی گرداند و سپس JSON را روی
/// آن اعمال می کند؛ پس JSON باید کامل باشد (UmbrellaCore.settingsJson).
class ChangeHiddifySettingsRequest extends $pb.GeneratedMessage {
  @override
  ChangeHiddifySettingsRequest clone() => create()..mergeFromMessage(this);

  factory ChangeHiddifySettingsRequest({String? hiddifySettingsJson}) {
    final ChangeHiddifySettingsRequest result = create();
    if (hiddifySettingsJson != null) {
      result.hiddifySettingsJson = hiddifySettingsJson;
    }
    return result;
  }

  ChangeHiddifySettingsRequest._() : super();
  factory ChangeHiddifySettingsRequest.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i =
      $pb.BuilderInfo('ChangeHiddifySettingsRequest',
          package: const $pb.PackageName('hcore'),
          createEmptyInstance: create)
        ..aOS(1, 'hiddifySettingsJson')
        ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static ChangeHiddifySettingsRequest create() => ChangeHiddifySettingsRequest._();
  ChangeHiddifySettingsRequest createEmptyInstance() => create();
  static $pb.PbList<ChangeHiddifySettingsRequest> createRepeated() =>
      $pb.PbList<ChangeHiddifySettingsRequest>();
  static ChangeHiddifySettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChangeHiddifySettingsRequest>(create);
  static ChangeHiddifySettingsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  String get hiddifySettingsJson => $_getSZ(0);
  @$pb.TagNumber(1)
  set hiddifySettingsJson(String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(1)
  bool hasHiddifySettingsJson() => $_has(0);
  @$pb.TagNumber(1)
  void clearHiddifySettingsJson() => clearField(1);
}

/// hcore.SystemInfo — آمار زنده هسته (ترافیک، اتصال ها، خروجی فعال).
class SystemInfo extends $pb.GeneratedMessage {
  @override
  SystemInfo clone() => create()..mergeFromMessage(this);

  factory SystemInfo({
    $fixnum.Int64? memory,
    int? goroutines,
    int? connectionsIn,
    int? connectionsOut,
    bool? trafficAvailable,
    $fixnum.Int64? uplink,
    $fixnum.Int64? downlink,
    $fixnum.Int64? uplinkTotal,
    $fixnum.Int64? downlinkTotal,
    String? currentOutbound,
    String? currentProfile,
  }) {
    final SystemInfo result = create();
    if (memory != null) {
      result.memory = memory;
    }
    if (goroutines != null) {
      result.goroutines = goroutines;
    }
    if (connectionsIn != null) {
      result.connectionsIn = connectionsIn;
    }
    if (connectionsOut != null) {
      result.connectionsOut = connectionsOut;
    }
    if (trafficAvailable != null) {
      result.trafficAvailable = trafficAvailable;
    }
    if (uplink != null) {
      result.uplink = uplink;
    }
    if (downlink != null) {
      result.downlink = downlink;
    }
    if (uplinkTotal != null) {
      result.uplinkTotal = uplinkTotal;
    }
    if (downlinkTotal != null) {
      result.downlinkTotal = downlinkTotal;
    }
    if (currentOutbound != null) {
      result.currentOutbound = currentOutbound;
    }
    if (currentProfile != null) {
      result.currentProfile = currentProfile;
    }
    return result;
  }

  SystemInfo._() : super();
  factory SystemInfo.fromBuffer(List<int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo('SystemInfo',
      package: const $pb.PackageName('hcore'),
      createEmptyInstance: create)
    ..aInt64(1, 'memory')
    ..a<int>(2, 'goroutines', $pb.PbFieldType.O3)
    ..a<int>(3, 'connectionsIn', $pb.PbFieldType.O3)
    ..a<int>(4, 'connectionsOut', $pb.PbFieldType.O3)
    ..aOB(5, 'trafficAvailable')
    ..aInt64(6, 'uplink')
    ..aInt64(7, 'downlink')
    ..aInt64(8, 'uplinkTotal')
    ..aInt64(9, 'downlinkTotal')
    ..aOS(10, 'currentOutbound')
    ..aOS(11, 'currentProfile')
    ..hasRequiredFields = false;

  $pb.BuilderInfo get info_ => _i;

  static SystemInfo create() => SystemInfo._();
  SystemInfo createEmptyInstance() => create();
  static $pb.PbList<SystemInfo> createRepeated() => $pb.PbList<SystemInfo>();
  static SystemInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SystemInfo>(create);
  static SystemInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get memory => $_getI64(0);
  @$pb.TagNumber(1)
  set memory($fixnum.Int64 v) {
    $_setInt64(0, v);
  }

  @$pb.TagNumber(1)
  bool hasMemory() => $_has(0);
  @$pb.TagNumber(1)
  void clearMemory() => clearField(1);

  @$pb.TagNumber(2)
  int get goroutines => $_getIZ(1);
  @$pb.TagNumber(2)
  set goroutines(int v) {
    $_setSignedInt32(1, v);
  }

  @$pb.TagNumber(2)
  bool hasGoroutines() => $_has(1);
  @$pb.TagNumber(2)
  void clearGoroutines() => clearField(2);

  @$pb.TagNumber(3)
  int get connectionsIn => $_getIZ(2);
  @$pb.TagNumber(3)
  set connectionsIn(int v) {
    $_setSignedInt32(2, v);
  }

  @$pb.TagNumber(3)
  bool hasConnectionsIn() => $_has(2);
  @$pb.TagNumber(3)
  void clearConnectionsIn() => clearField(3);

  @$pb.TagNumber(4)
  int get connectionsOut => $_getIZ(3);
  @$pb.TagNumber(4)
  set connectionsOut(int v) {
    $_setSignedInt32(3, v);
  }

  @$pb.TagNumber(4)
  bool hasConnectionsOut() => $_has(3);
  @$pb.TagNumber(4)
  void clearConnectionsOut() => clearField(4);

  @$pb.TagNumber(5)
  bool get trafficAvailable => $_getBF(4);
  @$pb.TagNumber(5)
  set trafficAvailable(bool v) {
    $_setBool(4, v);
  }

  @$pb.TagNumber(5)
  bool hasTrafficAvailable() => $_has(4);
  @$pb.TagNumber(5)
  void clearTrafficAvailable() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get uplink => $_getI64(5);
  @$pb.TagNumber(6)
  set uplink($fixnum.Int64 v) {
    $_setInt64(5, v);
  }

  @$pb.TagNumber(6)
  bool hasUplink() => $_has(5);
  @$pb.TagNumber(6)
  void clearUplink() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get downlink => $_getI64(6);
  @$pb.TagNumber(7)
  set downlink($fixnum.Int64 v) {
    $_setInt64(6, v);
  }

  @$pb.TagNumber(7)
  bool hasDownlink() => $_has(6);
  @$pb.TagNumber(7)
  void clearDownlink() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get uplinkTotal => $_getI64(7);
  @$pb.TagNumber(8)
  set uplinkTotal($fixnum.Int64 v) {
    $_setInt64(7, v);
  }

  @$pb.TagNumber(8)
  bool hasUplinkTotal() => $_has(7);
  @$pb.TagNumber(8)
  void clearUplinkTotal() => clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get downlinkTotal => $_getI64(8);
  @$pb.TagNumber(9)
  set downlinkTotal($fixnum.Int64 v) {
    $_setInt64(8, v);
  }

  @$pb.TagNumber(9)
  bool hasDownlinkTotal() => $_has(8);
  @$pb.TagNumber(9)
  void clearDownlinkTotal() => clearField(9);

  @$pb.TagNumber(10)
  String get currentOutbound => $_getSZ(9);
  @$pb.TagNumber(10)
  set currentOutbound(String v) {
    $_setString(9, v);
  }

  @$pb.TagNumber(10)
  bool hasCurrentOutbound() => $_has(9);
  @$pb.TagNumber(10)
  void clearCurrentOutbound() => clearField(10);

  @$pb.TagNumber(11)
  String get currentProfile => $_getSZ(10);
  @$pb.TagNumber(11)
  set currentProfile(String v) {
    $_setString(10, v);
  }

  @$pb.TagNumber(11)
  bool hasCurrentProfile() => $_has(10);
  @$pb.TagNumber(11)
  void clearCurrentProfile() => clearField(11);
}

// ── مقادیر enum هسته (از hcore.proto) ─────────────────────────────────────

/// CoreStates — وضعیت چرخه حیات هسته.
class CoreStates {
  const CoreStates._();
  static const int stopped = 0;
  static const int starting = 1;
  static const int started = 2;
  static const int stopping = 3;
  static const int hotReloading = 4;
  static const int waiting = 5;
  static const int noAvailableProxies = 6;
}

/// MessageType — نوع پیام نتیجه RPC های هسته.
class MessageType {
  const MessageType._();
  static const int empty = 0;
  static const int emptyConfiguration = 1;
  static const int startCommandServer = 2;
  static const int createService = 3;
  static const int startService = 4;
  static const int unexpectedError = 5;
  static const int alreadyStarted = 6;
  static const int alreadyStopped = 7;
  static const int instanceNotFound = 8;
  static const int instanceNotStopped = 9;
  static const int instanceNotStarted = 10;
  static const int errorBuildingConfig = 11;
  static const int errorParsingConfig = 12;
  static const int errorReadingConfig = 13;
  static const int errorExtension = 14;
  static const int hotReloadFailed = 15;
}

/// hcommon.ResponseCode.
class ResponseCode {
  const ResponseCode._();
  static const int ok = 0;
  static const int failed = 1;
  static const int authNeed = 2;
}
