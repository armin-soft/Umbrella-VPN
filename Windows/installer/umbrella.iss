; اسکریپت نصب فیلترشکن آمبرلا برای Inno Setup 6
; ابتدا tools\bootstrap.ps1 -Release را اجرا کنید تا خروجی ریلیز ساخته شود،
; سپس این فایل را با Inno Setup باز و کامپایل کنید.

#define AppName "فیلترشکن آمبرلا"
#define AppVersion "1.0.0"
#define AppPublisher "آرمین سافت"
#define AppExe "umbrella_vpn.exe"

[Setup]
AppId={{9A7E1F42-3C5B-4E7A-9D21-UMBRELLA1000}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Umbrella VPN
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=output
OutputBaseFilename=UmbrellaVPN-Setup-1.0.0-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; نصب و ساخت تونل به دسترسی مدیر نیاز دارد
PrivilegesRequired=admin
MinVersion=10.0
SetupIconFile=..\windows\runner\resources\app_icon.ico
DisableProgramGroupPage=yes
CloseApplications=yes

[Languages]
Name: "farsi"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "ساخت میانبر روی دسکتاپ"; GroupDescription: "میانبرها:"
Name: "autostart"; Description: "اجرای خودکار برنامه با ویندوز"; GroupDescription: "گزینه ها:"; Flags: unchecked

[Files]
; خروجی ساخت فلوتر
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; اگر هسته ها را کنار برنامه گذاشته اید، این پوشه هم نصب می شود
Source: "..\cores\*"; DestDir: "{app}\cores"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\حذف {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "UmbrellaVPN"; ValueData: """{app}\{#AppExe}"" --minimized"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#AppExe}"; Description: "اجرای {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall set allprofiles firewallpolicy blockinbound,allowoutbound"; Flags: runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\Umbrella"
