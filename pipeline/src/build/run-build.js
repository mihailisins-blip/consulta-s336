// Orquestador de la extracción completa (U1..U6): del corpus a una carpeta de datos.

import path from 'node:path';
import { promises as fs } from 'node:fs';
import { walkDir } from '../corpus/walk.js';
import { pdfToLines, pdfOutline } from '../corpus/pdf-text.js';
import { parseVmi } from '../corpus/vmi-parser.js';
import { parsePlan } from '../corpus/xlsx-plan.js';
import { parseMateriales } from '../corpus/xlsx-materiales.js';
import { buildCycleModel } from '../model/cycles.js';
import { buildCatalog } from '../model/catalog.js';
import { buildJoinGraph } from '../model/join.js';
import { normalizarCodigo } from '../model/codes.js';
import { writeDatabase } from './sqlite-writer.js';
import { carryOverridesAndDiff } from './diff.js';
import { selectAndCopyPdfs, esVmiIndividual } from './pdf-select-copy.js';
import { writeManifest, readManifest, SCHEMA_VERSION } from './manifest.js';

/**
 * Registra los errores de recorrido de un subárbol (p. ej. un permiso
 * denegado o una carpeta que desapareció a mitad de lectura en la red).
 * walkDir no lanza -- los devuelve en `errors` -- así que sin esto pasarían
 * inadvertidos: el build seguiría en verde con el corpus infracontado.
 * @param {string} area
 * @param {string[]} errors
 * @param {(m:string)=>void} log
 */
export function logWalkErrors(area, errors, log) {
  if (!errors.length) return;
  log(`  aviso: ${errors.length} error(es) al recorrer ${area}:`);
  for (const e of errors) log(`    - ${e}`);
}

/**
 * Índice código normalizado -> registro VMI. El mismo VMI puede archivarse en
 * más de una subcarpeta de ciclo (join.js lo deduplica igual, acumulando
 * `ciclosCarpeta`); aquí, ante duplicados del mismo código, se prefiere el
 * primer ejemplar que SÍ se pudo extraer -- es la fuente de `frecuencia`,
 * `procedimiento`, etc. que sqlite-writer.js lee por código normalizado.
 * @param {Array<{codigo:string, sinExtraer?:boolean}>} vmiRecords
 * @returns {Map<string, any>}
 */
export function buildVmiByCode(vmiRecords) {
  const vmiByCode = new Map();
  for (const r of vmiRecords) {
    const c = normalizarCodigo(r.codigo);
    if (!c) continue;
    const prev = vmiByCode.get(c);
    if (!prev || (prev.sinExtraer && !r.sinExtraer)) vmiByCode.set(c, r);
  }
  return vmiByCode;
}

/** map con concurrencia acotada */
async function pMap(items, fn, concurrency = 8) {
  const out = new Array(items.length);
  let i = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      out[idx] = await fn(items[idx], idx);
    }
  });
  await Promise.all(workers);
  return out;
}

/**
 * @param {object} args
 * @param {import('../config.js').ResolvedConfig} args.cfg
 * @param {string|null} [args.prevDir]
 * @param {boolean} [args.conToc]  extraer el TOC (outline) de los manuales de `05` (lento)
 * @param {(m:string)=>void} [args.log]
 */
