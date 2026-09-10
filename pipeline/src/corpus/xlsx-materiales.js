// Parser de `06 Catalogo piezas/Listas de materiales.xlsx`.
//
// Hoja única. Columnas: PM · TAREA · LISTA · PIEZA · DESCRIPCION · CANT · UD · RESERVA.
// Cada fila es un enlace material<->tarea con su cantidad, unidad y reserva.
// PIEZA es el código ERP interno (se conserva como texto, con sus ceros).

import { normalizarCodigo, parsePm } from '../model/codes.js';

/** Convierte "0,50" / "1.000" / "200" a número; null si no es numérico. */
export function parseCantidad(v) {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s || /[a-zA-Z]/.test(s.replace(/^kg$|^ud$|^l$|^bt$/i, ''))) {
    // deja pasar "Según necesidad" -> null
    if (!/^[\d.,\s]+$/.test(s)) return null;
  }
  // coma decimal española; sin separador de miles fiable, así que se asume
  // que una coma es decimal y un punto también
  const n = Number(s.replace(/\s/g, '').replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

/**
 * @param {import('xlsx')} xlsx  el módulo xlsx (SheetJS)
 * @param {import('xlsx').WorkBook} workbook
 * @returns {{filas: Array<{pm:string, nivel:string|null, lote:string|null, tarea:string|null, tareaRaw:string, lista:string|null, pieza:string|null, descripcion:string, cant:string|null, cantNum:number|null, ud:string|null, reserva:boolean|null}>, avisos:string[]}}
 */
export function parseMateriales(xlsx, workbook) {
  const sheetName = workbook.SheetNames[0];
  const ws = workbook.Sheets[sheetName];
  const rows = xlsx.utils.sheet_to_json(ws, { header: 1, raw: false, defval: null });
  const avisos = [];
  if (!rows.length) return { filas: [], avisos: ['hoja vacía'] };

  const head = rows[0].map((c) => String(c ?? '').trim().toUpperCase());
  const col = (name) => head.indexOf(name);
  const idx = {
    pm: col('PM'), tarea: col('TAREA'), lista: col('LISTA'), pieza: col('PIEZA'),
    descripcion: col('DESCRIPCION'), cant: col('CANT'), ud: col('UD'), reserva: col('RESERVA'),
  };
  for (const [k, v] of Object.entries(idx)) {
    if (v < 0) avisos.push(`columna '${k.toUpperCase()}' no encontrada en la cabecera`);
  }

  /** @type {any[]} */
  const filas = [];
  for (let r = 1; r < rows.length; r++) {
    const row = rows[r];
    const get = (i) => (i >= 0 && row[i] != null ? String(row[i]).trim() : '');
    const pmRaw = get(idx.pm);
    const tareaRaw = get(idx.tarea);
    if (!pmRaw && !tareaRaw && !get(idx.pieza)) continue; // fila en blanco

    const { nivel, lote } = parsePm(pmRaw);
    const cantRaw = get(idx.cant) || null;
    const reservaRaw = get(idx.reserva).toLowerCase();
    filas.push({
      pm: pmRaw,
      nivel,
      lote,
      tareaRaw,
      tarea: normalizarCodigo(tareaRaw),
      lista: get(idx.lista) || null,
      pieza: get(idx.pieza) || null,
      descripcion: get(idx.descripcion),
      cant: cantRaw,
      cantNum: parseCantidad(cantRaw),
      ud: get(idx.ud) || null,
      reserva: reservaRaw ? /^s[íi]$/.test(reservaRaw) : null,
    });
  }
  return { filas, avisos };
}

/**
 * @param {string} path
 */
export async function parseMaterialesFile(path) {
  const xlsx = (await import('xlsx')).default;
  return parseMateriales(xlsx, xlsx.readFile(path));
}
