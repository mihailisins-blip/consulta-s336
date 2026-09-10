// manifest.json de la carpeta de datos (KTD3 / R25 del plan).

import { promises as fs } from 'node:fs';
import path from 'node:path';

export const SCHEMA_VERSION = 1;

/**
 * @param {string} outDir
 * @param {object} info
 * @param {number} [info.dataFolderVersion]  versión de la carpeta (1 si es el primer build)
 * @param {Record<string,string>} [info.sources]  rutas/nombres de los documentos de origen
 * @param {Record<string,number>} [info.counts]   conteos para inspección rápida
 */
export async function writeManifest(outDir, info = {}) {
  const manifest = {
    schema_version: SCHEMA_VERSION,
    data_folder_version: info.dataFolderVersion ?? 1,
    build_date: new Date().toISOString(),
    generator: 'consulta-s336-pipeline',
    sources: info.sources ?? {},
    counts: info.counts ?? {},
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
