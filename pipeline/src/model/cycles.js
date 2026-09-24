// Modelo de ciclos de mantenimiento (R9–R12 del plan).
//
// Dos programas acumulativos:
//   - por kilómetros:  I1 -> I2 -> IM1 -> IM2 -> IM3 -> R1 -> R2
//   - por horas de motor diésel:  RDH1..RDH7 (500/1000/2000/4000/6000/8000/12000 h),
//     dentro del grupo NS
//   + grupo NS: tareas según condición, cuya frecuencia está en el plan (hoja de
//     PUESTA EN SERVICIO / OBSERVACIONES), no en un contador.
// Un nivel puede estar partido en lotes disjuntos (IM1A/B/C…), tomados de la
// columna PM del Excel de materiales.

export const KM_NIVELES = ['I1', 'I2', 'IM1', 'IM2', 'IM3', 'R1', 'R2'];

// Intervalos del programa por horas: dato de dominio confirmado por el usuario
// (coincide con el modelo de mantenimiento preventivo de flota-locomotoras).
export const RDH_INTERVALOS_H = {
  RDH1: 500, RDH2: 1000, RDH3: 2000, RDH4: 4000, RDH5: 6000, RDH6: 8000, RDH7: 12000,
};
export const RDH_NIVELES = Object.keys(RDH_INTERVALOS_H);

/**
 * @param {object} args
 * @param {ReturnType<import('../corpus/xlsx-plan.js').parsePlan>} args.plan
 * @param {ReturnType<import('../corpus/xlsx-materiales.js').parseMateriales>} args.materiales
 */
export function buildCycleModel({ plan, materiales }) {
  const cicloInfo = Object.fromEntries((plan?.ciclos ?? []).map((c) => [c.codigo, c]));

  const kmNiveles = KM_NIVELES.map((codigo, i) => ({
    codigo,
    orden: i + 1,
    descripcion: cicloInfo[codigo]?.descripcion ?? null,
    kmMedios: cicloInfo[codigo]?.kmMedios ?? null,
    kmNum: cicloInfo[codigo]?.kmNum ?? null,
  }));

  const horasNiveles = RDH_NIVELES.map((codigo, i) => ({
    codigo,
    orden: i + 1,
    intervaloH: RDH_INTERVALOS_H[codigo],
  }));

  // lotes + membresía de materiales por nivel y por lote
  /** @type {Record<string, Set<string>>} */
  const lotesSet = {};
  /** @type {Record<string, Set<string>>} */
  const materialesPorNivel = {};
  // actividadesPorLote: código de lote completo (p.ej. "IM1A") -> tareas.
  // A diferencia de lotesSet (solo qué lotes existen por nivel), esto es lo
  // que permite el desglose por lote de R11/R12/AE3 -- qué actividad cae en
  // cada lote, no solo qué lotes hay.
  /** @type {Record<string, Set<string>>} */
  const actividadesPorLote = {};
  for (const f of materiales?.filas ?? []) {
    if (!f.nivel) continue;
    if (f.lote) {
      const loteCodigo = f.nivel + f.lote;
      (lotesSet[f.nivel] ??= new Set()).add(loteCodigo);
      if (f.tarea) (actividadesPorLote[loteCodigo] ??= new Set()).add(f.tarea);
    }
    if (f.tarea) {
      (materialesPorNivel[f.nivel] ??= new Set()).add(f.tarea);
    }
  }
  const lotes = Object.fromEntries(
    Object.entries(lotesSet)
      .filter(([, s]) => s.size > 0)
      .map(([k, s]) => [k, [...s].sort()]),
  );

  return {
    programas: {
      km: { tipo: 'acumulativo', unidad: 'km', niveles: kmNiveles },
      horas: { tipo: 'acumulativo', unidad: 'horas_motor', niveles: horasNiveles },
    },
    ns: {
      descripcion: cicloInfo.NS?.descripcion ?? 'Tareas según condición',
      incluyePrograma: 'horas',
    },
    lotes,
    materialesPorNivel: Object.fromEntries(
      Object.entries(materialesPorNivel).map(([k, s]) => [k, [...s].sort()]),
    ),
    actividadesPorLote: Object.fromEntries(
      Object.entries(actividadesPorLote).map(([k, s]) => [k, [...s].sort()]),
    ),
  };
}

/**
 * Actividades de un nivel de ciclo (conjunto que se hace en ese nivel).
 * La matriz del plan ya marca cada ciclo donde una actividad aplica, así que
 * el conjunto de un nivel km es directo. Para RDH* el plan no tiene columna, así
 * que se deriva del Excel de materiales (parcial: solo las que consumen material).
 *
 * @returns {{codigos:string[], fuente:'plan'|'materiales'|'plan+materiales', parcial:boolean}}
 */
export function actividadesDeNivel(model, plan, nivel) {
  if (KM_NIVELES.includes(nivel)) {
    const codigos = (plan?.actividades ?? [])
      .filter((a) => a.ciclos.includes(nivel))
      .map((a) => a.codigo);
    return { codigos: [...new Set(codigos)].sort(), fuente: 'plan', parcial: false };
  }
  if (RDH_NIVELES.includes(nivel)) {
    const codigos = model.materialesPorNivel[nivel] ?? [];
    return { codigos: [...codigos].sort(), fuente: 'materiales', parcial: true };
  }
  if (nivel === 'NS') {
    const delPlan = (plan?.actividades ?? []).filter((a) => a.ciclos.includes('NS')).map((a) => a.codigo);
    const deRdh = RDH_NIVELES.flatMap((n) => model.materialesPorNivel[n] ?? []);
    return {
      codigos: [...new Set([...delPlan, ...deRdh])].sort(),
      fuente: 'plan+materiales',
      parcial: true,
    };
  }
  return { codigos: [], fuente: 'plan', parcial: true };
}
