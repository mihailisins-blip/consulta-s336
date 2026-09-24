// Escritura de `data.sqlite` — el dataset estructurado + índice FTS5 que lee la
// app Flutter (KTD3 / R1 / R14 / R16). Usa `node:sqlite` (Node >=22 con
// --experimental-sqlite); su SQLite trae FTS5.

import { promises as fs } from 'node:fs';
import { normalizarCodigo } from '../model/codes.js';
import { actividadesDeNivel, RDH_NIVELES } from '../model/cycles.js';
import { openDb } from './sqlite.js';

const SCHEMA = `
CREATE TABLE meta (clave TEXT PRIMARY KEY, valor TEXT);

CREATE TABLE sistema (
  codigo TEXT PRIMARY KEY, nombre TEXT, carpeta_manual TEXT, fuente_nombre TEXT
);
CREATE TABLE manual (
  id INTEGER PRIMARY KEY, sistema_codigo TEXT, rel_path TEXT
);
CREATE TABLE manual_toc (
  manual_id INTEGER, orden INTEGER, titulo TEXT, pagina INTEGER, nivel INTEGER
);
CREATE TABLE ficha_sistema (
  sistema_codigo TEXT PRIMARY KEY, cuerpo TEXT, revisado INTEGER DEFAULT 0
);

CREATE TABLE nivel_ciclo (
  codigo TEXT PRIMARY KEY, programa TEXT, tipo TEXT, orden INTEGER,
  descripcion TEXT, km_num INTEGER, intervalo_h INTEGER
);
CREATE TABLE lote (nivel TEXT, codigo TEXT);
CREATE TABLE actividad_nivel (actividad_codigo TEXT, nivel_codigo TEXT);
-- Qué actividad cae en qué lote (R11/R12/AE3: desglose por lote de un nivel
-- partido) -- distinto de la tabla lote, que solo lista qué lotes existen
-- por nivel, sin decir qué actividad va en cada uno.
CREATE TABLE actividad_lote (actividad_codigo TEXT, lote_codigo TEXT);

CREATE TABLE actividad (
  codigo TEXT PRIMARY KEY,
  sistema_codigo TEXT,
  vmi_rel_path TEXT,
  ciclo_carpeta TEXT,
  sin_extraer INTEGER DEFAULT 0,
  motivo TEXT,
  componente TEXT,
  actividad_tipo TEXT,
  operacion TEXT,
  frecuencia TEXT,
  edicion TEXT,
  fecha TEXT,
  descripcion_plan TEXT,
  marca_seguridad INTEGER DEFAULT 0,
  observaciones_plan TEXT,
  zonas_trabajo TEXT,
  seguridad TEXT,          -- texto de la sección 1 del VMI (R6, colapsable en la UI) -- v3
  duracion TEXT,          -- R7: la rellena el curador (vía overrides); reservado para el simulador
  zona TEXT,              -- R7: idem; la zona operativa "de simulación", distinta de zonas_trabajo del VMI
  fuente_vmi INTEGER, fuente_plan INTEGER, fuente_materiales INTEGER
);
CREATE TABLE actividad_paso (
  actividad_codigo TEXT, orden INTEGER, fase TEXT, paso_n INTEGER, texto TEXT
);

CREATE TABLE catalogo (
  id TEXT PRIMARY KEY, codigo_erp TEXT, descripcion TEXT, fabricante TEXT,
  referencia TEXT, unidad TEXT, tipo TEXT, fuente TEXT
);
CREATE TABLE catalogo_alias (catalogo_id TEXT, alias TEXT);
CREATE TABLE actividad_material (
  actividad_codigo TEXT, catalogo_id TEXT, cant TEXT, cant_num REAL,
  ud TEXT, uso TEXT, reserva INTEGER, fuente TEXT
);

CREATE TABLE incidencia_extraccion (tipo TEXT, ref TEXT, detalle TEXT);

-- Ediciones del curador. La re-extracción NUNCA escribe aquí; solo la copia
-- desde la carpeta anterior (KTD7). La app compone cada campo como override ?? extraído.
CREATE TABLE overrides (
  entidad TEXT, id TEXT, campo TEXT, valor TEXT, actualizado TEXT,
  PRIMARY KEY (entidad, id, campo)
);
-- Diferencias detectadas en el origen respecto a la carpeta anterior, para
-- revisión del curador (R21).
CREATE TABLE cambio_pendiente (
  entidad TEXT, id TEXT, campo TEXT, valor_antes TEXT, valor_despues TEXT,
  revisado INTEGER DEFAULT 0
);

CREATE INDEX ix_actividad_sistema ON actividad(sistema_codigo);
CREATE INDEX ix_actnivel ON actividad_nivel(nivel_codigo);
CREATE INDEX ix_actmat_act ON actividad_material(actividad_codigo);
CREATE INDEX ix_actmat_cat ON actividad_material(catalogo_id);
CREATE INDEX ix_paso_act ON actividad_paso(actividad_codigo);

CREATE VIRTUAL TABLE busqueda USING fts5(
  tipo UNINDEXED, ref UNINDEXED, titulo, cuerpo,
  tokenize = 'unicode61 remove_diacritics 2'
);
`;

