#include "tray_icon.h"

#include <cwchar>
#include <vector>

namespace umbrella {
namespace {

constexpr UINT kTrayMessage = WM_APP + 12;
constexpr wchar_t kWindowClass[] = L"UmbrellaTrayWindow";
constexpr int kMenuShow = 1001;
constexpr int kMenuToggle = 1002;
constexpr int kMenuSettings = 1003;
constexpr int kMenuQuit = 1004;
constexpr int kMenuServers = 1005;
constexpr UINT kIconId = 1;

std::wstring ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(size < 0 ? 0 : size), L'\0');
  if (size > 0) {
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), out.data(), size);
  }
  return out;
}

}  // namespace

TrayIcon::TrayIcon() = default;

TrayIcon::~TrayIcon() { Destroy(); }

bool TrayIcon::Create(EventCallback callback) {
  callback_ = std::move(callback);

  WNDCLASSEXW klass = {};
  klass.cbSize = sizeof(klass);
  klass.lpfnWndProc = &TrayIcon::WindowProc;
  klass.hInstance = GetModuleHandleW(nullptr);
  klass.lpszClassName = kWindowClass;
  RegisterClassExW(&klass);

  // A real (never shown) top level window instead of a message-only one: the
  // shell only delivers tray callbacks reliably to ordinary windows.
  window_ = CreateWindowExW(WS_EX_TOOLWINDOW, kWindowClass, L"Umbrella",
                            WS_POPUP, 0, 0, 0, 0, nullptr, nullptr,
                            GetModuleHandleW(nullptr), this);
  if (window_ == nullptr) return false;

  data_ = {};
  data_.cbSize = sizeof(data_);
  data_.hWnd = window_;
  data_.uID = kIconId;
  data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data_.uCallbackMessage = kTrayMessage;
  data_.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  icon_ = data_.hIcon;
  wcscpy_s(data_.szTip, L"فیلترشکن آمبرلا");

  icon_added_ = Shell_NotifyIconW(NIM_ADD, &data_) != FALSE;
  if (icon_added_) {
    data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data_);
  }
  return icon_added_;
}

void TrayIcon::Destroy() {
  if (icon_added_) {
    Shell_NotifyIconW(NIM_DELETE, &data_);
    icon_added_ = false;
  }
  if (window_ != nullptr) {
    DestroyWindow(window_);
    window_ = nullptr;
  }
  if (owns_icon_ && icon_ != nullptr) {
    DestroyIcon(icon_);
    owns_icon_ = false;
  }
  icon_ = nullptr;
}

bool TrayIcon::SetIconFromFile(const std::string& ico_path) {
  if (window_ == nullptr) return false;
  std::wstring path = ToWide(ico_path);
  HICON icon = static_cast<HICON>(
      LoadImageW(nullptr, path.c_str(), IMAGE_ICON, 0, 0,
                 LR_LOADFROMFILE | LR_DEFAULTSIZE));
  if (icon == nullptr) return false;
  if (owns_icon_ && icon_ != nullptr) {
    DestroyIcon(icon_);
    owns_icon_ = false;
  }
  icon_ = icon;
  owns_icon_ = true;
  data_.hIcon = icon;
  data_.uFlags = NIF_ICON;
  return Shell_NotifyIconW(NIM_MODIFY, &data_) != FALSE;
}

bool TrayIcon::SetTooltip(const std::string& text) {
  if (!icon_added_) return false;
  std::wstring wide = ToWide(text);
  wcsncpy_s(data_.szTip, wide.c_str(), _TRUNCATE);
  data_.uFlags = NIF_TIP;
  return Shell_NotifyIconW(NIM_MODIFY, &data_) != FALSE;
}

bool TrayIcon::SetMenuLabels(const std::string& connect_label,
                             const std::string& disconnect_label,
                             bool connected) {
  connect_label_ = ToWide(connect_label);
  disconnect_label_ = ToWide(disconnect_label);
  connected_ = connected;
  return true;
}

bool TrayIcon::ShowBalloon(const std::string& title, const std::string& body,
                           bool warning) {
  if (!icon_added_) return false;
  data_.uFlags = NIF_INFO;
  data_.dwInfoFlags = warning ? NIIF_WARNING : NIIF_USER;
  wcsncpy_s(data_.szInfoTitle, ToWide(title).c_str(), _TRUNCATE);
  wcsncpy_s(data_.szInfo, ToWide(body).c_str(), _TRUNCATE);
  data_.uTimeout = 10000;
  return Shell_NotifyIconW(NIM_MODIFY, &data_) != FALSE;
}

void TrayIcon::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuShow, L"نمایش پنجره");
  AppendMenuW(menu, MF_STRING, kMenuServers, L"سرورها");
  AppendMenuW(menu, MF_STRING, kMenuSettings, L"تنظیمات");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuToggle,
              connected_ ? disconnect_label_.c_str() : connect_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"خروج");

  POINT cursor;
  GetCursorPos(&cursor);
  SetForegroundWindow(window_);
  int command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, cursor.x, cursor.y,
      0, window_, nullptr);
  DestroyMenu(menu);

  if (callback_ == nullptr) return;
  switch (command) {
    case kMenuShow:
      callback_("show");
      break;
    case kMenuToggle:
      callback_("toggle");
      break;
    case kMenuServers:
      callback_("servers");
      break;
    case kMenuSettings:
      callback_("settings");
      break;
    case kMenuQuit:
      callback_("quit");
      break;
    default:
      break;
  }
}

LRESULT CALLBACK TrayIcon::WindowProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  if (message == WM_CREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    return 0;
  }
  auto* self = reinterpret_cast<TrayIcon*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (self == nullptr) return DefWindowProcW(window, message, wparam, lparam);
  return self->HandleMessage(window, message, wparam, lparam);
}

LRESULT TrayIcon::HandleMessage(HWND window, UINT message, WPARAM wparam,
                                LPARAM lparam) {
  if (message == kTrayMessage) {
    UINT event = LOWORD(lparam);
    if (event == WM_LBUTTONDBLCLK || event == NIN_BALLOONUSERCLICK) {
      if (callback_ != nullptr) callback_("show");
    } else if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      ShowMenu();
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace umbrella
