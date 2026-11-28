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
  if (balloon_icon_ != nullptr) {
    DestroyIcon(balloon_icon_);
    balloon_icon_ = nullptr;
  }
  icon_ = nullptr;
}

bool TrayIcon::SetIconFromFile(const std::string& ico_path) {
  if (window_ == nullptr) return false;
  HICON icon = nullptr;
  HICON balloon = nullptr;
  if (!ico_path.empty()) {
    std::wstring path = ToWide(ico_path);
    icon = static_cast<HICON>(
        LoadImageW(nullptr, path.c_str(), IMAGE_ICON, 0, 0,
                   LR_LOADFROMFILE | LR_DEFAULTSIZE));
    balloon = static_cast<HICON>(
        LoadImageW(nullptr, path.c_str(), IMAGE_ICON, 32, 32, LR_LOADFROMFILE));
  }
  // No usable file (missing asset in a stripped install): take the icon that
  // is embedded in our own executable. This is what makes the tray icon show
  // the umbrella instead of the generic Windows application icon.
  if (icon == nullptr) {
    wchar_t exe[MAX_PATH] = {0};
    if (GetModuleFileNameW(nullptr, exe, MAX_PATH) == 0) return false;
    // First icon of our own executable: the small frame is 16x16 for the
    // tray, the big one is 32x32 for the balloon. (`large`/`small` cannot be
    // used as names: they are macros in rpcndr.h.)
    HICON big_frame = nullptr;
    HICON tray_frame = nullptr;
    if (ExtractIconExW(exe, 0, &big_frame, &tray_frame, 1) == 0) return false;
    icon = tray_frame != nullptr ? tray_frame : big_frame;
    balloon = big_frame != nullptr ? big_frame : tray_frame;
    if (icon == nullptr) return false;
  }
  if (owns_icon_ && icon_ != nullptr) {
    DestroyIcon(icon_);
    owns_icon_ = false;
  }
  if (balloon_icon_ != nullptr) {
    DestroyIcon(balloon_icon_);
    balloon_icon_ = nullptr;
  }
  icon_ = icon;
  balloon_icon_ = balloon;
  owns_icon_ = true;
  data_.hIcon = icon;
  // The window icon and the taskbar button use the same image, so the app has
  // one identity everywhere. It used to be whatever the runner embedded, which
  // in the installed build could be the generic Flutter icon.
  if (window_ != nullptr) {
    // Large frame for the taskbar/Alt-Tab, small frame for the title bar.
    SendMessageW(window_, WM_SETICON, ICON_BIG,
                 reinterpret_cast<LPARAM>(balloon != nullptr ? balloon : icon));
    SendMessageW(window_, WM_SETICON, ICON_SMALL,
                 reinterpret_cast<LPARAM>(icon));
  }
  // NIF_TIP too, so the hover text survives an icon change.
  data_.uFlags = NIF_ICON | NIF_TIP;
  return Shell_NotifyIconW(NIM_MODIFY, &data_) != FALSE;
}

bool TrayIcon::SetTooltip(const std::string& text) {
  if (!icon_added_) return false;
  std::wstring wide = ToWide(text);
  wcsncpy_s(data_.szTip, wide.c_str(), _TRUNCATE);
  // NIF_ICON too: a tooltip-only update would drop the tray icon.
  data_.uFlags = NIF_TIP | NIF_ICON;
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
  // Keep the icon and tooltip in this update: NIM_MODIFY replaces whatever
  // uFlags names, so a balloon-only update would blank the tray icon.
  data_.uFlags = NIF_INFO | NIF_ICON | NIF_TIP;
  // NIIF_USER makes Windows draw *our* icon in the balloon. Two traps used to
  // leave it empty:
  //   * NIIF_INFO (the "i" bubble) ignores hBalloonIcon entirely, so the app
  //     icon could never appear;
  //   * NIIF_USER without a valid 32x32 HICON draws nothing at all.
  // `LoadImageW(..., LR_DEFAULTSIZE)` returns the 32x32 frame the shell wants,
  // but if the .ico could not be read the tray icon is still IDI_APPLICATION.
  // In that case fall back to the plain information icon so the balloon is
  // never iconless.
  const bool have_app_icon = owns_icon_ && data_.hIcon != nullptr;
  if (have_app_icon) {
    // NIIF_USER must be paired with NIIF_LARGE_ICON and a 32x32 icon, which is
    // exactly what LoadImageW(LR_DEFAULTSIZE) returns. It cannot be ORed with
    // NIIF_INFO/NIIF_WARNING: those bits select a different icon shape.
    data_.dwInfoFlags = NIIF_USER | NIIF_LARGE_ICON;
    data_.hBalloonIcon =
        balloon_icon_ != nullptr ? balloon_icon_ : data_.hIcon;
  } else if (warning) {
    data_.dwInfoFlags = NIIF_WARNING;
    data_.hBalloonIcon = nullptr;
  } else {
    data_.dwInfoFlags = NIIF_INFO;
    data_.hBalloonIcon = nullptr;
  }
  wcsncpy_s(data_.szInfoTitle, ToWide(title).c_str(), _TRUNCATE);
  wcsncpy_s(data_.szInfo, ToWide(body).c_str(), _TRUNCATE);
  data_.uTimeout = 10000;
  const bool shown = Shell_NotifyIconW(NIM_MODIFY, &data_) != FALSE;
  // Leave the struct ready for the next icon or tooltip update.
  data_.uFlags = NIF_ICON | NIF_TIP;
  data_.dwInfoFlags = 0;
  data_.hBalloonIcon = nullptr;
  return shown;
}

void TrayIcon::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuShow, L"نمایش پنجره");
  SetMenuDefaultItem(menu, kMenuShow, FALSE);
  AppendMenuW(menu, MF_STRING, kMenuServers, L"صفحه اتصال");
  AppendMenuW(menu, MF_STRING, kMenuSettings, L"تنظیمات");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING | (connected_ ? MF_CHECKED : MF_UNCHECKED),
              kMenuToggle,
              connected_ ? disconnect_label_.c_str() : connect_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuQuit, L"خروج");

  POINT cursor;
  GetCursorPos(&cursor);
  SetForegroundWindow(window_);
  int command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_LAYOUTRTL,
      cursor.x, cursor.y, 0, window_, nullptr);
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
    if (event == NIN_SELECT || event == NIN_KEYSELECT ||
        event == WM_LBUTTONDBLCLK) {
      if (callback_ != nullptr) callback_("show");
    } else if (event == NIN_BALLOONUSERCLICK) {
      if (callback_ != nullptr) callback_("balloon_click");
    } else if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      ShowMenu();
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace umbrella
