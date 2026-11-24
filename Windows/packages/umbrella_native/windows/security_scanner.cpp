#include "security_scanner.h"

#include <bcrypt.h>
#include <commdlg.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <softpub.h>
#include <tlhelp32.h>
#include <winver.h>
#include <wintrust.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstring>
#include <cwctype>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

#pragma comment(lib, "wintrust.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "version.lib")
#pragma comment(lib, "comdlg32.lib")

namespace umbrella {
namespace {

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

std::string ToLowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(::tolower(c)); });
  return value;
}

std::string Trim(std::string value) {
  size_t first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return std::string();
  size_t last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

std::string ExtractFileName(const std::string& path) {
  size_t slash = path.find_last_of("\\/");
  if (slash == std::string::npos) return path;
  return path.substr(slash + 1);
}

std::string BaseNameLower(const std::string& path) {
  return ToLowerAscii(ExtractFileName(path));
}

bool ContainsCi(const std::string& haystack, const std::string& needle) {
  if (haystack.empty() || needle.empty()) return false;
  return ToLowerAscii(haystack).find(ToLowerAscii(needle)) != std::string::npos;
}

bool EndsWithCi(const std::string& value, const std::string& suffix) {
  if (value.size() < suffix.size()) return false;
  return ToLowerAscii(value.substr(value.size() - suffix.size())) ==
         ToLowerAscii(suffix);
}

bool FileExistsW(const std::wstring& path) {
  if (path.empty()) return false;
  DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool IsUmbrellaSafeBinary(const std::string& path_or_name) {
  const std::string base = BaseNameLower(path_or_name);
  if (base == "umbrellavpn.exe" || base == "umbrellacli.exe" ||
      base == "umbrellacoreengine.exe" || base == "umbrellaadmin.exe" ||
      base == "unins000.exe") {
    return ContainsCi(path_or_name, "umbrella") ||
           base.rfind("umbrella", 0) == 0;
  }
  return ContainsCi(path_or_name, "\\umbrella\\") ||
         ContainsCi(path_or_name, "\\umbrellavpn\\") ||
         ContainsCi(path_or_name, "armin-soft");
}

bool IsSystemNoiseProcess(const std::string& lower_name) {
  static const char* kSystem[] = {
      "system",        "idle",          "registry",      "smss.exe",
      "csrss.exe",     "wininit.exe",   "services.exe",  "lsass.exe",
      "svchost.exe",   "fontdrvhost.exe", "winlogon.exe", "dwm.exe",
      "memory compression", "sihost.exe", "ctfmon.exe", "conhost.exe",
      "dllhost.exe",   "runtimebroker.exe", "searchindexer.exe",
      "audiodg.exe",   "spoolsv.exe",   "taskhostw.exe", "wudfhost.exe",
      "dasHost.exe",   "dashost.exe",   "securityhealthservice.exe",
      "msmpeng.exe",   "nissrv.exe",    "vmmem",         "wslservice.exe",
  };
  for (const char* item : kSystem) {
    if (lower_name == item) return true;
  }
  return false;
}

/// Extracts an executable path from commands like `"C:\Foo\bar.exe",0` or `"C:\Foo\bar.exe" --arg`.
std::string ExtractExePathFromCommand(const std::string& raw) {
  std::string s = Trim(raw);
  if (s.empty()) return std::string();

  // Strip surrounding quotes and look for .exe.
  if (s.front() == '"') {
    size_t close = s.find('"', 1);
    if (close != std::string::npos) {
      std::string inside = Trim(s.substr(1, close - 1));
      if (EndsWithCi(inside, ".exe")) return inside;
    }
  }

  const std::string lower = ToLowerAscii(s);
  size_t exe_pos = lower.find(".exe");
  if (exe_pos != std::string::npos) {
    std::string candidate = Trim(s.substr(0, exe_pos + 4));
    if (!candidate.empty() && candidate.front() == '"') {
      candidate.erase(0, 1);
    }
    return candidate;
  }
  return std::string();
}

std::string ExpandEnvVars(const std::wstring& input) {
  if (input.empty()) return std::string();
  wchar_t buf[MAX_PATH * 4] = {0};
  DWORD written = ExpandEnvironmentStringsW(input.c_str(), buf, MAX_PATH * 4);
  if (written == 0 || written > MAX_PATH * 4) return ToUtf8(input);
  return ToUtf8(buf);
}

std::string ReadVersionStringW(const std::wstring& path, const wchar_t* field) {
  if (!FileExistsW(path)) return std::string();
  DWORD dummy = 0;
  DWORD size = GetFileVersionInfoSizeW(path.c_str(), &dummy);
  if (size == 0 || size > 4 * 1024 * 1024) return std::string();
  std::vector<BYTE> data(size);
  if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
    return std::string();
  }
  struct LangAndCodePage {
    WORD language;
    WORD code_page;
  };
  LangAndCodePage* trans = nullptr;
  UINT trans_len = 0;
  if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<LPVOID*>(&trans), &trans_len) ||
      trans == nullptr || trans_len < sizeof(LangAndCodePage)) {
    return std::string();
  }
  wchar_t query[128] = {0};
  swprintf_s(query, L"\\StringFileInfo\\%04x%04x\\%s", trans[0].language,
             trans[0].code_page, field);
  wchar_t* value = nullptr;
  UINT val_len = 0;
  if (VerQueryValueW(data.data(), query, reinterpret_cast<LPVOID*>(&value),
                     &val_len) &&
      value != nullptr && val_len > 0) {
    return Trim(ToUtf8(std::wstring(value)));
  }
  return std::string();
}

