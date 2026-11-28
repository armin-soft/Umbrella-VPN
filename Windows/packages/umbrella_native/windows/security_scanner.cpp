#include "security_scanner.h"

#include <bcrypt.h>
#include <commdlg.h>
#include <knownfolders.h>
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
#include <cwchar>
#include <cwctype>
#include <fstream>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <utility>

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
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
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

std::string CurrentProcessDirLower() {
  wchar_t exe_path[MAX_PATH * 2] = {0};
  DWORD len = GetModuleFileNameW(nullptr, exe_path, MAX_PATH * 2);
  if (len == 0) return std::string();
  std::string utf8 = ToLowerAscii(ToUtf8(std::wstring(exe_path, len)));
  size_t slash = utf8.find_last_of("\\/");
  if (slash == std::string::npos) return std::string();
  return utf8.substr(0, slash + 1);
}

bool IsUmbrellaSafeBinary(const std::string& path_or_name) {
  const std::string lower = ToLowerAscii(path_or_name);
  const std::string base = BaseNameLower(path_or_name);
  if (base == "umbrellavpn.exe" || base == "umbrellacli.exe" ||
      base == "umbrellacoreengine.exe" || base == "umbrellaadmin.exe" ||
      base == "umbrellacore.dll" || base == "unins000.exe") {
    return ContainsCi(path_or_name, "umbrella") ||
           base.rfind("umbrella", 0) == 0;
  }
  const std::string self_dir = CurrentProcessDirLower();
  if (!self_dir.empty() && lower.find(self_dir) != std::string::npos) {
    return true;
  }
  return ContainsCi(path_or_name, "\\umbrella\\") ||
         ContainsCi(path_or_name, "\\umbrellavpn\\") ||
         ContainsCi(path_or_name, "\\umbrella vpn\\") ||
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

bool ContainsAsciiBytesCi(const std::vector<BYTE>& haystack, const char* needle);
bool HasPeHeaderAt(const std::vector<BYTE>& buf, size_t offset);
bool ContainsElfHeaderAt(const std::vector<BYTE>& buf, size_t offset);
bool ContainsDexHeaderAt(const std::vector<BYTE>& buf, size_t offset);
bool ReadFileSampleBytes(const std::wstring& path, size_t max_bytes,
                         std::vector<BYTE>* out);
bool ContainsDangerousUrlOrPayload(const std::string& lower_text);

double ComputeShannonEntropy(const BYTE* data, size_t len) {
  if (data == nullptr || len == 0) return 0.0;
  std::array<size_t, 256> freq{};
  for (size_t i = 0; i < len; ++i) {
    freq[data[i]]++;
  }
  double ent = 0.0;
  for (size_t count : freq) {
    if (count == 0) continue;
    double p = static_cast<double>(count) / static_cast<double>(len);
    ent -= p * std::log2(p);
  }
  return ent;
}

bool ContainsBinderOrPayloadBytes(const std::vector<BYTE>& buf,
                                  size_t start_offset = 0) {
  if (start_offset >= buf.size()) return false;
  for (size_t pos = start_offset; pos + 0x40 < buf.size(); ++pos) {
    if ((buf[pos] == 0x4D && buf[pos + 1] == 0x5A &&
         HasPeHeaderAt(buf, pos)) ||
        ContainsElfHeaderAt(buf, pos) ||
        ContainsDexHeaderAt(buf, pos)) {
      return true;
    }
    if (pos + 4 <= buf.size() && buf[pos] == 'P' && buf[pos + 1] == 'K' &&
        buf[pos + 2] == 0x03 && buf[pos + 3] == 0x04) {
      return true;
    }
    if (pos + 7 <= buf.size() && buf[pos] == 'R' && buf[pos + 1] == 'a' &&
        buf[pos + 2] == 'r' && buf[pos + 3] == '!' && buf[pos + 4] == 0x1A &&
        buf[pos + 5] == 0x07) {
      return true;
    }
    if (pos + 6 <= buf.size() && buf[pos] == '7' && buf[pos + 1] == 'z' &&
        buf[pos + 2] == 0xBC && buf[pos + 3] == 0xAF &&
        buf[pos + 4] == 0x27 && buf[pos + 5] == 0x1C) {
      return true;
    }
  }
  std::vector<BYTE> slice;
  if (start_offset == 0) {
    return ContainsAsciiBytesCi(buf, "eicar-standard-antivirus-test-file") ||
           ContainsAsciiBytesCi(buf, "<script") ||
           ContainsAsciiBytesCi(buf, "wscript.shell") ||
           ContainsAsciiBytesCi(buf, "urldownloadtofile") ||
           ContainsAsciiBytesCi(buf, "frombase64string") ||
           ContainsAsciiBytesCi(buf, "invoke-expression") ||
           ContainsAsciiBytesCi(buf, "powershell -enc") ||
           ContainsAsciiBytesCi(buf, "basestart-") ||
           ContainsAsciiBytesCi(buf, "-baseend") ||
           ContainsAsciiBytesCi(buf, "tvqqaam") ||
           ContainsAsciiBytesCi(buf, "uesdb");
  }
  slice.assign(buf.begin() + static_cast<std::ptrdiff_t>(start_offset), buf.end());
  return ContainsAsciiBytesCi(slice, "eicar-standard-antivirus-test-file") ||
         ContainsAsciiBytesCi(slice, "<script") ||
         ContainsAsciiBytesCi(slice, "wscript.shell") ||
         ContainsAsciiBytesCi(slice, "urldownloadtofile") ||
         ContainsAsciiBytesCi(slice, "frombase64string") ||
         ContainsAsciiBytesCi(slice, "invoke-expression") ||
         ContainsAsciiBytesCi(slice, "powershell -enc") ||
         ContainsAsciiBytesCi(slice, "basestart-") ||
         ContainsAsciiBytesCi(slice, "-baseend") ||
         ContainsAsciiBytesCi(slice, "tvqqaam") ||
         ContainsAsciiBytesCi(slice, "uesdb");
}

struct PeHeuristicResult {
  bool is_pe = false;
  bool suspicious = false;
  bool deterministic = false;
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
      size.QuadPart > 32LL * 1024 * 1024) {
    CloseHandle(file);
    return res;
  }
  const uint64_t total_file_size = static_cast<uint64_t>(size.QuadPart);
  const size_t cap = static_cast<size_t>(std::min<int64_t>(size.QuadPart, 4LL * 1024 * 1024));
  std::vector<BYTE> buf(cap);
  DWORD read_bytes = 0;
  bool ok = ReadFile(file, buf.data(), static_cast<DWORD>(cap), &read_bytes, nullptr) != 0;

  res.is_pe = (ok && read_bytes >= 64 && buf[0] == 'M' && buf[1] == 'Z');
  if (!ok || read_bytes < 256) {
    CloseHandle(file);
    return res;
  }

  // Parse PE sections & check for section-level high-entropy packing and bound overlays.
  uint64_t pe_end_offset = 0;
  bool high_entropy_code_section = false;
  if (HasPeHeaderAt(buf, 0)) {
    const uint32_t pe_off =
        static_cast<uint32_t>(buf[0x3C]) |
        (static_cast<uint32_t>(buf[0x3D]) << 8) |
        (static_cast<uint32_t>(buf[0x3E]) << 16) |
        (static_cast<uint32_t>(buf[0x3F]) << 24);
    if (pe_off + 24 <= read_bytes) {
      const uint16_t num_sections =
          static_cast<uint16_t>(buf[pe_off + 6]) |
          (static_cast<uint16_t>(buf[pe_off + 7]) << 8);
      const uint16_t opt_hdr_size =
          static_cast<uint16_t>(buf[pe_off + 20]) |
          (static_cast<uint16_t>(buf[pe_off + 21]) << 8);
      const size_t sec_table = static_cast<size_t>(pe_off) + 24 + opt_hdr_size;
      const uint16_t safe_secs = std::min<uint16_t>(num_sections, 32);
      for (uint16_t s = 0; s < safe_secs; ++s) {
        const size_t sh = sec_table + static_cast<size_t>(s) * 40;
        if (sh + 40 > read_bytes) break;
        std::string sec_name;
        for (size_t c = 0; c < 8 && buf[sh + c] != 0; ++c) {
          sec_name.push_back(static_cast<char>(std::tolower(buf[sh + c])));
        }
        const uint32_t raw_size =
            static_cast<uint32_t>(buf[sh + 16]) |
            (static_cast<uint32_t>(buf[sh + 17]) << 8) |
            (static_cast<uint32_t>(buf[sh + 18]) << 16) |
            (static_cast<uint32_t>(buf[sh + 19]) << 24);
        const uint32_t raw_ptr =
            static_cast<uint32_t>(buf[sh + 20]) |
            (static_cast<uint32_t>(buf[sh + 21]) << 8) |
            (static_cast<uint32_t>(buf[sh + 22]) << 16) |
            (static_cast<uint32_t>(buf[sh + 23]) << 24);
        if (raw_size > 0) {
          const uint64_t end_pos = static_cast<uint64_t>(raw_ptr) + raw_size;
          if (end_pos <= total_file_size && end_pos > pe_end_offset) {
            pe_end_offset = end_pos;
          }
          if (sec_name != ".rsrc" && raw_size >= 4096 &&
              raw_ptr < read_bytes) {
            const size_t avail = std::min<size_t>(
                static_cast<size_t>(raw_size),
                read_bytes - static_cast<size_t>(raw_ptr));
            if (avail >= 4096) {
              const double sec_ent =
                  ComputeShannonEntropy(buf.data() + raw_ptr, avail);
              if (sec_ent >= 7.65 &&
                  (sec_name == ".text" || sec_name == "upx0" ||
                   sec_name == "upx1" || sec_name == ".themida" ||
                   sec_name == ".vmp0" || sec_name == ".enigma")) {
                high_entropy_code_section = true;
              }
            }
          }
        }
      }
    }
  }

  // Check PE overlay (>16KB trailing data after last section) for bound second PE/archive/payload.
  if (pe_end_offset > 0 && total_file_size > pe_end_offset + 16384ULL) {
    const uint64_t overlay_len = total_file_size - pe_end_offset;
    const size_t overlay_cap = static_cast<size_t>(
        std::min<uint64_t>(overlay_len, 1024ULL * 1024ULL));
    std::vector<BYTE> overlay(overlay_cap);
    LARGE_INTEGER seek_pos = {};
    seek_pos.QuadPart = static_cast<LONGLONG>(pe_end_offset);
    DWORD ov_read = 0;
    if (SetFilePointerEx(file, seek_pos, nullptr, FILE_BEGIN) != 0 &&
        ReadFile(file, overlay.data(), static_cast<DWORD>(overlay_cap),
                 &ov_read, nullptr) != 0 &&
        ov_read >= 64) {
      overlay.resize(ov_read);
      if (ContainsBinderOrPayloadBytes(overlay, 0)) {
        CloseHandle(file);
        res.suspicious = true;
        res.deterministic = true;
        res.reason =
            "فایل بایندر با پی لود اجرایی یا آرشیو پنهان شده در بخش انتهایی (Overlay) شناسایی شد";
        return res;
      }
    }
  }
  CloseHandle(file);

  const double ent = ComputeShannonEntropy(buf.data(), read_bytes);
  res.entropy = ent;

  std::string ascii_view;
  ascii_view.reserve(read_bytes / 2);
  for (DWORD i = 0; i < read_bytes; ++i) {
    unsigned char ch = buf[i];
    if (ch >= 32 && ch <= 126) {
      ascii_view.push_back(static_cast<char>(std::tolower(ch)));
    } else if (!ascii_view.empty() && ascii_view.back() != ' ') {
      ascii_view.push_back(' ');
    }
  }

  // Extract UTF-16LE strings (.NET RATs like XWorm, AsyncRAT, AgentTesla store C2/API strings as UTF-16LE).
  std::string utf16_view;
  utf16_view.reserve(read_bytes / 4);
  for (DWORD i = 0; i + 1 < read_bytes; i += 2) {
    unsigned char ch = buf[i];
    unsigned char hi = buf[i + 1];
    if (hi == 0 && ch >= 32 && ch <= 126) {
      utf16_view.push_back(static_cast<char>(std::tolower(ch)));
    } else if (!utf16_view.empty() && utf16_view.back() != ' ') {
      utf16_view.push_back(' ');
    }
  }
  const std::string combined_view = ascii_view + " " + utf16_view;

  const bool injection_apis =
      (combined_view.find("virtualallocex") != std::string::npos &&
       combined_view.find("writeprocessmemory") != std::string::npos &&
       (combined_view.find("createremotethread") != std::string::npos ||
        combined_view.find("ntunmapviewofsection") != std::string::npos ||
        combined_view.find("zwunmapviewofsection") != std::string::npos ||
        combined_view.find("queueuserapc") != std::string::npos)) ||
      ((combined_view.find("ntunmapviewofsection") != std::string::npos ||
        combined_view.find("zwunmapviewofsection") != std::string::npos) &&
       (combined_view.find("setthreadcontext") != std::string::npos ||
        combined_view.find("wow64setthreadcontext") != std::string::npos) &&
       combined_view.find("resumethread") != std::string::npos);

  const bool amsi_etw_bypass =
      combined_view.find("amsiscanbuffer") != std::string::npos &&
      combined_view.find("virtualprotect") != std::string::npos &&
      (combined_view.find("etweventwrite") != std::string::npos || ent >= 6.8);

  const bool keylogger_apis =
      combined_view.find("setwindowshookexa") != std::string::npos ||
      combined_view.find("setwindowshookexw") != std::string::npos;

  const bool rat_family_marker =
      combined_view.find("xworm") != std::string::npos ||
      combined_view.find("asyncrat") != std::string::npos ||
      combined_view.find("asyncclient") != std::string::npos ||
      combined_view.find("remcos") != std::string::npos ||
      combined_view.find("njrat") != std::string::npos ||
      combined_view.find("lummastealer") != std::string::npos ||
      combined_view.find("agenttesla") != std::string::npos ||
      combined_view.find("nanocore") != std::string::npos ||
      combined_view.find("darkcomet") != std::string::npos ||
      combined_view.find("castleloader") != std::string::npos ||
      combined_view.find("latrodectus") != std::string::npos ||
      combined_view.find("deerstealer") != std::string::npos ||
      combined_view.find("redlinestealer") != std::string::npos ||
      combined_view.find("vidarstealer") != std::string::npos ||
      combined_view.find("cobaltstrike") != std::string::npos ||
      combined_view.find("meterpreter") != std::string::npos;

  const bool double_ext =
      ContainsCi(ToUtf8(path), ".pdf.exe") ||
      ContainsCi(ToUtf8(path), ".docx.exe") ||
      ContainsCi(ToUtf8(path), ".xlsx.exe") ||
      ContainsCi(ToUtf8(path), ".jpg.exe") ||
      ContainsCi(ToUtf8(path), ".png.exe") ||
      ContainsCi(ToUtf8(path), ".mp4.exe");

  if (double_ext) {
    res.suspicious = true;
    res.deterministic = true;
    res.reason = "فایل تروجانی با پسوند دوگانه فریبنده شناسایی شد";
    return res;
  }
  if (rat_family_marker) {
    res.suspicious = true;
    res.deterministic = true;
    res.reason = "امضای بدافزار سرقت اطلاعات یا کنترل از راه دور (RAT) در فایل شناسایی شد";
    return res;
  }
  if (amsi_etw_bypass) {
    res.suspicious = true;
    res.deterministic = true;
    res.reason = "الگوی دور زدن موتور امنیتی AMSI / ETW در فایل بدون امضا شناسایی شد";
    return res;
  }
  if (injection_apis && (ent >= 6.6 || high_entropy_code_section)) {
    res.suspicious = true;
    res.deterministic = true;
    res.reason = "الگوی تزریق کد یا Process Hollowing به همراه باینری فشرده شده شناسایی شد";
    return res;
  }
  if (keylogger_apis && (ent >= 6.9 || high_entropy_code_section)) {
    res.suspicious = true;
    res.deterministic = true;
    res.reason = "الگوی شنود کلیدها (کی لاگر) درون باینری رمزگذاری شده شناسایی شد";
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
  if (lower.find("xworm") != std::string::npos ||
      lower.find("asyncrat") != std::string::npos ||
      lower.find("remcos") != std::string::npos ||
      lower.find("njrat") != std::string::npos ||
      lower.find("quasar rat") != std::string::npos ||
      lower.find("nanocore") != std::string::npos ||
      lower.find("darkcomet") != std::string::npos ||
      lower.find("dcrat") != std::string::npos ||
      lower.find("lummastealer") != std::string::npos ||
      lower.find("lumma_stealer") != std::string::npos ||
      lower.find("vidarstealer") != std::string::npos ||
      lower.find("redlinestealer") != std::string::npos ||
      lower.find("agenttesla") != std::string::npos ||
      lower.find("castleloader") != std::string::npos ||
      lower.find("latrodectus") != std::string::npos ||
      lower.find("deerstealer") != std::string::npos ||
      lower.find("stealc") != std::string::npos) {
    return SignatureHit{
        true,
        "malware:rat_stealer",
        "بدافزار کنترل از راه دور یا سرقت اطلاعات (RAT / Infostealer)",
        "malware",
        "critical",
        "امضای تروجان کنترل از راه دور (RAT) یا بدافزار سرقت اطلاعات روی دستگاه شناسایی شد.",
    };
  }
  if (lower.find("hiddify") != std::string::npos ||
      lower.find("hiddifynext") != std::string::npos ||
      lower.find("hiddify-next") != std::string::npos ||
      lower.find("hiddify desktop") != std::string::npos) {
    return SignatureHit{
        true,
        "vpn:hiddify",
        "Hiddify / Hiddify Next (فیلترشکن ناسازگار)",
        "conflicting_vpn",
        "high",
        "نرم افزار Hiddify روی سیستم یافت شد؛ پیش از اتصال به آمبرلا باید آن را حذف کنید.",
    };
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

struct CleanFileStamp {
  uint64_t size = 0;
  uint64_t write_time = 0;
};

struct CachedProcVersion {
  uint64_t size = 0;
  uint64_t write_time = 0;
  std::string product_name;
  std::string company_name;
};

std::mutex g_scan_cache_mutex;
std::unordered_map<std::string, CleanFileStamp> g_clean_file_cache;
std::unordered_map<std::string, CachedProcVersion> g_proc_version_cache;
constexpr size_t kMaxCleanFileCacheEntries = 20000;
constexpr size_t kMaxProcVersionCacheEntries = 4096;

uint64_t FileTimeToUint64(const FILETIME& ft) {
  return (static_cast<uint64_t>(ft.dwHighDateTime) << 32) |
         static_cast<uint64_t>(ft.dwLowDateTime);
}

bool GetFileStampW(const std::wstring& path, uint64_t* size_out,
                   uint64_t* write_time_out) {
  WIN32_FILE_ATTRIBUTE_DATA fad = {};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &fad) ||
      (fad.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    return false;
  }
  *size_out = (static_cast<uint64_t>(fad.nFileSizeHigh) << 32) |
              static_cast<uint64_t>(fad.nFileSizeLow);
  *write_time_out = FileTimeToUint64(fad.ftLastWriteTime);
  return true;
}

bool IsCleanFileCached(const std::string& full_lower, uint64_t size,
                       uint64_t write_time) {
  std::lock_guard<std::mutex> lock(g_scan_cache_mutex);
  const auto it = g_clean_file_cache.find(full_lower);
  if (it == g_clean_file_cache.end()) return false;
  return it->second.size == size && it->second.write_time == write_time;
}

void RecordCleanFileCache(const std::string& full_lower, uint64_t size,
                          uint64_t write_time) {
  std::lock_guard<std::mutex> lock(g_scan_cache_mutex);
  if (g_clean_file_cache.size() >= kMaxCleanFileCacheEntries &&
      g_clean_file_cache.find(full_lower) == g_clean_file_cache.end()) {
    g_clean_file_cache.clear();
  }
  g_clean_file_cache[full_lower] = CleanFileStamp{size, write_time};
}

void InvalidateCleanFileCache(const std::string& path_utf8 = std::string()) {
  std::lock_guard<std::mutex> lock(g_scan_cache_mutex);
  if (path_utf8.empty()) {
    g_clean_file_cache.clear();
  } else {
    g_clean_file_cache.erase(ToLowerAscii(path_utf8));
  }
}

struct RunningProcessInfo {
  DWORD pid = 0;
  std::string name;
  std::string lower_name;
  std::string path;
  std::string cmdline;
  std::string product_name;
  std::string company_name;
};

struct NtUnicodeString64 {
  USHORT Length;
  USHORT MaximumLength;
  ULONGLONG Buffer;
};

struct NtProcessBasicInfo64 {
  ULONGLONG Reserved1;
  ULONGLONG PebBaseAddress;
  ULONGLONG Reserved2[2];
  ULONGLONG UniqueProcessId;
  ULONGLONG Reserved3;
};

bool IsLolbinProcessName(const std::string& lower_name) {
  return lower_name == "powershell.exe" || lower_name == "pwsh.exe" ||
         lower_name == "cmd.exe" || lower_name == "mshta.exe" ||
         lower_name == "wscript.exe" || lower_name == "cscript.exe" ||
         lower_name == "rundll32.exe" || lower_name == "regsvr32.exe" ||
         lower_name == "certutil.exe" || lower_name == "bitsadmin.exe" ||
         lower_name == "msbuild.exe" || lower_name == "finger.exe" ||
         lower_name == "curl.exe";
}

std::string ReadRemoteProcessCommandLine(DWORD pid) {
#ifdef _WIN64
  using NtQueryInfoProcFn = LONG(NTAPI*)(HANDLE, ULONG, PVOID, ULONG, PULONG);
  static NtQueryInfoProcFn query_fn = []() -> NtQueryInfoProcFn {
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    return ntdll ? reinterpret_cast<NtQueryInfoProcFn>(
                       GetProcAddress(ntdll, "NtQueryInformationProcess"))
                 : nullptr;
  }();
  if (query_fn == nullptr) return std::string();

  HANDLE proc = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
  if (proc == nullptr) return std::string();

  std::string cmd_utf8;
  BOOL is_wow64 = FALSE;
  if (IsWow64Process(proc, &is_wow64) && !is_wow64) {
    NtProcessBasicInfo64 pbi = {};
    ULONG ret_len = 0;
    if (query_fn(proc, 0, &pbi, sizeof(pbi), &ret_len) == 0 &&
        pbi.PebBaseAddress != 0) {
      ULONGLONG proc_params = 0;
      SIZE_T bytes_read = 0;
      // On x64 Windows PEB, ProcessParameters pointer sits at offset 0x20.
      if (ReadProcessMemory(
              proc, reinterpret_cast<LPCVOID>(pbi.PebBaseAddress + 0x20),
              &proc_params, sizeof(proc_params), &bytes_read) &&
          proc_params != 0) {
        NtUnicodeString64 cmd_us = {};
        // In RTL_USER_PROCESS_PARAMETERS (x64), CommandLine UNICODE_STRING sits at offset 0x70.
        if (ReadProcessMemory(proc, reinterpret_cast<LPCVOID>(proc_params + 0x70),
                              &cmd_us, sizeof(cmd_us), &bytes_read) &&
            cmd_us.Length > 0 && cmd_us.Buffer != 0) {
          const size_t wchar_count =
              std::min<size_t>(cmd_us.Length / sizeof(wchar_t), 2048);
          std::wstring wide_cmd(wchar_count, L'\0');
          if (ReadProcessMemory(proc, reinterpret_cast<LPCVOID>(cmd_us.Buffer),
                                wide_cmd.data(), wchar_count * sizeof(wchar_t),
                                &bytes_read)) {
            cmd_utf8 = ToUtf8(wide_cmd);
          }
        }
      }
    }
  }
  CloseHandle(proc);
  return cmd_utf8;
#else
  (void)pid;
  return std::string();
#endif
}

bool IsSuspiciousLolbinCommandLine(const std::string& lower_name,
                                   const std::string& raw_cmd) {
  if (raw_cmd.empty()) return false;
  const std::string cmd = ToLowerAscii(raw_cmd);
  if (IsUmbrellaSafeBinary(cmd)) return false;

  const bool obfuscated_exec =
      cmd.find(" -enc") != std::string::npos ||
      cmd.find(" /enc") != std::string::npos ||
      cmd.find("encodedcommand") != std::string::npos ||
      cmd.find("frombase64string") != std::string::npos ||
      cmd.find("-bxor") != std::string::npos ||
      cmd.find("gzipstream") != std::string::npos ||
      cmd.find("deflatestream") != std::string::npos ||
      cmd.find("iex(") != std::string::npos ||
      cmd.find("invoke-expression") != std::string::npos ||
      cmd.find("downloadstring") != std::string::npos ||
      cmd.find("urldownloadtofile") != std::string::npos ||
      cmd.find("scrobj.dll") != std::string::npos ||
      cmd.find("ms-msdt:") != std::string::npos;

  if ((lower_name == "powershell.exe" || lower_name == "pwsh.exe" ||
       lower_name == "cmd.exe" || lower_name == "wscript.exe" ||
       lower_name == "cscript.exe") &&
      (obfuscated_exec ||
       ((cmd.find("irm ") != std::string::npos ||
         cmd.find("invoke-restmethod") != std::string::npos ||
         cmd.find("invoke-webrequest") != std::string::npos) &&
        (cmd.find("iex") != std::string::npos ||
         cmd.find("invoke-expression") != std::string::npos ||
         cmd.find("http://") != std::string::npos ||
         cmd.find("https://") != std::string::npos)))) {
    return true;
  }
  if ((lower_name == "mshta.exe" || lower_name == "rundll32.exe" ||
       lower_name == "regsvr32.exe" || lower_name == "finger.exe") &&
      (obfuscated_exec ||
       cmd.find("javascript:") != std::string::npos ||
       cmd.find("vbscript:") != std::string::npos ||
       cmd.find("http://") != std::string::npos ||
       cmd.find("https://") != std::string::npos)) {
    return true;
  }
  if (lower_name == "certutil.exe" &&
      (cmd.find("-urlcache") != std::string::npos ||
       cmd.find("-split") != std::string::npos) &&
      (cmd.find("http://") != std::string::npos ||
       cmd.find("https://") != std::string::npos)) {
    return true;
  }
  return false;
}

std::vector<RunningProcessInfo> SnapshotProcesses(
    bool include_version_info = true,
    const std::string& skip_version_prefix_lower = std::string(),
    bool capture_lolbin_cmdline = false) {
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
        if (capture_lolbin_cmdline && IsLolbinProcessName(info.lower_name)) {
          info.cmdline = ReadRemoteProcessCommandLine(info.pid);
        }
        HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, info.pid);
        if (proc != nullptr) {
          wchar_t pbuf[MAX_PATH * 2] = {0};
          DWORD plen = MAX_PATH * 2;
          if (QueryFullProcessImageNameW(proc, 0, pbuf, &plen) && plen > 0) {
            std::wstring wpath(pbuf, plen);
            info.path = ToUtf8(wpath);
            const std::string lower_path = ToLowerAscii(info.path);
            const bool skip_ver =
                !include_version_info ||
                (!skip_version_prefix_lower.empty() &&
                 lower_path.rfind(skip_version_prefix_lower, 0) == 0);
            if (!skip_ver) {
              uint64_t fsize = 0;
              uint64_t mtime = 0;
              const bool has_stamp = GetFileStampW(wpath, &fsize, &mtime);
              bool cache_hit = false;
              if (has_stamp) {
                std::lock_guard<std::mutex> lock(g_scan_cache_mutex);
                auto it = g_proc_version_cache.find(lower_path);
                if (it != g_proc_version_cache.end() &&
                    it->second.size == fsize &&
                    it->second.write_time == mtime) {
                  info.product_name = it->second.product_name;
                  info.company_name = it->second.company_name;
                  cache_hit = true;
                }
              }
              if (!cache_hit) {
                info.product_name = ReadVersionStringW(wpath, L"ProductName");
                info.company_name = ReadVersionStringW(wpath, L"CompanyName");
                if (has_stamp) {
                  std::lock_guard<std::mutex> lock(g_scan_cache_mutex);
                  if (g_proc_version_cache.size() >= kMaxProcVersionCacheEntries) {
                    g_proc_version_cache.clear();
                  }
                  g_proc_version_cache[lower_path] = CachedProcVersion{
                      fsize, mtime, info.product_name, info.company_name};
                }
              }
            }
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
                            std::vector<RegistryAppRecord>* out,
                            bool skip_install_glob = false) {
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
      } else if (!skip_install_glob) {
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

bool DirectoryExistsW(const std::wstring& path) {
  if (path.empty()) return false;
  DWORD attrs = GetFileAttributesW(path.c_str());
  return attrs != INVALID_FILE_ATTRIBUTES &&
         (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

bool ReadFileSampleBytes(const std::wstring& path, size_t max_bytes,
                         std::vector<BYTE>* out) {
  out->clear();
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size = {};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0) {
    CloseHandle(file);
    return false;
  }
  const size_t to_read = static_cast<size_t>(
      std::min<int64_t>(size.QuadPart, static_cast<int64_t>(max_bytes)));
  out->resize(to_read);
  DWORD read_bytes = 0;
  bool ok = ReadFile(file, out->data(), static_cast<DWORD>(to_read), &read_bytes,
                     nullptr) != 0;
  CloseHandle(file);
  if (!ok || read_bytes == 0) {
    out->clear();
    return false;
  }
  out->resize(read_bytes);
  return true;
}

bool ReadFileHeadAndTailBytes(const std::wstring& path, size_t head_bytes,
                              size_t tail_bytes, std::vector<BYTE>* out) {
  out->clear();
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size = {};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0) {
    CloseHandle(file);
    return false;
  }
  const uint64_t total = static_cast<uint64_t>(size.QuadPart);
  if (total <= static_cast<uint64_t>(head_bytes + tail_bytes)) {
    const size_t to_read = static_cast<size_t>(total);
    out->resize(to_read);
    DWORD read_bytes = 0;
    bool ok = ReadFile(file, out->data(), static_cast<DWORD>(to_read),
                       &read_bytes, nullptr) != 0;
    CloseHandle(file);
    if (!ok || read_bytes == 0) {
      out->clear();
      return false;
    }
    out->resize(read_bytes);
    return true;
  }
  out->resize(head_bytes + tail_bytes);
  DWORD read_head = 0;
  bool ok_head = ReadFile(file, out->data(), static_cast<DWORD>(head_bytes),
                          &read_head, nullptr) != 0;
  LARGE_INTEGER tail_offset = {};
  tail_offset.QuadPart = static_cast<LONGLONG>(total - tail_bytes);
  DWORD read_tail = 0;
  bool ok_tail = ok_head &&
                 SetFilePointerEx(file, tail_offset, nullptr, FILE_BEGIN) != 0 &&
                 ReadFile(file, out->data() + read_head,
                          static_cast<DWORD>(tail_bytes), &read_tail, nullptr) != 0;
  CloseHandle(file);
  if (!ok_head || !ok_tail || (read_head + read_tail) == 0) {
    out->clear();
    return false;
  }
  out->resize(read_head + read_tail);
  return true;
}

bool HasValidImageMagic(const std::string& lower_fn,
                        const std::vector<BYTE>& bytes) {
  if ((EndsWithCi(lower_fn, ".jpg") || EndsWithCi(lower_fn, ".jpeg")) &&
      bytes.size() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return true;
  }
  if (EndsWithCi(lower_fn, ".png") && bytes.size() >= 8 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  if (EndsWithCi(lower_fn, ".gif") && bytes.size() >= 6 &&
      bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F' &&
      bytes[3] == '8') {
    return true;
  }
  if (EndsWithCi(lower_fn, ".webp") && bytes.size() >= 12 &&
      bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' &&
      bytes[3] == 'F' && bytes[8] == 'W' && bytes[9] == 'E' &&
      bytes[10] == 'B' && bytes[11] == 'P') {
    return true;
  }
  if (EndsWithCi(lower_fn, ".bmp") && bytes.size() >= 2 &&
      bytes[0] == 'B' && bytes[1] == 'M') {
    return true;
  }
  if (EndsWithCi(lower_fn, ".ico") && bytes.size() >= 4 &&
      bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 1 && bytes[3] == 0) {
    return true;
  }
  return false;
}

bool ContainsAsciiBytesCi(const std::vector<BYTE>& haystack, const char* needle) {
  const size_t nlen = std::strlen(needle);
  if (nlen == 0 || haystack.size() < nlen) return false;
  for (size_t i = 0; i + nlen <= haystack.size(); ++i) {
    bool match = true;
    for (size_t j = 0; j < nlen; ++j) {
      unsigned char a = static_cast<unsigned char>(std::tolower(haystack[i + j]));
      unsigned char b = static_cast<unsigned char>(std::tolower(static_cast<unsigned char>(needle[j])));
      if (a != b) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

bool HasPeHeaderAt(const std::vector<BYTE>& buf, size_t offset) {
  if (offset + 0x40 > buf.size()) return false;
  if (buf[offset] != 0x4D || buf[offset + 1] != 0x5A) return false;
  const uint32_t pe_rel =
      static_cast<uint32_t>(buf[offset + 0x3C]) |
      (static_cast<uint32_t>(buf[offset + 0x3D]) << 8) |
      (static_cast<uint32_t>(buf[offset + 0x3E]) << 16) |
      (static_cast<uint32_t>(buf[offset + 0x3F]) << 24);
  if (pe_rel < 0x20 || pe_rel > 0x2000) return false;
  const size_t pe = offset + static_cast<size_t>(pe_rel);
  if (pe + 6 > buf.size()) return false;
  if (buf[pe] != 'P' || buf[pe + 1] != 'E' || buf[pe + 2] != 0 || buf[pe + 3] != 0) {
    return false;
  }
  const uint16_t machine = static_cast<uint16_t>(buf[pe + 4]) |
                           (static_cast<uint16_t>(buf[pe + 5]) << 8);
  return machine == 0x014C || machine == 0x8664 || machine == 0xAA64;
}

bool HasRloSpoofCharW(const std::wstring& name) {
  for (wchar_t ch : name) {
    if (ch == 0x202E || ch == 0x202D || ch == 0x202A || ch == 0x202B ||
        (ch >= 0x2066 && ch <= 0x2069)) {
      return true;
    }
  }
  return false;
}

bool HasDoubleMasqueradeExtension(const std::string& lower_fn) {
  static const char* kDangerExts[] = {
      ".exe", ".scr", ".pif", ".com", ".bat", ".cmd", ".vbs", ".vbe",
      ".js",  ".jse", ".wsf", ".wsh", ".ps1", ".hta", ".msi", ".lnk",
  };
  static const char* kDecoyExts[] = {
      ".jpg.", ".jpeg.", ".png.", ".gif.", ".webp.", ".bmp.",
      ".pdf.", ".doc.",  ".docx.", ".xls.", ".mp4.", ".mp3.",
      ".txt.", ".zip.",  ".rar.",
  };
  bool ends_dangerous = false;
  for (const char* ext : kDangerExts) {
    if (EndsWithCi(lower_fn, ext)) {
      ends_dangerous = true;
      break;
    }
  }
  if (!ends_dangerous) return false;
  for (const char* decoy : kDecoyExts) {
    if (lower_fn.find(decoy) != std::string::npos) return true;
  }
  return false;
}

bool InspectShortcutThreat(const std::wstring& lnk_path, std::string* reason_out) {
  IShellLinkW* link = nullptr;
  if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                              IID_IShellLinkW, reinterpret_cast<void**>(&link))) ||
      link == nullptr) {
    return false;
  }
  bool malicious = false;
  IPersistFile* persist = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_IPersistFile,
                                     reinterpret_cast<void**>(&persist))) &&
      persist != nullptr) {
    if (SUCCEEDED(persist->Load(lnk_path.c_str(), STGM_READ))) {
      wchar_t target[MAX_PATH * 2] = {0};
      wchar_t args[2048] = {0};
      link->GetPath(target, MAX_PATH * 2, nullptr, SLGP_RAWPATH);
      link->GetArguments(args, 2048);
      const std::string combined = ToLowerAscii(ToUtf8(target) + " " + ToUtf8(args));
      const bool suspicious_runner =
          combined.find("powershell") != std::string::npos ||
          combined.find("cmd.exe") != std::string::npos ||
          combined.find("mshta") != std::string::npos ||
          combined.find("wscript") != std::string::npos ||
          combined.find("cscript") != std::string::npos ||
          combined.find("certutil") != std::string::npos ||
          combined.find("bitsadmin") != std::string::npos;
      const bool suspicious_payload =
          combined.find(" -enc") != std::string::npos ||
          combined.find("encodedcommand") != std::string::npos ||
          combined.find("downloadstring") != std::string::npos ||
          combined.find("invoke-webrequest") != std::string::npos ||
          combined.find("iwr ") != std::string::npos ||
          combined.find("http://") != std::string::npos ||
          combined.find("https://") != std::string::npos ||
          combined.find("\\temp\\") != std::string::npos;
      if (suspicious_runner && suspicious_payload) {
        malicious = true;
        *reason_out = "میانبر فریبنده برای اجرای کد پنهان یا دانلود تروجان شناسایی شد.";
      }
    }
    persist->Release();
  }
  link->Release();
  return malicious;
}

bool ContainsDangerousUrlOrPayload(const std::string& lower_text) {
  static const char* kBadMarkers[] = {
      "eicar-standard-antivirus-test-file",
      "wscript.shell",
      "activexobject",
      "urldownloadtofile",
      "ms-msdt:",
      "search-ms:",
      "eval(atob(",
      "grabify.link",
      "iplogger.org",
      "iplogger.com",
      "2no.co",
      "blasze.com",
      "ezstat.ru",
  };
  for (const char* marker : kBadMarkers) {
    if (lower_text.find(marker) != std::string::npos) return true;
  }
  return false;
}

bool IsOfficialPngChunk(const char t[4]) {
  static const char* kPublic[] = {
      "IHDR", "PLTE", "IDAT", "IEND", "tRNS", "cHRM", "gAMA", "iCCP",
      "sBIT", "sRGB", "tEXt", "zTXt", "iTXt", "bKGD", "hIST", "pHYs",
      "sPLT", "tIME", "eXIf", "acTL", "fcTL", "fdAT", "oFFs", "pCAL",
      "sCAL", "sTER", "dSIG",
  };
  for (const char* item : kPublic) {
    if (std::memcmp(t, item, 4) == 0) return true;
  }
  // Standard PNG rule: uppercase 2nd letter = critical/public chunk, lowercase = private.
  return !(t[1] >= 'a' && t[1] <= 'z');
}

bool HasSafeMotionPhotoTrailer(const std::vector<BYTE>& tail) {
  if (ContainsBinderOrPayloadBytes(tail, 0)) return false;
  return ContainsAsciiBytesCi(tail, "ftypmp4") ||
         ContainsAsciiBytesCi(tail, "ftypisom") ||
         ContainsAsciiBytesCi(tail, "seft");
}

bool InspectImagePolyglotW(const std::wstring& path,
                           const std::string& lower_fn,
                           uint64_t fsize,
                           std::string* reason_out,
                           std::string* key_tag_out) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;

  BYTE hdr[16] = {0};
  DWORD hread = 0;
  if (ReadFile(file, hdr, 12, &hread, nullptr) == 0 || hread < 4) {
    CloseHandle(file);
    return false;
  }

  // 1. PNG Chunk Structure & Post-IEND Appended Payload Detection
  if (EndsWithCi(lower_fn, ".png") && hread >= 8 &&
      hdr[0] == 0x89 && hdr[1] == 0x50 && hdr[2] == 0x4E && hdr[3] == 0x47 &&
      hdr[4] == 0x0D && hdr[5] == 0x0A && hdr[6] == 0x1A && hdr[7] == 0x0A) {
    uint64_t offset = 8;
    uint64_t iend_eof = 0;
    while (offset + 12 <= fsize) {
      LARGE_INTEGER li = {};
      li.QuadPart = static_cast<LONGLONG>(offset);
      BYTE chdr[8] = {0};
      DWORD cread = 0;
      if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) == 0 ||
          ReadFile(file, chdr, 8, &cread, nullptr) == 0 || cread < 8) {
        break;
      }
      const uint32_t clen = (static_cast<uint32_t>(chdr[0]) << 24) |
                            (static_cast<uint32_t>(chdr[1]) << 16) |
                            (static_cast<uint32_t>(chdr[2]) << 8) |
                            static_cast<uint32_t>(chdr[3]);
      const char ctype[4] = {static_cast<char>(chdr[4]), static_cast<char>(chdr[5]),
                             static_cast<char>(chdr[6]), static_cast<char>(chdr[7])};
      if (clen > 64U * 1024U * 1024U || offset + 12ULL + clen > fsize) break;

      const bool inspect_chunk =
          std::memcmp(ctype, "tEXt", 4) == 0 ||
          std::memcmp(ctype, "zTXt", 4) == 0 ||
          std::memcmp(ctype, "iTXt", 4) == 0 ||
          !IsOfficialPngChunk(ctype);
      if (inspect_chunk && clen > 0) {
        const size_t cap = static_cast<size_t>(std::min<uint32_t>(clen, 512U * 1024U));
        std::vector<BYTE> cbuf(cap);
        DWORD d_read = 0;
        if (ReadFile(file, cbuf.data(), static_cast<DWORD>(cap), &d_read, nullptr) != 0 &&
            d_read > 0) {
          cbuf.resize(d_read);
          if (ContainsBinderOrPayloadBytes(cbuf, 0) ||
              (!IsOfficialPngChunk(ctype) && d_read >= 8192 &&
               ComputeShannonEntropy(cbuf.data(), d_read) >= 7.65)) {
            CloseHandle(file);
            *key_tag_out = "dl:png_chunk:";
            *reason_out = "پی لود یا فایل بایندشده درون چانک مخفی تصویر PNG شناسایی شد.";
            return true;
          }
        }
      }
      offset += 12ULL + clen;
      if (std::memcmp(ctype, "IEND", 4) == 0) {
        iend_eof = offset;
        break;
      }
    }
    if (iend_eof > 0 && fsize > iend_eof) {
      const size_t cap = static_cast<size_t>(
          std::min<uint64_t>(fsize - iend_eof, 2ULL * 1024ULL * 1024ULL));
      std::vector<BYTE> trailer(cap);
      LARGE_INTEGER li = {};
      li.QuadPart = static_cast<LONGLONG>(iend_eof);
      DWORD tread = 0;
      if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) != 0 &&
          ReadFile(file, trailer.data(), static_cast<DWORD>(cap), &tread, nullptr) != 0 &&
          tread > 0) {
        trailer.resize(tread);
        size_t first_nz = 0;
        while (first_nz < trailer.size() && trailer[first_nz] == 0) first_nz++;
        const size_t meaningful = trailer.size() - first_nz;
        if (meaningful >= 16) {
          if (ContainsBinderOrPayloadBytes(trailer, first_nz) ||
              (meaningful >= 512 &&
               ComputeShannonEntropy(trailer.data() + first_nz, meaningful) >= 7.35)) {
            CloseHandle(file);
            *key_tag_out = "dl:png_eof:";
            *reason_out = "فایل یا بدافزار بایندشده پس از پایان تصویر PNG (بعد از IEND) شناسایی شد.";
            return true;
          }
        }
      }
    }
    CloseHandle(file);
    return false;
  }

  // 2. JPEG Marker Structure Traversal (skips EXIF thumbnails) + Post-EOI Appended Payload
  if ((EndsWithCi(lower_fn, ".jpg") || EndsWithCi(lower_fn, ".jpeg")) &&
      hread >= 3 && hdr[0] == 0xFF && hdr[1] == 0xD8 && hdr[2] == 0xFF) {
    uint64_t pos = 2;
    bool hit_sos = false;
    while (pos + 4 <= fsize) {
      LARGE_INTEGER li = {};
      li.QuadPart = static_cast<LONGLONG>(pos);
      BYTE m[4] = {0};
      DWORD mread = 0;
      if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) == 0 ||
          ReadFile(file, m, 4, &mread, nullptr) == 0 || mread < 2) {
        break;
      }
      if (m[0] != 0xFF) break;
      BYTE marker = m[1];
      while (marker == 0xFF && pos + 2 < fsize) {
        pos++;
        li.QuadPart = static_cast<LONGLONG>(pos);
        if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) == 0 ||
            ReadFile(file, m, 4, &mread, nullptr) == 0 || mread < 2) {
          break;
        }
        marker = m[1];
      }
      if (marker == 0xD9 || marker == 0x00) break;
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        pos += 2;
        continue;
      }
      if (mread < 4) break;
      const uint16_t seg_len =
          (static_cast<uint16_t>(m[2]) << 8) | static_cast<uint16_t>(m[3]);
      if (seg_len < 2 || pos + 2 + seg_len > fsize) break;
      if (marker == 0xDA) {
        hit_sos = true;
        pos += 2 + seg_len;
        break;
      }
      if ((marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE) {
        const size_t seg_cap = std::min<size_t>(seg_len - 2, 131072);
        if (seg_cap >= 8) {
          std::vector<BYTE> seg(seg_cap);
          DWORD sread = 0;
          if (ReadFile(file, seg.data(), static_cast<DWORD>(seg_cap), &sread, nullptr) != 0 &&
              sread > 0) {
            seg.resize(sread);
            if (ContainsAsciiBytesCi(seg, "<script") ||
                ContainsAsciiBytesCi(seg, "basestart-") ||
                ContainsAsciiBytesCi(seg, "tvqqaam") ||
                ContainsAsciiBytesCi(seg, "frombase64string") ||
                ContainsAsciiBytesCi(seg, "powershell -enc") ||
                ContainsAsciiBytesCi(seg, "wscript.shell")) {
              CloseHandle(file);
              *key_tag_out = "dl:jpg_meta:";
              *reason_out = "کد یا پی لود تروجانی تزریق شده درون متادیتای تصویر JPEG شناسایی شد.";
              return true;
            }
          }
        }
      }
      pos += 2 + seg_len;
    }

    if (hit_sos && pos < fsize) {
      const uint64_t tail_window = std::min<uint64_t>(fsize - pos, 2ULL * 1024ULL * 1024ULL);
      const uint64_t scan_start = fsize - tail_window;
      std::vector<BYTE> tail(static_cast<size_t>(tail_window));
      LARGE_INTEGER li = {};
      li.QuadPart = static_cast<LONGLONG>(scan_start);
      DWORD tread = 0;
      if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) != 0 &&
          ReadFile(file, tail.data(), static_cast<DWORD>(tail.size()), &tread, nullptr) != 0 &&
          tread > 4) {
        tail.resize(tread);
        size_t last_eoi = std::string::npos;
        for (size_t i = tail.size() - 2; i > 0; --i) {
          if (tail[i] == 0xFF && tail[i + 1] == 0xD9) {
            last_eoi = i + 2;
            break;
          }
        }
        if (last_eoi != std::string::npos && last_eoi < tail.size()) {
          size_t first_nz = last_eoi;
          while (first_nz < tail.size() && tail[first_nz] == 0) first_nz++;
          const size_t extra = tail.size() - first_nz;
          if (extra >= 64) {
            std::vector<BYTE> appended(
                tail.begin() + static_cast<std::ptrdiff_t>(first_nz), tail.end());
            if (!HasSafeMotionPhotoTrailer(appended) &&
                (ContainsBinderOrPayloadBytes(appended, 0) ||
                 (extra >= 1024 &&
                  ComputeShannonEntropy(appended.data(), appended.size()) >= 7.45))) {
              CloseHandle(file);
              *key_tag_out = "dl:jpg_eoi:";
              *reason_out = "فایل یا بدافزار بایندشده پس از پایان تصویر JPEG (بعد از FFD9) شناسایی شد.";
              return true;
            }
          }
        }
      }
    }
    CloseHandle(file);
    return false;
  }

  // 3. BMP Header Declared-Size Mismatch (Appended Binder)
  if (EndsWithCi(lower_fn, ".bmp") && hread >= 6 &&
      hdr[0] == 'B' && hdr[1] == 'M') {
    const uint32_t declared =
        static_cast<uint32_t>(hdr[2]) |
        (static_cast<uint32_t>(hdr[3]) << 8) |
        (static_cast<uint32_t>(hdr[4]) << 16) |
        (static_cast<uint32_t>(hdr[5]) << 24);
    if (declared >= 54 && fsize > static_cast<uint64_t>(declared) + 64ULL) {
      const size_t cap = static_cast<size_t>(
          std::min<uint64_t>(fsize - declared, 2ULL * 1024ULL * 1024ULL));
      std::vector<BYTE> extra(cap);
      LARGE_INTEGER li = {};
      li.QuadPart = static_cast<LONGLONG>(declared);
      DWORD tread = 0;
      if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) != 0 &&
          ReadFile(file, extra.data(), static_cast<DWORD>(cap), &tread, nullptr) != 0 &&
          tread >= 64) {
        extra.resize(tread);
        if (ContainsBinderOrPayloadBytes(extra, 0) ||
            ComputeShannonEntropy(extra.data(), extra.size()) >= 7.35) {
          CloseHandle(file);
          *key_tag_out = "dl:bmp_eof:";
          *reason_out = "داده یا فایل اجرایی بایندشده در انتهای تصویر BMP شناسایی شد.";
          return true;
        }
      }
    }
  }

  // 4. GIF87a/89a Trailer Appended Payload Detection
  if (EndsWithCi(lower_fn, ".gif") && hread >= 6 &&
      hdr[0] == 'G' && hdr[1] == 'I' && hdr[2] == 'F' && hdr[3] == '8') {
    const uint64_t tail_window = std::min<uint64_t>(fsize, 1024ULL * 1024ULL);
    const uint64_t scan_start = fsize - tail_window;
    std::vector<BYTE> tail(static_cast<size_t>(tail_window));
    LARGE_INTEGER li = {};
    li.QuadPart = static_cast<LONGLONG>(scan_start);
    DWORD tread = 0;
    if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) != 0 &&
        ReadFile(file, tail.data(), static_cast<DWORD>(tail.size()), &tread, nullptr) != 0 &&
        tread > 8) {
      tail.resize(tread);
      size_t last_trailer = std::string::npos;
      for (size_t i = tail.size(); i > 0; --i) {
        if (tail[i - 1] == 0x3B) {
          last_trailer = i;
          break;
        }
      }
      if (last_trailer != std::string::npos && last_trailer + 64 <= tail.size()) {
        size_t first_nz = last_trailer;
        while (first_nz < tail.size() && tail[first_nz] == 0) first_nz++;
        const size_t extra = tail.size() - first_nz;
        if (extra >= 64) {
          std::vector<BYTE> appended(
              tail.begin() + static_cast<std::ptrdiff_t>(first_nz), tail.end());
          if (ContainsBinderOrPayloadBytes(appended, 0) ||
              (extra >= 1024 &&
               ComputeShannonEntropy(appended.data(), appended.size()) >= 7.45)) {
            CloseHandle(file);
            *key_tag_out = "dl:gif_eof:";
            *reason_out = "فایل یا بدافزار بایندشده در انتهای تصویر GIF شناسایی شد.";
            return true;
          }
        }
      }
    }
  }

  // 5. WebP RIFF Container Size Mismatch (Appended Binder)
  if (EndsWithCi(lower_fn, ".webp") && hread >= 12 &&
      hdr[0] == 'R' && hdr[1] == 'I' && hdr[2] == 'F' && hdr[3] == 'F' &&
      hdr[8] == 'W' && hdr[9] == 'E' && hdr[10] == 'B' && hdr[11] == 'P') {
    const uint64_t riff_payload_size =
        static_cast<uint64_t>(hdr[4]) |
        (static_cast<uint64_t>(hdr[5]) << 8) |
        (static_cast<uint64_t>(hdr[6]) << 16) |
        (static_cast<uint64_t>(hdr[7]) << 24);
    const uint64_t declared = 8ULL + riff_payload_size;
    if (riff_payload_size >= 12ULL && fsize > declared + 64ULL) {
      const size_t cap = static_cast<size_t>(
          std::min<uint64_t>(fsize - declared, 2ULL * 1024ULL * 1024ULL));
      std::vector<BYTE> extra(cap);
      LARGE_INTEGER li = {};
      li.QuadPart = static_cast<LONGLONG>(declared);
      DWORD tread = 0;
      if (SetFilePointerEx(file, li, nullptr, FILE_BEGIN) != 0 &&
          ReadFile(file, extra.data(), static_cast<DWORD>(cap), &tread, nullptr) != 0 &&
          tread >= 64) {
        extra.resize(tread);
        if (ContainsBinderOrPayloadBytes(extra, 0) ||
            ComputeShannonEntropy(extra.data(), extra.size()) >= 7.35) {
          CloseHandle(file);
          *key_tag_out = "dl:webp_eof:";
          *reason_out = "داده یا فایل اجرایی بایندشده در انتهای تصویر WebP شناسایی شد.";
          return true;
        }
      }
    }
  }

  CloseHandle(file);
  return false;
}

