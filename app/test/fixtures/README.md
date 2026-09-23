# Fixtures de test de la app

`data.sqlite` es una copia REAL de la carpeta de datos que `pipeline/`
(Fase A) generó contra el corpus completo de `Z:\...\CDROM LOC ADIF ED.2` el
2026-09-10 -- no es sintética ni escrita a mano. 439 VMIs, 0 % sin extraer,
95 sistemas, 438 actividades, 620 entradas de catálogo, 1153 filas de
búsqueda (ver `manifest.json` de esa corrida para las cifras completas).

Se reutiliza en los tests de la app en vez de reconstruir el esquema de
`pipeline/src/build/sqlite-writer.js` en Dart -- así cada test corre contra
contenido real (términos en español con acentos, códigos reales del plan,
descripciones de catálogo reales) y queda automáticamente fiel al esquema
real sin mantener una segunda copia de la DDL.

Si el esquema de `pipeline/` cambia de forma incompatible (una nueva
`SCHEMA_VERSION`), regenera este archivo con una corrida real de
`pipeline/` (o con `pipeline/test/build.test.js`'s `writeDatabase` contra un
fixture mayor) y vuelve a copiarlo aquí.