/**
 * @param {string} dbPath
 * @param {object} data
 * @param {ReturnType<import('../corpus/xlsx-plan.js').parsePlan>} data.plan
 * @param {ReturnType<import('../corpus/xlsx-materiales.js').parseMateriales>} data.materiales
 * @param {ReturnType<import('../model/cycles.js').buildCycleModel>} data.model
 * @param {ReturnType<import('../model/catalog.js').buildCatalog>} data.catalog
 * @param {ReturnType<import('../model/join.js').buildJoinGraph>} data.join
 * @param {Map<string, any>} data.vmiByCode  código normalizado -> registro VMI parseado
 * @param {Record<string,string>} [data.meta]
 */
export async function writeDatabase(dbPath, data) {
  const { plan, materiales, model, catalog, join, vmiByCode = new Map(), meta = {} } = data;
  await fs.rm(dbPath, { force: true });
  await fs.rm(`${dbPath}-journal`, { force: true });
  await fs.rm(`${dbPath}-wal`, { force: true });
  await fs.rm(`${dbPath}-shm`, { force: true });
  const db = await openDb(dbPath);
  try {
    db.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;');
    db.exec(SCHEMA);
    db.exec('BEGIN');
    return writeAll(db, { plan, materiales, model, catalog, join, vmiByCode, meta });
  } catch (err) {
    try { db.exec('ROLLBACK'); } catch { /* no había transacción abierta, o la conexión ya es inválida */ }
    throw err;
  } finally {
    db.close();
  }
}

