; ---------------------------------------------------------------------------
; Umbrella VPN 1.0.4
; Windows 10 / 11 x64 only. Everything the operating system shows (setup text,
; app name, shortcuts, folder and exe name) is English; the application itself
; speaks Persian once it starts.
;
; Open this file in Inno Setup 6 and press Compile (requires Inno 6.0+).
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
AppUpdatesURL=https://github.com/armin-soft/Umbrella-VPN-Releases/releases
DefaultDirName={autopf}\Umbrella VPN
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=output
OutputBaseFilename=UmbrellaVPN-Setup-{#AppVersion}-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardImageAlphaFormat=defined
WizardImageFile=wizard-image.bmp,wizard-image-200.bmp
WizardSmallImageFile=wizard-small.bmp,wizard-small-150.bmp,wizard-small-200.bmp,wizard-small-250.bmp
Compression=lzma2/fast
SolidCompression=no
WizardStyle=modern
DisableProgramGroupPage=yes
DisableWelcomePage=no
; Do not set AppMutex here: Inno checks AppMutex before PrepareToInstall and
; shows a blocking "please close all instances" dialog (or aborts silent updates
; with exit code 5). Instead we gracefully shut down and clean up all running
; Umbrella VPN and core processes automatically in InitializeSetup/PrepareToInstall
; and InitializeUninstall, backed up by Restart Manager force-close.
CloseApplications=force
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no
#ifdef SignTool
SignTool=signtool
SignedUninstaller=yes
#endif
; Windows 10 (build 10240) is the oldest supported release, 11 is included.
MinVersion=10.0
; All 64-bit Windows 10 and Windows 11 editions (x64 and x64-capable 64-bit).
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
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
; The core must be prepared manually: put the engine library and its
; dependency in cores\umbrella inside the release bundle, so the
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
; AppUserModelID links the shortcut to the process, so Windows keeps the app's
; own icon in the taskbar, the Alt-Tab list and notification balloons. It must
; stay identical to the value in windows/runner/main.cpp; without it the shell
; groups the app under a generic host and draws an iconless notification.
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\{#AppExe}"; AppUserModelID: "Umbrella.VPN.Desktop"
Name: "{group}\Uninstall {#AppNameEn}"; Filename: "{uninstallexe}"; IconFilename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\{#AppExe}"; AppUserModelID: "Umbrella.VPN.Desktop"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "UmbrellaVPN"; ValueData: """{app}\{#AppExe}"" --minimized"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ runtime..."; Flags: waituntilterminated skipifsilent skipifdoesntexist
; The exe requires administrator rights (its manifest), so it must be started
; with the elevated token Setup already holds. Inno's postinstall entries run as
; the original, unelevated user by default, which fails with CreateProcess 740.
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent runascurrentuser
; When launched from the in-app updater (/SILENT /RelaunchAfterUpdate=1),
; automatically reopen the freshly upgraded application once copying finishes.
Filename: "{app}\{#AppExe}"; Flags: nowait skipifnotsilent runascurrentuser; Check: ShouldRelaunchAfterUpdate

[UninstallRun]
; Only the rules this client created are removed, the rest of the firewall stays untouched.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -Command ""Get-NetFirewallRule -DisplayName 'Umbrella-*' | Remove-NetFirewallRule -ErrorAction SilentlyContinue"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveUmbrellaFirewallRules"

[Code]
const
  UmbrellaAppMutex = 'Global\UmbrellaVPN.Desktop.SingleInstance';

function ShouldRelaunchAfterUpdate(): Boolean;
begin
  Result := ExpandConstant('{param:RelaunchAfterUpdate|0}') = '1';
end;

// علامت نقل قول تکی برای PowerShell: در رشته نقل قول شده، علامت نقل قول تکی
// با دو تا از خودش جایگزین می شود. بدون این کار، پوشه نصبی که اسم آن علامت
// نقل قول دارد (مثل D:\Reza's VPN) دستور را می شکند.
function PsQuote(const Value: String): String;
var
  I: Integer;
begin
  Result := '''';
  for I := 1 to Length(Value) do begin
    Result := Result + Value[I];
    if Value[I] = '''' then
      Result := Result + '''';
  end;
  Result := Result + '''';
end;

// اگر برنامه هنگام اتصال پراکسی سیستمی لوکال ثبت کرده بود، در زمان نصب یا حذف
// آن را خاموش می کنیم تا مرورگر کاربر بدون اینترنت نماند.
procedure ClearLoopbackProxy();
var
  ProxyServer: String;
begin
  if RegQueryStringValue(
       HKCU,
       'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
       'ProxyServer',
       ProxyServer) then
  begin
    if (Pos('127.0.0.1:', ProxyServer) > 0) or
       (Pos('localhost:', Lowercase(ProxyServer)) > 0) then
    begin
      RegWriteDWordValue(
        HKCU,
        'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        'ProxyEnable',
        0);
    end;
  end;
end;

function FindUmbrellaWindow(): HWND;
var
  TitleFa: String;
begin
  TitleFa := Chr($0641) + Chr($06CC) + Chr($0644) + Chr($062A) +
             Chr($0631) + Chr($0634) + Chr($06A9) + Chr($0646) + ' ' +
             Chr($0622) + Chr($0645) + Chr($0628) + Chr($0631) +
             Chr($0644) + Chr($0627);
  Result := FindWindowByWindowName(TitleFa);
  if Result = 0 then
    Result := FindWindowByWindowName('Umbrella VPN');
end;

// پیش از نصب، ارتقا یا حذف، برنامه قبلی و تمام فرایندهای زیرمجموعه و هسته آن
// را به صورت خودکار و بی صدا می بندد تا بدون نمایش خطای در حال اجرا بودن ادامه یابد.
procedure CloseAllUmbrellaProcesses(const AppDir: String);
var
  Wnd: HWND;
  Attempts, ResultCode: Integer;
  HadActiveApp: Boolean;
  KillScript: String;
begin
  HadActiveApp := CheckForMutexes(UmbrellaAppMutex);
  Wnd := FindUmbrellaWindow();
  if Wnd <> 0 then
  begin
    HadActiveApp := True;
    // WM_QUERYENDSESSION + WM_ENDSESSION باعث می شود برنامه حتی وقتی به سینی
    // سیستم پنهان شده است (WM_CLOSE فقط مخفی می کند)، اتصال و هسته و پروکسی
    // را تمیز جمع کرده و کاملا خارج شود.
    PostMessage(Wnd, $0011, 0, 0);
    PostMessage(Wnd, $0016, 1, 0);
    for Attempts := 1 to 24 do
    begin
      Sleep(150);
      if (FindUmbrellaWindow() = 0) and
         (not CheckForMutexes(UmbrellaAppMutex)) then
        Break;
    end;
  end;

  // ابتدا هسته ها و سرویس های جانبی را با درخت فرایند می بندیم.
  // هرگز /T را برای UmbrellaVPN.exe به کار نبرید؛ چون اگر نصب کننده
  // از داخل خود برنامه به عنوان زیرفرایند اجرا شده باشد، /T خودِ نصب کننده
  // را هم پیش از نصب خواهد بست!
  Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/F /T /IM UmbrellaCli.exe ' +
    '/IM UmbrellaCoreEngine.exe /IM UmbrellaAdmin.exe /IM sing-box.exe',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if ResultCode = 0 then
    HadActiveApp := True;

  if (FindUmbrellaWindow() <> 0) or CheckForMutexes(UmbrellaAppMutex) then
  begin
    Exec(
      ExpandConstant('{sys}\taskkill.exe'),
      '/F /IM UmbrellaVPN.exe',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if ResultCode = 0 then
      HadActiveApp := True;
  end;

  if (AppDir <> '') and DirExists(AppDir) then
  begin
    KillScript :=
      '$d=' + PsQuote(AddBackslash(AppDir)) + '; ' +
      '$me=$PID; ' +
      '$parentPid=(Get-CimInstance Win32_Process -Filter (''ProcessId='' + $me) -ErrorAction SilentlyContinue).ParentProcessId; ' +
      '$procs=Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ' +
      'Where-Object { $_.ProcessId -ne $me -and $_.ProcessId -ne $parentPid -and ' +
      '$_.Name -notlike ''unins*'' -and $_.Name -notlike ''UmbrellaVPN-Setup*'' -and ' +
      '$_.ExecutablePath -and $_.ExecutablePath.StartsWith($d, [System.StringComparison]::OrdinalIgnoreCase) }; ' +
      'foreach ($p in $procs) { ' +
      'Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue; ' +
      'Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue ' +
      '}; ';
    if HadActiveApp then
      KillScript := KillScript +
        'Get-NetFirewallRule -DisplayName ''Umbrella-*'' -ErrorAction SilentlyContinue | ' +
        'Remove-NetFirewallRule -ErrorAction SilentlyContinue';
    Exec(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -NonInteractive -Command "' + KillScript + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;

  for Attempts := 1 to 20 do
  begin
    if not CheckForMutexes(UmbrellaAppMutex) then
      Break;
    Sleep(100);
  end;

  if HadActiveApp then
    Sleep(200);

  ClearLoopbackProxy();
end;

function InitializeSetup(): Boolean;
begin
  CloseAllUmbrellaProcesses('');
  Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  if (CurPageID = wpReady) and
     ((FindUmbrellaWindow() <> 0) or CheckForMutexes(UmbrellaAppMutex)) then
    CloseAllUmbrellaProcesses(ExpandConstant('{app}'));
  Result := True;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseAllUmbrellaProcesses(ExpandConstant('{app}'));
  Result := '';
end;

// پوشه نصب را کاملا پاک می کند.
//
// Inno نمی تواند پوشه ای را که فایل اجرایی خودش (`unins000.exe`) در آن
// است حذف کند، پس بعد از «حذف برنامه» پوشه نصب با یک یا دو فایل `unins000`
// در آن باقی می ماند — دقیقا همان چیزی که کاربر دید و گزارش کرد. حذف
// کننده با دسترسی مدیر اجرا می شود، پس این فرایند جدا همان دسترسی را
// دارد و می تواند کل پوشه را بردارد.
//
// فرایند جدا غیر از حذف کننده است، پس وقتی حذف کننده بسته شود همه فایل
// های اجرایی آزاد شده اند و پوشه برداشته می شود. پوشه داده برنامه
// (`%APPDATA%\Umbrella`) هم پاک می شود تا هیچ چیزی باقی نماند.
procedure RemoveInstallFolder();
var
  ResultCode: Integer;
  UninstallerName, Command: String;
begin
  UninstallerName :=
    ChangeFileExt(ExtractFileName(ExpandConstant('{uninstallexe}')), '');
  // پوشه کاری را عوض می کنیم تا اگر حذف کننده پوشه نصب را پوشه کاری
  // خودش کرده بود، برداشتن پوشه به «دسترسی رد شد» نخورد.
  Command :=
    '$p=' + PsQuote(UninstallerName) + '; ' +
    'Set-Location -LiteralPath ([Environment]::GetFolderPath(''Windows'')); ' +
    '$null=Wait-Process -Name $p -Timeout 900 -ErrorAction SilentlyContinue; ' +
    'Remove-Item -LiteralPath ' + PsQuote(ExpandConstant('{app}')) +
      ' -Recurse -Force -ErrorAction SilentlyContinue; ' +
    'Remove-Item -LiteralPath ([Environment]::GetFolderPath(''ApplicationData'') '
      + '+ ''\Umbrella'') -Recurse -Force -ErrorAction SilentlyContinue';
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
       '-NoProfile -NonInteractive '
       + '-Command "' + Command + '"',
       '', SW_HIDE, ewNoWait, ResultCode);
end;

function InitializeUninstall(): Boolean;
begin
  CloseAllUmbrellaProcesses('');
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    CloseAllUmbrellaProcesses(ExpandConstant('{app}'));
    RemoveInstallFolder();
  end;
end;

[InstallDelete]
; نسخه های قبلی، پوشه هسته را با نام دیگری داشتند و کتابخانه را با نام دیگری
; می ریختند؛ فایل اجرایی کهنه بدون کتابخانه اش با 0xC0000135 باز نمی شد. حالا
; پوشه هسته و لانچرهای کهنه پاک می شوند تا فقط نسخه درست بماند.
Type: filesandordirs; Name: "{app}\cores\hiddify"
Type: filesandordirs; Name: "{app}\cores\umbrella"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\cores"
