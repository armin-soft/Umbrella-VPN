#include "system_ops.h"

#include <iphlpapi.h>
#include <ipifcons.h>
#include <netioapi.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <wininet.h>
#include <ws2tcpip.h>
#include <icmpapi.h>
#include <winternl.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <sstream>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "wininet.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")

namespace umbrella {
namespace {

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kKillSwitchKey[] = L"Software\\UmbrellaVPN";
constexpr wchar_t kKillSwitchValue[] = L"KillSwitchActive";

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
};

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
  std::wstring file = ToWide(exe);
  std::wstring parameters = ToWide(args);
  SHELLEXECUTEINFOW info = {0};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
  info.lpVerb = L"runas";
  info.lpFile = file.c_str();
  info.lpParameters = parameters.empty() ? nullptr : parameters.c_str();
  info.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&info)) return false;
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
  ULONG size = 16384;
  std::vector<BYTE> buffer(size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                GAA_FLAG_SKIP_DNS_SERVER;
  if (GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size) !=
      NO_ERROR) {
    return std::string();
  }
  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp) continue;
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr;
         unicast = unicast->Next) {
      if (unicast->Address.lpSockaddr->sa_family != AF_INET) continue;
      auto* ipv4 =
          reinterpret_cast<sockaddr_in*>(unicast->Address.lpSockaddr);
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
  ULONG size = 16384;
  std::vector<BYTE> buffer(size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                GAA_FLAG_SKIP_DNS_SERVER;
  if (GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size) !=
      NO_ERROR) {
    return std::string();
  }
  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp) continue;
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    if (adapter->FirstUnicastAddress == nullptr) continue;
    return ToUtf8(adapter->FriendlyName);
  }
  return std::string();
}

std::string SystemOps::DefaultAdapterMac() {
  ULONG size = 16384;
  std::vector<BYTE> buffer(size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                GAA_FLAG_SKIP_DNS_SERVER;
  if (GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size) !=
      NO_ERROR) {
    return std::string();
  }
  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp) continue;
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    if (adapter->PhysicalAddressLength < 6) continue;
    char text[32] = {0};
    snprintf(text, sizeof(text), "%02X%02X%02X%02X%02X%02X",
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

  OSVERSIONINFOEXW version = {0};
  version.dwOSVersionInfoSize = sizeof(version);
  typedef LONG(WINAPI * RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll != nullptr) {
    auto rtl_get_version =
        reinterpret_cast<RtlGetVersionPtr>(GetProcAddress(ntdll, "RtlGetVersion"));
    if (rtl_get_version != nullptr &&
        rtl_get_version(reinterpret_cast<PRTL_OSVERSIONINFOW>(&version)) == 0) {
      std::ostringstream os;
      os << "Windows " << version.dwMajorVersion << "." << version.dwMinorVersion
         << " (build " << version.dwBuildNumber << ")";
      info.os = os.str();
    }
  }

  SYSTEM_INFO system_info;
  GetNativeSystemInfo(&system_info);
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

  PROCESS_INFORMATION process = {0};
  std::wstring wdir = ToWide(work_dir);
  std::wstring buffer = command_line;
  DWORD flags = CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP | CREATE_UNICODE_ENVIRONMENT;
  BOOL started = CreateProcessW(
      wexe.empty() ? nullptr : wexe.c_str(), buffer.data(), nullptr, nullptr,
      log != INVALID_HANDLE_VALUE ? TRUE : FALSE, flags, nullptr,
      work_dir.empty() ? nullptr : wdir.c_str(), &startup, &process);
  if (log != INVALID_HANDLE_VALUE) CloseHandle(log);
  if (!started) {
    last_spawn_error_ = GetLastError();
    return -1;
  }
  int pid = static_cast<int>(process.dwProcessId);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return pid;
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
  if (pid <= 0) return false;
  HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE,
                               static_cast<DWORD>(pid));
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
  DWORD zero = 0;
  RegSetValueExW(key, L"ProxyEnable", 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&zero), sizeof(zero));
  // The bypass list was written by us when the tunnel came up.
  RegDeleteValueW(key, L"ProxyOverride");
  RegCloseKey(key);

  INTERNET_PER_CONN_OPTION_LIST list = {0};
  INTERNET_PER_CONN_OPTION option = {0};
  option.dwOption = INTERNET_PER_CONN_FLAGS;
  option.Value.dwValue = PROXY_TYPE_DIRECT;
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  list.dwOptionCount = 1;
  list.pOptions = &option;
  DWORD list_size = sizeof(list);
  InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list,
                     list_size);
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  RunAndWait(L"netsh winhttp reset proxy");
  return true;
}