export async function runBuild({ cfg, prevDir = null, conToc = false, log = () => {} }) {
  const outDir = cfg.outDir;
  await fs.mkdir(outDir, { recursive: true });

  // ---- compatibilidad de esquema con la carpeta anterior (--prev) ----
  // Se comprueba lo antes posible, antes de gastar tiempo parseando el
  // corpus: si la carpeta anterior es de un esquema distinto, la re-
  // extracción no destructiva (build/diff.js) podría comparar columnas que ya
  // no existen y generar cambio_pendiente falsos, o perder de vista overrides
  // en silencio -- justo lo que KTD7 existe para evitar. Se aborta pronto en
  // vez de arriesgar esa garantía.
  const prevManifest = prevDir ? await readManifest(prevDir) : null;
  if (prevDir && prevManifest && prevManifest.schema_version !== SCHEMA_VERSION) {
    throw new Error(
      `La carpeta anterior (--prev ${prevDir}) tiene esquema v${prevManifest.schema_version}, pero esta ` +
      `CLI escribe v${SCHEMA_VERSION}. Re-extraer con --prev entre versiones de esquema distintas no está ` +
      'soportado: podría perder overrides o generar cambios de origen falsos. Ejecuta sin --prev (los ' +
      'overrides existentes no se traspasarán) o usa una versión de esta CLI compatible con ese esquema.',
    );
  }

  // ---- XLSX ----
  const xlsx = (await import('xlsx')).default;
  const planWalk = await walkDir(cfg.roots.plan);
  const matWalk = await walkDir(cfg.roots.materiales);
  logWalkErrors('plan (03)', planWalk.errors, log);
  logWalkErrors('materiales (06)', matWalk.errors, log);
  const planXlsx = planWalk.files.find((f) => f.type === 'xlsx');
  const matXlsx = matWalk.files.find((f) => f.type === 'xlsx');
  if (!planXlsx) throw new Error(`no se encontró el XLSX del plan en ${cfg.roots.plan}`);
  if (!matXlsx) throw new Error(`no se encontró Listas de materiales.xlsx en ${cfg.roots.materiales}`);
  log(`plan:      ${planXlsx.name}`);
  log(`materiales: ${matXlsx.name}`);
  let plan;
  let materiales;
  try {
    plan = parsePlan(xlsx, xlsx.readFile(path.join(cfg.roots.plan, planXlsx.relPath)));
  } catch (e) {
    throw new Error(`no se pudo leer el XLSX del plan (${planXlsx.relPath}): ${e.message}`);
  }
  try {
    materiales = parseMateriales(xlsx, xlsx.readFile(path.join(cfg.roots.materiales, matXlsx.relPath)));
  } catch (e) {
    throw new Error(`no se pudo leer Listas de materiales.xlsx (${matXlsx.relPath}): ${e.message}`);
  }
  for (const a of [...plan.avisos, ...materiales.avisos]) log(`  aviso XLSX: ${a}`);

  // ---- VMIs ----
  const { files: vmiFiles, errors: vmiErrors } = await walkDir(cfg.roots.vmi);
  logWalkErrors('VMI (04)', vmiErrors, log);
  const vmiPdfs = vmiFiles.filter((f) => f.type === 'pdf' && esVmiIndividual(path.basename(f.name)));
  log(`VMI: parseando ${vmiPdfs.length} PDFs...`);
  let done = 0;
  const vmiRecords = await pMap(vmiPdfs, async (f) => {
    const codigo = path.basename(f.name).replace(/\.pdf$/i, '').replace(/_A\d+$/i, '');
    const ciclo = f.relPath.split('/')[0];
    let rec;
    try {
      rec = parseVmi(await pdfToLines(await fs.readFile(path.join(cfg.roots.vmi, f.relPath))), { codigo });
    } catch (e) {
      rec = { codigo, sinExtraer: true, motivo: `error al leer el PDF: ${e.message}` };
    }
    rec.relPath = f.relPath;
    rec.ciclo = ciclo;
    if ((++done % 100) === 0) log(`  ${done}/${vmiPdfs.length}`);
    return rec;
  });
  const sinExtraer = vmiRecords.filter((r) => r.sinExtraer);
  log(`VMI: ${vmiRecords.length} parseados, ${sinExtraer.length} sin extraer (${(100 * sinExtraer.length / vmiRecords.length).toFixed(1)}%)`);

  // ---- manuales de `05` ----
  const { files: manFiles, errors: manErrors } = await walkDir(cfg.roots.manuales);
  logWalkErrors('manuales (05)', manErrors, log);
  /** @type {Record<string, any[]>} */
  const bySub = {};
  for (const f of manFiles) {
    const seg = f.relPath.includes('/') ? f.relPath.slice(0, f.relPath.indexOf('/')) : '.';
    if (seg === '.') continue;
    (bySub[seg] ??= []).push(f);
  }
  const manualesDirs = Object.entries(bySub).map(([name, files]) => ({ name, relPath: name, files }));

  /** @type {Record<string, any[]>} */
  const tocPorManual = {};
  if (conToc) {
    const manPdfs = manFiles.filter((f) => f.type === 'pdf');
    log(`TOC: leyendo outline de ${manPdfs.length} manuales...`);
    await pMap(manPdfs, async (f) => {
      try {
        tocPorManual[f.relPath] = await pdfOutline(await fs.readFile(path.join(cfg.roots.manuales, f.relPath)));
      } catch {
        tocPorManual[f.relPath] = [];
      }
    }, 6);
  }

  // ---- modelo ----
  const model = buildCycleModel({ plan, materiales });
  const catalog = buildCatalog({ materiales, vmiRecords });
  const join = buildJoinGraph({ plan, materiales, vmiRecords, manualesDirs, tocPorManual });
  const vmiByCode = buildVmiByCode(vmiRecords);
  log(`unión: ${join.resumen.sistemas} sistemas, ${join.resumen.actividades} actividades, ${join.resumen.incidencias} incidencias`);

  // ---- versión de carpeta de datos ----
  const dataFolderVersion = (prevManifest?.data_folder_version ?? 0) + 1;

  // ---- escribir ----
  const dbPath = path.join(outDir, 'data.sqlite');
  const { counts } = await writeDatabase(dbPath, {
    plan, materiales, model, catalog, join, vmiByCode,
    meta: { plan_xlsx: planXlsx.name, materiales_xlsx: matXlsx.name, data_folder_version: String(dataFolderVersion) },
  });
  log(`db: ${JSON.stringify(counts)}`);

  // ---- re-extracción no destructiva (U7): traspasar overrides + registrar diffs ----
  let diff = null;
  if (prevDir) {
    const prevDb = path.join(prevDir, 'data.sqlite');
    diff = await carryOverridesAndDiff(dbPath, prevDb);
    log(`diff vs ${prevDir}: ${diff.overridesCopiados} overrides y ${diff.fichasCopiadas} fichas traspasados` +
      (diff.overridesHuerfanos ? ` (${diff.overridesHuerfanos} sin destino, revisar incidencias)` : '') +
      `; ${diff.cambios} cambios de origen marcados para revisión ${JSON.stringify(diff.cambiosPorEntidad)}`);
  }

  let copy = { copiados: 0, excluidos: [], fallidos: [], bytes: 0, porArea: {} };
  if (cfg.bundlePdfs) {
    copy = await selectAndCopyPdfs({ roots: cfg.roots, outDir, log });
    log(`pdfs: ${copy.copiados} copiados (${(copy.bytes / 1e6).toFixed(0)} MB), ${copy.excluidos.length} excluidos (mega-PDF)` +
      (copy.fallidos.length ? `, ${copy.fallidos.length} fallidos` : ''));
  } else {
    log('pdfs: omitidos (bundlePdfs=false)');
  }

  const manifest = await writeManifest(outDir, {
    dataFolderVersion,
    sources: {
      plan_xlsx: planXlsx.name,
      materiales_xlsx: matXlsx.name,
      cdrom_root: cfg.cdromRoot ?? null,
    },
    counts: { ...counts, vmi_sin_extraer: sinExtraer.length, pdfs: copy.copiados, pdfs_fallidos: copy.fallidos.length },
    // avisos de los parsers XLSX (p. ej. hoja/columna/cabecera no encontrada):
    // visibles en la propia carpeta de datos, no solo en el log de la consola.
    avisos: [...plan.avisos, ...materiales.avisos],
  });

  return {
    outDir,
    schemaVersion: SCHEMA_VERSION,
    dataFolderVersion,
    counts: manifest.counts,
    incidencias: join.incidencias,
    sinExtraer: sinExtraer.map((r) => ({ relPath: r.relPath, motivo: r.motivo })),
    diff,
    copy,
  };
}
