#include "system_ops.h"
#include "winhttp_client.h"

#include <iphlpapi.h>
#include <ipifcons.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <wininet.h>
#include <winver.h>
#include <ws2tcpip.h>
#include <icmpapi.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwctype>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "wininet.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "version.lib")

namespace umbrella {
namespace {

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), out.data(), size,
                      nullptr, nullptr);
  return out;
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

std::string Quote(const std::string& value) {
  std::string out = "\"";
  out += value;
  out += "\"";
  return out;
}

bool ReadRegistryString(HKEY root, const std::wstring& path,
                        const std::wstring& name, std::wstring* out) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, path.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t buffer[512] = {0};
  DWORD size = sizeof(buffer);
  DWORD type = 0;
  LSTATUS status = RegQueryValueExW(key, name.c_str(), nullptr, &type,
                                    reinterpret_cast<LPBYTE>(buffer), &size);
  RegCloseKey(key);
  if (status != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    return false;
  }
  *out = buffer;
  return true;
}

bool ReadRegistryDword(HKEY root, const std::wstring& path,
                       const std::wstring& name, DWORD* out) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, path.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD value = 0;
  DWORD size = sizeof(value);
  DWORD type = 0;
  LSTATUS status = RegQueryValueExW(key, name.c_str(), nullptr, &type,
                                    reinterpret_cast<LPBYTE>(&value), &size);
  RegCloseKey(key);
  if (status != ERROR_SUCCESS || type != REG_DWORD) {
    return false;
  }
  *out = value;
  return true;
}

bool WriteRegistryString(HKEY root, const std::wstring& path,
                         const std::wstring& name, const std::wstring& value) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(root, path.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr,
                      &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LSTATUS status = RegSetValueExW(
      key, name.c_str(), 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

bool DeleteRegistryValue(HKEY root, const std::wstring& path,
                         const std::wstring& name) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, path.c_str(), 0, KEY_WRITE, &key) != ERROR_SUCCESS) {
    return false;
  }
  LSTATUS status = RegDeleteValueW(key, name.c_str());
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

std::wstring ExePathW() {
  wchar_t buffer[MAX_PATH * 2] = {0};
  DWORD size = GetModuleFileNameW(nullptr, buffer, MAX_PATH * 2);
  if (size == 0) return std::wstring();
  return std::wstring(buffer, size);
}

std::string ExtractFileName(const std::string& path) {
  size_t slash = path.find_last_of("\\/");
  if (slash == std::string::npos) return path;
  return path.substr(slash + 1);
}

std::string ToLowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(::tolower(c)); });
  return value;
}

bool ContainsInsensitive(const std::string& haystack, const std::string& needle) {
  if (needle.empty()) return false;
  return ToLowerAscii(haystack).find(ToLowerAscii(needle)) != std::string::npos;
}

const char* kForeignCores[] = {
    "xray.exe",      "sing-box.exe",  "v2ray.exe",     "mihomo.exe",
    "clash.exe",     "clash-meta.exe", "clash-verge.exe", "wireguard.exe",
    "amneziawg.exe", "awg.exe",       "mieru.exe",     "openvpn.exe",
    "shadowsocks.exe", "ss-local.exe", "trojan.exe",   "hysteria.exe",
    "naive.exe",     "tun2socks.exe", "warp-svc.exe",  "nekoray.exe",
    "v2rayn.exe",    "shadowrocket.exe", "outline.exe", "psiphon.exe",
    "hiddifycli.exe", "hiddifycore.exe",
};

const char* kOwnedCores[] = {
    "umbrellacli.exe",
    "umbrellacoreengine.exe",
    "umbrellaadmin.exe",
    "hiddifycli.exe",
    "hiddifycore.exe",
};

bool IsOwnedCoreExe(const std::string& exe) {
  const std::string base = ToLowerAscii(ExtractFileName(exe));
  for (const char* name : kOwnedCores) {
    if (base == name) return true;
  }
  return false;
}

BOOL CALLBACK CloseUmbrellaCliWindowsProc(HWND hwnd, LPARAM /*param*/) {
  if (!IsWindow(hwnd)) return TRUE;
  wchar_t cls[64] = {0};
  const int cls_len = GetClassNameW(hwnd, cls, 63);
  if (cls_len <= 0) return TRUE;
  // Filter to console hosts first (kernel-local check) so we never touch
  // hundreds of unrelated or unresponsive desktop windows during exit.
  if (wcscmp(cls, L"ConsoleWindowClass") != 0 &&
      wcscmp(cls, L"CASCADIA_HOSTING_WINDOW_CLASS") != 0 &&
      wcscmp(cls, L"PseudoConsoleWindow") != 0) {
    return TRUE;
  }
  wchar_t title[128] = {0};
  DWORD_PTR copied = 0;
  if (SendMessageTimeoutW(hwnd, WM_GETTEXT, 127,
                          reinterpret_cast<LPARAM>(title),
                          SMTO_ABORTIFHUNG | SMTO_BLOCK, 15, &copied) != 0 &&
      copied > 0 && wcsncmp(title, L"Umbrella CLI", 12) == 0) {
    PostMessageW(hwnd, WM_CLOSE, 0, 0);
  }
  return TRUE;
}

}  // namespace

SystemOps& SystemOps::Instance() {
  static SystemOps instance;
  return instance;
}

bool SystemOps::IsElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation = {0};
  DWORD size = sizeof(elevation);
  bool elevated = false;
  if (GetTokenInformation(token, TokenElevation, &elevation, size, &size)) {
    elevated = elevation.TokenIsElevated != 0;
  }
  CloseHandle(token);
  return elevated;
}