std::string ComputeFileSha256(const std::wstring& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return std::string();

  LARGE_INTEGER size = {};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 ||
      size.QuadPart > 64LL * 1024 * 1024) {
    CloseHandle(file);
    return std::string();
  }

  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  std::string hex;
  if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) == 0) {
    DWORD obj_len = 0;
    DWORD cb = 0;
    if (BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH,
                          reinterpret_cast<PUCHAR>(&obj_len), sizeof(obj_len),
                          &cb, 0) == 0 &&
        obj_len > 0) {
      std::vector<UCHAR> obj(obj_len);
      if (BCryptCreateHash(alg, &hash, obj.data(), obj_len, nullptr, 0, 0) == 0) {
        std::vector<BYTE> buf(65536);
        DWORD read_bytes = 0;
        bool ok = true;
        while (ReadFile(file, buf.data(), static_cast<DWORD>(buf.size()),
                        &read_bytes, nullptr) &&
               read_bytes > 0) {
          if (BCryptHashData(hash, buf.data(), read_bytes, 0) != 0) {
            ok = false;
            break;
          }
        }
        if (ok) {
          std::array<UCHAR, 32> digest{};
          if (BCryptFinishHash(hash, digest.data(),
                               static_cast<ULONG>(digest.size()), 0) == 0) {
            static const char kHex[] = "0123456789abcdef";
            hex.reserve(64);
            for (UCHAR b : digest) {
              hex.push_back(kHex[(b >> 4) & 0x0f]);
              hex.push_back(kHex[b & 0x0f]);
            }
          }
        }
        BCryptDestroyHash(hash);
      }
    }
    BCryptCloseAlgorithmProvider(alg, 0);
  }
  CloseHandle(file);
  return hex;
}

bool VerifyAuthenticodeSignature(const std::wstring& path) {
  if (!FileExistsW(path)) return false;
  WINTRUST_FILE_INFO file_info = {};
  file_info.cbStruct = sizeof(WINTRUST_FILE_INFO);
  file_info.pcwszFilePath = path.c_str();

  GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  WINTRUST_DATA trust = {};
  trust.cbStruct = sizeof(WINTRUST_DATA);
  trust.dwUIChoice = WTD_UI_NONE;
  trust.fdwRevocationChecks = WTD_REVOKE_NONE;
  trust.dwUnionChoice = WTD_CHOICE_FILE;
  trust.dwStateAction = WTD_STATEACTION_VERIFY;
  trust.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;
  trust.pFile = &file_info;

  LONG status = WinVerifyTrust(nullptr, &action, &trust);
  trust.dwStateAction = WTD_STATEACTION_CLOSE;
  WinVerifyTrust(nullptr, &action, &trust);
  return status == ERROR_SUCCESS;
}

/// Optional live Windows Antimalware Scan Interface (AMSI) check via dynamic loading.
class AmsiScanner {
 public:
  AmsiScanner() {
    module_ = LoadLibraryW(L"amsi.dll");
    if (module_ == nullptr) return;
    init_fn_ = reinterpret_cast<InitFn>(GetProcAddress(module_, "AmsiInitialize"));
    uninit_fn_ = reinterpret_cast<UninitFn>(GetProcAddress(module_, "AmsiUninitialize"));
    open_fn_ = reinterpret_cast<OpenSessionFn>(GetProcAddress(module_, "AmsiOpenSession"));
    close_fn_ = reinterpret_cast<CloseSessionFn>(GetProcAddress(module_, "AmsiCloseSession"));
    scan_fn_ = reinterpret_cast<ScanBufferFn>(GetProcAddress(module_, "AmsiScanBuffer"));
    if (init_fn_ && open_fn_ && scan_fn_) {
      if (SUCCEEDED(init_fn_(L"UmbrellaVPNSecurity", &ctx_)) && ctx_ != nullptr) {
        if (FAILED(open_fn_(ctx_, &session_))) {
          session_ = nullptr;
        }
      }
    }
  }

  ~AmsiScanner() {
    if (close_fn_ && ctx_ && session_) close_fn_(ctx_, session_);
    if (uninit_fn_ && ctx_) uninit_fn_(ctx_);
    if (module_) FreeLibrary(module_);
  }

  bool ScanFile(const std::wstring& path, int* out_result) const {
    if (!ctx_ || !scan_fn_) return false;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 ||
        size.QuadPart > 8LL * 1024 * 1024) {
      CloseHandle(file);
      return false;
    }
    std::vector<BYTE> data(static_cast<size_t>(size.QuadPart));
    DWORD read_bytes = 0;
    bool read_ok = ReadFile(file, data.data(), static_cast<DWORD>(data.size()),
                            &read_bytes, nullptr) != 0;
    CloseHandle(file);
    if (!read_ok || read_bytes == 0) return false;

    int result = 0;
    HRESULT hr = scan_fn_(ctx_, data.data(), read_bytes, path.c_str(), session_, &result);
    if (FAILED(hr)) return false;
    if (out_result) *out_result = result;
    // AMSI_RESULT_DETECTED == 32768
    return result >= 32768;
  }

 private:
  using InitFn = HRESULT(WINAPI*)(LPCWSTR, void**);
  using UninitFn = void(WINAPI*)(void*);
  using OpenSessionFn = HRESULT(WINAPI*)(void*, void**);
  using CloseSessionFn = void(WINAPI*)(void*, void*);
  using ScanBufferFn = HRESULT(WINAPI*)(void*, PVOID, ULONG, LPCWSTR, void*, int*);

  HMODULE module_ = nullptr;
  InitFn init_fn_ = nullptr;
  UninitFn uninit_fn_ = nullptr;
  OpenSessionFn open_fn_ = nullptr;
  CloseSessionFn close_fn_ = nullptr;
  ScanBufferFn scan_fn_ = nullptr;
  void* ctx_ = nullptr;
  void* session_ = nullptr;
};

struct PeHeuristicResult {
  bool is_pe = false;
  bool suspicious = false;
  double entropy = 0.0;
  std::string reason;
};

