# consulta-s336

Herramienta de consulta del plan de mantenimiento del vehículo ferroviario **S336 / Eurolight**.

Convierte el corpus documental (plan de mantenimiento, 448 instrucciones VMI, manuales de sistema,
listas de materiales) en una aplicación de escritorio Windows autocontenida y sin conexión: buscar y
navegar cualquier actividad, ciclo, sistema, herramienta o consumible sin abrir un PDF.

## Estructura

| Carpeta | Qué es | Estado |
|---|---|---|
| `pipeline/` | CLI Node que extrae el corpus a una **carpeta de datos** versionada (SQLite + FTS5 + `pdfs/` + `manifest.json`). La ejecuta el curador en el equipo con acceso al corpus. | En construcción (Fase A) |
| `app/` | App Flutter Windows que lee la carpeta de datos. Modo curador (edición) y modo técnico (solo lectura). | Pendiente (Fase B/C) |
| `packaging/` | Instalador y procedimiento de distribución manual. | Pendiente |

Plan de implementación completo: `flota-locomotoras/docs/plans/2026-09-03-2018-feat-consulta-mantenimiento-s336-plan.md`.

## Pipeline — uso rápido

Requiere **Node >= 22** con el flag `--experimental-sqlite` (usa `node:sqlite`,
que ya trae FTS5). Los scripts de `npm` ya lo incluyen.

```
cd pipeline
npm install
npm run build -- --config <ruta-a-config.json>     # -> carpeta de datos en outDir
npm test
```

Equivale a `node --experimental-sqlite src/index.js build --config <…>`.

Flags de `build`:

| Flag | Efecto |
|---|---|
| `--config <json>` | Configuración (obligatorio). |
| `--dry-run` | Solo inventario; no escribe la carpeta de datos. |
| `--prev <carpeta>` | Re-extracción: traspasa las ediciones del curador (`overrides`, fichas revisadas) de esa carpeta anterior y marca los cambios de origen en `cambio_pendiente`. |
| `--con-toc` | Extrae el índice (outline) de los manuales de `05`. Lento; por defecto no. |

`config.json` (ejemplo — se admiten `/` en las rutas):

```json
{
  "cdromRoot": "Z:/OPERACIONES/.../CDROM LOC ADIF ED.2",
  "outDir": "./data",
  "bundlePdfs": true
}
```

La carpeta de datos resultante contiene `data.sqlite` (datos + índice FTS5),
`pdfs/` (los VMI individuales, manuales de `05` y esquemas; se excluyen los
mega-PDF pre-fusionados por ciclo) y `manifest.json` (versión de esquema y de
carpeta, fecha, orígenes, conteos).
