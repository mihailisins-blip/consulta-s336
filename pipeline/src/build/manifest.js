// manifest.json de la carpeta de datos (KTD3 / R25 del plan).

import { promises as fs } from 'node:fs';
import path from 'node:path';

// v2 (2026-09-23): añade la tabla actividad_lote (Fase B / U10 — R11/R12/AE3
// necesitan saber qué actividad cae en qué lote, no solo qué lotes existen
// por nivel). Una carpeta de datos v1 sigue siendo válida en todo lo demás,
// pero re-extráela para que el desglose por lote deje de estar vacío.
export const SCHEMA_VERSION = 2;

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