PeHeuristicResult AnalyzeFileHeuristics(const std::wstring& path) {
  PeHeuristicResult res;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return res;
  LARGE_INTEGER size = {};
  if (!GetFileSizeEx(file, &size) || size.QuadPart < 256 ||
      size.QuadPart > 24LL * 1024 * 1024) {
    CloseHandle(file);
    return res;
  }
  const size_t cap = static_cast<size_t>(std::min<int64_t>(size.QuadPart, 4LL * 1024 * 1024));
  std::vector<BYTE> buf(cap);
  DWORD read_bytes = 0;
  bool ok = ReadFile(file, buf.data(), static_cast<DWORD>(cap), &read_bytes, nullptr) != 0;
  CloseHandle(file);
  if (!ok || read_bytes < 256) return res;

  res.is_pe = (buf[0] == 'M' && buf[1] == 'Z');
  std::array<size_t, 256> freq{};
  for (DWORD i = 0; i < read_bytes; ++i) {
    freq[buf[i]]++;
  }
  double ent = 0.0;
  for (size_t count : freq) {
    if (count == 0) continue;
    double p = static_cast<double>(count) / static_cast<double>(read_bytes);
    ent -= p * std::log2(p);
  }
  res.entropy = ent;

  std::string ascii_view;
  ascii_view.reserve(read_bytes / 2);
  for (DWORD i = 0; i < read_bytes; ++i) {
    unsigned char ch = buf[i];
    if (ch >= 32 && ch <= 126) {
      ascii_view.push_back(static_cast<char>(::tolower(ch)));
    } else if (!ascii_view.empty() && ascii_view.back() != ' ') {
      ascii_view.push_back(' ');
    }
  }

  const bool injection_apis =
      ascii_view.find("virtualallocex") != std::string::npos &&
      ascii_view.find("writeprocessmemory") != std::string::npos &&
      (ascii_view.find("createremotethread") != std::string::npos ||
       ascii_view.find("ntunmapviewofsection") != std::string::npos);

  const bool keylogger_apis =
      ascii_view.find("setwindowshookexa") != std::string::npos ||
      ascii_view.find("setwindowshookexw") != std::string::npos;

  const bool double_ext =
      ContainsCi(ToUtf8(path), ".pdf.exe") ||
      ContainsCi(ToUtf8(path), ".docx.exe") ||
      ContainsCi(ToUtf8(path), ".xlsx.exe") ||
      ContainsCi(ToUtf8(path), ".jpg.exe") ||
      ContainsCi(ToUtf8(path), ".png.exe") ||
      ContainsCi(ToUtf8(path), ".mp4.exe");

  if (double_ext) {
    res.suspicious = true;
    res.reason = "فایل با پسوند دوگانه فریبنده شناسایی شد";
    return res;
  }
  if (injection_apis && ent >= 6.8) {
    res.suspicious = true;
    res.reason = "الگوی تزریق کد به پردازش و فشرده سازی مشکوک (Entropy بالا)";
    return res;
  }
  if (keylogger_apis && ent >= 7.1) {
    res.suspicious = true;
    res.reason = "الگوی شنود ورودی کاربر و باینری رمزگذاری شده";
    return res;
  }
  return res;
}

struct SignatureHit {
  bool matched = false;
  std::string family_key;
  std::string name;
  std::string category;
  std::string severity;
  std::string detail;
};

SignatureHit MatchKnownThreatText(const std::string& text) {
  const std::string lower = ToLowerAscii(text);
  if (lower.empty() || IsUmbrellaSafeBinary(lower)) {
    return SignatureHit{};
  }
  if (lower.find("jumpjump") != std::string::npos ||
      lower.find("jump-jump") != std::string::npos ||
      lower.find("jump jump") != std::string::npos) {
    return SignatureHit{
        true,
        "malware:jumpjump",
        "JumpJump VPN (بدافزار / ابزار مخرب)",
        "malware",
        "critical",
        "نرم افزار مخرب JumpJump VPN شناسایی شد و اتصال تا حذف کامل مسدود است.",
    };
  }
  if (lower.find("psiphon") != std::string::npos) {
    return SignatureHit{
        true,
        "vpn:psiphon",
        "Psiphon (فیلترشکن ناسازگار)",
        "conflicting_vpn",
        "high",
        "برنامه Psiphon روی سیستم یافت شد؛ اجرای هم زمان آن با آمبرلا تداخل و ناامنی ایجاد می کند.",
    };
  }
  if (lower.find("holavpn") != std::string::npos ||
      lower.find("hola_svc") != std::string::npos ||
      lower.find("hola vpn") != std::string::npos ||
      lower.find("luminati") != std::string::npos ||
      lower.find("brightdata") != std::string::npos) {
    return SignatureHit{
        true,
        "adware:hola_luminati",
        "Hola / Luminati Proxy (تبلیغ افزار و اشتراک پهنای باند)",
        "adware",
        "high",
        "سرویس اشتراک گذاری پهنای باند ناشناس شناسایی شد.",
    };
  }
  if (lower.find("honeygain") != std::string::npos ||
      lower.find("peer2profit") != std::string::npos ||
      lower.find("traffmonetizer") != std::string::npos ||
      lower.find("packetstream") != std::string::npos ||
      lower.find("earnapp") != std::string::npos) {
    return SignatureHit{
        true,
        "adware:bandwidth_miner",
        "ابزار سوءاستفاده از ترافیک شبکه",
        "adware",
        "high",
        "ابزار پس زمینه مصرف کننده ترافیک و پروکسی پنهان شناسایی شد.",
    };
  }
  return SignatureHit{};
}

struct RunningProcessInfo {
  DWORD pid = 0;
  std::string name;
  std::string lower_name;
  std::string path;
  std::string product_name;
  std::string company_name;
};

std::vector<RunningProcessInfo> SnapshotProcesses() {
  std::vector<RunningProcessInfo> out;
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) return out;

  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snap, &entry)) {
    do {
      RunningProcessInfo info;
      info.pid = entry.th32ProcessID;
      info.name = ToUtf8(entry.szExeFile);
      info.lower_name = ToLowerAscii(info.name);
      if (info.pid > 4 && !info.lower_name.empty()) {
        HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, info.pid);
        if (proc != nullptr) {
          wchar_t pbuf[MAX_PATH * 2] = {0};
          DWORD plen = MAX_PATH * 2;
          if (QueryFullProcessImageNameW(proc, 0, pbuf, &plen) && plen > 0) {
            std::wstring wpath(pbuf, plen);
            info.path = ToUtf8(wpath);
            info.product_name = ReadVersionStringW(wpath, L"ProductName");
            info.company_name = ReadVersionStringW(wpath, L"CompanyName");
          }
          CloseHandle(proc);
        }
        out.push_back(std::move(info));
      }
    } while (Process32NextW(snap, &entry));
  }
  CloseHandle(snap);
  return out;
}

