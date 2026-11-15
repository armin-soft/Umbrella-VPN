#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kMutexName[] = L"Global\\UmbrellaVPN.Desktop.SingleInstance";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// A second launch must bring the running copy forward instead of starting a
// second tunnel: two cores racing for the same TUN adapter is the fastest way
// to break a user's network.
void FocusExistingWindow() {
  HWND existing = FindWindowW(kWindowClassName, nullptr);
  if (existing == nullptr) {
    return;
  }
  if (IsIconic(existing)) {
    ShowWindow(existing, SW_RESTORE);
  }
  SetForegroundWindow(existing);
  FLASHWINFO info = {sizeof(FLASHWINFO), existing, FLASHW_ALL, 3, 0};
  FlashWindowEx(&info);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
  if (mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    FocusExistingWindow();
    CloseHandle(mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // The shell identifies the app (window icon, taskbar icon and — the part
  // users noticed — the ballon's icon) by its AppUserModelID. Without one,
  // Windows groups the process under a generic host and the notification
  // falls back to an iconless balloon. It must match the ID the installer
  // writes into the shortcut's AppUserModelID property.
  ::SetCurrentProcessExplicitAppUserModelID(L"Umbrella.VPN.Desktop");

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(0, 0);
  Win32Window::Size size(1280, 820);
  // Persian title, same as the window title the app sets after start-up.
  if (!window.Create(L"\u0641\u06cc\u0644\u062a\u0631\u0634\u06a9\u0646 "
                    L"\u0622\u0645\u0628\u0631\u0644\u0627",
                    origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (mutex != nullptr) {
    ReleaseMutex(mutex);
    CloseHandle(mutex);
  }

  return EXIT_SUCCESS;
}
