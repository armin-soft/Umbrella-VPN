#include "winhttp_client.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <winhttp.h>

#include <algorithm>
#include <cctype>
#include <sstream>
#include <vector>

#pragma comment(lib, "winhttp.lib")

#ifndef WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2
#define WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 0x00000800
#endif

#ifndef WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3
#define WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3 0x00002000
#endif

#ifndef WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY
#define WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY 4
#endif

#ifndef WINHTTP_OPTION_IPV6_FAST_FALLBACK
#define WINHTTP_OPTION_IPV6_FAST_FALLBACK 117
#endif

namespace umbrella {
namespace {

constexpr size_t kMaxResponseBytes = 8 * 1024 * 1024;
constexpr wchar_t kDefaultUserAgent[] =
    L"Mozilla/5.0 (Windows NT 10.0; Win64; x64) UmbrellaVPN/1.0.1";

std::wstring Utf8ToWide(const std::string& input) {
  if (input.empty()) return std::wstring();
  const int len = MultiByteToWideChar(
      CP_UTF8, 0, input.data(), static_cast<int>(input.size()), nullptr, 0);
  if (len <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, input.data(), static_cast<int>(input.size()),
                      out.data(), len);
  return out;
}

std::string WideToUtf8(const std::wstring& input) {
  if (input.empty()) return std::string();
  const int len = WideCharToMultiByte(CP_UTF8, 0, input.data(),
                                      static_cast<int>(input.size()), nullptr,
                                      0, nullptr, nullptr);
  if (len <= 0) return std::string();
  std::string out(static_cast<size_t>(len), '\0');
  WideCharToMultiByte(CP_UTF8, 0, input.data(), static_cast<int>(input.size()),
                      out.data(), len, nullptr, nullptr);
  return out;
}

std::string AsciiLower(std::string value) {
  std::transform(
      value.begin(), value.end(), value.begin(),
      [](unsigned char ch) { return static_cast<char>(::tolower(ch)); });
  return value;
}

std::string SanitizeHeaderToken(const std::string& value) {
  std::string out;
  out.reserve(value.size());
  for (char ch : value) {
    if (ch != '\r' && ch != '\n' && ch != '\0') {
      out.push_back(ch);
    }
  }
  return out;
}

std::string DescribeWinHttpError(const char* stage, DWORD code) {
  std::ostringstream out;
  out << stage << " (" << code;
  switch (code) {
    case ERROR_WINHTTP_TIMEOUT:
      out << ": timeout";
      break;
    case ERROR_WINHTTP_NAME_NOT_RESOLVED:
      out << ": dns_failed";
      break;
    case ERROR_WINHTTP_CANNOT_CONNECT:
      out << ": cannot_connect";
      break;
    case ERROR_WINHTTP_CONNECTION_ERROR:
      out << ": connection_error";
      break;
    case ERROR_WINHTTP_SECURE_FAILURE:
      out << ": tls_failure";
      break;
    case ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED:
      out << ": client_cert_needed";
      break;
    case ERROR_WINHTTP_INVALID_URL:
      out << ": invalid_url";
      break;
    default:
      break;
  }
  out << ")";
  return out.str();
}

struct ScopedWinHttpHandle {
  HINTERNET handle = nullptr;
  explicit ScopedWinHttpHandle(HINTERNET h = nullptr) : handle(h) {}
  ~ScopedWinHttpHandle() {
    if (handle != nullptr) {
      WinHttpCloseHandle(handle);
    }
  }
  ScopedWinHttpHandle(const ScopedWinHttpHandle&) = delete;
  ScopedWinHttpHandle& operator=(const ScopedWinHttpHandle&) = delete;
  operator HINTERNET() const { return handle; }
  explicit operator bool() const { return handle != nullptr; }
};

void ApplyCurrentUserProxyFallback(HINTERNET session, HINTERNET request,
                                   const std::wstring& url,
                                   bool allow_autoproxy) {
  WINHTTP_CURRENT_USER_IE_PROXY_CONFIG ie_config = {};
  if (!WinHttpGetIEProxyConfigForCurrentUser(&ie_config)) {
    return;
  }

  WINHTTP_PROXY_INFO proxy_info = {};
  bool have_proxy = false;

  if (allow_autoproxy &&
      (ie_config.fAutoDetect || ie_config.lpszAutoConfigUrl != nullptr)) {
    WINHTTP_AUTOPROXY_OPTIONS auto_opts = {};
    if (ie_config.fAutoDetect) {
      auto_opts.dwFlags |= WINHTTP_AUTOPROXY_AUTO_DETECT;
      auto_opts.dwAutoDetectFlags =
          WINHTTP_AUTO_DETECT_TYPE_DHCP | WINHTTP_AUTO_DETECT_TYPE_DNS_A;
    }
    if (ie_config.lpszAutoConfigUrl != nullptr) {
      auto_opts.dwFlags |= WINHTTP_AUTOPROXY_CONFIG_URL;
      auto_opts.lpszAutoConfigUrl = ie_config.lpszAutoConfigUrl;
    }
    auto_opts.fAutoLogonIfChallenged = TRUE;
    if (WinHttpGetProxyForUrl(session, url.c_str(), &auto_opts, &proxy_info)) {
      have_proxy = true;
    }
  }

  if (!have_proxy && ie_config.lpszProxy != nullptr &&
      ie_config.lpszProxy[0] != L'\0') {
    proxy_info.dwAccessType = WINHTTP_ACCESS_TYPE_NAMED_PROXY;
    proxy_info.lpszProxy = ie_config.lpszProxy;
    proxy_info.lpszProxyBypass = ie_config.lpszProxyBypass;
    WinHttpSetOption(request, WINHTTP_OPTION_PROXY, &proxy_info,
                     sizeof(proxy_info));
  } else if (have_proxy) {
    WinHttpSetOption(request, WINHTTP_OPTION_PROXY, &proxy_info,
                     sizeof(proxy_info));
    if (proxy_info.lpszProxy != nullptr) GlobalFree(proxy_info.lpszProxy);
    if (proxy_info.lpszProxyBypass != nullptr) {
      GlobalFree(proxy_info.lpszProxyBypass);
    }
  }

  if (ie_config.lpszAutoConfigUrl != nullptr) {
    GlobalFree(ie_config.lpszAutoConfigUrl);
  }
  if (ie_config.lpszProxy != nullptr) {
    GlobalFree(ie_config.lpszProxy);
  }
  if (ie_config.lpszProxyBypass != nullptr) {
    GlobalFree(ie_config.lpszProxyBypass);
  }
}

std::wstring QueryStringHeader(HINTERNET request, DWORD info_level) {
  DWORD bytes = 0;
  WinHttpQueryHeaders(request, info_level, WINHTTP_HEADER_NAME_BY_INDEX,
                      WINHTTP_NO_OUTPUT_BUFFER, &bytes,
                      WINHTTP_NO_HEADER_INDEX);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || bytes < sizeof(wchar_t)) {
    return std::wstring();
  }
  std::wstring buffer(bytes / sizeof(wchar_t), L'\0');
  if (!WinHttpQueryHeaders(request, info_level, WINHTTP_HEADER_NAME_BY_INDEX,
                           buffer.data(), &bytes, WINHTTP_NO_HEADER_INDEX)) {
    return std::wstring();
  }
  const size_t chars = bytes / sizeof(wchar_t);
  buffer.resize(chars);
  while (!buffer.empty() && buffer.back() == L'\0') {
    buffer.pop_back();
  }
  return buffer;
}

}  // namespace