struct RegistryAppRecord {
  std::string display_name;
  std::string publisher;
  std::string exe_path;
  std::string uninstall_cmd;
  bool system_component = false;
};

void EnumerateUninstallRoot(HKEY root, const wchar_t* subkey,
                            std::vector<RegistryAppRecord>* out) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, subkey, 0, KEY_READ, &key) != ERROR_SUCCESS) return;

  DWORD idx = 0;
  wchar_t child_name[256] = {0};
  DWORD child_len = 256;
  while (RegEnumKeyExW(key, idx++, child_name, &child_len, nullptr, nullptr,
                       nullptr, nullptr) == ERROR_SUCCESS) {
    HKEY item = nullptr;
    if (RegOpenKeyExW(key, child_name, 0, KEY_READ, &item) == ERROR_SUCCESS) {
      auto read_str = [&](const wchar_t* val) -> std::string {
        wchar_t buf[1024] = {0};
        DWORD sz = sizeof(buf);
        DWORD type = 0;
        if (RegQueryValueExW(item, val, nullptr, &type,
                             reinterpret_cast<LPBYTE>(buf), &sz) == ERROR_SUCCESS &&
            (type == REG_SZ || type == REG_EXPAND_SZ)) {
          return ExpandEnvVars(buf);
        }
        return std::string();
      };
      DWORD sys_comp = 0;
      DWORD sys_sz = sizeof(sys_comp);
      DWORD sys_type = 0;
      bool is_sys = false;
      if (RegQueryValueExW(item, L"SystemComponent", nullptr, &sys_type,
                           reinterpret_cast<LPBYTE>(&sys_comp), &sys_sz) == ERROR_SUCCESS &&
          sys_type == REG_DWORD && sys_comp == 1) {
        is_sys = true;
      }

      RegistryAppRecord rec;
      rec.display_name = Trim(read_str(L"DisplayName"));
      rec.publisher = Trim(read_str(L"Publisher"));
      rec.uninstall_cmd = Trim(read_str(L"QuietUninstallString"));
      if (rec.uninstall_cmd.empty()) {
        rec.uninstall_cmd = Trim(read_str(L"UninstallString"));
      }
      rec.system_component = is_sys;

      std::string icon_path = ExtractExePathFromCommand(read_str(L"DisplayIcon"));
      if (!icon_path.empty() && FileExistsW(ToWide(icon_path))) {
        rec.exe_path = icon_path;
      } else {
        std::string loc = Trim(read_str(L"InstallLocation"));
        if (!loc.empty() && loc.back() != '\\') loc.push_back('\\');
        if (!loc.empty()) {
          std::wstring pattern = ToWide(loc + "*.exe");
          WIN32_FIND_DATAW fd = {};
          HANDLE find = FindFirstFileW(pattern.c_str(), &fd);
          if (find != INVALID_HANDLE_VALUE) {
            do {
              if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
                std::string fname = ToUtf8(fd.cFileName);
                if (!ContainsCi(fname, "unins") && !ContainsCi(fname, "setup")) {
                  rec.exe_path = loc + fname;
                  break;
                }
              }
            } while (FindNextFileW(find, &fd));
            FindClose(find);
          }
        }
      }
      if (!rec.display_name.empty()) {
        out->push_back(std::move(rec));
      }
      RegCloseKey(item);
    }
    child_len = 256;
  }
  RegCloseKey(key);
}

void EnumerateStartMenuApps(const std::wstring& dir, int depth,
                            std::vector<InstalledAppEntry>* out) {
  if (dir.empty() || depth > 3) return;
  WIN32_FIND_DATAW fd = {};
  HANDLE find = FindFirstFileW((dir + L"\\*").c_str(), &fd);
  if (find == INVALID_HANDLE_VALUE) return;

  do {
    std::wstring name(fd.cFileName);
    if (name == L"." || name == L"..") continue;
    std::wstring full = dir + L"\\" + name;
    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      EnumerateStartMenuApps(full, depth + 1, out);
      continue;
    }
    if (!EndsWithCi(ToUtf8(name), ".lnk")) continue;

    IShellLinkW* link = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_IShellLinkW, reinterpret_cast<void**>(&link))) &&
        link != nullptr) {
      IPersistFile* persist = nullptr;
      if (SUCCEEDED(link->QueryInterface(IID_IPersistFile,
                                         reinterpret_cast<void**>(&persist))) &&
          persist != nullptr) {
        if (SUCCEEDED(persist->Load(full.c_str(), STGM_READ))) {
          wchar_t target[MAX_PATH * 2] = {0};
          if (SUCCEEDED(link->GetPath(target, MAX_PATH * 2, nullptr, SLGP_RAWPATH))) {
            std::string target_utf8 = ToUtf8(target);
            if (EndsWithCi(target_utf8, ".exe") &&
                FileExistsW(target) &&
                !ContainsCi(target_utf8, "unins")) {
              std::string stem = ToUtf8(name);
              if (stem.size() > 4) stem.resize(stem.size() - 4);
              InstalledAppEntry item;
              item.name = stem;
              item.process_name = ExtractFileName(target_utf8);
              item.path = target_utf8;
              item.publisher = ReadVersionStringW(target, L"CompanyName");
              out->push_back(std::move(item));
            }
          }
        }
        persist->Release();
      }
      link->Release();
    }
  } while (FindNextFileW(find, &fd));
  FindClose(find);
}

struct RunEntry {
  HKEY root = HKEY_CURRENT_USER;
  std::string root_label;
  std::wstring reg_path;
  std::string reg_path_utf8;
  std::string value_name;
  std::string command;
  std::string exe_path;
};

