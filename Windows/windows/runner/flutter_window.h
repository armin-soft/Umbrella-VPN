#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void EndSession(HWND window) noexcept;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Notifies Dart on WM_ENDSESSION (Windows shutdown/logoff or installer
  // Restart Manager) so VPN/CLI core and tray shut down cleanly even when the
  // window is hidden to tray.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      session_channel_;
  bool ending_session_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
