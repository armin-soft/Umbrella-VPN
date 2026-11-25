#include "umbrella_native_plugin.h"
#include "security_scanner.h"
#include "winhttp_client.h"

#include <flutter/standard_method_codec.h>
#include <knownfolders.h>
#include <shlobj.h>

#include <cstring>
#include <map>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace umbrella {
namespace {

// SMBIOS enclosure type distinguishes laptops from desktops with a UPS.
// Unknown or inaccessible firmware is deliberately not treated as a laptop.
int LaptopChassis() {
  constexpr DWORD kRawSmbios = 0x52534d42;  // 'RSMB'
  const UINT size = GetSystemFirmwareTable(kRawSmbios, 0, nullptr, 0);
  if (size < 8 || size > 1024 * 1024) return -1;
  std::vector<BYTE> data(size);
  if (GetSystemFirmwareTable(kRawSmbios, 0, data.data(), size) != size) return -1;
  DWORD table_length = 0;
  std::memcpy(&table_length, data.data() + 4, sizeof(table_length));
  if (table_length > size - 8) return -1;
  const size_t end = 8 + table_length;
  for (size_t pos = 8; pos + 4 <= end;) {
    const BYTE type = data[pos];
    const size_t length = data[pos + 1];
    if (length < 4 || length > end - pos) return -1;
    if (type == 3 && length >= 6) {
      const BYTE chassis = data[pos + 5] & 0x7f;
      switch (chassis) {
        case 8: case 9: case 10: case 14: case 30: case 31: case 32:
          return 1;
        case 1: case 2: return -1;
        default: return 0;
      }
    }
    if (type == 127) break;
    size_t next = pos + length;
    while (next + 1 < end && (data[next] != 0 || data[next + 1] != 0)) ++next;
    if (next + 1 >= end) return -1;
    pos = next + 2;
  }
  return -1;
}

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
  if (method == "primaryWorkArea") {
    RECT area = {};
    if (!SystemParametersInfoW(SPI_GETWORKAREA, 0, &area, 0)) {
      result->Success(flutter::EncodableValue());
      return;
    }
    const UINT dpi = GetDpiForSystem();
    const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
    flutter::EncodableMap map;
    map[flutter::EncodableValue("width")] = flutter::EncodableValue((area.right - area.left) / scale);
    map[flutter::EncodableValue("height")] = flutter::EncodableValue((area.bottom - area.top) / scale);
    result->Success(flutter::EncodableValue(map));
    return;
  }
  if (method == "powerStatus") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
      // Cache hardware classification; only the power status is polled.
      static const int laptop = LaptopChassis();
      SYSTEM_POWER_STATUS power = {};
      const bool success = GetSystemPowerStatus(&power) != 0;
      const bool battery_known = success && power.BatteryFlag != 255;
      const bool has_battery = battery_known && (power.BatteryFlag & 128) == 0;
      const bool ac_known = success && (power.ACLineStatus == 0 || power.ACLineStatus == 1);
      flutter::EncodableMap map;
      if (laptop >= 0)
        map[flutter::EncodableValue("isLaptop")] = flutter::EncodableValue(laptop == 1);
      map[flutter::EncodableValue("known")] =
          flutter::EncodableValue(battery_known && (!has_battery || ac_known));
      map[flutter::EncodableValue("hasBattery")] = flutter::EncodableValue(has_battery);
      map[flutter::EncodableValue("onBattery")] = flutter::EncodableValue(success && power.ACLineStatus == 0);
      map[flutter::EncodableValue("energySaver")] = flutter::EncodableValue(success && power.SystemStatusFlag == 1);
      map[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(
          success && power.BatteryLifePercent <= 100
              ? static_cast<int>(power.BatteryLifePercent)
              : -1);
      return flutter::EncodableValue(map);
    });
    return;
  }
  if (method == "processCpuTimeUs") {
    result->Success(flutter::EncodableValue(
        static_cast<int64_t>(ops_.ProcessCpuTimeMicros())));
    return;
  }
  if (method == "deviceInfo") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
    DeviceInfo info = SystemOps::Instance().CollectDeviceInfo();
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
    return flutter::EncodableValue(map);
    });
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
  if (method == "networkState") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
      const std::string ip = SystemOps::Instance().LocalIpv4();
      const std::string adapter = SystemOps::Instance().DefaultAdapterName();
      const bool online = !ip.empty() || !adapter.empty();
      flutter::EncodableMap map;
      map[flutter::EncodableValue("online")] = flutter::EncodableValue(online);
      map[flutter::EncodableValue("ip")] = flutter::EncodableValue(ip);
      map[flutter::EncodableValue("adapter")] =
          flutter::EncodableValue(adapter);
      map[flutter::EncodableValue("fingerprint")] =
          flutter::EncodableValue(adapter + "|" + ip);
      return flutter::EncodableValue(map);
    });
    return;
  }
  if (method == "resolveProcessLabels") {
    std::vector<std::string> names;
    auto it = args.find(flutter::EncodableValue(std::string("names")));
    if (it != args.end()) {
      if (const auto* list =
              std::get_if<flutter::EncodableList>(&it->second)) {
        for (const auto& item : *list) {
          if (const auto* s = std::get_if<std::string>(&item)) {
            if (!s->empty()) names.push_back(*s);
          }
        }
      }
    }
    RunOffUiThread(reply_guard_, std::move(result),
                   [names = std::move(names)]() {
                     const auto resolved =
                         SystemOps::Instance().ResolveProcessLabels(names);
                     flutter::EncodableMap out;
                     for (const auto& kv : resolved) {
                       out[flutter::EncodableValue(kv.first)] =
                           flutter::EncodableValue(kv.second);
                     }
                     return flutter::EncodableValue(std::move(out));
                   });
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
  if (method == "getInstalledApps") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
      const auto apps = SecurityScanner::Instance().CollectInstalledApps();
      flutter::EncodableList list;
      list.reserve(apps.size());
      for (const auto& app : apps) {
        flutter::EncodableMap m;
        m[flutter::EncodableValue("name")] = flutter::EncodableValue(app.name);
        m[flutter::EncodableValue("processName")] =
            flutter::EncodableValue(app.process_name);
        m[flutter::EncodableValue("path")] = flutter::EncodableValue(app.path);
        m[flutter::EncodableValue("publisher")] =
            flutter::EncodableValue(app.publisher);
        m[flutter::EncodableValue("running")] =
            flutter::EncodableValue(app.running);
        list.push_back(flutter::EncodableValue(std::move(m)));
      }
      return flutter::EncodableValue(std::move(list));
    });
    return;
  }
  if (method == "pickExecutableFile") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
      return flutter::EncodableValue(
          SecurityScanner::Instance().PickExecutableFile());
    });
    return;
  }
  if (method == "scanDeviceSecurity") {
    RunOffUiThread(reply_guard_, std::move(result), []() {
      const SecurityScanReport report =
          SecurityScanner::Instance().ScanDeviceSecurity();
      flutter::EncodableList threats;
      threats.reserve(report.threats.size());
      for (const auto& item : report.threats) {
        flutter::EncodableMap m;
        m[flutter::EncodableValue("key")] = flutter::EncodableValue(item.key);
        m[flutter::EncodableValue("name")] = flutter::EncodableValue(item.name);
        m[flutter::EncodableValue("category")] =
            flutter::EncodableValue(item.category);
        m[flutter::EncodableValue("severity")] =
            flutter::EncodableValue(item.severity);
        m[flutter::EncodableValue("target")] =
            flutter::EncodableValue(item.target);
        m[flutter::EncodableValue("detail")] =
            flutter::EncodableValue(item.detail);
        m[flutter::EncodableValue("remediationKind")] =
            flutter::EncodableValue(item.remediation_kind);
        m[flutter::EncodableValue("path")] = flutter::EncodableValue(item.path);
        m[flutter::EncodableValue("processName")] =
            flutter::EncodableValue(item.process_name);
        m[flutter::EncodableValue("uninstallCmd")] =
            flutter::EncodableValue(item.uninstall_cmd);
        m[flutter::EncodableValue("registryRoot")] =
            flutter::EncodableValue(item.registry_root);
        m[flutter::EncodableValue("registryPath")] =
            flutter::EncodableValue(item.registry_path);
        m[flutter::EncodableValue("registryValue")] =
            flutter::EncodableValue(item.registry_value);
        m[flutter::EncodableValue("sha256")] =
            flutter::EncodableValue(item.sha256);
        m[flutter::EncodableValue("active")] =
            flutter::EncodableValue(item.active);
        m[flutter::EncodableValue("signedValid")] =
            flutter::EncodableValue(item.signed_valid);
        m[flutter::EncodableValue("blockedByPolicy")] =
            flutter::EncodableValue(item.blocked_by_policy);
        threats.push_back(flutter::EncodableValue(std::move(m)));
      }
      flutter::EncodableMap out;
      out[flutter::EncodableValue("clean")] =
          flutter::EncodableValue(report.clean);
      out[flutter::EncodableValue("scannedProcesses")] =
          flutter::EncodableValue(report.scanned_processes);
      out[flutter::EncodableValue("scannedApps")] =
          flutter::EncodableValue(report.scanned_apps);
      out[flutter::EncodableValue("scannedFiles")] =
          flutter::EncodableValue(report.scanned_files);
      out[flutter::EncodableValue("scannedAtMs")] =
          flutter::EncodableValue(static_cast<int64_t>(report.scanned_at_ms));
      out[flutter::EncodableValue("threats")] =
          flutter::EncodableValue(std::move(threats));
      return flutter::EncodableValue(std::move(out));
    });
    return;
  }
  if (method == "remediateSecurityThreat") {
    SecurityThreatEntry target;
    target.key = StringOf(args, "key");
    target.name = StringOf(args, "name");
    target.category = StringOf(args, "category");
    target.remediation_kind = StringOf(args, "remediationKind");
    target.path = StringOf(args, "path");
    target.process_name = StringOf(args, "processName");
    target.uninstall_cmd = StringOf(args, "uninstallCmd");
    target.registry_root = StringOf(args, "registryRoot");
    target.registry_path = StringOf(args, "registryPath");
    target.registry_value = StringOf(args, "registryValue");
    RunOffUiThread(reply_guard_, std::move(result), [target]() {
      const RemediationOutcome outcome =
          SecurityScanner::Instance().RemediateThreat(target);
      flutter::EncodableMap out;
      out[flutter::EncodableValue("ok")] = flutter::EncodableValue(outcome.ok);
      out[flutter::EncodableValue("actionTaken")] =
          flutter::EncodableValue(outcome.action_taken);
      out[flutter::EncodableValue("stillPresent")] =
          flutter::EncodableValue(outcome.still_present);
      out[flutter::EncodableValue("message")] =
          flutter::EncodableValue(outcome.message);
      return flutter::EncodableValue(std::move(out));
    });
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