std::string NormalizeObfuscatedScript(const std::vector<BYTE>& bytes) {
  std::string stage1;
  stage1.reserve(bytes.size());
  for (unsigned char c : bytes) {
    if (c == 0 || c == '`' || c == '^') continue;
    if (c >= 32 && c <= 126) {
      stage1.push_back(static_cast<char>(std::tolower(c)));
    } else if (c == '\n' || c == '\r' || c == '\t') {
      stage1.push_back(' ');
    }
  }
  std::string out;
  out.reserve(stage1.size());
  for (size_t i = 0; i < stage1.size(); ++i) {
    char c = stage1[i];
    if (c == '\'' || c == '"') {
      if (i + 1 < stage1.size() && stage1[i + 1] == c) {
        i += 1;
        continue;
      }
      size_t j = i + 1;
      while (j < stage1.size() && stage1[j] == ' ') ++j;
      if (j < stage1.size() && (stage1[j] == '+' || stage1[j] == '&')) {
        size_t k = j + 1;
        while (k < stage1.size() && stage1[k] == ' ') ++k;
        if (k < stage1.size() && (stage1[k] == '\'' || stage1[k] == '"')) {
          i = k;
          continue;
        }
      }
    }
    out.push_back(c);
  }
  return out;
}

bool InspectPdfPayload(const std::vector<BYTE>& doc_bytes,
                       std::string* reason_out) {
  if (doc_bytes.size() < 8) return false;
  const bool has_js_or_launch =
      ContainsAsciiBytesCi(doc_bytes, "/js") ||
      ContainsAsciiBytesCi(doc_bytes, "/javascript") ||
      ContainsAsciiBytesCi(doc_bytes, "/launch");
  const bool has_auto_or_embed =
      ContainsAsciiBytesCi(doc_bytes, "/openaction") ||
      ContainsAsciiBytesCi(doc_bytes, "/aa ") ||
      ContainsAsciiBytesCi(doc_bytes, "/aa<<") ||
      ContainsAsciiBytesCi(doc_bytes, "/embeddedfile") ||
      ContainsAsciiBytesCi(doc_bytes, "/richmedia");
  if (has_js_or_launch && has_auto_or_embed) {
    *reason_out = "سند PDF حاوی اسکریپت یا فرمان خودکار اجرایی مخرب است.";
    return true;
  }
  const std::string tail_text = ToLowerAscii(std::string(
      reinterpret_cast<const char*>(doc_bytes.data()), doc_bytes.size()));
  const size_t last_eof = tail_text.rfind("%%eof");
  if (last_eof != std::string::npos && last_eof + 64 < doc_bytes.size()) {
    if (ContainsBinderOrPayloadBytes(doc_bytes, last_eof + 5)) {
      *reason_out = "فایل بایندشده یا کد اجرایی مخفی شده پس از پایان PDF شناسایی شد.";
      return true;
    }
  }
  return false;
}

