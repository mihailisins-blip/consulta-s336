// manifest.json de la carpeta de datos (KTD3 / R25 del plan).

import { promises as fs } from 'node:fs';
import path from 'node:path';

// v2 (2026-09-23): añade la tabla actividad_lote (Fase B / U10 — R11/R12/AE3
// necesitan saber qué actividad cae en qué lote, no solo qué lotes existen
// por nivel). Una carpeta de datos v1 sigue siendo válida en todo lo demás,
// pero re-extráela para que el desglose por lote deje de estar vacío.
// v3 (2026-09-23): añade `actividad.seguridad` (Fase B / U11 — R6 exige
// mostrar las medidas de seguridad de la sección 1 del VMI, aparte y
// colapsadas; vmi-parser.js reconocía esa sección como límite de la 2, pero
// descartaba su texto). Como en v2, una carpeta anterior no queda inválida
// como dato -- solo hay que re-extraer para que esa columna deje de estar
// vacía; la app SÍ exige que `schema_version` case exacto (AE6/R25).
// v4 (2026-09-24): añade `fusion_catalogo` (Fase C / U15 — R22: el registro
// de las fusiones del curador, para poder deshacerlas). A diferencia de v2/
// v3, esta tabla no la rellena la extracción -- la escribe la app en
// tiempo de ejecución -- pero una carpeta anterior tampoco la tiene, así
// que abrirla con la app nueva rompería igual (KTD3): sigue exigiendo el
// mismo bump de versión que cualquier cambio de forma del esquema.
export const SCHEMA_VERSION = 4;

/**
 * @param {string} outDir
 * @param {object} info
 * @param {number} [info.dataFolderVersion]  versión de la carpeta (1 si es el primer build)
 * @param {Record<string,string>} [info.sources]  rutas/nombres de los documentos de origen
 * @param {Record<string,number>} [info.counts]   conteos para inspección rápida
 * @param {string[]} [info.avisos]  avisos de los parsers (p. ej. hoja/columna no encontrada)
 *   que conviene poder ver sin repescar el log de la consola -- una hoja del
 *   plan sin fila de cabecera, por ejemplo, deja el build en verde pero con un
 *   modelo casi vacío; esto lo hace visible desde la propia carpeta de datos.
 */
export async function writeManifest(outDir, info = {}) {
  const manifest = {
    schema_version: SCHEMA_VERSION,
    data_folder_version: info.dataFolderVersion ?? 1,
    build_date: new Date().toISOString(),
    generator: 'consulta-s336-pipeline',
    sources: info.sources ?? {},
    counts: info.counts ?? {},
    avisos: info.avisos ?? [],
  };
  await fs.mkdir(outDir, { recursive: true });
  await fs.writeFile(path.join(outDir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

/** Lee el manifest de una carpeta de datos previa (para --prev). Null si no hay. */
export async function readManifest(dir) {
  try {
    return JSON.parse(await fs.readFile(path.join(dir, 'manifest.json'), 'utf8'));
  } catch {
    return null;
  }
}