bool SystemOps::RunElevated(const std::string& exe, const std::string& args) {
  const bool is_core = IsOwnedCoreExe(exe);
  if (is_core) {
    const std::wstring self_pid = std::to_wstring(GetCurrentProcessId());
    SetEnvironmentVariableW(L"UMBRELLA_OWNER_PID", self_pid.c_str());
  } else {
    SetEnvironmentVariableW(L"UMBRELLA_OWNER_PID", nullptr);
  }
  std::wstring file = ToWide(exe);
  std::wstring parameters = ToWide(args);
  SHELLEXECUTEINFOW info = {0};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
  info.lpVerb = L"runas";
  info.lpFile = file.c_str();
  info.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
  info.nShow = SW_SHOWNORMAL;
  const BOOL ok = ShellExecuteExW(&info);
  SetEnvironmentVariableW(L"UMBRELLA_OWNER_PID", nullptr);
  if (!ok) return false;
  if (is_core) {
    shutdown_clean_.store(false, std::memory_order_release);
  }
  if (info.hProcess) CloseHandle(info.hProcess);
  return true;
}

bool SystemOps::RelaunchElevated(const std::string& extra_args) {
  std::wstring exe = ExePathW();
  if (exe.empty()) return false;
  std::string args = extra_args;
  if (args.find("--elevated") == std::string::npos) {
    if (!args.empty()) args += " ";
    args += "--elevated";
  }
  return RunElevated(ToUtf8(exe), args);
}

std::string SystemOps::ExecutablePath() { return ToUtf8(ExePathW()); }

std::string SystemOps::LocalIpv4() {
  ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                GAA_FLAG_SKIP_DNS_SERVER;
  ULONG size = 16384;
  std::vector<BYTE> buffer;
  IP_ADAPTER_ADDRESSES* addresses = nullptr;
  for (int attempt = 0; attempt < 3; ++attempt) {
    buffer.assign(size, 0);
    addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    ULONG res = GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size);
    if (res == NO_ERROR) break;
    addresses = nullptr;
    if (res != ERROR_BUFFER_OVERFLOW) return std::string();
  }
  if (addresses == nullptr) return std::string();

  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp) continue;
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr;
         unicast = unicast->Next) {
      if (unicast->Address.lpSockaddr == nullptr) continue;
      if (unicast->Address.lpSockaddr->sa_family != AF_INET) continue;
      auto* ipv4 =
          reinterpret_cast<sockaddr_in*>(unicast->Address.lpSockaddr);
      // Skip the local TUN subnet (172.19.0.0/28) so physical LAN IP wins.
      if ((ntohl(ipv4->sin_addr.s_addr) & 0xFFFFFFF0u) == 0xAC130000u) {
        continue;
      }
      char text[INET_ADDRSTRLEN] = {0};
      if (inet_ntop(AF_INET, &ipv4->sin_addr, text, sizeof(text)) == nullptr) {
        continue;
      }
      if (strncmp(text, "169.254.", 8) == 0) continue;
      return std::string(text);
    }
  }
  return std::string();
}

std::string SystemOps::DefaultAdapterName() {
  ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                GAA_FLAG_SKIP_DNS_SERVER;
  ULONG size = 16384;
  std::vector<BYTE> buffer;
  IP_ADAPTER_ADDRESSES* addresses = nullptr;
  for (int attempt = 0; attempt < 3; ++attempt) {
    buffer.assign(size, 0);
    addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    ULONG res = GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size);
    if (res == NO_ERROR) break;
    addresses = nullptr;
    if (res != ERROR_BUFFER_OVERFLOW) return std::string();
  }
  if (addresses == nullptr) return std::string();

  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp) continue;
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    bool has_physical_ipv4 = false;
    for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr;
         unicast = unicast->Next) {
      if (unicast->Address.lpSockaddr == nullptr) continue;
      if (unicast->Address.lpSockaddr->sa_family != AF_INET) continue;
      auto* ipv4 =
          reinterpret_cast<sockaddr_in*>(unicast->Address.lpSockaddr);
      if ((ntohl(ipv4->sin_addr.s_addr) & 0xFFFFFFF0u) == 0xAC130000u) {
        continue;
      }
      char text[INET_ADDRSTRLEN] = {0};
      if (inet_ntop(AF_INET, &ipv4->sin_addr, text, sizeof(text)) == nullptr) {
        continue;
      }
      if (strncmp(text, "169.254.", 8) == 0) continue;
      has_physical_ipv4 = true;
      break;
    }
    if (!has_physical_ipv4) continue;
    return ToUtf8(adapter->FriendlyName);
  }
  return std::string();
}

std::string SystemOps::DefaultAdapterMac() {
  ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                GAA_FLAG_SKIP_DNS_SERVER;
  ULONG size = 16384;
  std::vector<BYTE> buffer;
  IP_ADAPTER_ADDRESSES* addresses = nullptr;
  for (int attempt = 0; attempt < 3; ++attempt) {
    buffer.assign(size, 0);
    addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    ULONG res = GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size);
    if (res == NO_ERROR) break;
    addresses = nullptr;
    if (res != ERROR_BUFFER_OVERFLOW) return std::string();
  }
  if (addresses == nullptr) return std::string();

  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp) continue;
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    if (adapter->PhysicalAddressLength < 6) continue;
    char text[32] = {0};
    snprintf(text, sizeof(text), "%02X:%02X:%02X:%02X:%02X:%02X",
             adapter->PhysicalAddress[0], adapter->PhysicalAddress[1],
             adapter->PhysicalAddress[2], adapter->PhysicalAddress[3],
             adapter->PhysicalAddress[4], adapter->PhysicalAddress[5]);
    return std::string(text);
  }
  return std::string();
}

