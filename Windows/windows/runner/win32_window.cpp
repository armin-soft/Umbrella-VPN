#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <map>

#include "resource.h"

#pragma comment(lib, "dwmapi.lib")

namespace {

// Scaling helpers ---------------------------------------------------------

UINT GetDpiForWindowSafe(HWND hwnd) {
  typedef UINT(WINAPI * GetDpiForWindowFn)(HWND);
  HMODULE user32 = GetModuleHandleW(L"user32.dll");
  if (user32 != nullptr) {
    auto fn = reinterpret_cast<GetDpiForWindowFn>(
        GetProcAddress(user32, "GetDpiForWindow"));
    if (fn != nullptr) {
      return fn(hwnd);
    }
  }
  return 96;
}

void EnableDarkTitleBar(HWND hwnd) {
  // The client area paints its own title bar; this keeps the frame dark while
  // the window is being created.
  BOOL dark = TRUE;
  const DWORD kAttribute = 20;  // DWMWA_USE_IMMERSIVE_DARK_MODE
  DwmSetWindowAttribute(hwnd, kAttribute, &dark, sizeof(dark));
}

std::map<HWND, Win32Window*>& WindowRegistry() {
  static std::map<HWND, Win32Window*> registry;
  return registry;
}

}  // namespace

Win32Window::Win32Window() = default;

Win32Window::~Win32Window() {
  if (window_handle_ != nullptr) {
    DestroyWindow(window_handle_);
  }
}

size_t Win32Window::GetActiveWindowCount() { return WindowRegistry().size(); }

void Win32Window::SetOnTopLevelWindowCreatedCallback(
    OnTopLevelWindowCreated callback, LPARAM user_data) {
  (void)callback;
  (void)user_data;
}

bool Win32Window::Create(const std::wstring& title, const Point& origin,
                         const Size& size) {
  if (!RegisterWindowClass()) {
    return false;
  }

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND handle = CreateWindow(
      kWindowClassName, title.c_str(),
      WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, origin.x,
      origin.y, static_cast<int>(size.width * scale_factor),
      static_cast<int>(size.height * scale_factor), nullptr, nullptr,
      GetModuleHandle(nullptr), this);

  if (handle == nullptr) {
    return false;
  }
  window_handle_ = handle;
  EnableDarkTitleBar(window_handle_);

  // The Flutter view is created once the HWND exists, so the client area is
  // already valid when the controller measures it.
  if (!OnCreate()) {
    DestroyWindow(handle);
    window_handle_ = nullptr;
    return false;
  }

  UpdateWindow(window_handle_);
  return true;
}

bool Win32Window::RegisterWindowClass() {
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = kWindowClassName;
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.cbClsExtra = 0;
  window_class.cbWndExtra = 0;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hIcon =
      LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.hbrBackground = 0;
  window_class.lpszMenuName = nullptr;
  window_class.lpfnWndProc = WndProc;
  RegisterClass(&window_class);
  return true;
}

bool Win32Window::Show() {
  if (window_handle_ == nullptr) {
    return false;
  }
  ShowWindow(window_handle_, SW_SHOWNORMAL);
  UpdateWindow(window_handle_);
  return true;
}

bool Win32Window::OnCreate() { return true; }

void Win32Window::OnDestroy() {
  if (window_handle_ != nullptr) {
    WindowRegistry().erase(window_handle_);
  }
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::Close() {
  PostMessage(window_handle_, WM_CLOSE, 0, 0);
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();
  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);
  SetFocus(child_content_);
}

LRESULT Win32Window::MessageHandler(HWND window, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      WindowRegistry().erase(window);
      OnDestroy();
      return 0;
    case WM_CLOSE:
      if (quit_on_close_) {
        DestroyWindow(window);
      } else {
        ShowWindow(window, SW_HIDE);
      }
      return 0;
    case WM_DPICHANGED: {
      auto* new_rect = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(window, nullptr, new_rect->left, new_rect->top,
                   new_rect->right - new_rect->left,
                   new_rect->bottom - new_rect->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_SIZE: {
      if (child_content_ != nullptr) {
        RECT frame = GetClientArea();
        MoveWindow(child_content_, frame.left, frame.top,
                   frame.right - frame.left, frame.bottom - frame.top, true);
      }
      return 0;
    }
    case WM_GETMINMAXINFO: {
      // A sane minimum size for the dashboard layout.
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = 1080;
      info->ptMinTrackSize.y = 700;
      return 0;
    }
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT CALLBACK Win32Window::WndProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    auto* self = reinterpret_cast<Win32Window*>(create_struct->lpCreateParams);
    WindowRegistry()[window] = self;
    self->window_handle_ = window;
  }

  auto found = WindowRegistry().find(window);
  if (found != WindowRegistry().end()) {
    return found->second->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}
