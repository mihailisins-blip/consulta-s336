// Worker de un VMI: lee el PDF, lo copia a la carpeta de datos (si se pide),
// extrae su texto y sus figuras, y devuelve el registro parseado. Se ejecuta
// dentro de un worker_thread (ver vmi-pool.js).
//
// El PDF se lee de la red UNA vez y los mismos bytes sirven para parsear y para
// copiar: el cuello de botella de una extracción completa es la lectura de la
// unidad de red, no la CPU. La copia va ANTES del parseo: un VMI que no se
// puede parsear conserva igualmente su PDF (R2).
//
// Cada VMI terminado deja un registro en `cacheFile` (escritura atómica), y con
// `usarCache` una ejecución reanudada (--reanudar) lo reutiliza sin tocar la
// red -- una extracción completa tarda más de lo que aguanta una conexión de
// red inestable, y reanudar evita repetir lo ya hecho.

import { parentPort } from 'node:worker_threads';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { pdfToLines } from './pdf-text.js';
import { parseVmiConImagenes } from './vmi-images.js';

/** Subir al cambiar el parser de VMI o la extracción de figuras: invalida las cachés viejas. */
export const VERSION_CACHE = 2;

async function leerCache({ cacheFile, tamano, outDir, copiarA }) {
  try {
    const c = JSON.parse(await fs.readFile(cacheFile, 'utf8'));
    if (c.version !== VERSION_CACHE || c.tamano !== tamano) return null;
    // lo que el registro da por hecho tiene que seguir en disco
    if (copiarA && (await fs.stat(copiarA)).size !== tamano) return null;
    for (const f of c.rec.figuras ?? []) await fs.stat(path.join(outDir, 'imagenes', f.archivo));
    return c;
  } catch {
    return null;
  }
}

async function guardarCache(cacheFile, datos) {
  await fs.mkdir(path.dirname(cacheFile), { recursive: true });
  const tmp = `${cacheFile}.tmp`;
  await fs.writeFile(tmp, JSON.stringify({ version: VERSION_CACHE, ...datos }));
  await fs.rename(tmp, cacheFile);
}

parentPort.on('message', async ({
  id, file, codigo, outDir, copiarA = null, cacheFile = null, usarCache = false, tamano = null,
}) => {
  if (cacheFile && usarCache) {
    const c = await leerCache({ cacheFile, tamano, outDir, copiarA });
    if (c) {
      parentPort.postMessage({ id, rec: c.rec, fallos: c.fallos, copia: c.copia, desdeCache: true });
      return;
    }
  }
  let copia = null;
  try {
    const bytes = await fs.readFile(file);
    if (copiarA) {
      try {
        await fs.mkdir(path.dirname(copiarA), { recursive: true });
        await fs.writeFile(copiarA, bytes);
        copia = { ok: true, bytes: bytes.length };
      } catch (e) {
        copia = { ok: false, error: e.code || e.message };
      }
    }
    const lineas = await pdfToLines(bytes, { fuentes: true });
    const { rec, fallos } = await parseVmiConImagenes(lineas, bytes, { codigo, outDir });
    if (cacheFile && (!copiarA || copia?.ok)) {
      try { await guardarCache(cacheFile, { tamano: bytes.length, rec, fallos, copia }); } catch { /* sin caché, no es grave */ }
    }
    parentPort.postMessage({ id, rec, fallos, copia });
  } catch (e) {
    parentPort.postMessage({ id, error: e?.message ?? String(e), copia });
  }
});
