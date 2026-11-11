#ifndef UMBRELLA_SYSTEM_OPS_H_
#define UMBRELLA_SYSTEM_OPS_H_

// Windows helper layer for the Umbrella VPN client.
//
// Everything the Flutter side cannot do on its own lives here: elevation,
// process supervision for the bundled cores, ICMP/TCP latency probes, the
// full tunnel interface counters, the firewall based kill switch and the
// housekeeping that removes foreign proxies before we connect.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

// winsock2 must come before windows.h so the Winsock 1 headers that older
// SDKs pull in do not clash with the Winsock 2 declarations we need.
#include <winsock2.h>
#include <windows.h>

#include <cstdint>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace umbrella {

struct DeviceInfo {
  std::string hostname;
  std::string username;
  std::string os;
  std::string arch;
  std::string machine_id;
  std::string cpu;
  std::string local_ip;
  std::string adapter_mac;
  bool elevated = false;
};

struct TunnelStats {
  uint64_t rx_bytes = 0;
  uint64_t tx_bytes = 0;
  bool available = false;
  std::string adapter;
};

class SystemOps {
 public:
  static SystemOps& Instance();

  bool IsElevated();
  bool RelaunchElevated(const std::string& extra_args);
  bool RunElevated(const std::string& exe, const std::string& args);

  DeviceInfo CollectDeviceInfo();
  std::string LocalIpv4();
  std::string DefaultAdapterName();
  std::string DefaultAdapterMac();

  int PingHost(const std::string& host, int timeout_ms);
  int TcpPing(const std::string& host, int port, int timeout_ms);
  bool Resolves(const std::string& host);

  int Spawn(const std::string& exe, const std::string& args,
            const std::string& work_dir, bool hidden);
  bool KillPid(int pid);
  int KillByName(const std::string& exe_name);
  bool IsRunning(const std::string& exe_name);
  std::vector<std::string> ListRunningCores();

  bool DisableSystemProxy();
  bool SetSystemProxy(const std::string& host, int port);
  bool SystemProxyEnabled();

  bool EnableKillSwitch(const std::vector<std::string>& allowed_exes,
                        const std::string& app_name);
  bool DisableKillSwitch(const std::string& app_name);
  bool KillSwitchActive(const std::string& app_name);

  bool FlushDns();
  TunnelStats ReadTunnelStats(const std::string& adapter_hint);

  bool SetAutostart(bool enabled, const std::string& app_name);
  bool AutostartEnabled(const std::string& app_name);

  std::string ExecutablePath();

 private:
  SystemOps() = default;
  bool RunAndWait(const std::wstring& command_line);
  std::vector<DWORD> FindProcessIds(const std::string& exe_name);

  std::mutex mutex_;
  std::map<int, HANDLE> processes_;
};

}  // namespace umbrella

#endif  // UMBRELLA_SYSTEM_OPS_H_
