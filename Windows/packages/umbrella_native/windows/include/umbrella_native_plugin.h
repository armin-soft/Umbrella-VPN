// Public entry point of the umbrella_native Windows plugin.
//
// flutter generates `generated_plugin_registrant.cc` which includes this header
// from the plugin's public include directory and calls the function below. Keep
// the signature in sync with the definition in umbrella_native_plugin.cpp.
#ifndef UMBRELLA_NATIVE_PLUGIN_PUBLIC_H_
#define UMBRELLA_NATIVE_PLUGIN_PUBLIC_H_

#include <flutter/plugin_registrar_windows.h>

#ifdef __cplusplus
extern "C" {
#endif

__declspec(dllexport) void UmbrellaNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#ifdef __cplusplus
}
#endif

#endif  // UMBRELLA_NATIVE_PLUGIN_PUBLIC_H_