std::vector<RunEntry> EnumerateRunKeys() {
  std::vector<RunEntry> out;
  struct Target {
    HKEY root;
    const char* root_label;
    const wchar_t* path;
    const char* path_utf8;
  } targets[] = {
      {HKEY_CURRENT_USER, "HKCU", L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
       "Software\\Microsoft\\Windows\\CurrentVersion\\Run"},
      {HKEY_CURRENT_USER, "HKCU", L"Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce",
       "Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce"},
      {HKEY_LOCAL_MACHINE, "HKLM", L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
       "Software\\Microsoft\\Windows\\CurrentVersion\\Run"},
      {HKEY_LOCAL_MACHINE, "HKLM", L"Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce",
       "Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce"},
  };

  for (const auto& t : targets) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(t.root, t.path, 0, KEY_READ, &key) != ERROR_SUCCESS) continue;
    DWORD idx = 0;
    wchar_t vname[256] = {0};
    DWORD vname_len = 256;
    BYTE data[2048] = {0};
    DWORD data_len = sizeof(data);
    DWORD type = 0;
    while (RegEnumValueW(key, idx++, vname, &vname_len, nullptr, &type, data,
                         &data_len) == ERROR_SUCCESS) {
      if (type == REG_SZ || type == REG_EXPAND_SZ) {
        std::wstring cmd_w(reinterpret_cast<wchar_t*>(data));
        RunEntry e;
        e.root = t.root;
        e.root_label = t.root_label;
        e.reg_path = t.path;
        e.reg_path_utf8 = t.path_utf8;
        e.value_name = ToUtf8(vname);
        e.command = ExpandEnvVars(cmd_w);
        e.exe_path = ExtractExePathFromCommand(e.command);
        out.push_back(std::move(e));
      }
      vname_len = 256;
      data_len = sizeof(data);
    }
    RegCloseKey(key);
  }
  return out;
}

std::vector<std::wstring> CandidateScanDirectories() {
  std::vector<std::wstring> dirs;
  wchar_t temp[MAX_PATH * 2] = {0};
  if (GetTempPathW(MAX_PATH * 2, temp) > 0) {
    dirs.emplace_back(temp);
  }
  PWSTR downloads = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr, &downloads)) &&
      downloads != nullptr) {
    dirs.emplace_back(downloads);
    CoTaskMemFree(downloads);
  }
  PWSTR startup = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Startup, 0, nullptr, &startup)) &&
      startup != nullptr) {
    dirs.emplace_back(startup);
    CoTaskMemFree(startup);
  }
  PWSTR common_startup = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_CommonStartup, 0, nullptr, &common_startup)) &&
      common_startup != nullptr) {
    dirs.emplace_back(common_startup);
    CoTaskMemFree(common_startup);
  }
  PWSTR desktop = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &desktop)) &&
      desktop != nullptr) {
    dirs.emplace_back(desktop);
    CoTaskMemFree(desktop);
  }
  return dirs;
}

bool TerminateProcessesMatching(const std::string& process_name,
                                const std::string& path_hint) {
  const std::string target_base = BaseNameLower(
      !process_name.empty() ? process_name : path_hint);
  if (target_base.empty() && path_hint.empty()) return false;

  bool terminated = false;
  for (const auto& proc : SnapshotProcesses()) {
    if (IsUmbrellaSafeBinary(proc.path.empty() ? proc.name : proc.path)) continue;
    const bool name_match = !target_base.empty() && proc.lower_name == target_base;
    const bool path_match = !path_hint.empty() && !proc.path.empty() &&
                            ToLowerAscii(proc.path) == ToLowerAscii(path_hint);
    if (!name_match && !path_match) continue;

    HANDLE h = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, proc.pid);
    if (h != nullptr) {
      if (TerminateProcess(h, 1)) {
        WaitForSingleObject(h, 2500);
        terminated = true;
      }
      CloseHandle(h);
    }
  }
  return terminated;
}

bool DeleteRegistryRunEntry(const std::string& root_label,
                            const std::string& reg_path,
                            const std::string& val_name) {
  if (reg_path.empty() || val_name.empty()) return false;
  HKEY root = (root_label == "HKLM") ? HKEY_LOCAL_MACHINE : HKEY_CURRENT_USER;
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, ToWide(reg_path).c_str(), 0, KEY_WRITE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  LSTATUS st = RegDeleteValueW(key, ToWide(val_name).c_str());
  RegCloseKey(key);
  return st == ERROR_SUCCESS;
}

bool DeleteTargetFile(const std::string& path_utf8) {
  if (path_utf8.empty()) return false;
  std::wstring wide = ToWide(path_utf8);
  if (!FileExistsW(wide)) return false;
  if (IsUmbrellaSafeBinary(path_utf8)) return false;
  SetFileAttributesW(wide.c_str(), FILE_ATTRIBUTE_NORMAL);
  if (DeleteFileW(wide.c_str())) return true;
  // Schedule removal on reboot if file handle was held by Windows Explorer.
  if (MoveFileExW(wide.c_str(), nullptr, MOVEFILE_DELAY_UNTIL_REBOOT)) {
    return true;
  }
  return false;
}

}  // namespace

SecurityScanner& SecurityScanner::Instance() {
  static SecurityScanner instance;
  return instance;
}

