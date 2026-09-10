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

```
cd pipeline
npm install
node src/index.js build --config <ruta-a-config.json>
npm test
```

`config.json` (ejemplo):

```json
{
  "cdromRoot": "Z:\\OPERACIONES\\...\\CDROM LOC ADIF ED.2",
  "outDir": "./data"
}
```
