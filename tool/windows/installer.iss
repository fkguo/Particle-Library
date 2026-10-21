#ifndef StagingDir
  #error StagingDir must point to the staged Windows release directory.
#endif
#ifndef OutputDir
  #error OutputDir must point to the release output directory.
#endif
#ifndef AppVersion
  #error AppVersion must be provided from pubspec.yaml.
#endif

[Setup]
AppId=io.github.fkguo.particlelibrary
AppName=Particle Library
AppVersion={#AppVersion}
AppPublisher=Particle Library contributors
DefaultDirName={localappdata}\Particle Library
DefaultGroupName=Particle Library
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
Uninstallable=no
CreateUninstallRegKey=no
OutputDir={#OutputDir}
OutputBaseFilename=Particle-Library-{#AppVersion}-Windows-x64-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupIconFile={#StagingDir}\app_icon.ico
[Files]
Source: {#StagingDir}\*; DestDir: {app}; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: {group}\Particle Library; Filename: {app}\ParticleLibrary.exe; WorkingDir: {app}
Name: {autodesktop}\Particle Library; Filename: {app}\ParticleLibrary.exe; WorkingDir: {app}

[Run]
Filename: {app}\ParticleLibrary.exe; Description: Launch Particle Library; Flags: postinstall nowait skipifsilent