/** Cuerpo de la escritura, ya dentro de BEGIN..COMMIT (ver writeDatabase). Todo síncrono -- node:sqlite no expone una API async. */
function writeAll(db, { plan, materiales, model, catalog, join, vmiByCode, meta }) {
  const run = (sql, ...params) => db.prepare(sql).run(...params);
  for (const [k, v] of Object.entries(meta)) run('INSERT INTO meta VALUES (?,?)', k, String(v));

  // --- ciclos ---
  const insNivel = db.prepare(
    'INSERT INTO nivel_ciclo (codigo,programa,tipo,orden,descripcion,km_num,intervalo_h) VALUES (?,?,?,?,?,?,?)',
  );
  for (const n of model.programas.km.niveles) {
    insNivel.run(n.codigo, 'km', 'acumulativo', n.orden, n.descripcion, n.kmNum, null);
  }
  for (const n of model.programas.horas.niveles) {
    insNivel.run(n.codigo, 'horas', 'acumulativo', n.orden, null, null, n.intervaloH);
  }
  insNivel.run('NS', 'ns', 'condicion', 99, model.ns.descripcion, null, null);
  const insLote = db.prepare('INSERT INTO lote VALUES (?,?)');
  for (const [nivel, lotes] of Object.entries(model.lotes)) {
    for (const l of lotes) insLote.run(nivel, l);
  }

  // --- sistemas + manuales + fichas ---
  const insSis = db.prepare('INSERT INTO sistema VALUES (?,?,?,?)');
  const insMan = db.prepare('INSERT INTO manual (id,sistema_codigo,rel_path) VALUES (?,?,?)');
  const insToc = db.prepare('INSERT INTO manual_toc VALUES (?,?,?,?,?)');
  const insFicha = db.prepare('INSERT INTO ficha_sistema VALUES (?,?,?)');
  let manId = 0;
  for (const s of join.sistemas) {
    insSis.run(s.codigo, s.nombre, s.carpetaManual, s.fuenteNombre);
    for (const m of s.manuales) {
      const id = ++manId;
      insMan.run(id, s.codigo, m.relPath);
      (m.toc ?? []).forEach((t, i) => insToc.run(id, i, t.titulo, t.pagina, t.nivel));
    }
  }
  for (const f of join.fichasSistema) insFicha.run(f.codigo, f.cuerpo ?? '', f.revisado ? 1 : 0);

  // --- actividades ---
  const insAct = db.prepare(`INSERT INTO actividad
    (codigo,sistema_codigo,vmi_rel_path,ciclo_carpeta,sin_extraer,motivo,componente,actividad_tipo,
     operacion,frecuencia,edicion,fecha,descripcion_plan,marca_seguridad,observaciones_plan,zonas_trabajo,
     seguridad,fuente_vmi,fuente_plan,fuente_materiales)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);
  const insPaso = db.prepare('INSERT INTO actividad_paso VALUES (?,?,?,?,?)');
  const insActNivel = db.prepare('INSERT INTO actividad_nivel VALUES (?,?)');
  for (const a of join.actividades) {
    const rec = vmiByCode.get(a.codigo) ?? {};
    insAct.run(
      a.codigo, a.sistema, a.vmiRelPath,
      Array.isArray(a.ciclosCarpeta) ? a.ciclosCarpeta.join(',') : a.cicloCarpeta,
      a.sinExtraer ? 1 : 0, rec.motivo ?? null,
      a.componente, a.actividadTipo, a.operacion, rec.frecuencia ?? null, a.edicion, rec.fecha ?? null,
      a.descripcionPlan, a.marcaSeguridad ? 1 : 0, a.observacionesPlan, rec.zonasTrabajo ?? null,
      rec.seguridad ?? null,
      a.fuentes.vmi ? 1 : 0, a.fuentes.plan ? 1 : 0, a.fuentes.materiales ? 1 : 0,
    );
    for (const nivel of a.ciclos ?? []) insActNivel.run(a.codigo, nivel);
    let orden = 0;
    for (const fase of rec.procedimiento?.fases ?? []) {
      for (const p of fase.pasos) insPaso.run(a.codigo, orden++, fase.titulo || null, p.n, p.texto);
    }
  }

  // --- pertenencia a niveles RDH1..RDH7 (R9/R10/R12/AE3) ---
  // El plan de mantenimiento (03) no tiene columna por nivel RDH: esas tareas
  // solo aparecen marcadas 'NS' en su matriz (a.ciclos, arriba). La pertenencia
  // a un RDH concreto se deriva de la columna PM del Excel de materiales
  // (model/cycles.js: actividadesDeNivel). Se inserta solo para códigos que son
  // actividades reales de este build, para no dejar filas de actividad_nivel
  // colgantes cuando una tarea de materiales no tiene VMI ni fila de plan.
  const codigosActividad = new Set(join.actividades.map((a) => a.codigo));
  for (const nivel of RDH_NIVELES) {
    const { codigos } = actividadesDeNivel(model, plan, nivel);
    for (const codigo of codigos) {
      if (codigosActividad.has(codigo)) insActNivel.run(codigo, nivel);
    }
  }

  // --- actividad <-> lote (R11/R12/AE3: desglose por lote) ---
  // Igual criterio que arriba: solo para códigos que son actividades reales
  // de este build, no para cualquier tarea que aparezca en materiales.
  const insActLote = db.prepare('INSERT INTO actividad_lote VALUES (?,?)');
  for (const [loteCodigo, codigos] of Object.entries(model.actividadesPorLote ?? {})) {
    for (const codigo of codigos) {
      if (codigosActividad.has(codigo)) insActLote.run(codigo, loteCodigo);
    }
  }

  // --- catálogo ---
  const insCat = db.prepare('INSERT INTO catalogo VALUES (?,?,?,?,?,?,?,?)');
  const insAlias = db.prepare('INSERT INTO catalogo_alias VALUES (?,?)');
  for (const e of catalog.entradas) {
    insCat.run(e.id, e.codigoErp, e.descripcion, e.fabricante, e.referencia, e.unidad, e.tipo, e.fuente);
    for (const al of e.aliases ?? []) insAlias.run(e.id, al);
  }
  const insEnl = db.prepare('INSERT INTO actividad_material VALUES (?,?,?,?,?,?,?,?)');
  for (const l of catalog.enlaces) {
    insEnl.run(l.actividad, l.entradaId, l.cant, l.cantNum, l.ud, l.uso, l.reserva == null ? null : (l.reserva ? 1 : 0), l.fuente);
  }

  // --- incidencias ---
  const insInc = db.prepare('INSERT INTO incidencia_extraccion VALUES (?,?,?)');
  for (const i of join.incidencias) insInc.run(i.tipo, i.ref, i.detalle);

  // --- índice de búsqueda (R14: resultados mixtos) ---
  const insFts = db.prepare('INSERT INTO busqueda (tipo,ref,titulo,cuerpo) VALUES (?,?,?,?)');
  for (const a of join.actividades) {
    const rec = vmiByCode.get(a.codigo) ?? {};
    const pasos = (rec.procedimiento?.fases ?? []).flatMap((f) => f.pasos.map((p) => p.texto)).join(' ');
    const cuerpo = [a.descripcionPlan, a.operacion, a.componente, rec.zonasTrabajo, pasos]
      .filter(Boolean).join(' — ');
    insFts.run('actividad', a.codigo, a.descripcionPlan || a.operacion || a.codigo, cuerpo);
  }
  for (const s of join.sistemas) {
    const toc = s.manuales.flatMap((m) => (m.toc ?? []).map((t) => t.titulo)).join(' ');
    insFts.run('sistema', s.codigo, `${s.codigo} ${s.nombre ?? ''}`.trim(), `${s.nombre ?? ''} ${toc}`.trim());
  }
  for (const e of catalog.entradas) {
    insFts.run('catalogo', e.id, e.descripcion, [e.descripcion, ...(e.aliases ?? []), e.referencia, e.fabricante, e.codigoErp].filter(Boolean).join(' '));
  }

  db.exec('COMMIT');
  db.exec('PRAGMA wal_checkpoint(TRUNCATE); PRAGMA optimize;');
  const counts = {
    sistemas: db.prepare('SELECT count(*) c FROM sistema').get().c,
    actividades: db.prepare('SELECT count(*) c FROM actividad').get().c,
    catalogo: db.prepare('SELECT count(*) c FROM catalogo').get().c,
    enlaces: db.prepare('SELECT count(*) c FROM actividad_material').get().c,
    incidencias: db.prepare('SELECT count(*) c FROM incidencia_extraccion').get().c,
    busqueda: db.prepare('SELECT count(*) c FROM busqueda').get().c,
  };
  return { counts };
}

/** Helper de conveniencia para código normalizado (re-export). */
export { normalizarCodigo };