bool ContainsElfHeaderAt(const std::vector<BYTE>& buf, size_t offset) {
  return offset + 4 <= buf.size() && buf[offset] == 0x7F &&
         buf[offset + 1] == 'E' && buf[offset + 2] == 'L' &&
         buf[offset + 3] == 'F';
}

bool ContainsDexHeaderAt(const std::vector<BYTE>& buf, size_t offset) {
  return offset + 6 <= buf.size() && buf[offset] == 'd' &&
         buf[offset + 1] == 'e' && buf[offset + 2] == 'x' &&
         buf[offset + 3] == '\n' && buf[offset + 4] == '0' &&
         buf[offset + 5] == '3';
}

bool IsDangerousArchiveEntryName(const std::string& lower_name,
                                 bool is_office_openxml) {
  if (lower_name.empty()) return false;
  if (HasDoubleMasqueradeExtension(lower_name)) return true;
  if (MatchKnownThreatText(lower_name).matched) return true;
  if (is_office_openxml && lower_name.find("vbaproject.bin") != std::string::npos) {
    return true;
  }
  static const char* kDangerArchiveExts[] = {
      ".exe", ".scr", ".pif", ".com", ".bat", ".cmd", ".vbs", ".vbe",
      ".js",  ".jse", ".wsf", ".wsh", ".ps1", ".hta", ".msi", ".lnk",
      ".dll", ".apk",
  };
  for (const char* ext : kDangerArchiveExts) {
    if (EndsWithCi(lower_name, ext)) return true;
  }
  return false;
}

