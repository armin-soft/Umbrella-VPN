; ---------------------------------------------------------------------------
; فیلترشکن آمبرلا - Umbrella VPN 1.0.0
; Windows 10 / 11 x64 only. The product name stays Persian, every installer
; message and every OS level string is English on purpose.
;
; Build it with: tools\build-installer.ps1
; Or open this file in Inno Setup 6 and press Compile (requires Inno 6.0+).
; ---------------------------------------------------------------------------

#define AppName "فیلترشکن آمبرلا"
#define AppNameEn "Umbrella VPN"
#define AppVersion "1.0.0"
#define AppPublisher "Armin Soft"
#define AppExe "umbrella_vpn.exe"
#define AppId "{{8F3D2C41-7B5E-4A19-9C6D-2E4F1A7B8C90}"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://user.umbrella-server.ir/
AppSupportURL=https://t.me/umbrella_support
AppUpdatesURL=https://user.umbrella-server.ir/
DefaultDirName={autopf}\Umbrella VPN
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=output
OutputBaseFilename=UmbrellaVPN-Setup-{#AppVersion}-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardImageFile=wizard-image.bmp
WizardSmallImageFile=wizard-small.bmp
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
DisableWelcomePage=no
CloseApplications=yes
RestartApplications=no
; Windows 10 (build 10240) is the oldest supported release, 11 is included.
MinVersion=10.0
; 64 bit only. The client refuses to start on 32 bit Windows.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Installing a VPN tunnel adapter and a firewall kill switch needs admin.
PrivilegesRequired=admin
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppNameEn} Setup
VersionInfoProductName={#AppNameEn}
VersionInfoProductVersion={#AppVersion}

[Languages]
; Installer language is English per the specification.
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "autostart"; Description: "Start {#AppNameEn} when Windows starts (minimised to the tray)"; GroupDescription: "Options:"; Flags: unchecked

[Files]
; Flutter release bundle: exe, flutter_windows.dll, plugin dll, data folder.
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Cores shipped with the installer (cores\bin is filled by tools\fetch-cores.ps1 at build time).
Source: "..\cores\*"; DestDir: "{app}\cores"; Flags: ignoreversion recursesubdirs createallsubdirs
; Optional Visual C++ runtime, put VC_redist.x64.exe in installer\redist to ship it.
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppNameEn}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "UmbrellaVPN"; ValueData: """{app}\{#AppExe}"" --minimized"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ runtime..."; Flags: waituntilterminated skipifsilent skipifdoesntexist
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Only the rules this client created are removed, the rest of the firewall stays untouched.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""Get-NetFirewallRule -DisplayName 'Umbrella-*' | Remove-NetFirewallRule -ErrorAction SilentlyContinue"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveUmbrellaFirewallRules"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\cores"
