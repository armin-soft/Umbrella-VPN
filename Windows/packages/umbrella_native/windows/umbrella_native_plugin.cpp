#include "umbrella_native_plugin.h"
#include "winhttp_client.h"

#include <flutter/standard_method_codec.h>
#include <knownfolders.h>
#include <shlobj.h>

#include <map>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace umbrella {
namespace {

std::wstring ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), out.data(), size);
  return out;
}

std::string StringOf(const flutter::EncodableMap& args, const char* key,
                     const std::string& fallback = std::string()) {
  auto iterator = args.find(flutter::EncodableValue(std::string(key)));
  if (iterator == args.end()) return fallback;
  const auto* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? fallback : *value;
}

int IntOf(const flutter::EncodableMap& args, const char* key, int fallback) {
  auto iterator = args.find(flutter::EncodableValue(std::string(key)));
  if (iterator == args.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) return *value;
  if (const auto* value64 = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(*value64);
  }
  return fallback;
}

bool BoolOf(const flutter::EncodableMap& args, const char* key, bool fallback) {
  auto iterator = args.find(flutter::EncodableValue(std::string(key)));
  if (iterator == args.end()) return fallback;
  const auto* value = std::get_if<bool>(&iterator->second);
  return value == nullptr ? fallback : *value;
}

std::map<std::string, std::string> StringMapOf(const flutter::EncodableMap& args,
                                               const char* key) {
  std::map<std::string, std::string> out;
  auto iterator = args.find(flutter::EncodableValue(std::string(key)));
  if (iterator == args.end()) return out;
  const auto* map = std::get_if<flutter::EncodableMap>(&iterator->second);
  if (map == nullptr) return out;
  for (const auto& entry : *map) {
    const auto* k = std::get_if<std::string>(&entry.first);
    const auto* v = std::get_if<std::string>(&entry.second);
    if (k != nullptr && v != nullptr && !k->empty()) {
      out[*k] = *v;
    }
  }
  return out;
}

template <typename WorkFn>
void RunOffUiThread(
    const std::shared_ptr<PluginReplyGuard>& guard,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    WorkFn&& work) {
  auto shared_result =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
          result.release());
  std::thread([guard, shared_result, fn = std::forward<WorkFn>(work)]() mutable {
    flutter::EncodableValue payload = fn();
    std::lock_guard<std::mutex> lock(guard->mutex);
    if (guard->alive && shared_result != nullptr) {
      shared_result->Success(payload);
    } else {
      shared_result.reset();
    }
  }).detach();
}

/// جریان رویدادهای سینی سیستم؛ بدون وابستگی به کلاس های کمکی نسخه های
/// مختلف پلاگین، فقط از پایه استاندارد StreamHandler استفاده می کند.
class TrayStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit TrayStreamHandler(UmbrellaNativePlugin* plugin) : plugin_(plugin) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
      override {
    plugin_->AttachTraySink(std::move(events));
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue* arguments) override {
    plugin_->AttachTraySink(nullptr);
    return nullptr;
  }

 private:
  UmbrellaNativePlugin* plugin_;
};

}  // namespace

void UmbrellaNativePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<UmbrellaNativePlugin>();
  plugin->SetupChannels(registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

void UmbrellaNativePlugin::SetupChannels(flutter::BinaryMessenger* messenger) {
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "ir.umbrella.app/native",
          &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  tray_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "ir.umbrella.app/tray",
          &flutter::StandardMethodCodec::GetInstance());
  tray_channel_->SetStreamHandler(std::make_unique<TrayStreamHandler>(this));
}

UmbrellaNativePlugin::UmbrellaNativePlugin() {
  data_dir_ = DataDirectory();
  std::wstring wide = ToWide(data_dir_);
  CreateDirectoryW(wide.c_str(), nullptr);
  CreateDirectoryW((wide + L"\\cores").c_str(), nullptr);
}

UmbrellaNativePlugin::~UmbrellaNativePlugin() {
  {
    std::lock_guard<std::mutex> lock(reply_guard_->mutex);
    reply_guard_->alive = false;
  }
  if (method_channel_ != nullptr) {
    method_channel_->SetMethodCallHandler(nullptr);
  }
  if (tray_channel_ != nullptr) {
    tray_channel_->SetStreamHandler(nullptr);
  }
  tray_sink_.reset();
  tray_.Destroy();
  ops_.ShutdownOwnedCores(/*skip_if_clean=*/true);
}