DeviceInfo SystemOps::CollectDeviceInfo() {
  DeviceInfo info;
  wchar_t name[MAX_COMPUTERNAME_LENGTH + 1] = {0};
  DWORD name_size = MAX_COMPUTERNAME_LENGTH + 1;
  if (GetComputerNameW(name, &name_size)) info.hostname = ToUtf8(name);

  wchar_t user[256] = {0};
  DWORD user_size = 256;
  if (GetUserNameW(user, &user_size)) info.username = ToUtf8(user);

  DWORD major_ver = 0;
  std::wstring build_str;
  const bool has_major = ReadRegistryDword(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
      L"CurrentMajorVersionNumber", &major_ver);
  const bool has_build = ReadRegistryString(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
      L"CurrentBuildNumber", &build_str);
  if (has_build && !build_str.empty()) {
    const int build_num = static_cast<int>(wcstol(build_str.c_str(), nullptr, 10));
    if (build_num > 0) {
      info.os_build = build_num;
      const int raw_major = has_major ? static_cast<int>(major_ver) : 10;
      const int display_major =
          (raw_major == 10 && build_num >= 22000) ? 11 : raw_major;
      std::ostringstream os;
      os << "Windows " << display_major << " (build " << build_num << ")";
      info.os = os.str();
    }
  }

  std::wstring edition_id;
  if (ReadRegistryString(HKEY_LOCAL_MACHINE,
                         L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
                         L"EditionID", &edition_id)) {
    info.os_edition = ToUtf8(edition_id);
  }
  std::wstring display_ver;
  if (ReadRegistryString(HKEY_LOCAL_MACHINE,
                         L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
                         L"DisplayVersion", &display_ver)) {
    info.os_display_version = ToUtf8(display_ver);
  }

  SYSTEM_INFO system_info;
  GetNativeSystemInfo(&system_info);
  info.cpu_cores = static_cast<int>(system_info.dwNumberOfProcessors);
  switch (system_info.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64:
      info.arch = "x64";
      break;
    case PROCESSOR_ARCHITECTURE_ARM64:
      info.arch = "arm64";
      break;
    case PROCESSOR_ARCHITECTURE_INTEL:
      info.arch = "x86";
      break;
    default:
      info.arch = "unknown";
      break;
  }

  std::wstring machine_guid;
  if (ReadRegistryString(HKEY_LOCAL_MACHINE,
                         L"SOFTWARE\\Microsoft\\Cryptography", L"MachineGuid",
                         &machine_guid)) {
    info.machine_id = ToUtf8(machine_guid);
  }
  std::wstring cpu;
  if (ReadRegistryString(HKEY_LOCAL_MACHINE,
                         L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                         L"ProcessorNameString", &cpu)) {
    info.cpu = ToUtf8(cpu);
  }
  MEMORYSTATUSEX mem_status = {0};
  mem_status.dwLength = sizeof(mem_status);
  if (GlobalMemoryStatusEx(&mem_status)) {
    const uint64_t total_mb = mem_status.ullTotalPhys / (1024ULL * 1024ULL);
    const uint64_t avail_mb = mem_status.ullAvailPhys / (1024ULL * 1024ULL);
    info.ram_total_mb = static_cast<int64_t>(total_mb);
    info.ram_used_mb = static_cast<int64_t>(
        total_mb > avail_mb ? (total_mb - avail_mb) : 0ULL);
    info.ram_load_percent = static_cast<int>(mem_status.dwMemoryLoad);
  }

  wchar_t sys_dir[MAX_PATH] = {0};
  UINT sys_len = GetSystemDirectoryW(sys_dir, MAX_PATH);
  std::wstring root_drive = L"C:\\";
  if (sys_len >= 3 && sys_dir[1] == L':') {
    root_drive.assign(sys_dir, 3);
  }
  ULARGE_INTEGER free_avail = {0};
  ULARGE_INTEGER total_bytes = {0};
  ULARGE_INTEGER total_free = {0};
  if (GetDiskFreeSpaceExW(root_drive.c_str(), &free_avail, &total_bytes,
                          &total_free)) {
    info.disk_total_mb =
        static_cast<int64_t>(total_bytes.QuadPart / (1024ULL * 1024ULL));
    info.disk_free_mb =
        static_cast<int64_t>(total_free.QuadPart / (1024ULL * 1024ULL));
  }

  info.screen_width = GetSystemMetrics(SM_CXSCREEN);
  info.screen_height = GetSystemMetrics(SM_CYSCREEN);

  SYSTEM_POWER_STATUS power = {0};
  if (GetSystemPowerStatus(&power)) {
    const bool no_system_battery = (power.BatteryFlag & 128) != 0 ||
                                   power.BatteryFlag == 255;
    info.has_battery = !no_system_battery;
    if (power.BatteryLifePercent <= 100) {
      info.battery_percent = static_cast<int>(power.BatteryLifePercent);
    }
    info.power_plugged = (power.ACLineStatus == 1) || !info.has_battery;
  }

  info.uptime_seconds = static_cast<int64_t>(GetTickCount64() / 1000ULL);
  info.adapter_name = DefaultAdapterName();
  info.local_ip = LocalIpv4();
  info.adapter_mac = DefaultAdapterMac();
  info.elevated = IsElevated();
  return info;
}

bool SystemOps::Resolves(const std::string& host) {
  WSADATA data;
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return false;
  addrinfo hints = {0};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* result = nullptr;
  bool ok = getaddrinfo(host.c_str(), nullptr, &hints, &result) == 0 &&
            result != nullptr;
  if (result != nullptr) freeaddrinfo(result);
  WSACleanup();
  return ok;
}

