// Grafo de unión actividad ⇄ ciclo ⇄ sistema ⇄ manual (R5 / R11 / R12 / R16 / R20).
//
// Une por la clave de sufijo (normalizarCodigo, KTD4). Lo que no une se registra
// como incidencia y NO se inventa (condición de parada del Goal Capsule):
//   - actividad sin sistema resoluble
//   - VMI sin fila en el plan / en el Excel de materiales
//   - fila del Excel / actividad del plan sin VMI
//
// Genera además una ficha de sistema en borrador por sistema, con el índice
// (TOC) de sus manuales de `05`.

import { normalizarCodigo, sistemaDeCodigo } from './codes.js';

const reCarpetaSistema = /^BB\d+\s+([A-Z]{1,3}\d[A-Z]?)\s+(.+)$/;

/** Extrae {codigo, nombre} del nombre de carpeta de un manual de `05`. */
export function parseCarpetaSistema(nombre) {
  const m = String(nombre).trim().match(reCarpetaSistema);
  if (!m) return null;
  return { codigo: m[1].toUpperCase(), nombre: m[2].trim() };
}

/**
 * @param {object} args
 * @param {ReturnType<import('../corpus/xlsx-plan.js').parsePlan>} args.plan
 * @param {ReturnType<import('../corpus/xlsx-materiales.js').parseMateriales>} args.materiales
 * @param {Array<{codigo:string, relPath?:string, componente?:string, actividadTipo?:string, operacion?:string, edicion?:string, sinExtraer?:boolean, ciclo?:string}>} args.vmiRecords
 *        cada VMI ya parseado; `relPath` = ruta relativa dentro de `04`; `ciclo` = subcarpeta (I1, NS…)
 * @param {Array<{name:string, relPath:string, files:Array<{relPath:string}>}>} [args.manualesDirs]
 *        subcarpetas de `05` con sus PDFs
 * @param {Record<string, Array>} [args.tocPorManual]  relPath de manual -> TOC (de pdfOutline)
 */
