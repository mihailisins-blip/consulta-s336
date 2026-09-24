; Instalador Windows autocontenido de Consulta S336 (R23/R24/R26/U16).
;
; Empaqueta la salida de `flutter build windows --release` (el runner +
; sus DLLs + la carpeta `data/` de Flutter -- assets, icudtl.dat, kernel
; blob, NUNCA la carpeta de datos de la app, que se llama `datos/` a
; propósito para no colisionar con esa) junto con una carpeta `datos/`
; (data.sqlite + pdfs/ + manifest.json, KTD3) que el curador genera aparte
; con `pipeline/` y coloca en `packaging/datos/` antes de compilar.
;
; La carpeta `datos/` solo se copia si el destino AÚN NO la tiene
; (Flags: onlyifdoesntexist) -- así, reinstalar para actualizar solo el
; binario nunca pisa una carpeta de datos que el técnico ya haya
; actualizado a mano reemplazándola (R24: "publicar una corrección de
; contenido consiste en reemplazar esa carpeta", un paso manual aparte de
; este instalador, documentado en README.md).
;
; Requiere Inno Setup 6 (https://jrsoftware.org/isinfo.php). Compilar con:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" packaging\installer.iss
; después de:
;   1. cd app && flutter build windows --release
;   2. colocar una carpeta de datos real (generada por pipeline/) en
;      packaging\datos\ (manifest.json, data.sqlite, pdfs\)

#define AppName "Consulta S336"
#define AppVersion "1.0.0"
#define AppExeName "consulta_s336_app.exe"
; Debe coincidir con app/pubspec.yaml (version:) -- este instalador no lee
; pubspec.yaml automáticamente (mantenedor único, KD1 -- ver el resto del
; plan); actualízalo a mano en cada release.

[Setup]
AppId={{B6E2B9B0-5C9E-4B7A-9C3E-2B6C3E9D4A11}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Curador de mantenimiento S336
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
; No exige admin -- per-usuario en {localappdata} sigue siendo perfectamente
; válido para el grupo reducido de equipos de R26, y evita fricción de UAC.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=dist
OutputBaseFilename=ConsultaS336-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
; La app es autocontenida y sin instalador de dependencias (KTD1/R23) --
; nada de .NET/VC++ redistributable que registrar aquí.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
; El build entero de Flutter -- exe, DLLs, y su propia carpeta `data/`
; (NO es la carpeta de datos de la app -- ver la nota de cabecera).
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
; La carpeta de datos de la app (R24/KTD3) -- junto al ejecutable, nunca
; dentro de él. Solo se copia si no existe ya en el destino.
Source: "datos\*"; DestDir: "{app}\datos"; Flags: recursesubdirs createallsubdirs onlyifdoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos adicionales:"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent
