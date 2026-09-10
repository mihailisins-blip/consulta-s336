// Inventario del corpus: recorre los subárboles y clasifica cada archivo.
// No parsea nada — solo lista. Los parsers viven en vmi-parser.js / xlsx-*.js.

import { promises as fs } from 'node:fs';
import path from 'node:path';

/** @typedef {'pdf'|'xlsx'|'xls'|'otro'} FileType */

/**
 * Clasifica un archivo por su extensión (case-insensitive).
 * @param {string} name
 * @returns {FileType}
 */
export function classifyType(name) {
  const ext = path.extname(name).toLowerCase();
  if (ext === '.pdf') return 'pdf';
  if (ext === '.xlsx') return 'xlsx';
  if (ext === '.xls') return 'xls';
  return 'otro';
}

/**
 * Recorre `absDir` recursivamente.
 * @param {string} absDir  ruta absoluta a recorrer
 * @param {string} [baseDir=absDir]  base para calcular rutas relativas
 * @returns {Promise<{files: Array<{relPath:string,name:string,ext:string,type:FileType,size:number}>, errors: string[]}>}
 */
export async function walkDir(absDir, baseDir = absDir) {
  /** @type {Array<{relPath:string,name:string,ext:string,type:FileType,size:number}>} */
  const files = [];
  /** @type {string[]} */
  const errors = [];

  /** @param {string} dir */
  async function recurse(dir) {
    let entries;
    try {
      entries = await fs.readdir(dir, { withFileTypes: true });
    } catch (err) {
      errors.push(`${dir}: ${err.code || err.message}`);
      return;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        await recurse(full);
      } else if (entry.isFile()) {
        let size = 0;
        try {
          size = (await fs.stat(full)).size;
        } catch {
          // archivo desaparecido entre readdir y stat; lo listamos con size 0
        }
        files.push({
          relPath: path.relative(baseDir, full).split(path.sep).join('/'),
          name: entry.name,
          ext: path.extname(entry.name).toLowerCase(),
          type: classifyType(entry.name),
          size,
        });
      }
      // symlinks y otros tipos se ignoran a propósito
    }
  }

  await recurse(absDir);
  files.sort((a, b) => a.relPath.localeCompare(b.relPath));
  return { files, errors };
}

/**
 * Resume una lista de archivos: total y conteo por tipo.
 * @param {Array<{type:FileType}>} files
 */
export function summarize(files) {
  /** @type {Record<FileType, number>} */
  const byType = { pdf: 0, xlsx: 0, xls: 0, otro: 0 };
  for (const f of files) byType[f.type]++;
  return { count: files.length, byType };
}

/**
 * Agrupa por la primera carpeta relativa (útil para ver los ciclos en `04` o los sistemas en `05`).
 * @param {Array<{relPath:string,type:FileType}>} files
 * @returns {Record<string,{count:number,byType:Record<FileType,number>}>}
 */
export function byImmediateSubdir(files) {
  /** @type {Record<string,{count:number,byType:Record<FileType,number>}>} */
  const out = {};
  for (const f of files) {
    const seg = f.relPath.includes('/') ? f.relPath.slice(0, f.relPath.indexOf('/')) : '.';
    if (!out[seg]) out[seg] = { count: 0, byType: { pdf: 0, xlsx: 0, xls: 0, otro: 0 } };
    out[seg].count++;
    out[seg].byType[f.type]++;
  }
  return out;
}

/**
 * Inventario completo de los subárboles nombrados.
 * @param {Record<string,string>} roots  { plan, vmi, manuales, materiales, esquemas? } -> ruta absoluta
 * @returns {Promise<{roots: Record<string, {path:string, count:number, byType:Record<FileType,number>, bySubdir:Record<string,{count:number,byType:Record<FileType,number>}>, files:Array}>, totals:{files:number, byType:Record<FileType,number>}, errors:string[]}>}
 */
export async function inventory(roots) {
  /** @type {any} */
  const result = { roots: {}, totals: { files: 0, byType: { pdf: 0, xlsx: 0, xls: 0, otro: 0 } }, errors: [] };
  for (const [name, absPath] of Object.entries(roots)) {
    const { files, errors } = await walkDir(absPath);
    result.errors.push(...errors);
    const s = summarize(files);
    result.roots[name] = {
      path: absPath,
      count: s.count,
      byType: s.byType,
      bySubdir: byImmediateSubdir(files),
      files,
    };
    result.totals.files += s.count;
    for (const t of /** @type {FileType[]} */ (['pdf', 'xlsx', 'xls', 'otro'])) {
      result.totals.byType[t] += s.byType[t];
    }
  }
  return result;
}