int SystemOps::PingHost(const std::string& host, int timeout_ms) {
  WSADATA data;
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return -1;
  addrinfo hints = {0};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* result = nullptr;
  int latency = -1;
  if (getaddrinfo(host.c_str(), nullptr, &hints, &result) == 0 &&
      result != nullptr) {
    auto* address = reinterpret_cast<sockaddr_in*>(result->ai_addr);
    IPAddr destination = address->sin_addr.s_addr;
    HANDLE icmp = IcmpCreateFile();
    if (icmp != INVALID_HANDLE_VALUE) {
      char payload[16] = "umbrella";
      DWORD reply_size = sizeof(ICMP_ECHO_REPLY) + sizeof(payload) + 8;
      std::vector<BYTE> reply(reply_size);
      DWORD count = IcmpSendEcho(icmp, destination, payload,
                                 static_cast<WORD>(sizeof(payload)), nullptr,
                                 reply.data(), reply_size,
                                 static_cast<DWORD>(timeout_ms));
      if (count > 0) {
        auto* echo = reinterpret_cast<ICMP_ECHO_REPLY*>(reply.data());
        latency = static_cast<int>(echo->RoundTripTime);
      }
      IcmpCloseHandle(icmp);
    }
    freeaddrinfo(result);
  }
  WSACleanup();
  return latency;
}

int SystemOps::TcpPing(const std::string& host, int port, int timeout_ms) {
  WSADATA data;
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return -1;
  addrinfo hints = {0};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  addrinfo* result = nullptr;
  int elapsed = -1;
  if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &result) ==
          0 &&
      result != nullptr) {
    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock != INVALID_SOCKET) {
      u_long non_blocking = 1;
      ioctlsocket(sock, FIONBIO, &non_blocking);
      ULONGLONG start = GetTickCount64();
      int connected = connect(sock, result->ai_addr,
                              static_cast<int>(result->ai_addrlen));
      bool ok = connected == 0;
      if (!ok && WSAGetLastError() == WSAEWOULDBLOCK) {
        fd_set write_set;
        FD_ZERO(&write_set);
        FD_SET(sock, &write_set);
        timeval timeout;
        timeout.tv_sec = timeout_ms / 1000;
        timeout.tv_usec = (timeout_ms % 1000) * 1000;
        int selected = select(0, nullptr, &write_set, nullptr, &timeout);
        if (selected > 0) {
          int error = 0;
          int length = sizeof(error);
          getsockopt(sock, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error),
                     &length);
          ok = error == 0;
        }
      }
      if (ok) {
        elapsed = static_cast<int>(GetTickCount64() - start);
      }
      closesocket(sock);
    }
    freeaddrinfo(result);
  }
  WSACleanup();
  return elapsed;
}

bool SystemOps::RunAndWait(const std::wstring& command_line) {
  STARTUPINFOW startup = {0};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process = {0};
  std::wstring buffer = command_line;
  if (!CreateProcessW(nullptr, buffer.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    return false;
  }
  WaitForSingleObject(process.hProcess, 15000);
  DWORD exit_code = 1;
  GetExitCodeProcess(process.hProcess, &exit_code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return exit_code == 0;
}

int SystemOps::Spawn(const std::string& exe, const std::string& args,
                     const std::string& work_dir, bool hidden,
                     const std::string& log_path) {
  last_spawn_error_ = 0;
  std::wstring wexe = ToWide(exe);
  std::wstring wargs = ToWide(args);
  std::wstring command_line = ToWide(Quote(exe));
  if (!args.empty()) {
    command_line += L" ";
    command_line += wargs;
  }
  STARTUPINFOW startup = {0};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = hidden ? SW_HIDE : SW_SHOWNORMAL;

  // خروجی و خطای هسته در یک فایل ثبت می شود تا اگر اجرا نشد، دلیلش خوانده شود.
  HANDLE log = INVALID_HANDLE_VALUE;
  if (!log_path.empty()) {
    SECURITY_ATTRIBUTES security = {0};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;
    std::wstring wlog = ToWide(log_path);
    log = CreateFileW(wlog.c_str(), FILE_APPEND_DATA,
                      FILE_SHARE_READ | FILE_SHARE_WRITE, &security,
                      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (log != INVALID_HANDLE_VALUE) {
      startup.dwFlags |= STARTF_USESTDHANDLES;
      startup.hStdOutput = log;
      startup.hStdError = log;
      startup.hStdInput = nullptr;
    }
  }

  const bool is_core = IsOwnedCoreExe(exe);
  if (is_core) {
    const std::wstring self_pid = std::to_wstring(GetCurrentProcessId());
    SetEnvironmentVariableW(L"UMBRELLA_OWNER_PID", self_pid.c_str());
  } else {
    SetEnvironmentVariableW(L"UMBRELLA_OWNER_PID", nullptr);
  }

  PROCESS_INFORMATION process = {0};
  std::wstring wdir = ToWide(work_dir);
  std::wstring buffer = command_line;
  DWORD flags = CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP | CREATE_UNICODE_ENVIRONMENT;
  BOOL started = CreateProcessW(
      wexe.empty() ? nullptr : wexe.c_str(), buffer.data(), nullptr, nullptr,
      log != INVALID_HANDLE_VALUE ? TRUE : FALSE, flags, nullptr,
      work_dir.empty() ? nullptr : wdir.c_str(), &startup, &process);
  SetEnvironmentVariableW(L"UMBRELLA_OWNER_PID", nullptr);
  if (log != INVALID_HANDLE_VALUE) CloseHandle(log);
  if (!started) {
    last_spawn_error_ = GetLastError();
    return -1;
  }
  int pid = static_cast<int>(process.dwProcessId);
  if (is_core) {
    shutdown_clean_.store(false, std::memory_order_release);
    std::lock_guard<std::mutex> lock(mutex_);
    HANDLE job = EnsureCoreJobLocked();
    if (job != nullptr) {
      AssignProcessToJobObject(job, process.hProcess);
    }
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return pid;
}

HANDLE SystemOps::EnsureCoreJobLocked() {
  if (core_job_ != nullptr) return core_job_;
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) return nullptr;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {};
  info.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info,
                               sizeof(info))) {
    CloseHandle(job);
    return nullptr;
  }
  core_job_ = job;
  return core_job_;
}

bool SystemOps::AttachCoreJob(int pid) {
  if (pid <= 0 || static_cast<DWORD>(pid) == GetCurrentProcessId()) {
    return false;
  }
  HANDLE process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE,
                               static_cast<DWORD>(pid));
  if (process == nullptr) return false;
  bool attached = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    HANDLE job = EnsureCoreJobLocked();
    if (job != nullptr) {
      attached = AssignProcessToJobObject(job, process) != 0;
    }
  }
  if (attached) {
    shutdown_clean_.store(false, std::memory_order_release);
  }
  CloseHandle(process);
  return attached;
}

