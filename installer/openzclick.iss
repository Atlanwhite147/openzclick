; Installs openzclick for one user, with no administrator prompt.
;
; The point of this file is that installing the bridge should be one download and
; one double-click, and that afterwards the application is where a rider expects
; a program to be: a shortcut, an entry in the Start menu, and an uninstaller.
; A zip that has to be unzipped somewhere and remembered is not an installation.
;
; Per-user rather than per-machine on purpose: no UAC, no administrator password
; on a rider's own laptop, and the uninstaller leaves nothing behind.

#define AppName "openzclick"
#define AppVersion "0.3.0"
#define AppPublisher "openzclick contributors"
#define AppUrl "https://github.com/Atlanwhite147/openzclick"
#define AppExe "openzclick.exe"

[Setup]
AppId={{7A2E4C1D-9F3B-4E6A-9C21-5D8B0F3A6E14}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=openzclick-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
; The application is not signed: say so rather than pretend, and keep SmartScreen
; out of the wizard's way by not asking for elevation it does not need.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Start openzclick when I sign in to Windows"; GroupDescription: "Startup"; Flags: unchecked

[Files]
; Everything the Flutter Windows build produced: the executable, the engine and
; the plugin DLLs.
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; One value under HKCU, removed by the uninstaller: nothing global, nothing that
; needs an administrator.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; \
    ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
