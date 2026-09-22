// Parser del `03 Plan mantenimiento/…PLAN DE MANTENIMIENTO….XLSX`.
//
// Hojas usadas:
//   CICLOS             -> definición de I1..R2 + NS (km medios, tiempo medio)
//   PUESTA EN SERVICIO  -> tareas de una sola vez (código, descripción, intervalo)
//   PLAN MANTENIMIENTO  -> matriz autoritativa actividad × ciclo:
//        fila 6 = cabecera: CÓDIGO | DESCRIPCIÓN… | MARCA SEG. | I1 I2 IM1 IM2 IM3 R1 R2 NS | OBSERVACIONES
//        filas siguientes, código jerárquico:
//          "B"           grupo
//          "BA1"         sistema (nombre en DESCRIPCIÓN)
//          "BA1.01"      subsistema
//          "BA1.01.01"   ACTIVIDAD  (X en la columna del ciclo donde aplica)

import { normalizarCodigo, sistemaDeCodigo } from '../model/codes.js';

const CICLO_COLS = ['I1', 'I2', 'IM1', 'IM2', 'IM3', 'R1', 'R2', 'NS'];

const reGrupo = /^[A-Z]$/;
const reSistema = /^[A-Z]{1,3}\d[A-Z]?$/;
const reSub = /^[A-Z]{1,3}\d[A-Z]?\.\d{1,3}$/;
const reActividad = /^[A-Z]{1,3}\d[A-Z]?\.\d{1,3}\.\d{1,3}$/;

/** Devuelve las celdas de una hoja como matriz de strings (formateadas). */
function sheetMatrix(xlsx, ws) {
  return xlsx.utils.sheet_to_json(ws, { header: 1, raw: false, defval: null });
}

function firstNum(s) {
  if (s == null) return null;
  const m = String(s).replace(/\./g, '').match(/\d[\d]*/);
  return m ? Number(m[0]) : null;
}

/**
 * @param {import('xlsx')} xlsx
 * @param {import('xlsx').WorkBook} workbook
 */
export function parsePlan(xlsx, workbook) {
  const avisos = [];
  const has = (n) => workbook.SheetNames.includes(n);

  // ---- CICLOS ----
  const ciclos = [];
  if (has('CICLOS')) {
    const m = sheetMatrix(xlsx, workbook.Sheets.CICLOS);
    for (const row of m) {
      const cells = row.map((c) => (c == null ? '' : String(c).trim()));
      const codeCell = cells.find((c) => CICLO_COLS.includes(c) || c === 'NS');
      const ci = cells.indexOf(codeCell);
      if (ci >= 0 && codeCell && CICLO_COLS.includes(codeCell)) {
        const desc = cells.slice(ci + 1).find((c) => c && !/^\d/.test(c)) || null;
        const kmCell = cells.slice(ci + 1).find((c) => /\d{4,}/.test(c.replace(/\./g, '')));
        const tiempo = cells.slice(ci + 1).find((c) => /Años|años|meses/.test(c)) || null;
        ciclos.push({
          codigo: codeCell,
          descripcion: desc,
          kmMedios: kmCell || null,
          kmNum: firstNum(kmCell),
          tiempoMedio: tiempo,
        });
      }
    }
  } else {
    avisos.push("hoja 'CICLOS' ausente");
  }

  // ---- PUESTA EN SERVICIO ----
  const puestaEnServicio = [];
  if (has('PUESTA EN SERVICIO')) {
    const m = sheetMatrix(xlsx, workbook.Sheets['PUESTA EN SERVICIO']);
    let headerRow = -1;
    for (let i = 0; i < m.length; i++) {
      const r = m[i].map((c) => String(c ?? '').trim().toUpperCase());
      if (r.includes('CÓDIGO') || r.includes('CODIGO')) { headerRow = i; break; }
    }
    if (headerRow >= 0) {
      const hr = m[headerRow].map((c) => String(c ?? '').trim().toUpperCase());
      const cCod = Math.max(hr.indexOf('CÓDIGO'), hr.indexOf('CODIGO'));
      const cDesc = hr.indexOf('DESCRIPCIÓN') >= 0 ? hr.indexOf('DESCRIPCIÓN') : hr.indexOf('DESCRIPCION');
      const cInt = hr.indexOf('INTERVALO');
      for (let i = headerRow + 1; i < m.length; i++) {
        const row = m[i].map((c) => (c == null ? '' : String(c).trim()));
        const cod = row[cCod] || '';
        const desc = cDesc >= 0 ? row[cDesc] : '';
        if (!cod && !desc) continue;
        if (/^OPERACIONES|^NOTAS/i.test(cod)) continue;
        puestaEnServicio.push({
          codigo: cod === '--' ? null : normalizarCodigo(cod) || cod || null,
          codigoRaw: cod || null,
          descripcion: desc || null,
          intervalo: cInt >= 0 ? (row[cInt] || null) : null,
        });
      }
    } else {
      avisos.push("'PUESTA EN SERVICIO': sin fila de cabecera con CÓDIGO");
    }
  } else {
    avisos.push("hoja 'PUESTA EN SERVICIO' ausente");
  }

  // ---- PLAN MANTENIMIENTO ----
  const actividades = [];
  const sistemas = [];
  const grupos = [];
  if (has('PLAN MANTENIMIENTO')) {
    const ws = workbook.Sheets['PLAN MANTENIMIENTO'];
    const range = xlsx.utils.decode_range(ws['!ref']);
    const maxC = Math.min(range.e.c, 30);
    const get = (r, c) => {
      const cell = ws[xlsx.utils.encode_cell({ r, c })];
      return cell && cell.v != null ? String(cell.w ?? cell.v).trim() : '';
    };
    // cabecera: primera fila cuya col A sea "CÓDIGO" (sin límite de fila --
    // una versión editada de la hoja puede tener filas de título/leyenda
    // extra antes de la cabecera real).
    let hr = -1;
    for (let r = range.s.r; r <= range.e.r; r++) {
      if (/^CÓDIGO$|^CODIGO$/i.test(get(r, 0))) { hr = r; break; }
    }
    if (hr < 0) {
      avisos.push("'PLAN MANTENIMIENTO': sin fila de cabecera");
    } else {
      /** @type {Record<string, number>} */
      const cicloCol = {};
      let cObs = -1;
      let cMarca = -1;
      for (let c = 0; c <= maxC; c++) {
        const h = get(hr, c).toUpperCase();
        if (CICLO_COLS.includes(h)) cicloCol[h] = c;
        if (/MARCA/.test(h)) cMarca = c;
        if (/OBSERVAC/.test(h)) cObs = c;
      }
      for (let r = hr + 1; r <= range.e.r; r++) {
        const cod = get(r, 0);
        if (!cod) continue;
        const desc = get(r, 1);
        if (reGrupo.test(cod)) { grupos.push({ codigo: cod, nombre: desc || null }); continue; }
        if (reSistema.test(cod)) { sistemas.push({ codigo: cod, nombre: desc || null }); continue; }
        if (reSub.test(cod)) continue; // subsistema: no aporta al modelo
        if (reActividad.test(cod)) {
          const ciclos2 = CICLO_COLS.filter((k) => cicloCol[k] != null && /^x$/i.test(get(r, cicloCol[k])));
          actividades.push({
            codigo: normalizarCodigo(cod) || cod,
            codigoRaw: cod,
            sistema: sistemaDeCodigo(normalizarCodigo(cod) || cod),
            descripcion: desc || null,
            marcaSeguridad: cMarca >= 0 ? get(r, cMarca) === '!' : false,
            ciclos: ciclos2,
            observaciones: cObs >= 0 ? (get(r, cObs) || null) : null,
          });
        }
      }
    }
  } else {
    avisos.push("hoja 'PLAN MANTENIMIENTO' ausente");
  }

  return { ciclos, puestaEnServicio, actividades, sistemas, grupos, avisos };
}

/** @param {string} path */
export async function parsePlanFile(path) {
  const xlsx = (await import('xlsx')).default;
  return parsePlan(xlsx, xlsx.readFile(path));
}