std::vector<InstalledAppEntry> SecurityScanner::CollectInstalledApps() {
  HRESULT com_hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool com_init = SUCCEEDED(com_hr);

  std::map<std::string, InstalledAppEntry> by_key;
  const auto processes = SnapshotProcesses();

  auto upsert = [&](InstalledAppEntry entry) {
    if (entry.process_name.empty() && entry.path.empty()) return;
    if (entry.process_name.empty()) {
      entry.process_name = ExtractFileName(entry.path);
    }
    if (entry.name.empty()) entry.name = entry.process_name;
    const std::string key = ToLowerAscii(entry.process_name);
    if (key.empty() || IsSystemNoiseProcess(key) || IsUmbrellaSafeBinary(key)) {
      return;
    }
    auto it = by_key.find(key);
    if (it == by_key.end()) {
      by_key.emplace(key, std::move(entry));
    } else {
      if (it->second.path.empty() && !entry.path.empty()) {
        it->second.path = entry.path;
      }
      if (it->second.publisher.empty() && !entry.publisher.empty()) {
        it->second.publisher = entry.publisher;
      }
      if (entry.running) it->second.running = true;
      if (it->second.name == it->second.process_name &&
          entry.name != entry.process_name) {
        it->second.name = entry.name;
      }
    }
  };

  for (const auto& proc : processes) {
    if (IsSystemNoiseProcess(proc.lower_name)) continue;
    InstalledAppEntry entry;
    entry.process_name = proc.name;
    entry.path = proc.path;
    entry.name = !proc.product_name.empty() ? proc.product_name : proc.name;
    entry.publisher = proc.company_name;
    entry.running = true;
    upsert(std::move(entry));
  }

  std::vector<RegistryAppRecord> reg_apps;
  EnumerateUninstallRoot(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", &reg_apps);
  EnumerateUninstallRoot(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
      &reg_apps);
  EnumerateUninstallRoot(
      HKEY_CURRENT_USER,
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", &reg_apps);

  for (const auto& reg : reg_apps) {
    if (reg.system_component) continue;
    if (reg.exe_path.empty()) continue;
    InstalledAppEntry entry;
    entry.name = reg.display_name;
    entry.process_name = ExtractFileName(reg.exe_path);
    entry.path = reg.exe_path;
    entry.publisher = reg.publisher;
    upsert(std::move(entry));
  }

  std::vector<InstalledAppEntry> shortcut_apps;
  PWSTR start_user = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &start_user)) &&
      start_user != nullptr) {
    EnumerateStartMenuApps(start_user, 0, &shortcut_apps);
    CoTaskMemFree(start_user);
  }
  PWSTR start_common = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_CommonPrograms, 0, nullptr,
                                     &start_common)) &&
      start_common != nullptr) {
    EnumerateStartMenuApps(start_common, 0, &shortcut_apps);
    CoTaskMemFree(start_common);
  }
  for (auto& item : shortcut_apps) {
    upsert(std::move(item));
  }

  if (com_init) CoUninitialize();

  std::vector<InstalledAppEntry> out;
  out.reserve(by_key.size());
  for (auto& kv : by_key) {
    out.push_back(std::move(kv.second));
  }
  std::sort(out.begin(), out.end(),
            [](const InstalledAppEntry& a, const InstalledAppEntry& b) {
              if (a.running != b.running) return a.running && !b.running;
              return ToLowerAscii(a.name) < ToLowerAscii(b.name);
            });
  return out;
}

std::string SecurityScanner::PickExecutableFile() {
  wchar_t file_buf[MAX_PATH * 2] = {0};
  OPENFILENAMEW ofn = {};
  ofn.lStructSize = sizeof(ofn);
  ofn.hwndOwner = nullptr;
  ofn.lpstrFile = file_buf;
  ofn.nMaxFile = MAX_PATH * 2;
  ofn.lpstrFilter =
      L"Executable Files (*.exe)\0*.exe\0All Files (*.*)\0*.*\0";
  ofn.nFilterIndex = 1;
  ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR | OFN_EXPLORER;
  if (GetOpenFileNameW(&ofn)) {
    return ToUtf8(file_buf);
  }
  return std::string();
}