export function buildJoinGraph({ plan, materiales, vmiRecords, manualesDirs = [], tocPorManual = {} }) {
  const incidencias = [];
  const addInc = (tipo, ref, detalle) => incidencias.push({ tipo, ref, detalle });

  // ---- sistemas: unión de `05` (carpetas) y el plan ----
  /** @type {Map<string, any>} */
  const sistemas = new Map();
  for (const dir of manualesDirs) {
    const parsed = parseCarpetaSistema(dir.name);
    if (!parsed) { addInc('carpeta-manual-no-parseable', dir.relPath ?? dir.name, dir.name); continue; }
    const manuales = (dir.files ?? [])
      .filter((f) => /\.pdf$/i.test(f.relPath))
      .map((f) => ({ relPath: f.relPath, toc: tocPorManual[f.relPath] ?? [] }));
    sistemas.set(parsed.codigo, {
      codigo: parsed.codigo,
      nombre: parsed.nombre,
      fuenteNombre: '05',
      carpetaManual: dir.relPath ?? dir.name,
      manuales,
      actividades: [],
    });
  }
  for (const s of plan?.sistemas ?? []) {
    const existing = sistemas.get(s.codigo);
    if (existing) {
      if (!existing.nombre && s.nombre) existing.nombre = s.nombre;
    } else {
      sistemas.set(s.codigo, {
        codigo: s.codigo,
        nombre: s.nombre ?? null,
        fuenteNombre: 'plan',
        carpetaManual: null,
        manuales: [],
        actividades: [],
      });
    }
  }

  // ---- índices auxiliares ----
  const planPorCodigo = new Map((plan?.actividades ?? []).map((a) => [a.codigo, a]));
  const materialesPorTarea = new Map();
  for (const f of materiales?.filas ?? []) {
    if (!f.tarea) continue;
    if (!materialesPorTarea.has(f.tarea)) materialesPorTarea.set(f.tarea, []);
    materialesPorTarea.get(f.tarea).push(f);
  }
  const vmiPorCodigo = new Map();

  // ---- actividades: una por CÓDIGO (el mismo VMI se archiva en varias
  //      subcarpetas de ciclo; se deduplica acumulando `ciclosCarpeta`) ----
  /** @type {Map<string, any>} */
  const actMap = new Map();
  for (const rec of vmiRecords) {
    const codigo = normalizarCodigo(rec.codigo);
    if (!codigo) { addInc('vmi-codigo-no-normalizable', rec.relPath ?? rec.codigo, rec.codigo); continue; }

    const existing = actMap.get(codigo);
    if (existing) {
      if (rec.ciclo && !existing.ciclosCarpeta.includes(rec.ciclo)) existing.ciclosCarpeta.push(rec.ciclo);
      if (rec.relPath) existing.vmiRelPaths.push(rec.relPath);
      // si el registro que teníamos estaba sin extraer y este sí, sustituye los campos
      if (existing.sinExtraer && !rec.sinExtraer) {
        Object.assign(existing, {
          sinExtraer: false,
          componente: rec.componente ?? null,
          actividadTipo: rec.actividadTipo ?? null,
          operacion: rec.operacion ?? null,
          edicion: rec.edicion ?? null,
          // el contenido promocionado viene de ESTE ejemplar del VMI -- el
          // enlace "ver el PDF original" debe apuntar al mismo, no quedarse
          // en la primera copia (posiblemente sin extraer) que se vio.
          vmiRelPath: rec.relPath ?? existing.vmiRelPath,
          cicloCarpeta: rec.ciclo ?? existing.cicloCarpeta,
        });
        vmiPorCodigo.set(codigo, rec);
      }
      continue;
    }
    vmiPorCodigo.set(codigo, rec);

    const sistema = sistemaDeCodigo(codigo);
    if (!sistema || !sistemas.has(sistema)) {
      addInc('actividad-sin-sistema', codigo, `sistema '${sistema ?? '?'}' no está en \`05\` ni en el plan`);
    } else {
      sistemas.get(sistema).actividades.push(codigo);
    }

    const enPlan = planPorCodigo.get(codigo) ?? null;
    const enMateriales = materialesPorTarea.get(codigo) ?? [];
    if (!enPlan) addInc('vmi-sin-fila-plan', codigo, rec.relPath ?? '');

    actMap.set(codigo, {
      codigo,
      sistema: sistema && sistemas.has(sistema) ? sistema : null,
      vmiRelPath: rec.relPath ?? null,
      vmiRelPaths: rec.relPath ? [rec.relPath] : [],
      cicloCarpeta: rec.ciclo ?? null,
      ciclosCarpeta: rec.ciclo ? [rec.ciclo] : [],
      sinExtraer: !!rec.sinExtraer,
      componente: rec.componente ?? null,
      actividadTipo: rec.actividadTipo ?? null,
      operacion: rec.operacion ?? null,
      edicion: rec.edicion ?? null,
      descripcionPlan: enPlan?.descripcion ?? null,
      ciclos: enPlan?.ciclos ?? [],
      marcaSeguridad: enPlan?.marcaSeguridad ?? false,
      observacionesPlan: enPlan?.observaciones ?? null,
      fuentes: { vmi: true, plan: !!enPlan, materiales: enMateriales.length > 0 },
    });
  }
  const actividades = [...actMap.values()];

  // ---- incidencias inversas: plan / materiales sin VMI ----
  for (const a of plan?.actividades ?? []) {
    if (!vmiPorCodigo.has(a.codigo)) addInc('actividad-plan-sin-vmi', a.codigo, a.descripcion ?? '');
  }
  for (const tarea of materialesPorTarea.keys()) {
    if (!vmiPorCodigo.has(tarea) && !planPorCodigo.has(tarea)) {
      addInc('tarea-materiales-sin-vmi-ni-plan', tarea, '');
    }
  }

  // ---- fichas de sistema en borrador ----
  const fichasSistema = [...sistemas.values()].map((s) => ({
    codigo: s.codigo,
    nombre: s.nombre,
    manuales: s.manuales.map((m) => ({ relPath: m.relPath, toc: m.toc })),
    cuerpo: '',
    revisado: false,
  }));

  for (const s of sistemas.values()) s.actividades = [...new Set(s.actividades)].sort();

  return {
    sistemas: [...sistemas.values()].sort((a, b) => a.codigo.localeCompare(b.codigo)),
    actividades,
    fichasSistema,
    incidencias,
    resumen: {
      sistemas: sistemas.size,
      actividades: actividades.length,
      actividadesSinSistema: incidencias.filter((i) => i.tipo === 'actividad-sin-sistema').length,
      vmiSinPlan: incidencias.filter((i) => i.tipo === 'vmi-sin-fila-plan').length,
      planSinVmi: incidencias.filter((i) => i.tipo === 'actividad-plan-sin-vmi').length,
      incidencias: incidencias.length,
    },
  };
}
