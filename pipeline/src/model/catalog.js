// Catálogo normalizado de materiales y herramientas (KTD5 / R3 / R8 del plan).
//
// Identidad de una entrada = código ERP (columna PIEZA del Excel de materiales),
// más descripción canónica, alias, fabricante, referencia, unidad. La cantidad y
// el uso (S/SC) NO viven en la entrada, sino en el enlace actividad<->entrada,
// para que un material usado en varias tareas con cantidades distintas sea una
// sola entrada.
//
// El Excel de materiales es la fuente primaria (trae el código ERP). Las tablas
// de sección 2 de los VMI son secundarias: aportan las herramientas (que no
// están en el Excel) y el indicador de uso S/SC.

import { normalizarCodigo } from './codes.js';

const norm = (s) => String(s ?? '')
  .normalize('NFD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/** Toma el valor más frecuente; a igualdad, el más largo. */
function canonico(valores) {
  const cont = new Map();
  for (const v of valores) {
    if (!v) continue;
    cont.set(v, (cont.get(v) ?? 0) + 1);
  }
  let best = null;
  let bestKey = -1;
  for (const [v, c] of cont) {
    const key = c * 1000 + v.length;
    if (key > bestKey) { best = v; bestKey = key; }
  }
  return best;
}

/** @param {Record<string,string>} fila  fila de tabla de VMI (columnas variables) */
function campoTabla(fila, ...nombres) {
  for (const n of nombres) {
    for (const [k, v] of Object.entries(fila)) {
      if (norm(k).includes(norm(n)) && v) return String(v).trim();
    }
  }
  return null;
}

/**
 * @param {object} args
 * @param {ReturnType<import('../corpus/xlsx-materiales.js').parseMateriales>} args.materiales
 * @param {Array<{codigo:string, herramientas?:any, consumibles?:any, repuestos?:any}>} [args.vmiRecords]
 */
export function buildCatalog({ materiales, vmiRecords = [] }) {
  /** @type {Map<string, any>} */
  const porErp = new Map();
  /** @type {Array<{actividad:string|null, entradaId:string, cant:string|null, cantNum:number|null, ud:string|null, uso:string|null, reserva:boolean|null, fuente:string}>} */
  const enlaces = [];

  // ---- 1. sembrar desde el Excel de materiales (por PIEZA) ----
  /** @type {Map<string,string[]>} */
  const descsPorErp = new Map();
  /** @type {Map<string,string[]>} */
  const udsPorErp = new Map();
  for (const f of materiales.filas) {
    if (!f.pieza) continue;
    (descsPorErp.get(f.pieza) ?? descsPorErp.set(f.pieza, []).get(f.pieza)).push(f.descripcion);
    if (f.ud) (udsPorErp.get(f.pieza) ?? udsPorErp.set(f.pieza, []).get(f.pieza)).push(f.ud);
    enlaces.push({
      actividad: f.tarea,
      entradaId: `erp:${f.pieza}`,
      cant: f.cant,
      cantNum: f.cantNum,
      ud: f.ud,
      uso: null,
      reserva: f.reserva,
      fuente: 'materiales',
    });
  }
  let aliasesFusionados = 0;
  for (const [pieza, descs] of descsPorErp) {
    const distintas = [...new Set(descs.filter(Boolean))];
    const desc = canonico(descs);
    const aliases = distintas.filter((d) => d !== desc);
    aliasesFusionados += aliases.length;
    porErp.set(pieza, {
      id: `erp:${pieza}`,
      codigoErp: pieza,
      descripcion: desc,
      aliases,
      fabricante: null,
      referencia: null,
      unidad: canonico(udsPorErp.get(pieza) ?? []),
      tipo: 'material',
      fuente: 'erp',
    });
  }

  // ---- 2. herramientas y consumibles de los VMI ----
  /** @type {Map<string, any>} */
  const porVmi = new Map();
  const buscaErp = (desc, ref) => {
    const nd = norm(desc);
    const nr = norm(ref);
    for (const e of porErp.values()) {
      const ne = norm(e.descripcion);
      if (nd && (ne.includes(nd) || nd.includes(ne))) return e;
      if (nr && nr.length >= 4 && ne.includes(nr)) return e;
      for (const a of e.aliases) if (nd && norm(a).includes(nd)) return e;
    }
    return null;
  };

  for (const rec of vmiRecords) {
    const actividad = normalizarCodigo(rec.codigo);
    for (const [tipo, tabla] of [
      ['herramienta', rec.herramientas],
      ['consumible', rec.consumibles],
      ['consumible', rec.repuestos],
    ]) {
      if (!tabla?.aplica || !Array.isArray(tabla.filas)) continue;
      for (const fila of tabla.filas) {
        const desc = campoTabla(fila, 'descripcion', 'descripción');
        if (!desc) continue;
        const ref = campoTabla(fila, 'referencia');
        const fab = campoTabla(fila, 'fabricante');
        const cant = campoTabla(fila, 'cantidad', 'cantidad por tren');
        const uso = campoTabla(fila, 'uso');

        const erp = tipo === 'herramienta' ? null : buscaErp(desc, ref);
        let entradaId;
        if (erp) {
          entradaId = erp.id;
          if (desc && desc !== erp.descripcion && !erp.aliases.includes(desc)) {
            erp.aliases.push(desc);
            aliasesFusionados++;
          }
          if (!erp.fabricante && fab) erp.fabricante = fab;
          if (!erp.referencia && ref) erp.referencia = ref;
        } else {
          const key = `vmi:${norm(desc)}`;
          if (!porVmi.has(key)) {
            porVmi.set(key, {
              id: key,
              codigoErp: null,
              descripcion: desc,
              aliases: [],
              fabricante: fab,
              referencia: ref,
              unidad: null,
              tipo,
              fuente: 'vmi',
            });
          }
          entradaId = key;
        }
        enlaces.push({
          actividad,
          entradaId,
          cant: cant || null,
          cantNum: null,
          ud: null,
          uso: uso === 'S' || uso === 'SC' ? uso : null,
          reserva: null,
          fuente: 'vmi',
        });
      }
    }
  }

  const entradas = [...porErp.values(), ...porVmi.values()];
  // dedup de enlaces por (actividad, entradaId): conserva el que trae más datos
  const enlaceKey = (e) => `${e.actividad ?? '?'}|${e.entradaId}`;
  /** @type {Map<string, any>} */
  const enlaceMap = new Map();
  for (const e of enlaces) {
    const k = enlaceKey(e);
    const prev = enlaceMap.get(k);
    if (!prev) { enlaceMap.set(k, e); continue; }
    enlaceMap.set(k, {
      ...prev,
      cant: prev.cant ?? e.cant,
      cantNum: prev.cantNum ?? e.cantNum,
      ud: prev.ud ?? e.ud,
      uso: prev.uso ?? e.uso,
      reserva: prev.reserva ?? e.reserva,
      fuente: prev.fuente === e.fuente ? prev.fuente : `${prev.fuente}+${e.fuente}`,
    });
  }
  const enlacesFinal = [...enlaceMap.values()];

  return {
    entradas,
    enlaces: enlacesFinal,
    metricas: {
      entradas: entradas.length,
      conCodigoErp: entradas.filter((e) => e.codigoErp).length,
      sinCodigoErp: entradas.filter((e) => !e.codigoErp).length,
      aliasesFusionados,
      enlaces: enlacesFinal.length,
      enlacesSinActividad: enlacesFinal.filter((e) => !e.actividad).length,
    },
  };
}