void UmbrellaNativePlugin::AttachTraySink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  tray_sink_ = std::move(sink);
}

void UmbrellaNativePlugin::EmitTrayEvent(const std::string& event) {
  if (tray_sink_ != nullptr) {
    tray_sink_->Success(flutter::EncodableValue(event));
  }
}

std::string UmbrellaNativePlugin::DataDirectory() {
  PWSTR path = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_ProgramData, 0, nullptr, &path))) {
    std::wstring wide(path);
    CoTaskMemFree(path);
    int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                                   static_cast<int>(wide.size()), nullptr, 0,
                                   nullptr, nullptr);
    std::string result(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()),
                        result.data(), size, nullptr, nullptr);
    result += "\\Umbrella";
    return result;
  }
  char buffer[MAX_PATH] = {0};
  GetEnvironmentVariableA("LOCALAPPDATA", buffer, MAX_PATH);
  return std::string(buffer) + "\\Umbrella";
}

void UmbrellaNativePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  flutter::EncodableMap args =
      arguments == nullptr ? flutter::EncodableMap() : *arguments;

  if (method == "isElevated") {
    result->Success(flutter::EncodableValue(ops_.IsElevated()));
    return;
  }
  if (method == "relaunchElevated") {
    result->Success(flutter::EncodableValue(ops_.RelaunchElevated("")));
    return;
  }
  if (method == "runElevated") {
    result->Success(flutter::EncodableValue(
        ops_.RunElevated(StringOf(args, "exe"), StringOf(args, "args"))));
    return;
  }
  if (method == "deviceInfo") {
    DeviceInfo info = ops_.CollectDeviceInfo();
    flutter::EncodableMap map;
    map[flutter::EncodableValue("hostname")] = flutter::EncodableValue(info.hostname);
    map[flutter::EncodableValue("username")] = flutter::EncodableValue(info.username);
    map[flutter::EncodableValue("os")] = flutter::EncodableValue(info.os);
    map[flutter::EncodableValue("osEdition")] = flutter::EncodableValue(info.os_edition);
    map[flutter::EncodableValue("osDisplayVersion")] = flutter::EncodableValue(info.os_display_version);
    map[flutter::EncodableValue("osBuild")] = flutter::EncodableValue(info.os_build);
    map[flutter::EncodableValue("arch")] = flutter::EncodableValue(info.arch);
    map[flutter::EncodableValue("machineId")] = flutter::EncodableValue(info.machine_id);
    map[flutter::EncodableValue("cpu")] = flutter::EncodableValue(info.cpu);
    map[flutter::EncodableValue("cpuCores")] = flutter::EncodableValue(info.cpu_cores);
    map[flutter::EncodableValue("ramTotalMb")] = flutter::EncodableValue(info.ram_total_mb);
    map[flutter::EncodableValue("ramUsedMb")] = flutter::EncodableValue(info.ram_used_mb);
    map[flutter::EncodableValue("ramLoadPercent")] = flutter::EncodableValue(info.ram_load_percent);
    map[flutter::EncodableValue("diskTotalMb")] = flutter::EncodableValue(info.disk_total_mb);
    map[flutter::EncodableValue("diskFreeMb")] = flutter::EncodableValue(info.disk_free_mb);
    map[flutter::EncodableValue("screenWidth")] = flutter::EncodableValue(info.screen_width);
    map[flutter::EncodableValue("screenHeight")] = flutter::EncodableValue(info.screen_height);
    map[flutter::EncodableValue("hasBattery")] = flutter::EncodableValue(info.has_battery);
    map[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(info.battery_percent);
    map[flutter::EncodableValue("powerPlugged")] = flutter::EncodableValue(info.power_plugged);
    map[flutter::EncodableValue("uptimeSeconds")] = flutter::EncodableValue(info.uptime_seconds);
    map[flutter::EncodableValue("adapterName")] = flutter::EncodableValue(info.adapter_name);
    map[flutter::EncodableValue("localIp")] = flutter::EncodableValue(info.local_ip);
    map[flutter::EncodableValue("mac")] = flutter::EncodableValue(info.adapter_mac);
    map[flutter::EncodableValue("elevated")] = flutter::EncodableValue(info.elevated);
    result->Success(flutter::EncodableValue(map));
    return;
  }
  if (method == "localIp") {
    result->Success(flutter::EncodableValue(ops_.LocalIpv4()));
    return;
  }
  if (method == "adapterName") {
    result->Success(flutter::EncodableValue(ops_.DefaultAdapterName()));
    return;
  }
  if (method == "httpRequest") {
    WinHttpRequestSpec spec;
    spec.method = StringOf(args, "method", "GET");
    spec.url = StringOf(args, "url");
    spec.headers = StringMapOf(args, "headers");
    spec.body = StringOf(args, "body");
    spec.timeout_ms = IntOf(args, "timeoutMs", 15000);
    spec.use_system_proxy = BoolOf(args, "useProxy", false);
    RunOffUiThread(reply_guard_, std::move(result),
                   [spec = std::move(spec)]() {
                     WinHttpResponseData resp = PerformWinHttpRequest(spec);
                     flutter::EncodableMap map;
                     map[flutter::EncodableValue("ok")] =
                         flutter::EncodableValue(resp.ok);
                     map[flutter::EncodableValue("statusCode")] =
                         flutter::EncodableValue(resp.status_code);
                     map[flutter::EncodableValue("winError")] =
                         flutter::EncodableValue(
                             static_cast<int64_t>(resp.win_error));
                     map[flutter::EncodableValue("contentType")] =
                         flutter::EncodableValue(resp.content_type);
                     std::vector<uint8_t> body_bytes(resp.body.begin(),
                                                     resp.body.end());
                     map[flutter::EncodableValue("bodyBytes")] =
                         flutter::EncodableValue(std::move(body_bytes));
                     map[flutter::EncodableValue("error")] =
                         flutter::EncodableValue(resp.error);
                     return flutter::EncodableValue(map);
                   });
    return;
  }
  if (method == "ping") {
    const std::string host = StringOf(args, "host");
    const int timeout_ms = IntOf(args, "timeoutMs", 1500);
    RunOffUiThread(reply_guard_, std::move(result), [host, timeout_ms]() {
      return flutter::EncodableValue(
          SystemOps::Instance().PingHost(host, timeout_ms));
    });
    return;
  }
  if (method == "tcpPing") {
    const std::string host = StringOf(args, "host");
    const int port = IntOf(args, "port", 443);
    const int timeout_ms = IntOf(args, "timeoutMs", 1500);
    RunOffUiThread(
        reply_guard_, std::move(result), [host, port, timeout_ms]() {
          return flutter::EncodableValue(
              SystemOps::Instance().TcpPing(host, port, timeout_ms));
        });
    return;
  }
  if (method == "spawn") {
    result->Success(flutter::EncodableValue(ops_.Spawn(
        StringOf(args, "exe"), StringOf(args, "args"),
        StringOf(args, "workDir"), BoolOf(args, "hidden", true),
        StringOf(args, "logPath"))));
    return;
  }
  if (method == "lastSpawnError") {
    result->Success(flutter::EncodableValue(ops_.LastSpawnError()));
    return;
  }
  if (method == "attachCoreJob") {
    result->Success(
        flutter::EncodableValue(ops_.AttachCoreJob(IntOf(args, "pid", 0))));
    return;
  }
  if (method == "shutdownCores") {
    const bool skip_if_clean = BoolOf(args, "skipIfClean", false);
    RunOffUiThread(reply_guard_, std::move(result), [skip_if_clean]() {
      return flutter::EncodableValue(
          SystemOps::Instance().ShutdownOwnedCores(skip_if_clean));
    });
    return;
  }
  if (method == "killPid") {
    result->Success(flutter::EncodableValue(ops_.KillPid(IntOf(args, "pid", 0))));
    return;
  }
  if (method == "killByName") {
    result->Success(
        flutter::EncodableValue(ops_.KillByName(StringOf(args, "name"))));
    return;
  }
  if (method == "pidsHoldingPort") {
    flutter::EncodableList list;
    for (int pid : ops_.PidsHoldingPort(IntOf(args, "port", 0))) {
      list.push_back(flutter::EncodableValue(pid));
    }
    result->Success(flutter::EncodableValue(list));
    return;
  }
  if (method == "processNameOf") {
    result->Success(
        flutter::EncodableValue(ops_.ProcessNameOf(IntOf(args, "pid", 0))));
    return;
  }
  if (method == "processPathOf") {
    result->Success(
        flutter::EncodableValue(ops_.ProcessPathOf(IntOf(args, "pid", 0))));
    return;
  }
  if (method == "isRunning") {
    result->Success(
        flutter::EncodableValue(ops_.IsRunning(StringOf(args, "name"))));
    return;
  }
  if (method == "runningCores") {
    flutter::EncodableList list;
    for (const auto& name : ops_.ListRunningCores()) {
      list.push_back(flutter::EncodableValue(name));
    }
    result->Success(flutter::EncodableValue(list));
    return;
  }
  if (method == "setSystemProxy") {
    result->Success(flutter::EncodableValue(ops_.SetSystemProxy(
        StringOf(args, "host", "127.0.0.1"), IntOf(args, "port", 0))));
    return;
  }
  if (method == "disableSystemProxy") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
      return flutter::EncodableValue(
          SystemOps::Instance().DisableSystemProxy());
    });
    return;
  }
  if (method == "systemProxyEnabled") {
    result->Success(flutter::EncodableValue(ops_.SystemProxyEnabled()));
    return;
  }
  if (method == "flushDns") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
      return flutter::EncodableValue(SystemOps::Instance().FlushDns());
    });
    return;
  }
  if (method == "tunnelStats") {
    TunnelStats stats = ops_.ReadTunnelStats(StringOf(args, "hint", "sing-box"));
    flutter::EncodableMap map;
    map[flutter::EncodableValue("rx")] =
        flutter::EncodableValue(static_cast<int64_t>(stats.rx_bytes));
    map[flutter::EncodableValue("tx")] =
        flutter::EncodableValue(static_cast<int64_t>(stats.tx_bytes));
    map[flutter::EncodableValue("available")] =
        flutter::EncodableValue(stats.available);
    map[flutter::EncodableValue("adapter")] =
        flutter::EncodableValue(stats.adapter);
    result->Success(flutter::EncodableValue(map));
    return;
  }
  if (method == "autostart") {
    result->Success(flutter::EncodableValue(ops_.SetAutostart(
        BoolOf(args, "enabled", false), StringOf(args, "appName", "UmbrellaVPN"))));
    return;
  }
  if (method == "autostartEnabled") {
    result->Success(flutter::EncodableValue(
        ops_.AutostartEnabled(StringOf(args, "appName", "UmbrellaVPN"))));
    return;
  }
  if (method == "exePath") {
    result->Success(flutter::EncodableValue(ops_.ExecutablePath()));
    return;
  }
  if (method == "dataDir") {
    result->Success(flutter::EncodableValue(data_dir_));
    return;
  }
  if (method == "openPath") {
    std::wstring path = ToWide(StringOf(args, "path"));
    HINSTANCE instance = ShellExecuteW(nullptr, L"open", path.c_str(), nullptr,
                                       nullptr, SW_SHOWNORMAL);
    result->Success(flutter::EncodableValue(
        reinterpret_cast<INT_PTR>(instance) > 32));
    return;
  }
  if (method == "trayInit") {
    bool created = tray_.Create([this](const std::string& event) {
      EmitTrayEvent(event);
    });
    if (created) {
      // The tray must never appear as the generic Windows application icon.
      // Load our own icon immediately; Dart calls `trayIcon` right after, but
      // an empty path there must not leave IDI_APPLICATION behind.
      tray_.SetIconFromFile(std::string());
    }
    result->Success(flutter::EncodableValue(created));
    return;
  }
  if (method == "trayIcon") {
    result->Success(
        flutter::EncodableValue(tray_.SetIconFromFile(StringOf(args, "path"))));
    return;
  }
  if (method == "trayTooltip") {
    result->Success(
        flutter::EncodableValue(tray_.SetTooltip(StringOf(args, "text"))));
    return;
  }
  if (method == "trayMenu") {
    result->Success(flutter::EncodableValue(tray_.SetMenuLabels(
        StringOf(args, "connectLabel"), StringOf(args, "disconnectLabel"),
        BoolOf(args, "connected", false))));
    return;
  }
  if (method == "trayBalloon") {
    result->Success(flutter::EncodableValue(tray_.ShowBalloon(
        StringOf(args, "title"), StringOf(args, "body"),
        BoolOf(args, "warning", false))));
    return;
  }
  if (method == "trayDestroy") {
    tray_.Destroy();
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "restoreNetworkDefaults") {
    bool proxy = ops_.DisableSystemProxy();
    ops_.FlushDns();
    result->Success(flutter::EncodableValue(proxy));
    return;
  }

  result->NotImplemented();
}

}  // namespace umbrella

extern "C" __declspec(dllexport) void UmbrellaNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  umbrella::UmbrellaNativePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
