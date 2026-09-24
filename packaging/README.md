# Empaquetado y distribución (R23/R24/R26/U16)

Procedimiento manual completo: generar una carpeta de datos, compilar el
instalador, instalarlo, y publicar una actualización de contenido más
adelante. Dirigido a un grupo reducido de equipos conocidos (R26) — no hay
tienda de aplicaciones ni auto-actualización.

## 0. Herramientas necesarias (una sola vez por máquina de build)

- Flutter con soporte de escritorio Windows habilitado (`flutter doctor` en
  verde para "Windows").
- Node 22+ con `--experimental-sqlite` (para `pipeline/`).
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) — instala `ISCC.exe`
  (normalmente en `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`; no queda
  en el PATH por defecto).

## 1. Generar la carpeta de datos

Desde `pipeline/`, con acceso a `Z:\...\CDROM LOC ADIF ED.2`:

```bash
cd pipeline
node --experimental-sqlite src/index.js build --config <ruta-a-tu-config.json>
```

Esto produce una carpeta con `manifest.json`, `data.sqlite` y `pdfs/`
(KTD3). El `manifest.json` ya trae `schema_version` (debe coincidir con
`kExpectedSchemaVersion` de `app/lib/data/data_folder.dart` — R25/AE6) y
`data_folder_version`, que se incrementa solo si pasas `--prev <carpeta
anterior>` para una re-extracción no destructiva (R21/KTD7).

**Revisa las incidencias de unión** (`incidencia_extraccion` en
`data.sqlite`, o el resumen que imprime la CLI) antes de distribuir —
son los VMI o filas del Excel que no se pudieron enlazar por código
(KTD4), y conviene que el curador las revise, no que se ignoren en
silencio.

## 2. Compilar la app

```bash
cd app
flutter build windows --release
```

Salida esperada en `app/build/windows/x64/runner/Release/`:
`consulta_s336_app.exe`, varias `.dll`, y una carpeta `data/` — **esa
`data/` es de Flutter** (assets, `icudtl.dat`, el kernel blob de Dart), no
tiene nada que ver con la carpeta de datos de la app, que se llama
**`datos/`** a propósito para no colisionar con ella (era el mismo bug real
que motivó ese renombrado en U10 — Flutter Windows ya usa `data/` junto al
ejecutable para su propio runtime).

## 3. Compilar el instalador

```bash
# 1. coloca la carpeta de datos del paso 1 en packaging/datos/
#    (packaging/datos/manifest.json, packaging/datos/data.sqlite, packaging/datos/pdfs/)
# 2. compila
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" packaging\installer.iss
```

`packaging/datos/` **nunca se versiona** (está en `.gitignore` junto con
`packaging/dist/`) — es contenido real y pesado (los PDF), específico de
cada curador y cada momento.

El resultado queda en `packaging/dist/ConsultaS336-Setup-<versión>.exe`.
Antes de distribuir una versión nueva, **actualiza `#define AppVersion` en
`installer.iss`** para que coincida con `app/pubspec.yaml` (`version:`) —
el script no lo lee automáticamente (mantenedor único, KD1).

### Qué hace el instalador (comportamiento importante)

- Copia el build de Flutter entero (exe + DLLs + `data/`) — siempre,
  sobrescribiendo, en cada instalación o reinstalación.
- Copia `datos/` **solo si el destino todavía no la tiene**
  (`onlyifdoesntexist`). Esto es deliberado: reinstalar para actualizar
  solo el binario de la app **nunca** pisa una carpeta de datos que el
  técnico ya haya actualizado a mano (paso 4) — si lo hiciera, una
  actualización de la app borraría silenciosamente el trabajo de curación
  más reciente.
- No pide privilegios de administrador por defecto (instala en
  `%LOCALAPPDATA%` si el usuario no elige "para todos los usuarios") —
  reduce fricción de UAC para un grupo reducido de equipos ya conocidos.

## 4. Publicar solo una actualización de contenido (R24)

Sin tocar el instalador ni el ejecutable: genera la carpeta de datos nueva
(paso 1, con `--prev` para conservar overrides — KTD7) y **reemplaza
íntegra** la carpeta `datos/` junto al ejecutable instalado (p. ej.
`%LOCALAPPDATA%\Consulta S336\datos\`) por la nueva. Si el
`schema_version` de la carpeta nueva no coincide con el que espera esa
versión de la app instalada, el aviso de incompatibilidad salta al abrir
(AE6/R25) — en ese caso hace falta distribuir también un instalador nuevo
(porque `kExpectedSchemaVersion` es una constante compilada en el binario,
no algo que la carpeta de datos pueda cambiar).

## 5. Distribuir

Copia `ConsultaS336-Setup-<versión>.exe` a cada equipo del grupo conocido
(R26) por el medio que uses habitualmente (USB, carpeta compartida
interna) y ejecútalo. No hay descarga automática ni comprobación de
versión disponible más allá de lo que ya hace la propia app al arrancar
(AE6).

## Verificación (U16 — sin cobertura unitaria, por diseño)

Este paso es deliberadamente manual (ver el plan: "preferir verificación
por instalación y arranque en una máquina limpia sobre cobertura
unitaria") — no hay tests automatizados de `packaging/`. Antes de
distribuir una versión:

1. Compila el instalador (pasos 1-3) contra una carpeta de datos real.
2. Instálalo en una máquina limpia (sin el toolchain de Flutter/Node).
3. Arranca sin conexión de red: debe llegar al hub sin avisos.
4. Haz una búsqueda y una exportación (R27) cualquiera.
5. Reemplaza `datos/` por una carpeta de un `schema_version` distinto y
   confirma que el aviso de incompatibilidad salta (AE6) en vez de abrir
   datos desajustados en silencio.

`installer.iss` en sí SÍ se verificó de extremo a extremo en esta sesión
-- compilado con Inno Setup 6.7.3 contra un build real de
`flutter build windows --release` y una carpeta de datos de prueba
(generada con `pipeline/scripts/gen-app-fixture.mjs`), instalado en
silencio (`/VERYSILENT`) en un directorio temporal, y confirmado que
`data/` y `datos/` quedan junto al ejecutable con la forma exacta que
espera `data_folder.dart`, y que el proceso arranca y responde. No se
verificó visualmente que la UI llegue al hub (esta sesión no tiene forma
fiable de capturar solo la ventana de la app sin arriesgarse a capturar
el escritorio real del usuario) -- eso queda para el paso 3 de arriba, en
una verificación manual real.