bool SystemOps::SetSystemProxy(const std::string& host, int port) {
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

bool SystemOps::EnableKillSwitch(const std::vector<std::string>& allowed_exes,
                                const std::string& app_name) {
  // Windows Firewall lets block rules win over allow rules, so a «block all»
  // rule plus allow rules would kill every packet. The kill switch therefore
  // flips the outbound default action to block and then re-allows only what
  // the tunnel needs.
  std::string prefix = "Umbrella-" + app_name + "-KS";
  DisableKillSwitch(app_name);

  auto add_rule = [&](const std::string& suffix, const std::string& program,
                      const std::string& extra) {
    std::string command = "netsh advfirewall firewall add rule name=\"" +
                          prefix + "-" + suffix + "\" dir=out action=allow";
    if (!program.empty()) {
      command += " program=" + Quote(program);
    }
    if (!extra.empty()) command += " " + extra;
    command += " profile=any enable=yes";
    return RunAndWait(ToWide(command));
  };

  // اول قاعده های مجاز ساخته می شوند و بعد خروجی پیش فرض مسدود می شود؛
  // وگرنه اگر ساخت قاعده ها شکست بخورد کاربر بی اینترنت می ماند.
  add_rule("loopback", "", "remoteip=127.0.0.1");
  add_rule("subnet", "", "remoteip=localsubnet");
  add_rule("app", ExecutablePath(), "");
  for (size_t index = 0; index < allowed_exes.size(); ++index) {
    add_rule("core" + std::to_string(index), allowed_exes[index], "");
  }

  if (!RunAndWait(L"netsh advfirewall set allprofiles firewallpolicy "
                  L"blockinbound,blockoutbound")) {
    // مسدودسازی انجام نشد؛ همه چیز به حالت عادی برمی گردد.
    DisableKillSwitch(app_name);
    return false;
  }

  WriteRegistryString(HKEY_CURRENT_USER, kKillSwitchKey, kKillSwitchValue,
                      L"1");
  return true;
}

bool SystemOps::DisableKillSwitch(const std::string& app_name) {
  std::string prefix = "Umbrella-" + app_name + "-KS";
  for (const char* suffix :
       {"loopback", "subnet", "app", "core0", "core1", "core2", "core3",
        "core4", "core5"}) {
    std::string command = "netsh advfirewall firewall delete rule name=\"" +
                          prefix + "-" + suffix + "\"";
    RunAndWait(ToWide(command));
  }
  RunAndWait(L"netsh advfirewall set allprofiles firewallpolicy "
             L"blockinbound,allowoutbound");
  DeleteRegistryValue(HKEY_CURRENT_USER, kKillSwitchKey, kKillSwitchValue);
  return true;
}

bool SystemOps::KillSwitchActive(const std::string& app_name) {
  std::wstring value;
  if (ReadRegistryString(HKEY_CURRENT_USER, kKillSwitchKey, kKillSwitchValue,
                         &value)) {
    return value == L"1";
  }
  return false;
}

bool SystemOps::FlushDns() {
  return RunAndWait(L"ipconfig /flushdns");
}

TunnelStats SystemOps::ReadTunnelStats(const std::string& adapter_hint) {
  TunnelStats stats;
  ULONG size = 32768;
  std::vector<BYTE> buffer(size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG flags = GAA_FLAG_INCLUDE_ALL_INTERFACES | GAA_FLAG_SKIP_ANYCAST |
                GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
  if (GetAdaptersAddresses(AF_INET, flags, nullptr, addresses, &size) !=
      NO_ERROR) {
    return stats;
  }
  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    std::string friendly = ToUtf8(adapter->FriendlyName);
    std::string description = ToUtf8(adapter->Description);
    bool match = ContainsInsensitive(friendly, adapter_hint) ||
                 ContainsInsensitive(description, adapter_hint);
    if (!match) continue;
    MIB_IF_ROW2 row = {0};
    row.InterfaceLuid = adapter->Luid;
    if (GetIfEntry2(&row) != NO_ERROR) continue;
    stats.rx_bytes = row.InOctets;
    stats.tx_bytes = row.OutOctets;
    stats.available = true;
    stats.adapter = friendly;
    return stats;
  }
  return stats;
}

bool SystemOps::SetAutostart(bool enabled, const std::string& app_name) {
  std::wstring name = ToWide(app_name);
  if (!enabled) {
    return DeleteRegistryValue(HKEY_CURRENT_USER, kRunKey, name);
  }
  std::string exe = ExecutablePath();
  std::wstring value = ToWide(Quote(exe) + " --minimized");
  return WriteRegistryString(HKEY_CURRENT_USER, kRunKey, name, value);
}

bool SystemOps::AutostartEnabled(const std::string& app_name) {
  std::wstring value;
  return ReadRegistryString(HKEY_CURRENT_USER, kRunKey, ToWide(app_name),
                            &value);
}

}  // namespace umbrella