bool InspectZipBufferForPayloads(const std::vector<BYTE>& buf,
                                 bool is_office_openxml,
                                 std::string* hit_entry_out) {
  // Scan PKZIP Local File Headers (PK\x03\x04) and Central Directory entries (PK\x01\x02)
  // directly inside the sampled buffer — zero external dependencies required.
  for (size_t i = 0; i + 46 < buf.size(); ++i) {
    if (buf[i] != 'P' || buf[i + 1] != 'K') continue;
    if (buf[i + 2] == 0x03 && buf[i + 3] == 0x04 && i + 30 < buf.size()) {
      const uint16_t name_len =
          static_cast<uint16_t>(buf[i + 26]) |
          (static_cast<uint16_t>(buf[i + 27]) << 8);
      if (name_len > 0 && name_len <= 512 && i + 30 + name_len <= buf.size()) {
        std::string entry_name(
            reinterpret_cast<const char*>(buf.data() + i + 30), name_len);
        const std::string lower_entry = ToLowerAscii(entry_name);
        if (IsDangerousArchiveEntryName(lower_entry, is_office_openxml)) {
          *hit_entry_out = entry_name;
          return true;
        }
      }
    } else if (buf[i + 2] == 0x01 && buf[i + 3] == 0x02 && i + 46 < buf.size()) {
      const uint16_t name_len =
          static_cast<uint16_t>(buf[i + 28]) |
          (static_cast<uint16_t>(buf[i + 29]) << 8);
      if (name_len > 0 && name_len <= 512 && i + 46 + name_len <= buf.size()) {
        std::string entry_name(
            reinterpret_cast<const char*>(buf.data() + i + 46), name_len);
        const std::string lower_entry = ToLowerAscii(entry_name);
        if (IsDangerousArchiveEntryName(lower_entry, is_office_openxml)) {
          *hit_entry_out = entry_name;
          return true;
        }
      }
    }
  }
  return false;
}

