#ifndef UMBRELLA_NATIVE_PLUGIN_H_
#define UMBRELLA_NATIVE_PLUGIN_H_

// The native helpers must come first: they pull in winsock2 before windows.h
// (which the flutter headers include transitively), otherwise the Winsock 1
// declarations clash with Winsock 2 and the plugin does not compile.
#include "system_ops.h"
#include "tray_icon.h"

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define UMBRELLA_PLUGIN_EXPORT __declspec(dllexport)
#else
#define UMBRELLA_PLUGIN_EXPORT __declspec(dllimport)
#endif

#include <memory>
#include <string>

namespace umbrella {

class UMBRELLA_PLUGIN_EXPORT UmbrellaNativePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  UmbrellaNativePlugin();
  ~UmbrellaNativePlugin() override;

  void SetupChannels(flutter::BinaryMessenger* messenger);

  /// جریان رویدادهای سینی سیستم را وصل یا جدا می کند.
  void AttachTraySink(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::string DataDirectory();
  void EmitTrayEvent(const std::string& event);

  SystemOps& ops_ = SystemOps::Instance();
  TrayIcon tray_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> tray_sink_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> tray_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::string data_dir_;
};

}  // namespace umbrella

extern "C" UMBRELLA_PLUGIN_EXPORT void UmbrellaNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // UMBRELLA_NATIVE_PLUGIN_H_
