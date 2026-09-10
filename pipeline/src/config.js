// Carga y validación del archivo de configuración de la extracción.
//
// El corpus vive en un CDROM ("CDROM LOC ADIF ED.2") con subcarpetas fijas.
// La config declara la raíz de ese CDROM (sin letra de unidad fija) y, opcionalmente,
// sobreescribe rutas concretas. `outDir` es donde se escribe la carpeta de datos.

import { promises as fs } from 'node:fs';
import path from 'node:path';

/** Nombres de subcarpeta por defecto dentro del CDROM. */
export const DEFAULT_SUBDIRS = {
  plan: '03 Plan mantenimiento',
  vmi: '04 Instrucciones plan mantenimiento (VMI)',
  manuales: '05 Manuales mantenimiento',
  materiales: '06 Catalogo piezas',
  esquemas: '07 Esquemas',
};

/** Raíces que deben existir para poder extraer. `esquemas` es opcional. */
export const REQUIRED_ROOTS = ['plan', 'vmi', 'manuales', 'materiales'];

/**
 * @typedef {Object} ResolvedConfig
 * @property {string} configPath
 * @property {string|null} cdromRoot
 * @property {Record<string,string>} roots  nombre -> ruta absoluta
 * @property {string} outDir  ruta absoluta
 * @property {boolean} bundlePdfs
 */

/**
 * Lee y resuelve el archivo de config. Las rutas relativas se resuelven contra
 * la carpeta que contiene el propio archivo de config.
 * @param {string} configPath
 * @returns {Promise<ResolvedConfig>}
 */
export async function loadConfig(configPath) {
  const abs = path.resolve(configPath);
  let raw;
  try {
    raw = await fs.readFile(abs, 'utf8');
  } catch (err) {
    throw new Error(`No se puede leer la config en ${abs}: ${err.code || err.message}`);
  }
  let cfg;
  try {
    cfg = JSON.parse(raw);
  } catch (err) {
    throw new Error(`Config con JSON inválido (${abs}): ${err.message}`);
  }

  const baseDir = path.dirname(abs);
  const resolveMaybe = (p) => (p ? path.resolve(baseDir, p) : null);

  const cdromRoot = resolveMaybe(cfg.cdromRoot);
  const overrides = cfg.roots && typeof cfg.roots === 'object' ? cfg.roots : {};

  /** @type {Record<string,string>} */
  const roots = {};
  for (const [name, sub] of Object.entries(DEFAULT_SUBDIRS)) {
    if (overrides[name]) {
      roots[name] = path.resolve(baseDir, overrides[name]);
    } else if (cdromRoot) {
      roots[name] = path.join(cdromRoot, sub);
    }
    // si no hay ni override ni cdromRoot, la raíz queda sin definir -> lo detecta validateRoots
  }

  const outDir = resolveMaybe(cfg.outDir) || path.resolve(baseDir, 'data');
  const bundlePdfs = cfg.bundlePdfs !== false; // por defecto true

  return { configPath: abs, cdromRoot, roots, outDir, bundlePdfs };
}

/**
 * Comprueba que las raíces requeridas existen y son directorios.
 * @param {ResolvedConfig} cfg
 * @returns {Promise<{ok: boolean, missing: string[], problems: string[]}>}
 */
export async function validateRoots(cfg) {
  const missing = [];
  const problems = [];
  for (const name of REQUIRED_ROOTS) {
    const p = cfg.roots[name];
    if (!p) {
      missing.push(`${name} (sin ruta: falta 'cdromRoot' o 'roots.${name}' en la config)`);
      continue;
    }
    try {
      const st = await fs.stat(p);
      if (!st.isDirectory()) problems.push(`${name}: ${p} no es un directorio`);
    } catch (err) {
      missing.push(`${name}: ${p} (${err.code || err.message})`);
    }
  }
  return { ok: missing.length === 0 && problems.length === 0, missing, problems };
}
