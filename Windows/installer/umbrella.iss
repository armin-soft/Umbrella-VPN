; ---------------------------------------------------------------------------
; Umbrella VPN 1.0.4
; Windows 10 / 11 x64 only. Everything the operating system shows (setup text,
; app name, shortcuts, folder and exe name) is English; the application itself
; speaks Persian once it starts.
;
; Build it with: tools\build-installer.ps1
; Or open this file in Inno Setup 6 and press Compile (requires Inno 6.0+).
; ---------------------------------------------------------------------------

#define AppName "Umbrella VPN"
#define AppNameEn "Umbrella VPN"
#define AppVersion "1.0.4"
#define AppPublisher "Armin Soft"
#define AppExe "UmbrellaVPN.exe"
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
; The core ships inside the installer: tools\fetch-cores.ps1 puts the engine
; library and its dependency in cores\umbrella next to the build output, so the
; rule above carries them into {app}\cores\umbrella, where the launchers load
; them from. They stay in that folder on purpose: copying 109 MB twice would
; only make the installer bigger.
; ── فایل های اجرایی هسته، همین جا ساخته می شوند ──────────────────────────
; UmbrellaCli.exe، UmbrellaAdmin.exe و UmbrellaCoreEngine.exe لانچرهای خود ما
; هستند (native/umbrella_launcher.c) و همراه خروجی ساخت می آیند؛ قانون بالا
; آن ها را در {app} می ریزد. هسته در cores\umbrella می ماند:
;
;   UmbrellaCore.dll          — خود موتور (۱۰۹ مگابایت)، با نام آمبرلا.
;                               تغییر نامش بی خطر است چون لانچر ما کتابخانه را
;                               با مسیر بار می کند، نه با پیوند نام.
;   libcronet.dll             — کتابخانه وابسته هسته
;
; کپی دوباره این فایل ها در {app} فقط حجم فایل نصبی را دو برابر می کرد.

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
; The exe requires administrator rights (its manifest), so it must be started
; with the elevated token Setup already holds. Inno's postinstall entries run as
; the original, unelevated user by default, which fails with CreateProcess 740.
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent runascurrentuser

[UninstallRun]
; Only the rules this client created are removed, the rest of the firewall stays untouched.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""Get-NetFirewallRule -DisplayName 'Umbrella-*' | Remove-NetFirewallRule -ErrorAction SilentlyContinue"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveUmbrellaFirewallRules"

[Code]
// برنامه در حال اجرا با فایل های نصب قفل می کند؛ قبل از کپی، هر نسخه در حال
// اجرا و هسته های بازمانده بسته می شوند تا کاربر مجبور به تسک منیجر نشود.
procedure KillRunning();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM UmbrellaVPN.exe /T',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM umbrella_vpn.exe /T',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // هسته (پنجره CLI) و موتور گرافیکی هم بسته می شوند تا فایل در حال استفاده
  // نماند. هسته قدیمی نسخه های قبلی هم پاک می شود.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM UmbrellaCli.exe /T',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM UmbrellaCoreEngine.exe /T',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM HiddifyCli.exe /T',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(600);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillRunning();
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    KillRunning();
end;

[InstallDelete]
; نسخه های قبلی، پوشه هسته را با نام دیگری داشتند و کتابخانه را با نام دیگری
; می ریختند؛ فایل اجرایی کهنه بدون کتابخانه اش با 0xC0000135 باز نمی شد. حالا
; پوشه هسته و لانچرهای کهنه پاک می شوند تا فقط نسخه درست بماند.
Type: filesandordirs; Name: "{app}\cores\hiddify"
Type: filesandordirs; Name: "{app}\cores\umbrella"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\cores"
