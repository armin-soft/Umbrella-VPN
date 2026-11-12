#include "umbrella_native_plugin.h"

#include <flutter/standard_method_codec.h>
#include <knownfolders.h>
#include <shlobj.h>

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

UmbrellaNativePlugin::~UmbrellaNativePlugin() { tray_.Destroy(); }

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
    map[flutter::EncodableValue("arch")] = flutter::EncodableValue(info.arch);
    map[flutter::EncodableValue("machineId")] = flutter::EncodableValue(info.machine_id);
    map[flutter::EncodableValue("cpu")] = flutter::EncodableValue(info.cpu);
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
  if (method == "ping") {
    result->Success(flutter::EncodableValue(ops_.PingHost(
        StringOf(args, "host"), IntOf(args, "timeoutMs", 1500))));
    return;
  }
  if (method == "tcpPing") {
    result->Success(flutter::EncodableValue(ops_.TcpPing(
        StringOf(args, "host"), IntOf(args, "port", 443),
        IntOf(args, "timeoutMs", 1500))));
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
  if (method == "killPid") {
    result->Success(flutter::EncodableValue(ops_.KillPid(IntOf(args, "pid", 0))));
    return;
  }
  if (method == "killByName") {
    result->Success(
        flutter::EncodableValue(ops_.KillByName(StringOf(args, "name"))));
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
    result->Success(flutter::EncodableValue(ops_.DisableSystemProxy()));
    return;
  }
  if (method == "systemProxyEnabled") {
    result->Success(flutter::EncodableValue(ops_.SystemProxyEnabled()));
    return;
  }
  if (method == "killSwitchOn") {
    std::vector<std::string> allowed;
    auto iterator = args.find(flutter::EncodableValue(std::string("allowed")));
    if (iterator != args.end()) {
      if (const auto* list = std::get_if<flutter::EncodableList>(&iterator->second)) {
        for (const auto& item : *list) {
          if (const auto* text = std::get_if<std::string>(&item)) {
            allowed.push_back(*text);
          }
        }
      }
    }
    result->Success(flutter::EncodableValue(ops_.EnableKillSwitch(
        allowed, StringOf(args, "appName", "Umbrella"))));
    return;
  }
  if (method == "killSwitchOff") {
    result->Success(flutter::EncodableValue(
        ops_.DisableKillSwitch(StringOf(args, "appName", "Umbrella"))));
    return;
  }
  if (method == "killSwitchActive") {
    result->Success(flutter::EncodableValue(
        ops_.KillSwitchActive(StringOf(args, "appName", "Umbrella"))));
    return;
  }
  if (method == "flushDns") {
    result->Success(flutter::EncodableValue(ops_.FlushDns()));
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
    bool kill_switch = ops_.DisableKillSwitch(StringOf(args, "appName", "Umbrella"));
    ops_.FlushDns();
    result->Success(flutter::EncodableValue(proxy && kill_switch));
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
