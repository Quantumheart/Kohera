[Setup]
AppId={{io.github.quantumheart.kohera}
AppName=Kohera
AppVersion={#AppVersion}
AppPublisher=Kohera
AppPublisherURL=https://github.com/Quantumheart/Kohera
DefaultDirName={autopf}\Kohera
DefaultGroupName=Kohera
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=kohera-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Kohera"; Filename: "{app}\kohera.exe"; AppUserModelID: "io.github.quantumheart.kohera"
Name: "{autodesktop}\Kohera"; Filename: "{app}\kohera.exe"; Tasks: desktopicon; AppUserModelID: "io.github.quantumheart.kohera"

[Registry]
; Register matrix: URI scheme handler
Root: HKCU; Subkey: "Software\Classes\matrix"; ValueType: string; ValueName: ""; ValueData: "URL:Matrix Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\matrix"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\matrix\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\kohera.exe,0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\matrix\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\kohera.exe"" ""%1"""; Flags: uninsdeletekey
; Register io.github.quantumheart.kohera: URI scheme handler
Root: HKCU; Subkey: "Software\Classes\io.github.quantumheart.kohera"; ValueType: string; ValueName: ""; ValueData: "URL:Kohera Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\io.github.quantumheart.kohera"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\io.github.quantumheart.kohera\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\kohera.exe,0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\io.github.quantumheart.kohera\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\kohera.exe"" ""%1"""; Flags: uninsdeletekey

[Run]
Filename: "{app}\kohera.exe"; Description: "{cm:LaunchProgram,Kohera}"; Flags: nowait postinstall skipifsilent