int SystemOps::KillOwnedCoreTreeSinglePass() {
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return 0;

  const DWORD self_pid = GetCurrentProcessId();
  std::unordered_map<DWORD, std::vector<DWORD>> children;
  std::vector<DWORD> queue;
  std::unordered_set<DWORD> targets;

  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) {
    do {
      const DWORD pid = entry.th32ProcessID;
      if (pid == 0) continue;
      children[entry.th32ParentProcessID].push_back(pid);
      if (pid == self_pid) continue;
      const std::string name = ToLowerAscii(ToUtf8(entry.szExeFile));
      for (const char* owned : kOwnedCores) {
        if (name == owned) {
          if (targets.insert(pid).second) {
            queue.push_back(pid);
          }
          break;
        }
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);

  // Expand all descendant processes from the same snapshot in O(N).
  for (size_t i = 0; i < queue.size(); ++i) {
    auto it = children.find(queue[i]);
    if (it == children.end()) continue;
    for (DWORD child : it->second) {
      if (child != 0 && child != self_pid && targets.insert(child).second) {
        queue.push_back(child);
      }
    }
  }

  int killed = 0;
  for (DWORD pid : queue) {
    HANDLE proc = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
    if (proc == nullptr) continue;
    if (TerminateProcess(proc, 0) != FALSE) {
      ++killed;
    }
    CloseHandle(proc);
  }
  return killed;
}

void SystemOps::NotifyProxySettingsChangedFast() {
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  INTERNET_PER_CONN_OPTIONW option = {};
  option.dwOption = INTERNET_PER_CONN_FLAGS;
  option.Value.dwValue = PROXY_TYPE_DIRECT;
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  list.dwOptionCount = 1;
  list.pOptions = &option;
  InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list,
                     sizeof(list));
  // Non-blocking broadcast notifies browsers and WinINet listeners immediately
  // without stalling for seconds when any third-party window is hung.
  SendNotifyMessageW(
      HWND_BROADCAST, WM_SETTINGCHANGE, 0,
      reinterpret_cast<LPARAM>(
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings"));
  ResetWinHttpProxyFast();
}

void SystemOps::ClearLoopbackProxyFast() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet "
                    L"Settings",
                    0, KEY_READ | KEY_WRITE, &key) != ERROR_SUCCESS) {
    return;
  }
  DWORD enabled = 0;
  DWORD size = sizeof(enabled);
  DWORD type = 0;
  bool cleared = false;
  if (RegQueryValueExW(key, L"ProxyEnable", nullptr, &type,
                       reinterpret_cast<LPBYTE>(&enabled),
                       &size) == ERROR_SUCCESS &&
      type == REG_DWORD && enabled != 0) {
    wchar_t server[256] = {0};
    DWORD server_size = sizeof(server) - sizeof(wchar_t);
    DWORD server_type = 0;
    if (RegQueryValueExW(key, L"ProxyServer", nullptr, &server_type,
                         reinterpret_cast<LPBYTE>(server),
                         &server_size) == ERROR_SUCCESS &&
        server_type == REG_SZ &&
        (wcsstr(server, L"127.0.0.1:") != nullptr ||
         wcsstr(server, L"localhost:") != nullptr)) {
      DWORD zero = 0;
      RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                     reinterpret_cast<const BYTE*>(&zero), sizeof(zero));
      RegDeleteValueW(key, L"ProxyOverride");
      cleared = true;
    }
  }
  RegCloseKey(key);
  if (cleared) {
    NotifyProxySettingsChangedFast();
  }
}

int SystemOps::ShutdownOwnedCores(bool skip_if_clean) {
  if (skip_if_clean && shutdown_clean_.load(std::memory_order_acquire)) {
    ClearLoopbackProxyFast();
    return 0;
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (core_job_ != nullptr) {
      CloseHandle(core_job_);
      core_job_ = nullptr;
    }
  }
  const int killed = KillOwnedCoreTreeSinglePass();
  EnumWindows(CloseUmbrellaCliWindowsProc, 0);
  ClearLoopbackProxyFast();
  shutdown_clean_.store(true, std::memory_order_release);
  return killed;
}

std::string SystemOps::LastSpawnError() const {
  if (last_spawn_error_ == 0) return std::string();
  std::wstring text;
  LPWSTR buffer = nullptr;
  DWORD size = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, last_spawn_error_, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPWSTR>(&buffer), 0, nullptr);
  if (buffer != nullptr) {
    if (size > 0) text.assign(buffer, size);
    LocalFree(buffer);
  }
  while (!text.empty() && (text.back() == L'\r' || text.back() == L'\n' ||
                           text.back() == L' ')) {
    text.pop_back();
  }
  std::ostringstream out;
  out << last_spawn_error_;
  if (!text.empty()) out << " - " << ToUtf8(text);
  return out.str();
}

std::vector<DWORD> SystemOps::FindProcessIds(const std::string& exe_name) {
  std::vector<DWORD> pids;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return pids;
  PROCESSENTRY32W entry = {0};
  entry.dwSize = sizeof(entry);
  std::wstring target = ToWide(ToLowerAscii(ExtractFileName(exe_name)));
  if (Process32FirstW(snapshot, &entry)) {
    do {
      std::wstring current = entry.szExeFile;
      std::transform(current.begin(), current.end(), current.begin(),
                     [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
      if (current == target) {
        pids.push_back(entry.th32ProcessID);
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return pids;
}

bool SystemOps::KillPid(int pid) {
  if (pid <= 0 || static_cast<DWORD>(pid) == GetCurrentProcessId()) {
    return false;
  }
  const DWORD target = static_cast<DWORD>(pid);
  // Also terminate any direct child processes (e.g. CLI host -> UmbrellaCli.exe)
  // so detached console sessions never outlive the parent request.
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot != INVALID_HANDLE_VALUE) {
    PROCESSENTRY32W entry = {0};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry)) {
      do {
        if (entry.th32ParentProcessID == target &&
            entry.th32ProcessID != target &&
            entry.th32ProcessID != GetCurrentProcessId()) {
          HANDLE child =
              OpenProcess(PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
          if (child != nullptr) {
            TerminateProcess(child, 0);
            CloseHandle(child);
          }
        }
      } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
  }
  HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, target);
  if (process == nullptr) return false;
  bool ok = TerminateProcess(process, 0) != 0;
  CloseHandle(process);
  return ok;
}

int SystemOps::KillByName(const std::string& exe_name) {
  int killed = 0;
  for (DWORD pid : FindProcessIds(exe_name)) {
    if (KillPid(static_cast<int>(pid))) killed++;
  }
  return killed;
}

std::vector<int> SystemOps::PidsHoldingPort(int port) {
  std::vector<int> pids;
  PMIB_TCPTABLE_OWNER_PID table = nullptr;
  DWORD size = 0;
  // اولین فراخوانی اندازه را می دهد و شکست می خورد؛ این خطا طبیعی است.
  GetExtendedTcpTable(nullptr, &size, FALSE, AF_INET,
                      TCP_TABLE_OWNER_PID_LISTENER, 0);
  if (size == 0) return pids;
  table = static_cast<PMIB_TCPTABLE_OWNER_PID>(malloc(size));
  if (table == nullptr) return pids;
  const DWORD result = GetExtendedTcpTable(table, &size, FALSE, AF_INET,
                                           TCP_TABLE_OWNER_PID_LISTENER, 0);
  if (result == ERROR_SUCCESS) {
    for (DWORD i = 0; i < table->dwNumEntries; ++i) {
      const MIB_TCPROW_OWNER_PID& row = table->table[i];
      // پورت در ساختار شبکه به ترتیب بایت است.
      const int local = ntohs(static_cast<u_short>(row.dwLocalPort));
      if (local != port) continue;
      const int pid = static_cast<int>(row.dwOwningPid);
      if (pid > 0 &&
          std::find(pids.begin(), pids.end(), pid) == pids.end()) {
        pids.push_back(pid);
      }
    }
  }
  free(table);
  return pids;
}

std::string SystemOps::ProcessNameOf(int pid) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               static_cast<DWORD>(pid));
  if (process == nullptr) return std::string();
  wchar_t buffer[MAX_PATH] = {0};
  DWORD size = MAX_PATH;
  std::string name;
  if (QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    const std::wstring full(buffer, size);
    const size_t slash = full.find_last_of(L"\\/");
    const std::wstring base =
        slash == std::wstring::npos ? full : full.substr(slash + 1);
    name = ToUtf8(base);
  }
  CloseHandle(process);
  return name;
}

std::string SystemOps::ProcessPathOf(int pid) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               static_cast<DWORD>(pid));
  if (process == nullptr) return std::string();
  wchar_t buffer[MAX_PATH * 2] = {0};
  DWORD size = MAX_PATH * 2;
  std::string path;
  if (QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    path = ToUtf8(std::wstring(buffer, size));
  }
  CloseHandle(process);
  return path;
}

bool SystemOps::IsRunning(const std::string& exe_name) {
  return !FindProcessIds(exe_name).empty();
}

std::vector<std::string> SystemOps::ListRunningCores() {
  std::vector<std::string> found;
  for (const char* core : kForeignCores) {
    if (IsRunning(core)) found.push_back(core);
  }
  return found;
}

bool SystemOps::SystemProxyEnabled() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet "
                    L"Settings",
                    0, KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD enabled = 0;
  DWORD size = sizeof(enabled);
  DWORD type = 0;
  LSTATUS status = RegQueryValueExW(key, L"ProxyEnable", nullptr, &type,
                                    reinterpret_cast<LPBYTE>(&enabled), &size);
  RegCloseKey(key);
  return status == ERROR_SUCCESS && type == REG_DWORD && enabled != 0;
}

bool SystemOps::DisableSystemProxy() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet "
                    L"Settings",
                    0, KEY_READ | KEY_WRITE, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD enabled = 0;
  DWORD enabled_size = sizeof(enabled);
  DWORD enabled_type = 0;
  const bool was_enabled =
      RegQueryValueExW(key, L"ProxyEnable", nullptr, &enabled_type,
                       reinterpret_cast<LPBYTE>(&enabled),
                       &enabled_size) == ERROR_SUCCESS &&
      enabled_type == REG_DWORD && enabled != 0;
  DWORD zero = 0;
  RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&zero), sizeof(zero));
  // The bypass list was written by us when the tunnel came up.
  const bool had_override =
      RegDeleteValueW(key, L"ProxyOverride") == ERROR_SUCCESS;
  RegCloseKey(key);

  if (was_enabled || had_override) {
    NotifyProxySettingsChangedFast();
  }
  return true;
}

bool SystemOps::SetSystemProxy(const std::string& host, int port) {
  shutdown_clean_.store(false, std::memory_order_release);
  std::wstring entry = ToWide(host + ":" + std::to_string(port));
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet "
                    L"Settings",
                    0, KEY_READ | KEY_WRITE, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD one = 1;
  RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&one), sizeof(one));
  RegSetValueExW(key, L"ProxyServer", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(entry.c_str()),
                 static_cast<DWORD>((entry.size() + 1) * sizeof(wchar_t)));
  // Loopback and the local network must never go through the tunnel proxy,
  // otherwise the app cannot reach its own core.
  const std::wstring bypass = L"<local>;127.0.0.1;localhost;::1";
  RegSetValueExW(key, L"ProxyOverride", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(bypass.c_str()),
                 static_cast<DWORD>((bypass.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  return true;
}

bool SystemOps::FlushDns() {
  return RunAndWait(L"ipconfig /flushdns");
}

TunnelStats SystemOps::ReadTunnelStats(const std::string& adapter_hint) {
  TunnelStats stats;
  ULONG flags = GAA_FLAG_INCLUDE_ALL_INTERFACES | GAA_FLAG_SKIP_ANYCAST |
                GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
  // The first size is only a guess: with a VPN, Hyper-V and a few adapters the
  // table easily passes 32 KB, and the call then fails with
  // ERROR_BUFFER_OVERFLOW and reports nothing. Ask for the size it needs.
  ULONG size = 16384;
  std::vector<BYTE> buffer;
  auto* addresses = static_cast<IP_ADAPTER_ADDRESSES*>(nullptr);
  for (int attempt = 0; attempt < 3; attempt++) {
    buffer.assign(size, 0);
    addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    ULONG result = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addresses,
                                        &size);
    if (result == NO_ERROR) break;
    if (result != ERROR_BUFFER_OVERFLOW) return stats;
    addresses = nullptr;
  }
  if (addresses == nullptr) return stats;

  // The TUN of the engine carries two addresses: 172.19.0.1/28 and
  // fdfe:dcba:9876::1/126 (v2/config/builder.go). Either one identifies it,
  // whichever the adapter kept. The address comes first because it is the
  // engine's own; a name can also belong to an adapter an older install left.
  IP_ADAPTER_ADDRESSES* fallback = nullptr;
  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    for (auto* uni = adapter->FirstUnicastAddress; uni != nullptr;
         uni = uni->Next) {
      if (uni->Address.lpSockaddr == nullptr) continue;
      if (uni->Address.lpSockaddr->sa_family == AF_INET) {
        auto* sa = reinterpret_cast<sockaddr_in*>(uni->Address.lpSockaddr);
        if ((ntohl(sa->sin_addr.s_addr) & 0xFFFFFFF0u) == 0xAC130000u) {
          fallback = adapter;  // 172.19.0.0/28
          break;
        }
      } else if (uni->Address.lpSockaddr->sa_family == AF_INET6) {
        auto* sa6 = reinterpret_cast<sockaddr_in6*>(uni->Address.lpSockaddr);
        const BYTE* b = sa6->sin6_addr.s6_addr;
        // fdfe:dcba:9876::/126
        if (b[0] == 0xfd && b[1] == 0xfe && b[2] == 0xdc && b[3] == 0xba &&
            b[4] == 0x98 && b[5] == 0x76 && (b[15] & 0xFC) == 0x00) {
          fallback = adapter;
          break;
        }
      }
    }
    if (fallback == adapter) break;
  }

  // The tunnel address decides; the name hint is only a last resort (a TUN the
  // engine named after itself, still coming up). A name alone is not enough:
  // an adapter an older install left behind must not pass for the live tunnel.
  IP_ADAPTER_ADDRESSES* chosen = fallback;
  if (chosen == nullptr && !adapter_hint.empty()) {
    for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
      if (ContainsInsensitive(ToUtf8(adapter->FriendlyName), adapter_hint) ||
          ContainsInsensitive(ToUtf8(adapter->Description), adapter_hint)) {
        chosen = adapter;
        break;
      }
    }
  }
  if (chosen == nullptr) return stats;

  // GetIfEntry is available on every supported Windows version, unlike the
  // netioapi helpers whose declarations depend on the SDK version.
  MIB_IFROW row = {};
  row.dwIndex = chosen->IfIndex;
  if (GetIfEntry(&row) != NO_ERROR) return stats;
  stats.rx_bytes = row.dwInOctets;
  stats.tx_bytes = row.dwOutOctets;
  stats.available = true;
  stats.adapter = ToUtf8(chosen->FriendlyName);
  return stats;
}

bool SystemOps::SetAutostart(bool enabled, const std::string& app_name) {
  std::wstring name = ToWide(app_name);
  if (!enabled) {
    return DeleteRegistryValue(HKEY_CURRENT_USER, kRunKey, name);
  }
  std::string exe = ExecutablePath();
  if (exe.empty()) return false;
  std::wstring value = ToWide(Quote(exe) + " --autostart --minimized");
  return WriteRegistryString(HKEY_CURRENT_USER, kRunKey, name, value);
}