SecurityScanReport SecurityScanner::ScanDeviceSecurity() {
  SecurityScanReport report;
  report.scanned_at_ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::system_clock::now().time_since_epoch())
          .count();

  AmsiScanner amsi;
  std::map<std::string, SecurityThreatEntry> findings;
  auto add_finding = [&](SecurityThreatEntry item) {
    if (item.key.empty()) return;
    auto it = findings.find(item.key);
    if (it == findings.end()) {
      findings.emplace(item.key, std::move(item));
      return;
    }
    if (item.active) it->second.active = true;
    if (it->second.path.empty() && !item.path.empty()) it->second.path = item.path;
    if (it->second.process_name.empty() && !item.process_name.empty()) {
      it->second.process_name = item.process_name;
    }
    if (it->second.uninstall_cmd.empty() && !item.uninstall_cmd.empty()) {
      it->second.uninstall_cmd = item.uninstall_cmd;
    }
    if (it->second.registry_value.empty() && !item.registry_value.empty()) {
      it->second.registry_root = item.registry_root;
      it->second.registry_path = item.registry_path;
      it->second.registry_value = item.registry_value;
    }
    if (it->second.sha256.empty() && !item.sha256.empty()) {
      it->second.sha256 = item.sha256;
    }
    if (it->second.remediation_kind != "composite" &&
        !item.remediation_kind.empty() &&
        it->second.remediation_kind != item.remediation_kind) {
      it->second.remediation_kind = "composite";
    }
  };

  wchar_t win_dir_w[MAX_PATH] = {0};
  GetWindowsDirectoryW(win_dir_w, MAX_PATH);
  const std::string win_dir = ToLowerAscii(ToUtf8(win_dir_w));

  // 1. Running processes inspection
  const auto processes = SnapshotProcesses();
  report.scanned_processes = static_cast<int>(processes.size());
  for (const auto& proc : processes) {
    if (IsUmbrellaSafeBinary(proc.path.empty() ? proc.name : proc.path)) continue;
    const std::string combined =
        proc.name + " " + proc.path + " " + proc.product_name + " " + proc.company_name;
    const SignatureHit sig = MatchKnownThreatText(combined);
    if (sig.matched) {
      SecurityThreatEntry item;
      item.key = sig.family_key;
      item.name = sig.name;
      item.category = sig.category;
      item.severity = sig.severity;
      item.target = !proc.path.empty() ? proc.path : proc.name;
      item.detail = sig.detail;
      item.remediation_kind = "process";
      item.path = proc.path;
      item.process_name = proc.name;
      item.active = true;
      if (!proc.path.empty()) {
        std::wstring wpath = ToWide(proc.path);
        item.signed_valid = VerifyAuthenticodeSignature(wpath);
        item.sha256 = ComputeFileSha256(wpath);
      }
      add_finding(std::move(item));
      continue;
    }

    // Detect masquerading system binary running outside Windows directory
    if ((proc.lower_name == "svchost.exe" || proc.lower_name == "csrss.exe" ||
         proc.lower_name == "lsass.exe" || proc.lower_name == "smss.exe" ||
         proc.lower_name == "services.exe" || proc.lower_name == "winlogon.exe") &&
        !proc.path.empty() && !win_dir.empty() &&
        ToLowerAscii(proc.path).rfind(win_dir, 0) != 0) {
      std::wstring wpath = ToWide(proc.path);
      const bool signed_ok = VerifyAuthenticodeSignature(wpath);
      if (!signed_ok) {
        const std::string sha = ComputeFileSha256(wpath);
        SecurityThreatEntry item;
        item.key = !sha.empty() ? ("proc:masquerade:" + sha.substr(0, 16))
                                : ("proc:masquerade:" + proc.lower_name);
        item.name = "فرایند جعلی سیستم (" + proc.name + ")";
        item.category = "malware";
        item.severity = "critical";
        item.target = proc.path;
        item.detail =
            "یک فایل اجرایی غیرمعتبر با نام پردازش حیاتی ویندوز خارج از پوشه سیستم در حال اجراست.";
        item.remediation_kind = "composite";
        item.path = proc.path;
        item.process_name = proc.name;
        item.sha256 = sha;
        item.active = true;
        item.signed_valid = false;
        add_finding(std::move(item));
      }
    }
  }

  // 2. Installed programs (Registry Uninstall)
  std::vector<RegistryAppRecord> reg_apps;
  EnumerateUninstallRoot(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", &reg_apps);
  EnumerateUninstallRoot(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
      &reg_apps);
  EnumerateUninstallRoot(
      HKEY_CURRENT_USER,
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", &reg_apps);
  report.scanned_apps = static_cast<int>(reg_apps.size());

  for (const auto& app : reg_apps) {
    const std::string combined =
        app.display_name + " " + app.publisher + " " + app.exe_path + " " + app.uninstall_cmd;
    const SignatureHit sig = MatchKnownThreatText(combined);
    if (sig.matched) {
      SecurityThreatEntry item;
      item.key = sig.family_key;
      item.name = sig.name;
      item.category = sig.category;
      item.severity = sig.severity;
      item.target = !app.exe_path.empty() ? app.exe_path : app.display_name;
      item.detail = sig.detail;
      item.remediation_kind =
          !app.uninstall_cmd.empty() ? "uninstall" : "file";
      item.path = app.exe_path;
      item.process_name = ExtractFileName(app.exe_path);
      item.uninstall_cmd = app.uninstall_cmd;
      if (!app.exe_path.empty()) {
        item.sha256 = ComputeFileSha256(ToWide(app.exe_path));
      }
      add_finding(std::move(item));
    }
  }

  // 3. Persistence Run / RunOnce Registry entries
  for (const auto& run : EnumerateRunKeys()) {
    const std::string combined =
        run.value_name + " " + run.command + " " + run.exe_path;
    const SignatureHit sig = MatchKnownThreatText(combined);
    if (sig.matched) {
      SecurityThreatEntry item;
      item.key = sig.family_key;
      item.name = sig.name;
      item.category = sig.category;
      item.severity = sig.severity;
      item.target = !run.exe_path.empty() ? run.exe_path : run.value_name;
      item.detail = sig.detail;
      item.remediation_kind = "composite";
      item.path = run.exe_path;
      item.process_name = ExtractFileName(run.exe_path);
      item.registry_root = run.root_label;
      item.registry_path = run.reg_path_utf8;
      item.registry_value = run.value_name;
      add_finding(std::move(item));
      continue;
    }

    // Suspicious obfuscated PowerShell / script autostart persistence
    const std::string cmd_lower = ToLowerAscii(run.command);
    if (!IsUmbrellaSafeBinary(run.command) &&
        ((cmd_lower.find("powershell") != std::string::npos &&
          (cmd_lower.find(" -enc") != std::string::npos ||
           cmd_lower.find("encodedcommand") != std::string::npos ||
           cmd_lower.find("downloadstring") != std::string::npos)) ||
         cmd_lower.find("mshta http") != std::string::npos ||
         (cmd_lower.find("\\temp\\") != std::string::npos &&
          (cmd_lower.find(".vbs") != std::string::npos ||
           cmd_lower.find(".js") != std::string::npos ||
           cmd_lower.find(".bat") != std::string::npos)))) {
      SecurityThreatEntry item;
      item.key = "reg_run:" + ToLowerAscii(run.value_name);
      item.name = "اجرای خودکار مشکوک در استارتاپ (" + run.value_name + ")";
      item.category = "malware";
      item.severity = "high";
      item.target = run.value_name;
      item.detail =
          "یک فرمان مخفی یا اسکریپت پرخطر در فهرست اجرای خودکار ویندوز ثبت شده است.";
      item.remediation_kind = "registry_run";
      item.path = run.exe_path;
      item.registry_root = run.root_label;
      item.registry_path = run.reg_path_utf8;
      item.registry_value = run.value_name;
      add_finding(std::move(item));
    }
  }

  // 4. High-risk user directories scan (Temp, Downloads, Startup, Desktop)
  std::unordered_set<std::string> visited_paths;
  for (const auto& dir : CandidateScanDirectories()) {
    WIN32_FIND_DATAW fd = {};
    HANDLE find = FindFirstFileW((dir + L"\\*").c_str(), &fd);
    if (find == INVALID_HANDLE_VALUE) continue;

    int checked_in_dir = 0;
    do {
      if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) continue;
      if (++checked_in_dir > 250) break;

      const std::string fname = ToUtf8(fd.cFileName);
      const std::string lower_fn = ToLowerAscii(fname);
      const bool is_exec = EndsWithCi(lower_fn, ".exe") ||
                           EndsWithCi(lower_fn, ".scr") ||
                           EndsWithCi(lower_fn, ".bat") ||
                           EndsWithCi(lower_fn, ".vbs") ||
                           EndsWithCi(lower_fn, ".ps1");
      if (!is_exec) continue;

      const std::wstring wfull = dir + L"\\" + fd.cFileName;
      const std::string full = ToUtf8(wfull);
      if (IsUmbrellaSafeBinary(full)) continue;
      const std::string full_lower = ToLowerAscii(full);
      if (!visited_paths.insert(full_lower).second) continue;
      report.scanned_files++;

      const std::string product = ReadVersionStringW(wfull, L"ProductName");
      const std::string company = ReadVersionStringW(wfull, L"CompanyName");
      const SignatureHit sig =
          MatchKnownThreatText(fname + " " + full + " " + product + " " + company);
      if (sig.matched) {
        SecurityThreatEntry item;
        item.key = sig.family_key;
        item.name = sig.name;
        item.category = sig.category;
        item.severity = sig.severity;
        item.target = full;
        item.detail = sig.detail;
        item.remediation_kind = "file";
        item.path = full;
        item.process_name = fname;
        item.sha256 = ComputeFileSha256(wfull);
        item.signed_valid = VerifyAuthenticodeSignature(wfull);
        add_finding(std::move(item));
        continue;
      }

      int amsi_result = 0;
      if (amsi.ScanFile(wfull, &amsi_result)) {
        const std::string sha = ComputeFileSha256(wfull);
        SecurityThreatEntry item;
        item.key = !sha.empty() ? ("amsi:" + sha.substr(0, 16))
                                : ("amsi:" + lower_fn);
        item.name = "بدافزار شناسایی شده (" + fname + ")";
        item.category = "malware";
        item.severity = "critical";
        item.target = full;
        item.detail =
            "موتور امنیتی ویندوز (AMSI) این فایل را به عنوان بدافزار شناسایی کرد.";
        item.remediation_kind = "file";
        item.path = full;
        item.process_name = fname;
        item.sha256 = sha;
        add_finding(std::move(item));
        continue;
      }

      if (EndsWithCi(lower_fn, ".exe") || EndsWithCi(lower_fn, ".scr")) {
        const PeHeuristicResult pe = AnalyzeFileHeuristics(wfull);
        if (pe.suspicious && !VerifyAuthenticodeSignature(wfull)) {
          const std::string sha = ComputeFileSha256(wfull);
          SecurityThreatEntry item;
          item.key = !sha.empty() ? ("heur:" + sha.substr(0, 16))
                                  : ("heur:" + lower_fn);
          item.name = "فایل مشکوک و پرخطر (" + fname + ")";
          item.category = "suspicious";
          item.severity = "high";
          item.target = full;
          item.detail = pe.reason;
          item.remediation_kind = "file";
          item.path = full;
          item.process_name = fname;
          item.sha256 = sha;
          item.signed_valid = false;
          add_finding(std::move(item));
        }
      }
    } while (FindNextFileW(find, &fd));
    FindClose(find);
  }

  report.threats.reserve(findings.size());
  for (auto& kv : findings) {
    report.threats.push_back(std::move(kv.second));
  }
  std::sort(report.threats.begin(), report.threats.end(),
            [](const SecurityThreatEntry& a, const SecurityThreatEntry& b) {
              auto rank = [](const std::string& sev) {
                if (sev == "critical") return 0;
                if (sev == "high") return 1;
                return 2;
              };
              if (rank(a.severity) != rank(b.severity)) {
                return rank(a.severity) < rank(b.severity);
              }
              return a.name < b.name;
            });
  report.clean = report.threats.empty();
  return report;
}

