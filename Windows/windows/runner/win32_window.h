#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// extended from but to have minimal scaffolding.
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  static constexpr const wchar_t kWindowClassName[] =
      L"FLUTTER_RUNNER_WIN32_WINDOW";

  // The number of Win32Window objects that currently exist.
  static size_t GetActiveWindowCount();

  // Registers a top level window factory. This is called whenever a window is
  // created, so plugins can hook into the top level window.
  using OnTopLevelWindowCreated =
      std::function<void(HWND window, LPARAM user_data)>;

  static void SetOnTopLevelWindowCreatedCallback(
      OnTopLevelWindowCreated callback, LPARAM user_data);

  // Creates the window and returns true on success. The size is in physical
  // pixels.
  bool Create(const std::wstring& title, const Point& origin,
              const Size& size);

  bool Show();
  void SetQuitOnClose(bool quit_on_close);
  RECT GetClientArea();
  HWND GetHandle() { return window_handle_; }
  void Close();

 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();

  // Processes and routes all window messages.
  virtual LRESULT MessageHandler(HWND window, UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  void SetChildContent(HWND content);

  // The backing HWND.
  HWND window_handle_ = nullptr;

 private:
  struct WindowClassRegistrar;

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);

  bool RegisterWindowClass();

  bool quit_on_close_ = false;
  HWND child_content_ = nullptr;
  RECT window_rect_ = {0, 0, 0, 0};
};

#endif  // RUNNER_WIN32_WINDOW_H_