bool SystemOps::AutostartEnabled(const std::string& app_name) {
  std::wstring value;
  return ReadRegistryString(HKEY_CURRENT_USER, kRunKey, ToWide(app_name),
                            &value) &&
         !value.empty();
}

std::map<std::string, std::string> SystemOps::ResolveProcessLabels(
    const std::vector<std::string>& names) {
  std::map<std::string, std::string> result;
  if (names.empty()) return result;

  auto read_pe_label = [](const std::wstring& exe_path) -> std::string {
    if (exe_path.empty()) return std::string();
    const DWORD attrs = GetFileAttributesW(exe_path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
      return std::string();
    }
    DWORD dummy = 0;
    const DWORD size = GetFileVersionInfoSizeW(exe_path.c_str(), &dummy);
    if (size == 0 || size > 4 * 1024 * 1024) return std::string();
    std::vector<BYTE> data(size);
    if (!GetFileVersionInfoW(exe_path.c_str(), 0, size, data.data())) {
      return std::string();
    }
    struct LangCp {
      WORD lang;
      WORD cp;
    };
    LangCp* trans = nullptr;
    UINT trans_len = 0;
    std::vector<LangCp> probes;
    if (VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                       reinterpret_cast<LPVOID*>(&trans), &trans_len) &&
        trans != nullptr && trans_len >= sizeof(LangCp)) {
      probes.push_back(trans[0]);
    }
    probes.push_back(LangCp{0x0409, 0x04B0});
    probes.push_back(LangCp{0x0409, 0x04E4});

    auto query_field = [&](const wchar_t* field) -> std::string {
      for (const LangCp& lc : probes) {
        wchar_t q[128] = {0};
        swprintf_s(q, L"\\StringFileInfo\\%04x%04x\\%s", lc.lang, lc.cp, field);
        wchar_t* val = nullptr;
        UINT val_len = 0;
        if (VerQueryValueW(data.data(), q, reinterpret_cast<LPVOID*>(&val),
                           &val_len) &&
            val != nullptr && val_len > 0) {
          std::string utf8 = ToUtf8(std::wstring(val));
          while (!utf8.empty() &&
                 (utf8.back() == ' ' || utf8.back() == '\t' ||
                  utf8.back() == '\r' || utf8.back() == '\n')) {
            utf8.pop_back();
          }
          size_t lead = 0;
          while (lead < utf8.size() &&
                 (utf8[lead] == ' ' || utf8[lead] == '\t')) {
            ++lead;
          }
          utf8 = utf8.substr(lead);
          if (!utf8.empty()) return utf8;
        }
      }
      return std::string();
    };

    std::string desc = query_field(L"FileDescription");
    std::string prod = query_field(L"ProductName");
    const std::string desc_low = ToLowerAscii(desc);
    if (!desc.empty() && desc_low != "application" &&
        desc_low != "launcher" && desc_low != "setup" &&
        desc_low.find(".exe") == std::string::npos) {
      return desc;
    }
    const std::string prod_low = ToLowerAscii(prod);
    if (!prod.empty() &&
        !(prod_low.find("windows") != std::string::npos &&
          prod_low.find("operating system") != std::string::npos) &&
        prod_low.find(".exe") == std::string::npos) {
      return prod;
    }
    return !desc.empty() ? desc : prod;
  };

  std::unordered_map<std::string, std::wstring> running_paths;
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap != INVALID_HANDLE_VALUE) {
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snap, &entry)) {
      do {
        const std::string exe_key = ToLowerAscii(ToUtf8(entry.szExeFile));
        if (exe_key.empty() || running_paths.count(exe_key) > 0) continue;
        HANDLE proc =
            OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID);
        if (proc != nullptr) {
          wchar_t buf[MAX_PATH * 4] = {0};
          DWORD len = static_cast<DWORD>(sizeof(buf) / sizeof(buf[0]));
          if (QueryFullProcessImageNameW(proc, 0, buf, &len) && len > 0) {
            running_paths[exe_key] = std::wstring(buf, len);
          }
          CloseHandle(proc);
        }
      } while (Process32NextW(snap, &entry));
    }
    CloseHandle(snap);
  }

  for (const std::string& raw : names) {
    if (raw.empty()) continue;
    std::wstring path;
    if (raw.find('\\') != std::string::npos || raw.find('/') != std::string::npos) {
      path = ToWide(raw);
    }
    if (path.empty()) {
      const std::string key = ToLowerAscii(ExtractFileName(raw));
      auto it = running_paths.find(key);
      if (it != running_paths.end()) {
        path = it->second;
      }
    }
    std::string label = read_pe_label(path);
    if (!label.empty()) {
      result[raw] = label;
    }
  }
  return result;
}

int64_t SystemOps::ProcessCpuTimeMicros() {
  FILETIME create_time = {};
  FILETIME exit_time = {};
  FILETIME kernel_time = {};
  FILETIME user_time = {};
  if (GetProcessTimes(GetCurrentProcess(), &create_time, &exit_time,
                      &kernel_time, &user_time) == 0) {
    return -1;
  }
  ULARGE_INTEGER k = {};
  k.LowPart = kernel_time.dwLowDateTime;
  k.HighPart = kernel_time.dwHighDateTime;
  ULARGE_INTEGER u = {};
  u.LowPart = user_time.dwLowDateTime;
  u.HighPart = user_time.dwHighDateTime;
  return static_cast<int64_t>((k.QuadPart + u.QuadPart) / 10ULL);
}

}  // namespace umbrella
