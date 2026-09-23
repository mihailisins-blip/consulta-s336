# Fixtures de test de la app

## `data.sqlite` (grande, esquema v1)

Copia REAL de la carpeta de datos que `pipeline/` (Fase A) generó contra el
corpus completo de `Z:\...\CDROM LOC ADIF ED.2` el 2026-09-10 -- no es
sintética ni escrita a mano. 439 VMIs, 0 % sin extraer, 95 sistemas, 438
actividades, 620 entradas de catálogo, 1153 filas de búsqueda (ver
`manifest.json` de esa corrida para las cifras completas).

Se reutiliza en los tests de la app en vez de reconstruir el esquema de
`pipeline/src/build/sqlite-writer.js` en Dart -- así cada test corre contra
contenido real (términos en español con acentos, códigos reales del plan,
descripciones de catálogo reales) y queda automáticamente fiel al esquema
real sin mantener una segunda copia de la DDL.

**Es de esquema v1** (anterior a la tabla `actividad_lote`, al alta de
niveles RDH en `actividad_nivel` y a la columna `actividad.seguridad`,
todos de 2026-09-23) -- no se puede regenerar sin acceso a `Z:`, que este
entorno no tiene. Válido para search_service_test.dart (no toca esas
tablas); no usar para nada que necesite actividad_lote, niveles RDH o
texto de medidas de seguridad.

## `data-lotes.sqlite` (pequeño, esquema v3)

Generado con `pipeline/scripts/gen-app-fixture.mjs`, que reutiliza los
mismos 4 VMI reales de `pipeline/test/fixtures/vmi/` y los workbooks de
`pipeline/test/helpers/xlsx-fixtures.js` que ya usa la suite de tests de
`pipeline/` -- real en cuanto al esquema (lo escribe el propio
`sqlite-writer.js`), pequeño porque no requiere el corpus completo.
Sí tiene `actividad_lote` y `actividad.seguridad` (FD5.02.04 trae texto real
de la sección 1 del VMI). Para regenerarlo tras un cambio de esquema:

```
cd pipeline
node --experimental-sqlite scripts/gen-app-fixture.mjs ../app/test/fixtures/data-lotes.sqlite
```

## Regla general

Si el esquema de `pipeline/` cambia de forma incompatible (nueva
`SCHEMA_VERSION`), `data-lotes.sqlite` se puede regenerar sin más (arriba);
`data.sqlite` necesita una corrida real contra `Z:` que solo el curador
puede hacer.