struct ScanDirSpec {
  std::wstring path;
  int max_depth = 3;
  int max_files = 800;
};

struct ScannedFileEntry {
  std::wstring path;
  std::wstring name;
  uint64_t size = 0;
  uint64_t write_time = 0;
};

std::vector<ScanDirSpec> CandidateScanDirectories(bool quick) {
  std::vector<ScanDirSpec> dirs;
  wchar_t temp[MAX_PATH * 2] = {0};
  if (GetTempPathW(MAX_PATH * 2, temp) > 0) {
    dirs.push_back(ScanDirSpec{std::wstring(temp), 1, quick ? 80 : 160});
  }
  PWSTR downloads = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Downloads, 0, nullptr, &downloads)) &&
      downloads != nullptr) {
    std::wstring dl(downloads);
    dirs.push_back(ScanDirSpec{dl, quick ? 1 : 3, quick ? 200 : 800});
    std::wstring tg_dl = dl + L"\\Telegram Desktop";
    if (DirectoryExistsW(tg_dl)) {
      dirs.push_back(ScanDirSpec{tg_dl, quick ? 1 : 3, quick ? 200 : 800});
    }
    CoTaskMemFree(downloads);
  }
  PWSTR desktop = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &desktop)) &&
      desktop != nullptr) {
    dirs.push_back(ScanDirSpec{std::wstring(desktop), quick ? 1 : 3, quick ? 200 : 800});
    CoTaskMemFree(desktop);
  }
  if (!quick) {
    PWSTR pictures = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Pictures, 0, nullptr, &pictures)) &&
        pictures != nullptr) {
      dirs.push_back(ScanDirSpec{std::wstring(pictures), 3, 800});
      CoTaskMemFree(pictures);
    }
    PWSTR videos = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Videos, 0, nullptr, &videos)) &&
        videos != nullptr) {
      dirs.push_back(ScanDirSpec{std::wstring(videos), 3, 800});
      CoTaskMemFree(videos);
    }
    PWSTR music = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Music, 0, nullptr, &music)) &&
        music != nullptr) {
      dirs.push_back(ScanDirSpec{std::wstring(music), 3, 800});
      CoTaskMemFree(music);
    }
    PWSTR documents = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &documents)) &&
        documents != nullptr) {
      dirs.push_back(ScanDirSpec{std::wstring(documents), 3, 800});
      CoTaskMemFree(documents);
    }
    PWSTR roaming = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &roaming)) &&
        roaming != nullptr) {
      dirs.push_back(ScanDirSpec{std::wstring(roaming), 1, 200});
      std::wstring tg_roaming = std::wstring(roaming) + L"\\Telegram Desktop";
      if (DirectoryExistsW(tg_roaming)) {
        dirs.push_back(ScanDirSpec{tg_roaming, 3, 800});
      }
      CoTaskMemFree(roaming);
    }
    PWSTR progdata = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_ProgramData, 0, nullptr, &progdata)) &&
        progdata != nullptr) {
      dirs.push_back(ScanDirSpec{std::wstring(progdata), 1, 150});
      CoTaskMemFree(progdata);
    }
  }
  PWSTR startup = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Startup, 0, nullptr, &startup)) &&
      startup != nullptr) {
    dirs.push_back(ScanDirSpec{std::wstring(startup), quick ? 2 : 3, quick ? 100 : 800});
    CoTaskMemFree(startup);
  }
  PWSTR common_startup = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_CommonStartup, 0, nullptr, &common_startup)) &&
      common_startup != nullptr) {
    dirs.push_back(ScanDirSpec{std::wstring(common_startup), quick ? 2 : 3, quick ? 100 : 800});
    CoTaskMemFree(common_startup);
  }
  return dirs;
}

bool ShouldSkipSubdirLower(const std::string& lower_dir_name) {
  return lower_dir_name == "." || lower_dir_name == ".." ||
         lower_dir_name == ".git" || lower_dir_name == "node_modules" ||
         lower_dir_name == "__pycache__";
}

void CollectFilesRecursiveBounded(
    const std::wstring& root_dir,
    int depth,
    int max_depth,
    int max_files,
    std::vector<ScannedFileEntry>* out) {
  if (static_cast<int>(out->size()) >= max_files || depth > max_depth) return;
  WIN32_FIND_DATAW fd = {};
  HANDLE find = FindFirstFileW((root_dir + L"\\*").c_str(), &fd);
  if (find == INVALID_HANDLE_VALUE) return;

  std::vector<std::wstring> subdirs;
  do {
    const std::wstring fname_w(fd.cFileName);
    if (fname_w == L"." || fname_w == L"..") continue;
    if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      if (depth < max_depth &&
          (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
        const std::string lower_sub = ToLowerAscii(ToUtf8(fname_w));
        if (!ShouldSkipSubdirLower(lower_sub)) {
          subdirs.push_back(root_dir + L"\\" + fname_w);
        }
      }
      continue;
    }
    ScannedFileEntry item;
    item.path = root_dir + L"\\" + fname_w;
    item.name = fname_w;
    item.size = (static_cast<uint64_t>(fd.nFileSizeHigh) << 32) |
                static_cast<uint64_t>(fd.nFileSizeLow);
    item.write_time = FileTimeToUint64(fd.ftLastWriteTime);
    out->push_back(std::move(item));
    if (static_cast<int>(out->size()) >= max_files) break;
  } while (FindNextFileW(find, &fd));
  FindClose(find);

  for (const auto& sub : subdirs) {
    if (static_cast<int>(out->size()) >= max_files) break;
    CollectFilesRecursiveBounded(sub, depth + 1, max_depth, max_files, out);
  }
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
  HRESULT com_hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool com_init = SUCCEEDED(com_hr);

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
  std::string result;
  if (GetOpenFileNameW(&ofn)) {
    result = ToUtf8(file_buf);
  }
  if (com_init) CoUninitialize();
  return result;
}