RemediationOutcome SecurityScanner::RemediateThreat(
    const SecurityThreatEntry& target) {
  RemediationOutcome out;
  bool took_action = false;

  if (!target.process_name.empty() || !target.path.empty()) {
    if (TerminateProcessesMatching(target.process_name, target.path)) {
      took_action = true;
    }
  }
  if (!target.registry_value.empty() && !target.registry_path.empty()) {
    if (DeleteRegistryRunEntry(target.registry_root, target.registry_path,
                               target.registry_value)) {
      took_action = true;
    }
  }
  if (!target.uninstall_cmd.empty()) {
    std::wstring cmd = ToWide(target.uninstall_cmd);
    STARTUPINFOW si = {};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {};
    std::vector<wchar_t> cmd_mut(cmd.begin(), cmd.end());
    cmd_mut.push_back(L'\0');
    if (CreateProcessW(nullptr, cmd_mut.data(), nullptr, nullptr, FALSE, 0,
                       nullptr, nullptr, &si, &pi)) {
      took_action = true;
      WaitForSingleObject(pi.hProcess, 15000);
      CloseHandle(pi.hThread);
      CloseHandle(pi.hProcess);
    }
  }
  if (!target.path.empty()) {
    if (DeleteTargetFile(target.path)) {
      took_action = true;
    }
  }

  // Re-verify if the threat key is still present after remediation
  const SecurityScanReport verify = ScanDeviceSecurity();
  bool still_present = false;
  for (const auto& item : verify.threats) {
    if (item.key == target.key) {
      still_present = true;
      break;
    }
  }

  out.action_taken = took_action;
  out.still_present = still_present;
  out.ok = !still_present;
  if (!still_present) {
    out.message = "تهدید با موفقیت متوقف و پاکسازی شد.";
  } else if (took_action) {
    out.message =
        "فرآیند متوقف شد اما برخی فایل ها یا برنامه هنوز در سیستم باقی مانده اند؛ حذف کامل را تکمیل کنید.";
  } else {
    out.message =
        "حذف خودکار کامل نشد؛ ممکن است نیاز به دسترسی مدیر یا بستن دستی برنامه باشد.";
  }
  return out;
}

}  // namespace umbrella
