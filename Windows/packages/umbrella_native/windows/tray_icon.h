#ifndef UMBRELLA_TRAY_ICON_H_
#define UMBRELLA_TRAY_ICON_H_

#include <windows.h>
#include <shellapi.h>

#include <functional>
#include <string>

namespace umbrella {

// A minimal Shell_NotifyIcon wrapper: one tray icon, a right click menu in
// Persian and balloon notifications. It owns a hidden window that receives the
// callback messages, so the Flutter runner loop can dispatch them.
class TrayIcon {
 public:
  using EventCallback = std::function<void(const std::string&)>;

  TrayIcon();
  ~TrayIcon();

  bool Create(EventCallback callback);
  void Destroy();

  bool SetIconFromFile(const std::string& ico_path);
  bool SetTooltip(const std::string& text);
  bool SetMenuLabels(const std::string& connect_label,
                     const std::string& disconnect_label,
                     bool connected);
  bool ShowBalloon(const std::string& title, const std::string& body,
                   bool warning);
  bool Available() const { return icon_added_; }

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam);
  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  void ShowMenu();

  HWND window_ = nullptr;
  HICON icon_ = nullptr;
  NOTIFYICONDATAW data_ = {};
  bool icon_added_ = false;
  EventCallback callback_;
  std::wstring connect_label_ = L"اتصال";
  std::wstring disconnect_label_ = L"قطع اتصال";
  bool connected_ = false;
};

}  // namespace umbrella

#endif  // UMBRELLA_TRAY_ICON_H_