SecurityScanReport SecurityScanner::ScanDeviceSecurity(bool quick) {
  HRESULT com_hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool com_init = SUCCEEDED(com_hr);

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

  // 1. Running processes inspection (cached PE version metadata; skip Windows system binaries)
  const auto processes = SnapshotProcesses(true, win_dir, true);
  report.scanned_processes = static_cast<int>(processes.size());
  for (const auto& proc : processes) {
    if (IsUmbrellaSafeBinary(proc.path.empty() ? proc.name : proc.path)) continue;
    const std::string combined =
        proc.name + " " + proc.path + " " + proc.product_name + " " +
        proc.company_name + " " + proc.cmdline;
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

    // Live 2026 Fileless / ClickFix LOLBin execution monitor (command-line inspection via PEB)
    if (IsLolbinProcessName(proc.lower_name) &&
        IsSuspiciousLolbinCommandLine(proc.lower_name, proc.cmdline)) {
      SecurityThreatEntry item;
      item.key = "proc:lolbin:" + std::to_string(proc.pid);
      item.name = "اجرای فرمان پنهان یا بی فایل در حافظه (" + proc.name + ")";
      item.category = "malware";
      item.severity = "critical";
      item.target = !proc.path.empty() ? proc.path : proc.name;
      item.detail =
          "یک پردازش سیستمی (LOLBin) در حال اجرای فرمان رمزنگاری شده یا بارگذاری پی لود تروجانی در حافظه (الگوی ClickFix/RAT) است.";
      item.remediation_kind = "process";
      item.path = proc.path;
      item.process_name = proc.name;
      item.active = true;
      item.signed_valid = false;
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
        continue;
      }
    }

    // Live binary + AMSI inspection for active non-system unsigned processes outside Program Files
    if (!proc.path.empty() && !win_dir.empty()) {
      const std::string p_lower = ToLowerAscii(proc.path);
      const bool in_windows = p_lower.rfind(win_dir, 0) == 0;
      const bool in_program_files =
          p_lower.find(":\\program files\\") != std::string::npos ||
          p_lower.find(":\\program files (x86)\\") != std::string::npos;
      if (!in_windows && !in_program_files) {
        std::wstring wpath = ToWide(proc.path);
        uint64_t psize = 0;
        uint64_t pmtime = 0;
        if (GetFileStampW(wpath, &psize, &pmtime) &&
            !IsCleanFileCached(p_lower, psize, pmtime)) {
          int proc_amsi = 0;
          if (amsi.ScanFile(wpath, &proc_amsi)) {
            const std::string sha = ComputeFileSha256(wpath);
            SecurityThreatEntry item;
            item.key = !sha.empty() ? ("proc:amsi:" + sha.substr(0, 16))
                                    : ("proc:amsi:" + proc.lower_name);
            item.name = "بدافزار در حال اجرا (" + proc.name + ")";
            item.category = "malware";
            item.severity = "critical";
            item.target = proc.path;
            item.detail =
                "موتور امنیتی ویندوز (AMSI) فایل اجرایی این پردازش فعال را به عنوان بدافزار شناسایی کرد.";
            item.remediation_kind = "composite";
            item.path = proc.path;
            item.process_name = proc.name;
            item.sha256 = sha;
            item.active = true;
            item.signed_valid = false;
            add_finding(std::move(item));
            continue;
          }
          const PeHeuristicResult pe = AnalyzeFileHeuristics(wpath);
          if (pe.suspicious && !VerifyAuthenticodeSignature(wpath)) {
            const std::string sha = ComputeFileSha256(wpath);
            SecurityThreatEntry item;
            item.key = !sha.empty() ? ("proc:heur:" + sha.substr(0, 16))
                                    : ("proc:heur:" + proc.lower_name);
            item.name = pe.deterministic
                            ? ("بدافزار / تروجان فعال در حافظه (" + proc.name + ")")
                            : ("فرایند پرخطر در حال اجرا (" + proc.name + ")");
            item.category = "malware";
            item.severity = pe.deterministic ? "critical" : "high";
            item.target = proc.path;
            item.detail = pe.reason;
            item.remediation_kind = "composite";
            item.path = proc.path;
            item.process_name = proc.name;
            item.sha256 = sha;
            item.active = true;
            item.signed_valid = false;
            add_finding(std::move(item));
            continue;
          }
          RecordCleanFileCache(p_lower, psize, pmtime);
        }
      }
    }
  }

  // 2. Installed programs (Registry Uninstall)
  std::vector<RegistryAppRecord> reg_apps;
  EnumerateUninstallRoot(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", &reg_apps,
      quick);
  EnumerateUninstallRoot(
      HKEY_LOCAL_MACHINE,
      L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
      &reg_apps, quick);
  EnumerateUninstallRoot(
      HKEY_CURRENT_USER,
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", &reg_apps,
      quick);
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

  // 3B. ClickFix RunMRU forensic persistence & suspicious user Scheduled Tasks
  {
    HKEY mru_key = nullptr;
    const wchar_t* mru_path =
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\RunMRU";
    if (RegOpenKeyExW(HKEY_CURRENT_USER, mru_path, 0, KEY_READ, &mru_key) ==
        ERROR_SUCCESS) {
      DWORD idx = 0;
      wchar_t vname[128] = {0};
      DWORD vlen = 128;
      BYTE vdata[2048] = {0};
      DWORD dlen = sizeof(vdata);
      DWORD vtype = 0;
      while (RegEnumValueW(mru_key, idx++, vname, &vlen, nullptr, &vtype, vdata,
                           &dlen) == ERROR_SUCCESS) {
        if ((vtype == REG_SZ || vtype == REG_EXPAND_SZ) &&
            std::wcscmp(vname, L"MRUList") != 0) {
          const std::string cmd_str = ToUtf8(reinterpret_cast<wchar_t*>(vdata));
          const std::string cmd_l = ToLowerAscii(cmd_str);
          const bool clickfix_mru =
              !IsUmbrellaSafeBinary(cmd_l) &&
              (cmd_l.find("powershell") != std::string::npos ||
               cmd_l.find("pwsh") != std::string::npos ||
               cmd_l.find("mshta") != std::string::npos ||
               cmd_l.find("cmd ") != std::string::npos ||
               cmd_l.find("rundll32") != std::string::npos ||
               cmd_l.find("finger ") != std::string::npos) &&
              (cmd_l.find(" -enc") != std::string::npos ||
               cmd_l.find("encodedcommand") != std::string::npos ||
               cmd_l.find("frombase64string") != std::string::npos ||
               cmd_l.find("iex(") != std::string::npos ||
               cmd_l.find("invoke-expression") != std::string::npos ||
               cmd_l.find("invoke-restmethod") != std::string::npos ||
               cmd_l.find("irm ") != std::string::npos ||
               cmd_l.find("downloadstring") != std::string::npos ||
               cmd_l.find("http://") != std::string::npos ||
               cmd_l.find("https://") != std::string::npos);
          if (clickfix_mru) {
            const std::string vn = ToUtf8(vname);
            SecurityThreatEntry item;
            item.key = "reg_runmru:" + ToLowerAscii(vn);
            item.name = "فرمان مشکوک ClickFix در تاریخچه اجرای ویندوز";
            item.category = "malware";
            item.severity = "high";
            item.target = "HKCU\\...\\RunMRU\\" + vn;
            item.detail =
                "یک دستور پرخطر برای اجرای کد از طریق پنجره Run (الگوی ClickFix) در رجیستری ثبت شده است.";
            item.remediation_kind = "registry_run";
            item.registry_root = "HKCU";
            item.registry_path =
                "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\RunMRU";
            item.registry_value = vn;
            add_finding(std::move(item));
          }
        }
        vlen = 128;
        dlen = sizeof(vdata);
      }
      RegCloseKey(mru_key);
    }

    if (win_dir_w[0] != L'\0') {
      const std::wstring tasks_root = std::wstring(win_dir_w) + L"\\System32\\Tasks";
      std::vector<ScannedFileEntry> task_files;
      WIN32_FIND_DATAW fd = {};
      HANDLE find = FindFirstFileW((tasks_root + L"\\*").c_str(), &fd);
      if (find != INVALID_HANDLE_VALUE) {
        do {
          const std::wstring tn(fd.cFileName);
          if (tn == L"." || tn == L"..") continue;
          if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) continue;
          if (task_files.size() >= 120) break;
          task_files.push_back(ScannedFileEntry{
              tasks_root + L"\\" + tn, tn, 0, 0});
        } while (FindNextFileW(find, &fd));
        FindClose(find);
      }
      for (const auto& tf : task_files) {
        std::vector<BYTE> tbytes;
        if (!ReadFileSampleBytes(tf.path, 256 * 1024, &tbytes)) continue;
        // Task XMLs may be UTF-16LE or UTF-8; compact ASCII view catches both.
        std::string compact;
        compact.reserve(tbytes.size());
        for (BYTE b : tbytes) {
          if (b >= 32 && b <= 126) {
            compact.push_back(static_cast<char>(std::tolower(b)));
          }
        }
        if (IsUmbrellaSafeBinary(compact)) continue;
        const bool bad_task =
            ((compact.find("powershell") != std::string::npos &&
              (compact.find("-enc") != std::string::npos ||
               compact.find("frombase64string") != std::string::npos ||
               compact.find("downloadstring") != std::string::npos ||
               compact.find("invoke-expression") != std::string::npos)) ||
             compact.find("mshtahttp") != std::string::npos ||
             (compact.find("\\temp\\") != std::string::npos &&
              (compact.find(".vbs") != std::string::npos ||
               compact.find(".js") != std::string::npos ||
               compact.find(".ps1") != std::string::npos)));
        if (bad_task) {
          const std::string tfname = ToUtf8(tf.name);
          const std::string tfull = ToUtf8(tf.path);
          SecurityThreatEntry item;
          item.key = "task:" + ToLowerAscii(tfname);
          item.name = "وظیفه زمان بندی شده مخرب (" + tfname + ")";
          item.category = "malware";
          item.severity = "high";
          item.target = tfull;
          item.detail =
              "یک وظیفه زمان بندی شده برای اجرای خودکار اسکریپت یا فرمان مخفی در سیستم یافت شد.";
          item.remediation_kind = "file";
          item.path = tfull;
          item.process_name = tfname;
          add_finding(std::move(item));
        }
      }
    }
  }

  // 4. High-risk user directories scan (recursive bounded traversal across ALL extensions:
  //    executables, scripts, archives, images, audio, video, documents, and disguised files)
  std::unordered_set<std::string> visited_paths;
  for (const auto& dir_spec : CandidateScanDirectories(quick)) {
    std::vector<ScannedFileEntry> files;
    CollectFilesRecursiveBounded(dir_spec.path, 0, dir_spec.max_depth,
                                 dir_spec.max_files, &files);
    for (const auto& entry : files) {
      const std::wstring& wfull = entry.path;
      const std::wstring& fname_w = entry.name;
      const uint64_t fsize = entry.size;
      const uint64_t mtime = entry.write_time;
      const std::string fname = ToUtf8(fname_w);
      const std::string lower_fn = ToLowerAscii(fname);
      const std::string full = ToUtf8(wfull);
      if (IsUmbrellaSafeBinary(full)) {
        continue;
      }
      if (EndsWithCi(lower_fn, ".tmp") || EndsWithCi(lower_fn, ".crdownload") ||
          EndsWithCi(lower_fn, ".part")) {
        continue;
      }
      const std::string full_lower = ToLowerAscii(full);
      if (!visited_paths.insert(full_lower).second) continue;

      report.scanned_files++;
      if (IsCleanFileCached(full_lower, fsize, mtime)) {
        continue;
      }

      const bool is_exec = EndsWithCi(lower_fn, ".exe") ||
                           EndsWithCi(lower_fn, ".scr") ||
                           EndsWithCi(lower_fn, ".pif") ||
                           EndsWithCi(lower_fn, ".com") ||
                           EndsWithCi(lower_fn, ".bat") ||
                           EndsWithCi(lower_fn, ".cmd") ||
                           EndsWithCi(lower_fn, ".vbs") ||
                           EndsWithCi(lower_fn, ".vbe") ||
                           EndsWithCi(lower_fn, ".js") ||
                           EndsWithCi(lower_fn, ".jse") ||
                           EndsWithCi(lower_fn, ".wsf") ||
                           EndsWithCi(lower_fn, ".wsh") ||
                           EndsWithCi(lower_fn, ".ps1") ||
                           EndsWithCi(lower_fn, ".hta") ||
                           EndsWithCi(lower_fn, ".msi") ||
                           EndsWithCi(lower_fn, ".dll") ||
                           EndsWithCi(lower_fn, ".apk");
      const bool is_image = EndsWithCi(lower_fn, ".jpg") ||
                            EndsWithCi(lower_fn, ".jpeg") ||
                            EndsWithCi(lower_fn, ".png") ||
                            EndsWithCi(lower_fn, ".gif") ||
                            EndsWithCi(lower_fn, ".webp") ||
                            EndsWithCi(lower_fn, ".bmp") ||
                            EndsWithCi(lower_fn, ".svg") ||
                            EndsWithCi(lower_fn, ".ico");
      const bool is_media = EndsWithCi(lower_fn, ".mp4") ||
                            EndsWithCi(lower_fn, ".mkv") ||
                            EndsWithCi(lower_fn, ".avi") ||
                            EndsWithCi(lower_fn, ".mov") ||
                            EndsWithCi(lower_fn, ".webm") ||
                            EndsWithCi(lower_fn, ".mp3") ||
                            EndsWithCi(lower_fn, ".wav") ||
                            EndsWithCi(lower_fn, ".flac") ||
                            EndsWithCi(lower_fn, ".ogg") ||
                            EndsWithCi(lower_fn, ".m4a") ||
                            EndsWithCi(lower_fn, ".aac") ||
                            EndsWithCi(lower_fn, ".opus");
      const bool is_archive = EndsWithCi(lower_fn, ".zip") ||
                              EndsWithCi(lower_fn, ".rar") ||
                              EndsWithCi(lower_fn, ".7z") ||
                              EndsWithCi(lower_fn, ".tar") ||
                              EndsWithCi(lower_fn, ".gz") ||
                              EndsWithCi(lower_fn, ".iso") ||
                              EndsWithCi(lower_fn, ".img");
      const bool is_office = EndsWithCi(lower_fn, ".doc") ||
                             EndsWithCi(lower_fn, ".docx") ||
                             EndsWithCi(lower_fn, ".xls") ||
                             EndsWithCi(lower_fn, ".xlsx") ||
                             EndsWithCi(lower_fn, ".ppt") ||
                             EndsWithCi(lower_fn, ".pptx") ||
                             EndsWithCi(lower_fn, ".rtf");
      const bool is_link_or_doc = is_archive || is_office ||
                                  EndsWithCi(lower_fn, ".lnk") ||
                                  EndsWithCi(lower_fn, ".url") ||
                                  EndsWithCi(lower_fn, ".html") ||
                                  EndsWithCi(lower_fn, ".htm") ||
                                  EndsWithCi(lower_fn, ".pdf") ||
                                  EndsWithCi(lower_fn, ".txt") ||
                                  EndsWithCi(lower_fn, ".csv");

      const auto scan_file_clean = [&]() -> bool {
        // A. Unicode RLO / Double-Extension masquerade detection (e.g., photo.jpg.exe)
        if (HasRloSpoofCharW(fname_w) || HasDoubleMasqueradeExtension(lower_fn)) {
          const std::string sha = ComputeFileSha256(wfull);
          SecurityThreatEntry item;
          item.key = !sha.empty() ? ("dl:masq:" + sha.substr(0, 16))
                                  : ("dl:masq:" + lower_fn);
          item.name = "فایل تروجانی با نام فریبنده (" + fname + ")";
          item.category = "malicious_download";
          item.severity = "critical";
          item.target = full;
          item.detail =
              "این فایل با پسوند دوگانه یا تغییر جهت کاراکتر سعی در پنهان کردن فایل اجرایی به جای عکس یا سند دارد.";
          item.remediation_kind = "file";
          item.path = full;
          item.process_name = fname;
          item.sha256 = sha;
          add_finding(std::move(item));
          return false;
        }

        // B. Malicious Windows shortcut (.lnk) inspection
        if (EndsWithCi(lower_fn, ".lnk")) {
          std::string lnk_reason;
          if (InspectShortcutThreat(wfull, &lnk_reason)) {
            const std::string sha = ComputeFileSha256(wfull);
            SecurityThreatEntry item;
            item.key = !sha.empty() ? ("dl:lnk:" + sha.substr(0, 16))
                                    : ("dl:lnk:" + lower_fn);
            item.name = "میانبر تروجانی مخرب (" + fname + ")";
            item.category = "malicious_download";
            item.severity = "critical";
            item.target = full;
            item.detail = lnk_reason;
            item.remediation_kind = "file";
            item.path = full;
            item.process_name = fname;
            item.sha256 = sha;
            add_finding(std::move(item));
            return false;
          }
          return true;
        }

        // C. Downloaded images & polyglot / disguised malware detection
        if (is_image) {
          std::vector<BYTE> header_bytes;
          if (!ReadFileSampleBytes(wfull, 65536, &header_bytes)) {
            return false;
          }
          if (EndsWithCi(lower_fn, ".svg")) {
            std::vector<BYTE> img_bytes;
            if (!ReadFileSampleBytes(wfull, 2 * 1024 * 1024, &img_bytes)) {
              return false;
            }
            if (ContainsAsciiBytesCi(img_bytes, "<script") ||
                ContainsAsciiBytesCi(img_bytes, "onload=") ||
                ContainsAsciiBytesCi(img_bytes, "onerror=") ||
                ContainsAsciiBytesCi(img_bytes, "javascript:") ||
                ContainsAsciiBytesCi(img_bytes, "wscript.shell") ||
                ContainsAsciiBytesCi(img_bytes, "eicar-standard-antivirus-test-file")) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("dl:svg:" + sha.substr(0, 16))
                                      : ("dl:svg:" + lower_fn);
              item.name = "تصویر SVG حاوی کد تروجانی (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail = "فایل تصویر SVG حاوی اسکریپت یا کد مخرب است.";
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
            int amsi_svg = 0;
            if (amsi.ScanFile(wfull, &amsi_svg)) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("dl:amsi_img:" + sha.substr(0, 16))
                                      : ("dl:amsi_img:" + lower_fn);
              item.name = "تصویر بدافزاری شناسایی شده (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail =
                  "موتور امنیتی ویندوز (AMSI) این تصویر دانلودی را به عنوان بدافزار شناسایی کرد.";
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
            return true;
          }

          const bool valid_magic = HasValidImageMagic(lower_fn, header_bytes);
          if (valid_magic) {
            std::string poly_reason;
            std::string poly_tag;
            if (InspectImagePolyglotW(wfull, lower_fn, fsize, &poly_reason, &poly_tag)) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? (poly_tag + sha.substr(0, 16))
                                      : (poly_tag + lower_fn);
              item.name = "تصویر حاوی فایل یا بدافزار بایندشده (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail = poly_reason;
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
          }

          std::vector<BYTE> img_bytes;
          if (valid_magic && fsize > 768ULL * 1024ULL) {
            if (!ReadFileHeadAndTailBytes(wfull, 256 * 1024, 512 * 1024, &img_bytes)) {
              return false;
            }
          } else {
            if (!ReadFileSampleBytes(wfull, 2 * 1024 * 1024, &img_bytes)) {
              return false;
            }
          }

          if (!valid_magic &&
              (HasPeHeaderAt(img_bytes, 0) ||
               ContainsElfHeaderAt(img_bytes, 0) ||
               ContainsDexHeaderAt(img_bytes, 0) ||
               ContainsAsciiBytesCi(img_bytes, "<script") ||
               ContainsAsciiBytesCi(img_bytes, "wscript.shell") ||
               ContainsAsciiBytesCi(img_bytes, "activexobject") ||
               ContainsAsciiBytesCi(img_bytes, "powershell") ||
               ContainsAsciiBytesCi(img_bytes, "frombase64string") ||
               ContainsAsciiBytesCi(img_bytes, "basestart-") ||
               ContainsAsciiBytesCi(img_bytes, "eicar-standard-antivirus-test-file"))) {
            const std::string sha = ComputeFileSha256(wfull);
            SecurityThreatEntry item;
            item.key = !sha.empty() ? ("dl:fake_img:" + sha.substr(0, 16))
                                    : ("dl:fake_img:" + lower_fn);
            item.name = "بدافزار در پوشش تصویر (" + fname + ")";
            item.category = "malicious_download";
            item.severity = "critical";
            item.target = full;
            item.detail =
                "این فایل با نام تصویر ذخیره شده اما در واقع برنامه اجرایی یا اسکریپت مخرب است.";
            item.remediation_kind = "file";
            item.path = full;
            item.process_name = fname;
            item.sha256 = sha;
            add_finding(std::move(item));
            return false;
          }

          bool embedded_payload = false;
          for (size_t pos = 16; pos + 0x40 < img_bytes.size(); ++pos) {
            if ((img_bytes[pos] == 0x4D && img_bytes[pos + 1] == 0x5A &&
                 HasPeHeaderAt(img_bytes, pos)) ||
                ContainsElfHeaderAt(img_bytes, pos) ||
                ContainsDexHeaderAt(img_bytes, pos)) {
              embedded_payload = true;
              break;
            }
          }
          if (embedded_payload ||
              ContainsAsciiBytesCi(img_bytes, "eicar-standard-antivirus-test-file") ||
              ContainsAsciiBytesCi(img_bytes, "<script") ||
              ContainsAsciiBytesCi(img_bytes, "wscript.shell") ||
              ContainsAsciiBytesCi(img_bytes, "urldownloadtofile") ||
              ContainsAsciiBytesCi(img_bytes, "frombase64string") ||
              ContainsAsciiBytesCi(img_bytes, "basestart-") ||
              ContainsAsciiBytesCi(img_bytes, "tvqqaam") ||
              ContainsAsciiBytesCi(img_bytes, "powershell -enc")) {
            const std::string sha = ComputeFileSha256(wfull);
            SecurityThreatEntry item;
            item.key = !sha.empty() ? ("dl:poly_img:" + sha.substr(0, 16))
                                    : ("dl:poly_img:" + lower_fn);
            item.name = "تصویر آلوده به پی لود تروجانی (" + fname + ")";
            item.category = "malicious_download";
            item.severity = "critical";
            item.target = full;
            item.detail =
                "کد اجرایی یا اسکریپت مخرب پنهان شده در فایل تصویر شناسایی شد.";
            item.remediation_kind = "file";
            item.path = full;
            item.process_name = fname;
            item.sha256 = sha;
            add_finding(std::move(item));
            return false;
          }
          if (!valid_magic) {
            int amsi_img = 0;
            if (amsi.ScanFile(wfull, &amsi_img)) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("dl:amsi_img:" + sha.substr(0, 16))
                                      : ("dl:amsi_img:" + lower_fn);
              item.name = "تصویر بدافزاری شناسایی شده (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail =
                  "موتور امنیتی ویندوز (AMSI) این تصویر دانلودی را به عنوان بدافزار شناسایی کرد.";
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
          }
          return true;
        }

        // D. Downloaded audio/video media polyglot & disguised binary detection
        if (is_media) {
          std::vector<BYTE> media_bytes;
          const bool sampled = (fsize > 768ULL * 1024ULL)
              ? ReadFileHeadAndTailBytes(wfull, 256 * 1024, 512 * 1024, &media_bytes)
              : ReadFileSampleBytes(wfull, 768 * 1024, &media_bytes);
          if (!sampled) return false;
          const bool binary_header =
              HasPeHeaderAt(media_bytes, 0) ||
              ContainsElfHeaderAt(media_bytes, 0) ||
              ContainsDexHeaderAt(media_bytes, 0);
          bool media_threat =
              binary_header ||
              ContainsAsciiBytesCi(media_bytes, "eicar-standard-antivirus-test-file") ||
              ContainsAsciiBytesCi(media_bytes, "<script") ||
              ContainsAsciiBytesCi(media_bytes, "wscript.shell") ||
              ContainsAsciiBytesCi(media_bytes, "urldownloadtofile") ||
              ContainsAsciiBytesCi(media_bytes, "frombase64string") ||
              ContainsAsciiBytesCi(media_bytes, "basestart-") ||
              ContainsAsciiBytesCi(media_bytes, "tvqqaam") ||
              ContainsAsciiBytesCi(media_bytes, "powershell -enc");
          if (!media_threat) {
            for (size_t pos = 16; pos + 0x40 < media_bytes.size(); ++pos) {
              if ((media_bytes[pos] == 0x4D && media_bytes[pos + 1] == 0x5A &&
                   HasPeHeaderAt(media_bytes, pos)) ||
                  ContainsElfHeaderAt(media_bytes, pos) ||
                  ContainsDexHeaderAt(media_bytes, pos) ||
                  (pos + 7 <= media_bytes.size() && media_bytes[pos] == 'R' &&
                   media_bytes[pos + 1] == 'a' && media_bytes[pos + 2] == 'r' &&
                   media_bytes[pos + 3] == '!' && media_bytes[pos + 4] == 0x1A &&
                   media_bytes[pos + 5] == 0x07) ||
                  (pos + 6 <= media_bytes.size() && media_bytes[pos] == '7' &&
                   media_bytes[pos + 1] == 'z' && media_bytes[pos + 2] == 0xBC &&
                   media_bytes[pos + 3] == 0xAF && media_bytes[pos + 4] == 0x27 &&
                   media_bytes[pos + 5] == 0x1C)) {
                media_threat = true;
                break;
              }
            }
          }
          if (media_threat) {
            const std::string sha = ComputeFileSha256(wfull);
            SecurityThreatEntry item;
            item.key = !sha.empty() ? ("dl:media:" + sha.substr(0, 16))
                                    : ("dl:media:" + lower_fn);
            item.name = "فایل رسانه ای حاوی بدافزار (" + fname + ")";
            item.category = "malicious_download";
            item.severity = "critical";
            item.target = full;
            item.detail =
                "این فایل صوتی یا ویدیویی در واقع حاوی فایل اجرایی یا کد مخرب تروجانی است.";
            item.remediation_kind = "file";
            item.path = full;
            item.process_name = fname;
            item.sha256 = sha;
            add_finding(std::move(item));
            return false;
          }
          if (binary_header) {
            int amsi_media = 0;
            if (amsi.ScanFile(wfull, &amsi_media)) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("dl:amsi_media:" + sha.substr(0, 16))
                                      : ("dl:amsi_media:" + lower_fn);
              item.name = "فایل رسانه ای بدافزاری (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail =
                  "موتور امنیتی ویندوز (AMSI) این فایل صوتی/ویدیویی را به عنوان بدافزار شناسایی کرد.";
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
          }
          return true;
        }

        // E. Downloaded .url shortcuts, HTML, PDF, Office docs, and archives inspection
        if (is_link_or_doc) {
          std::vector<BYTE> doc_bytes;
          if (ReadFileSampleBytes(wfull, 4 * 1024 * 1024, &doc_bytes)) {
            if (EndsWithCi(lower_fn, ".url") || EndsWithCi(lower_fn, ".html") ||
                EndsWithCi(lower_fn, ".htm")) {
              std::string body_lower = ToLowerAscii(std::string(
                  reinterpret_cast<const char*>(doc_bytes.data()), doc_bytes.size()));
              if (ContainsDangerousUrlOrPayload(body_lower) ||
                  HasPeHeaderAt(doc_bytes, 0)) {
                const std::string sha = ComputeFileSha256(wfull);
                SecurityThreatEntry item;
                item.key = !sha.empty() ? ("dl:web:" + sha.substr(0, 16))
                                        : ("dl:web:" + lower_fn);
                item.name = "فایل لینک / صفحه تروجانی (" + fname + ")";
                item.category = "malicious_download";
                item.severity = "high";
                item.target = full;
                item.detail =
                    "این فایل لینک یا صفحه وب دانلودی حاوی نشانی یا اسکریپت تروجانی است.";
                item.remediation_kind = "file";
                item.path = full;
                item.process_name = fname;
                item.sha256 = sha;
                add_finding(std::move(item));
                return false;
              }
            } else {
              // Inspect ZIP / Office OpenXML entries + disguised PE/script payloads inside docs/archives.
              const bool check_zip = is_archive || is_office;
              std::string dangerous_entry;
              const bool has_bad_zip_entry =
                  check_zip &&
                  InspectZipBufferForPayloads(doc_bytes, is_office, &dangerous_entry);
              std::string pdf_reason;
              const bool bad_pdf =
                  EndsWithCi(lower_fn, ".pdf") &&
                  InspectPdfPayload(doc_bytes, &pdf_reason);
              bool embedded_pe = HasPeHeaderAt(doc_bytes, 0) ||
                                 ContainsElfHeaderAt(doc_bytes, 0);
              if (!embedded_pe && !is_archive) {
                for (size_t pos = 16; pos + 0x40 < doc_bytes.size(); ++pos) {
                  if (doc_bytes[pos] == 0x4D && doc_bytes[pos + 1] == 0x5A &&
                      HasPeHeaderAt(doc_bytes, pos)) {
                    embedded_pe = true;
                    break;
                  }
                }
              }
              if (has_bad_zip_entry || bad_pdf || embedded_pe ||
                  ContainsAsciiBytesCi(doc_bytes, "eicar-standard-antivirus-test-file") ||
                  ContainsAsciiBytesCi(doc_bytes, "wscript.shell") ||
                  ContainsAsciiBytesCi(doc_bytes, "urldownloadtofile") ||
                  ContainsAsciiBytesCi(doc_bytes, "frombase64string") ||
                  ContainsAsciiBytesCi(doc_bytes, "basestart-") ||
                  ContainsAsciiBytesCi(doc_bytes, "powershell -enc")) {
                const std::string sha = ComputeFileSha256(wfull);
                SecurityThreatEntry item;
                item.key = !sha.empty() ? ("dl:doc:" + sha.substr(0, 16))
                                        : ("dl:doc:" + lower_fn);
                item.name = has_bad_zip_entry
                                ? ("آرشیو / سند حاوی فایل مخرب (" + fname + ")")
                                : ("سند یا فایل دانلودی آلوده (" + fname + ")");
                item.category = "malicious_download";
                item.severity = "critical";
                item.target = full;
                item.detail = has_bad_zip_entry
                                  ? ("فایل خطرناک درون بسته یا سند یافت شد: " + dangerous_entry)
                                  : (bad_pdf ? pdf_reason
                                             : "پی لود اجرایی، اسکریپت مخرب یا امضای بدافزار درون فایل دانلود شده یافت شد.");
                item.remediation_kind = "file";
                item.path = full;
                item.process_name = fname;
                item.sha256 = sha;
                add_finding(std::move(item));
                return false;
              }
            }
          }
          if (!EndsWithCi(lower_fn, ".txt") && !EndsWithCi(lower_fn, ".csv")) {
            int amsi_doc = 0;
            if (amsi.ScanFile(wfull, &amsi_doc)) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("dl:amsi_doc:" + sha.substr(0, 16))
                                      : ("dl:amsi_doc:" + lower_fn);
              item.name = "سند یا فایل دانلودی آلوده (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail =
                  "موتور امنیتی ویندوز (AMSI) این فایل دانلود شده را به عنوان بدافزار شناسایی کرد.";
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
          }
          return true;
        }

        // F. Unknown / extensionless files: detect disguised PE/ELF/DEX, scripts, EICAR, or AMSI hits
        if (!is_exec) {
          std::vector<BYTE> unknown_bytes;
          if (ReadFileSampleBytes(wfull, 2 * 1024 * 1024, &unknown_bytes)) {
            if (HasPeHeaderAt(unknown_bytes, 0) ||
                ContainsElfHeaderAt(unknown_bytes, 0) ||
                ContainsDexHeaderAt(unknown_bytes, 0) ||
                ContainsAsciiBytesCi(unknown_bytes, "eicar-standard-antivirus-test-file") ||
                ContainsAsciiBytesCi(unknown_bytes, "wscript.shell") ||
                ContainsAsciiBytesCi(unknown_bytes, "powershell -enc")) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("dl:unk:" + sha.substr(0, 16))
                                      : ("dl:unk:" + lower_fn);
              item.name = "فایل ناشناس یا پنهان آلوده (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail =
                  "فایل بدون پسوند معتبر حاوی سرآیند اجرایی یا اسکریپت مخرب است.";
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
          }
          int amsi_unk = 0;
          if (amsi.ScanFile(wfull, &amsi_unk)) {
            const std::string sha = ComputeFileSha256(wfull);
            SecurityThreatEntry item;
            item.key = !sha.empty() ? ("dl:amsi_unk:" + sha.substr(0, 16))
                                    : ("dl:amsi_unk:" + lower_fn);
            item.name = "فایل بدافزاری شناسایی شده (" + fname + ")";
            item.category = "malicious_download";
            item.severity = "critical";
            item.target = full;
            item.detail =
                "موتور امنیتی ویندوز (AMSI) این فایل را به عنوان بدافزار شناسایی کرد.";
            item.remediation_kind = "file";
            item.path = full;
            item.process_name = fname;
            item.sha256 = sha;
            add_finding(std::move(item));
            return false;
          }
          return true;
        }

        // G. Executables & script installers in Downloads / Temp / Desktop
        const std::string product = ReadVersionStringW(wfull, L"ProductName");
        const std::string company = ReadVersionStringW(wfull, L"CompanyName");
        const SignatureHit sig =
            MatchKnownThreatText(fname + " " + full + " " + product + " " + company);
        if (sig.matched) {
          SecurityThreatEntry item;
          item.key = sig.family_key + ":file";
          item.name = sig.name;
          item.category = sig.category == "conflicting_vpn" ? "conflicting_vpn" : "malicious_download";
          item.severity = sig.severity;
          item.target = full;
          item.detail = sig.detail;
          item.remediation_kind = "file";
          item.path = full;
          item.process_name = fname;
          item.sha256 = ComputeFileSha256(wfull);
          item.signed_valid = VerifyAuthenticodeSignature(wfull);
          add_finding(std::move(item));
          return false;
        }

        int amsi_result = 0;
        if (amsi.ScanFile(wfull, &amsi_result)) {
          const std::string sha = ComputeFileSha256(wfull);
          SecurityThreatEntry item;
          item.key = !sha.empty() ? ("amsi:" + sha.substr(0, 16))
                                  : ("amsi:" + lower_fn);
          item.name = "بدافزار دانلودی شناسایی شده (" + fname + ")";
          item.category = "malicious_download";
          item.severity = "critical";
          item.target = full;
          item.detail =
              "موتور امنیتی ویندوز (AMSI) این فایل را به عنوان بدافزار شناسایی کرد.";
          item.remediation_kind = "file";
          item.path = full;
          item.process_name = fname;
          item.sha256 = sha;
          add_finding(std::move(item));
          return false;
        }

        if (!EndsWithCi(lower_fn, ".exe") && !EndsWithCi(lower_fn, ".dll") &&
            !EndsWithCi(lower_fn, ".msi") && !EndsWithCi(lower_fn, ".apk") &&
            !EndsWithCi(lower_fn, ".scr")) {
          std::vector<BYTE> script_bytes;
          if (ReadFileSampleBytes(wfull, 1024 * 1024, &script_bytes)) {
            const std::string norm_script =
                NormalizeObfuscatedScript(script_bytes);
            const bool obfuscated_dropper =
                (norm_script.find("frombase64string") != std::string::npos &&
                 (norm_script.find("invoke-expression") != std::string::npos ||
                  norm_script.find("iex(") != std::string::npos ||
                  norm_script.find("-bxor") != std::string::npos ||
                  norm_script.find("gzipstream") != std::string::npos)) ||
                (norm_script.find("wscript.shell") != std::string::npos &&
                 (norm_script.find("http://") != std::string::npos ||
                  norm_script.find("https://") != std::string::npos ||
                  norm_script.find("powershell") != std::string::npos ||
                  norm_script.find("urldownloadtofile") != std::string::npos)) ||
                norm_script.find("urldownloadtofile") != std::string::npos ||
                norm_script.find("eval(atob(") != std::string::npos ||
                norm_script.find("basestart-") != std::string::npos ||
                norm_script.find("tvqqaam") != std::string::npos ||
                norm_script.find("eicar-standard-antivirus-test-file") !=
                    std::string::npos;
            if (obfuscated_dropper) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("dl:script:" + sha.substr(0, 16))
                                      : ("dl:script:" + lower_fn);
              item.name = "اسکریپت تروجانی یا دراپر مخرب (" + fname + ")";
              item.category = "malicious_download";
              item.severity = "critical";
              item.target = full;
              item.detail =
                  "اسکریپت دانلود شده حاوی الگوی رمزگشایی پی لود، اجرای بی فایل یا دانلود تروجان است.";
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              add_finding(std::move(item));
              return false;
            }
          }
        }

        if (EndsWithCi(lower_fn, ".exe") || EndsWithCi(lower_fn, ".scr")) {
          const bool looks_official_setup =
              EndsWithCi(lower_fn, ".exe") &&
              !HasDoubleMasqueradeExtension(lower_fn) &&
              (lower_fn.rfind("umbrella-vpn-", 0) == 0 ||
               lower_fn.rfind("umbrellavpn", 0) == 0) &&
              lower_fn.find("setup") != std::string::npos &&
              lower_fn.find("crack") == std::string::npos &&
              lower_fn.find("patch") == std::string::npos &&
              lower_fn.find("keygen") == std::string::npos &&
              ToLowerAscii(company).find("armin") != std::string::npos;
          if (!looks_official_setup) {
            const PeHeuristicResult pe = AnalyzeFileHeuristics(wfull);
            if (pe.suspicious && !VerifyAuthenticodeSignature(wfull)) {
              const std::string sha = ComputeFileSha256(wfull);
              SecurityThreatEntry item;
              item.key = !sha.empty() ? ("heur:" + sha.substr(0, 16))
                                      : ("heur:" + lower_fn);
              item.name = pe.deterministic
                              ? ("بدافزار / تروجان شناسایی شده (" + fname + ")")
                              : ("فایل پرخطر غیرمعتبر (" + fname + ")");
              item.category = "malicious_download";
              item.severity = pe.deterministic ? "critical" : "high";
              item.target = full;
              item.detail = pe.reason;
              item.remediation_kind = "file";
              item.path = full;
              item.process_name = fname;
              item.sha256 = sha;
              item.signed_valid = false;
              add_finding(std::move(item));
              return false;
            }
          }
        }
        return true;
      };

      if (scan_file_clean()) {
        RecordCleanFileCache(full_lower, fsize, mtime);
      }
    }
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
  if (com_init) CoUninitialize();
  return report;
}

RemediationOutcome SecurityScanner::RemediateThreat(
    const SecurityThreatEntry& target) {
  RemediationOutcome out;
  bool took_action = false;

  if (target.key.rfind("proc:lolbin:", 0) == 0) {
    DWORD target_pid = 0;
    try {
      target_pid = static_cast<DWORD>(std::stoul(target.key.substr(12)));
    } catch (...) {
      target_pid = 0;
    }
    if (target_pid > 4) {
      HANDLE h = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, target_pid);
      if (h != nullptr) {
        if (TerminateProcess(h, 1)) {
          WaitForSingleObject(h, 2500);
          took_action = true;
        }
        CloseHandle(h);
      }
    }
  } else if (!target.process_name.empty() || !target.path.empty()) {
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
  InvalidateCleanFileCache(target.path);

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