WinHttpResponseData PerformWinHttpRequest(const WinHttpRequestSpec& spec) {
  WinHttpResponseData result;

  const std::wstring wide_url = Utf8ToWide(spec.url);
  if (wide_url.empty()) {
    result.win_error = ERROR_WINHTTP_INVALID_URL;
    result.error = "empty_url";
    return result;
  }

  URL_COMPONENTS parts = {};
  parts.dwStructSize = sizeof(parts);
  parts.dwSchemeLength = static_cast<DWORD>(-1);
  parts.dwHostNameLength = static_cast<DWORD>(-1);
  parts.dwUrlPathLength = static_cast<DWORD>(-1);
  parts.dwExtraInfoLength = static_cast<DWORD>(-1);

  if (!WinHttpCrackUrl(wide_url.c_str(), static_cast<DWORD>(wide_url.size()), 0,
                       &parts)) {
    result.win_error = GetLastError();
    result.error = DescribeWinHttpError("crack_url", result.win_error);
    return result;
  }

  if (parts.nScheme != INTERNET_SCHEME_HTTPS &&
      parts.nScheme != INTERNET_SCHEME_HTTP) {
    result.win_error = ERROR_WINHTTP_UNRECOGNIZED_SCHEME;
    result.error = "unsupported_scheme";
    return result;
  }

  const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  std::wstring path_and_query;
  if (parts.lpszUrlPath != nullptr && parts.dwUrlPathLength > 0) {
    path_and_query.append(parts.lpszUrlPath, parts.dwUrlPathLength);
  } else {
    path_and_query.push_back(L'/');
  }
  if (parts.lpszExtraInfo != nullptr && parts.dwExtraInfoLength > 0) {
    path_and_query.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
  }

  std::wstring user_agent = kDefaultUserAgent;
  std::wstring extra_headers;
  for (const auto& kv : spec.headers) {
    const std::string clean_key = SanitizeHeaderToken(kv.first);
    const std::string clean_val = SanitizeHeaderToken(kv.second);
    if (clean_key.empty()) continue;
    if (AsciiLower(clean_key) == "user-agent") {
      if (!clean_val.empty()) {
        user_agent = Utf8ToWide(clean_val);
      }
      continue;
    }
    extra_headers.append(Utf8ToWide(clean_key));
    extra_headers.append(L": ");
    extra_headers.append(Utf8ToWide(clean_val));
    extra_headers.append(L"\r\n");
  }

  bool need_manual_ie_proxy = false;
  DWORD access_type = spec.use_system_proxy
                          ? WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY
                          : WINHTTP_ACCESS_TYPE_NO_PROXY;
  HINTERNET raw_session =
      WinHttpOpen(user_agent.c_str(), access_type, WINHTTP_NO_PROXY_NAME,
                  WINHTTP_NO_PROXY_BYPASS, 0);
  if (raw_session == nullptr && spec.use_system_proxy) {
    raw_session =
        WinHttpOpen(user_agent.c_str(), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    need_manual_ie_proxy = true;
  }
  ScopedWinHttpHandle session(raw_session);
  if (!session) {
    result.win_error = GetLastError();
    result.error = DescribeWinHttpError("open_session", result.win_error);
    return result;
  }

  const int total_ms = std::clamp(spec.timeout_ms, 3000, 60000);
  const int resolve_ms = std::min(total_ms, 8000);
  const int connect_ms = std::min(total_ms, 10000);
  const int send_ms = std::min(total_ms, 12000);
  WinHttpSetTimeouts(session, resolve_ms, connect_ms, send_ms, total_ms);

  // Prefer TLS 1.2 + TLS 1.3; gracefully fall back to TLS 1.2 on older 64-bit
  // Windows 10 releases whose Schannel stack predates TLS 1.3.
  DWORD tls_protocols =
      WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
  if (!WinHttpSetOption(session, WINHTTP_OPTION_SECURE_PROTOCOLS,
                        &tls_protocols, sizeof(tls_protocols))) {
    DWORD tls12_only = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2;
    WinHttpSetOption(session, WINHTTP_OPTION_SECURE_PROTOCOLS, &tls12_only,
                     sizeof(tls12_only));
  }

  // Happy Eyeballs: fall back rapidly to IPv4 when ISP IPv6 routing is broken.
  BOOL ipv6_fast_fallback = TRUE;
  WinHttpSetOption(session, WINHTTP_OPTION_IPV6_FAST_FALLBACK,
                   &ipv6_fast_fallback, sizeof(ipv6_fast_fallback));

#ifdef WINHTTP_OPTION_DECOMPRESSION
  DWORD decompression = WINHTTP_DECOMPRESSION_FLAG_ALL;
  WinHttpSetOption(session, WINHTTP_OPTION_DECOMPRESSION, &decompression,
                   sizeof(decompression));
#endif

  ScopedWinHttpHandle connection(
      WinHttpConnect(session, host.c_str(), parts.nPort, 0));
  if (!connection) {
    result.win_error = GetLastError();
    result.error = DescribeWinHttpError("connect", result.win_error);
    return result;
  }

  const std::wstring method =
      Utf8ToWide(spec.method.empty() ? "GET" : spec.method);
  const DWORD req_flags = (parts.nScheme == INTERNET_SCHEME_HTTPS)
                              ? (WINHTTP_FLAG_SECURE | WINHTTP_FLAG_REFRESH)
                              : WINHTTP_FLAG_REFRESH;

  ScopedWinHttpHandle request(WinHttpOpenRequest(
      connection, method.c_str(), path_and_query.c_str(), nullptr,
      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, req_flags));
  if (!request) {
    result.win_error = GetLastError();
    result.error = DescribeWinHttpError("open_request", result.win_error);
    return result;
  }

  DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP;
  WinHttpSetOption(request, WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy,
                   sizeof(redirect_policy));

  // If the system has WinHttpAutoProxySvc disabled, still honor the user's
  // active Windows Internet Settings proxy when proxy mode was requested.
  if (spec.use_system_proxy) {
    ApplyCurrentUserProxyFallback(session, request, wide_url,
                                  need_manual_ie_proxy);
  }

  if (!extra_headers.empty()) {
    WinHttpAddRequestHeaders(
        request, extra_headers.c_str(),
        static_cast<DWORD>(extra_headers.size()),
        WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
  }

  const DWORD body_size = static_cast<DWORD>(spec.body.size());
  LPVOID body_ptr = body_size > 0
                        ? const_cast<char*>(spec.body.data())
                        : WINHTTP_NO_REQUEST_DATA;

  if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, body_ptr,
                          body_size, body_size, 0)) {
    result.win_error = GetLastError();
    result.error = DescribeWinHttpError("send_request", result.win_error);
    return result;
  }

  if (!WinHttpReceiveResponse(request, nullptr)) {
    result.win_error = GetLastError();
    result.error = DescribeWinHttpError("receive_response", result.win_error);
    return result;
  }

  DWORD status_code = 0;
  DWORD status_size = sizeof(status_code);
  if (!WinHttpQueryHeaders(
          request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
          WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size,
          WINHTTP_NO_HEADER_INDEX)) {
    result.win_error = GetLastError();
    result.error = DescribeWinHttpError("query_status", result.win_error);
    return result;
  }

  result.content_type =
      WideToUtf8(QueryStringHeader(request, WINHTTP_QUERY_CONTENT_TYPE));

  std::string body;
  std::vector<char> chunk;
  for (;;) {
    DWORD available = 0;
    if (!WinHttpQueryDataAvailable(request, &available)) {
      result.win_error = GetLastError();
      result.error = DescribeWinHttpError("query_data", result.win_error);
      return result;
    }
    if (available == 0) break;
    if (body.size() + available > kMaxResponseBytes) {
      result.win_error = ERROR_FILE_TOO_LARGE;
      result.error = "response_too_large";
      return result;
    }
    chunk.resize(available);
    DWORD read = 0;
    if (!WinHttpReadData(request, chunk.data(), available, &read)) {
      result.win_error = GetLastError();
      result.error = DescribeWinHttpError("read_data", result.win_error);
      return result;
    }
    if (read == 0) break;
    body.append(chunk.data(), read);
  }

  result.ok = true;
  result.status_code = static_cast<int>(status_code);
  result.body = std::move(body);
  return result;
}

bool ResetWinHttpProxyFast() {
  WINHTTP_PROXY_INFO info = {};
  info.dwAccessType = WINHTTP_ACCESS_TYPE_NO_PROXY;
  info.lpszProxy = WINHTTP_NO_PROXY_NAME;
  info.lpszProxyBypass = WINHTTP_NO_PROXY_BYPASS;
  return WinHttpSetDefaultProxyConfiguration(&info) != FALSE;
}

}  // namespace umbrella
