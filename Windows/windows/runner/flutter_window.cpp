#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kEndSessionTimerId = 0x554D4252;
constexpr UINT kEndSessionTimeoutMs = 4500;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation and layout cycles, so get the client area.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  session_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "ir.umbrella.app/session",
          &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Let the engine show the window once the first frame is ready unless
  // launched hidden (--autostart / --minimized), so the app never flashes an
  // empty surface or pops up during Windows startup.
  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  session_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::EndSession(HWND window) noexcept {
  if (ending_session_) {
    return;
  }
  ending_session_ = true;
  SetTimer(window, kEndSessionTimerId, kEndSessionTimeoutMs, nullptr);
  if (session_channel_) {
    session_channel_->InvokeMethod("endSession", nullptr);
  } else {
    PostQuitMessage(0);
  }
}

LRESULT FlutterWindow::MessageHandler(HWND window, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  // Handle Windows logoff/shutdown and installer Restart Manager promptly even
  // when hidden to the system tray (preventClose intercepting WM_CLOSE).
  if (message == WM_QUERYENDSESSION) {
    return TRUE;
  }
  if (message == WM_ENDSESSION) {
    if (wparam != 0) {
      EndSession(window);
    }
    return 0;
  }
  if (message == WM_TIMER && wparam == kEndSessionTimerId) {
    KillTimer(window, kEndSessionTimerId);
    PostQuitMessage(0);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(window, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(window, message, wparam, lparam);
}
