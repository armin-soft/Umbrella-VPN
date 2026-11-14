Place VC_redist.x64.exe here (Microsoft Visual C++ 2015-2022 Redistributable, x64)
to bundle it with the installer. Download:

  https://aka.ms/vs/17/release/vc_redist.x64.exe

The setup script installs it silently before launching the client. If this file
is missing the build still succeeds, the runtime is simply not bundled.
