#ifndef UMBRELLA_WINHTTP_CLIENT_H_
#define UMBRELLA_WINHTTP_CLIENT_H_

#include <cstdint>
#include <map>
#include <string>

namespace umbrella {

struct WinHttpRequestSpec {
  std::string method = "GET";
  std::string url;
  std::map<std::string, std::string> headers;
  std::string body;
  int timeout_ms = 15000;
  bool use_system_proxy = false;
};

struct WinHttpResponseData {
  bool ok = false;
  int status_code = 0;
  uint32_t win_error = 0;
  std::string content_type;
  std::string body;
  std::string error;
};

/// Performs an HTTPS/HTTP request through Windows native WinHTTP + Schannel.
///
/// Works across all 64-bit Windows 10 and Windows 11 builds, uses the OS trust
/// store (including automatic AuthRoot / AIA intermediate retrieval), enables
/// fast IPv6-to-IPv4 fallback, and negotiates TLS 1.3 or TLS 1.2 cleanly.
WinHttpResponseData PerformWinHttpRequest(const WinHttpRequestSpec& spec);

/// Resets the WinHTTP proxy configuration directly via Win32 API without
/// spawning an external netsh.exe process.
bool ResetWinHttpProxyFast();

}  // namespace umbrella

#endif  // UMBRELLA_WINHTTP_CLIENT_H_
