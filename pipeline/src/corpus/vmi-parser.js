// Parser de una instrucción de trabajo VMI.
//
// Se ancla a la plantilla verificada (KTD9 del plan):
//   cabecera clave-valor  ->  1 Medidas de seguridad (común)  ->
//   2 Herramientas / Consumibles / Repuestos  ->  3 Zonas de trabajo  ->
//   4 Procedimiento (pasos numerados, fases Desmontaje/Montaje)
// (+ secciones 5 Hoja de control y 6 Índice de revisión, fuera del alcance R6).
//
// Un PDF que no encaje (sin cabecera reconocible o sin la sección 2) se marca
// `sinExtraer: true` con `motivo`, conservando su código y su ruta (R2 / AE1).
//
// Trabaja sobre las "líneas" que produce pdf-text.js; es puro y testeable
// contra fixtures de líneas.

const HEADER_LABELS = [
  'Vehículo', 'Componente', 'Actividad',
  'Herramientas especiales', 'Consumibles', 'Repuestos',
  'Frecuencia', 'Operación',
];

const CALLOUTS = new Set(['AVISO', 'PELIGRO', 'INFORMACIÓN', 'NOTA', 'ATENCIÓN']);

const SECTION_TITLES = {
  1: 'Medidas de seguridad',
  2: 'Herramientas / Consumibles / Repuestos',
  3: 'Zonas de trabajo',
  4: 'Procedimiento',
};

/** @typedef {import('./pdf-text.js').PdfLine} PdfLine */

const reFooter = /Página\s+\d+\s*\/\s*\d+/;
const reBareCode = /^VMI\.[0-9][\w.]*(?:\s*\([^)]*\))?$/i;
const reSectionHead = /^([1-6])\s+([A-Za-zÁÉÍÓÚÑáéíóúñ].*)$/;
const reStep = /^(\d{1,3})\.\s+(.+)$/;
const reSubstep = /^([a-z])\.\s+(.+)$/;
const rePartRef = /^\d{3}\s+\S/;

/**
 * Quita pies de página, líneas de código sueltas y cabeceras de página repetidas.
 * @param {PdfLine[]} lines
 */
function cleanLines(lines) {
  return lines.filter((l) => {
    // el pie real trae la fecha y la paginación en la misma línea
    // ("Fecha: DD.MM.AAAA ... Página N / M"), así que basta con reFooter.
    if (reFooter.test(l.text)) return false;
    if (reBareCode.test(l.text.trim())) return false;
    // cabecera de página repetida (título de sección a y>=785 en páginas >1)
    if (l.page > 1 && l.y >= 785) return false;
    return true;
  });
}

/** @param {PdfLine[]} raw */
function extractMeta(raw) {
  const p1 = raw.filter((l) => l.page === 1);
  let codigoEnDoc = null;
  for (const l of p1) {
    const m = l.text.trim().match(/^(VMI\.[0-9][\w.]+)$/i);
    if (m) { codigoEnDoc = m[1]; break; }
  }
  let edicion = null;
  const ed = raw.find((l) => /INSTRUCCIÓN DE TRABAJO/i.test(l.text));
  if (ed) {
    const m = ed.text.match(/Edición\s+(.+?)\s*$/i);
    if (m) edicion = m[1].trim();
  }
  let fecha = null;
  let paginas = null;
  for (const l of raw) {
    if (!fecha) {
      const m = l.text.match(/Fecha:\s*(\d{2}\.\d{2}\.\d{4})/);
      if (m) fecha = m[1];
    }
    if (!paginas) {
      const m = l.text.match(/Página\s+\d+\s*\/\s*(\d+)/);
      if (m) paginas = Number(m[1]);
    }
  }
  return { codigoEnDoc, edicion, fecha, paginas };
}

/**
 * Cabecera clave-valor de la página 1 (antes de "1 Medidas de seguridad").
 * @param {PdfLine[]} lines  ya limpias
 */
function parseHeaderBlock(lines) {
  const header = {};
  const p1 = lines.filter((l) => l.page === 1);
  // recorta en el primer marcador de sección
  let end = p1.length;
  for (let i = 0; i < p1.length; i++) {
    if (reSectionHead.test(p1[i].text) && p1[i].x < 65) { end = i; break; }
  }
  const block = p1.slice(0, end);

  for (let i = 0; i < block.length; i++) {
    const t = block[i].text;
    const md = t.match(/^Documentos de\s+(.*)$/);
    if (md) { header.documentosReferencia = md[1].trim() || null; continue; }
    for (const label of HEADER_LABELS) {
      const re = new RegExp(`^${label.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\$&')}:\\s*(.*)$`);
      const m = t.match(re);
      if (m) {
        let val = m[1].trim();
        // continuación en la columna de valores (x>=150) hasta la siguiente etiqueta
        for (let j = i + 1; j < block.length; j++) {
          const nt = block[j].text;
          if (block[j].x < 150) break;
          if (/^[A-ZÁÉÍÓÚ][\wáéíóúñ ]*:\s/.test(nt)) break;
          val += ` ${nt.trim()}`;
        }
        header[label] = val.replace(/\s+/g, ' ').trim() || null;
        break;
      }
    }
  }
  return header;
}

/** Índices de los marcadores de sección 1..6. @param {PdfLine[]} lines */
function findSections(lines) {
  /** @type {Record<number, number>} */
  const idx = {};
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].text.match(reSectionHead);
    if (!m || lines[i].x >= 65) continue;
    const n = Number(m[1]);
    if (idx[n] !== undefined) continue;
    const title = m[2].trim();
    const expected = SECTION_TITLES[n];
    // 1..4: el título debe casar (tolerante a mayúsculas/acentos); 5..6: cualquiera
    if (!expected || norm(title).startsWith(norm(expected).slice(0, 8))) {
      idx[n] = i;
    }
  }
  return idx;
}

function norm(s) {
  return (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

/**
 * Reparte una línea en columnas según los inicios de columna del encabezado.
 * @param {PdfLine} line
 * @param {number[]} colStarts  x de inicio de cada columna, ascendente
 */
function bucketByColumns(line, colStarts) {
  const cols = colStarts.map(() => []);
  for (const sp of line.spans) {
    let c = 0;
    for (let k = colStarts.length - 1; k >= 0; k--) {
      if (sp.x + 3 >= colStarts[k]) { c = k; break; }
    }
    cols[c].push(sp.text);
  }
  return cols.map((parts) => parts.join('').replace(/\s+/g, ' ').trim());
}

/**
 * Parsea una de las 3 subtablas de la sección 2.
 * @param {PdfLine[]} rows  líneas de la subsección (sin el subtítulo)
 * @returns {{aplica:boolean, raw?:string, columnas?:string[], filas?:any[], confianza?:string}}
 */
function parseSubTable(rows) {
  const nonEmpty = rows.filter((l) => l.text.trim());
  if (nonEmpty.length === 0) return { aplica: false };
  if (nonEmpty.length === 1 && /^no aplica\.?$/i.test(nonEmpty[0].text.trim())) {
    return { aplica: false };
  }
  if (nonEmpty.every((l) => /^no aplica\.?$/i.test(l.text.trim()))) return { aplica: false };

  // localiza la línea de encabezado de columnas
  const headerIdx = nonEmpty.findIndex((l) => /DESCRIPCIÓN/i.test(l.text) && /REFERENCIA/i.test(l.text));
  const raw = nonEmpty.map((l) => l.text).join('\n');
  if (headerIdx === -1) {
    return { aplica: true, raw, filas: [], confianza: 'sin-encabezado' };
  }

  const headerLine = nonEmpty[headerIdx];
  // nombres y x de inicio de columna, en orden
  const colSpans = headerLine.spans.filter((s) => s.text.trim());
  const columnas = colSpans.map((s) => s.text.trim().replace(/\*$/, ''));
  const colStarts = colSpans.map((s) => s.x);

  const body = nonEmpty.slice(headerIdx + 1).filter(
    (l) => !/^\*\s*S:\s*Sistemático/i.test(l.text) && !/^POR\s+TREN$/i.test(l.text),
  );

  /** @type {Array<Record<string,string>>} */
  const filas = [];
  let wrapped = false;
  for (const line of body) {
    const cells = bucketByColumns(line, colStarts);
    const firstCol = cells[0];
    const startsRow = firstCol && line.spans[0].x <= colStarts[0] + 6;
    // una fila nueva tiene descripción y algo más (ref/fabricante/uso)
    const hasOther = cells.slice(1).some((c) => c);
    if (startsRow && (hasOther || filas.length === 0)) {
      const fila = {};
      columnas.forEach((name, k) => { if (cells[k]) fila[name] = cells[k]; });
      filas.push(fila);
    } else if (filas.length) {
      wrapped = true;
      const prev = filas[filas.length - 1];
      cells.forEach((c, k) => {
        if (!c) return;
        const name = columnas[k] || `col${k}`;
        prev[name] = prev[name] ? `${prev[name]} ${c}` : c;
      });
    }
  }
  return {
    aplica: true,
    raw,
    columnas,
    filas,
    confianza: wrapped ? 'parcial' : 'ok',
  };
}

const rePhaseKeyword = /^(Desmontaje|Montaje|Desarme|Armado|Inspección|Verificación|Comprobación|Sustitución|Reemplazo|Cambio|Ajuste|Regulación|Limpieza|Lubricación|Engrase|Prueba|Ensayo|Puesta en servicio|Puesta fuera de servicio)\b/i;

/**
 * Sección 4: preámbulo, fases, pasos numerados y avisos.
 * @param {PdfLine[]} lines
 */
function parseProcedimiento(lines) {
  /** @type {{titulo:string, pasos:any[], notas:any[]}[]} */
  const fases = [];
  const preNotas = [];
  let preambulo = '';
  const nuevaFase = (t) => {
    const f = { titulo: t, pasos: [], notas: [] };
    fases.push(f);
    return f;
  };
  let fase = null;
  let paso = null;
  let callout = null;      // { titulo, texto } en curso
  let seenStepOrPhase = false;
  const items = lines.map((l) => ({ x: l.x, t: l.text.trim() })).filter((it) => it.t);

  const flushCallout = () => {
    if (!callout) return;
    callout.texto = callout.texto.replace(/\s+/g, ' ').trim();
    const target = paso?.notas ?? fase?.notas ?? preNotas;
    target.push(callout);
    callout = null;
  };

  for (let i = 0; i < items.length; i++) {
    const { x, t } = items[i];
    const next = items[i + 1]?.t ?? '';
    const next2 = items[i + 2]?.t ?? '';

    if (CALLOUTS.has(t.toUpperCase())) {
      flushCallout();
      callout = { titulo: t, texto: '' };
      continue;
    }

    const stepM = t.match(reStep);
    if (stepM && x < 70) {
      flushCallout();
      seenStepOrPhase = true;
      if (!fase) fase = nuevaFase('');
      paso = { n: Number(stepM[1]), texto: stepM[2].trim(), subpasos: [], notas: [] };
      fase.pasos.push(paso);
      continue;
    }
    const subM = t.match(reSubstep);
    if (subM && paso && x >= 62) {
      paso.subpasos.push({ letra: subM[1], texto: subM[2].trim() });
      continue;
    }

    // título de fase: palabra clave de operación (siempre corta el aviso en curso),
    // o la primera línea sustantiva tras el preámbulo cuando no hay aviso abierto.
    // Va ANTES del descarte de bloques de piezas (si no, "Desmontaje" seguido de
    // "002 ..." se perdería).
    const titleLike = x < 95 && !stepM && !subM && t.length <= 70 && !/[.;:]$/.test(t);
    const isPhaseKeyword = titleLike && rePhaseKeyword.test(t);
    const isFirstTitle = titleLike && !callout && !seenStepOrPhase && /[a-záéíóú]/.test(t);
    if (isPhaseKeyword || isFirstTitle) {
      flushCallout();
      fase = nuevaFase(t);
      paso = null;
      seenStepOrPhase = true;
      continue;
    }

    if (rePartRef.test(t)) continue; // "002 Cuerpo de acoplamiento" — se ignora para R6
    // encabezado de bloque de piezas: título a la izquierda seguido de líneas "NNN ..."
    if (x < 75 && (rePartRef.test(next) || rePartRef.test(next2))) continue;

    // texto de continuación
    if (callout) { callout.texto += (callout.texto ? ' ' : '') + t; continue; }
    if (!seenStepOrPhase) { preambulo += (preambulo ? ' ' : '') + t; continue; }
    if (paso) { paso.texto += ` ${t}`; continue; }
    if (fase) fase.notas.push(t);
  }
  flushCallout();

  for (const f of fases) for (const p of f.pasos) p.texto = p.texto.replace(/\s+/g, ' ').trim();
  return {
    preambulo: preambulo.replace(/\s+/g, ' ').trim() || null,
    notas: preNotas,
    fases: fases.filter((f) => f.titulo || f.pasos.length),
  };
}

/**
 * @param {PdfLine[]} rawLines  salida de pdf-text.js
 * @param {{codigo:string}} opts
 */
export function parseVmi(rawLines, { codigo }) {
  const meta = extractMeta(rawLines);
  const lines = cleanLines(rawLines);
  const header = parseHeaderBlock(lines);
  const sections = findSections(lines);

  const labelsFound = HEADER_LABELS.filter((k) => header[k] != null).length;
  const sinCabecera = labelsFound < 3;
  const sinSeccion2 = sections[2] === undefined;

  /** @type {any} */
  const record = {
    codigo,
    codigoEnDoc: meta.codigoEnDoc,
    edicion: meta.edicion,
    fecha: meta.fecha,
    paginas: meta.paginas,
    vehiculo: header['Vehículo'] || null,
    componente: header['Componente'] || null,
    actividadTipo: header['Actividad'] || null,
    documentosReferencia: header.documentosReferencia || null,
    frecuencia: header['Frecuencia'] || null,
    operacion: header['Operación'] || null,
    herramientasHeader: header['Herramientas especiales'] || null,
    consumiblesHeader: header['Consumibles'] || null,
    repuestosHeader: header['Repuestos'] || null,
    herramientas: { aplica: false },
    consumibles: { aplica: false },
    repuestos: { aplica: false },
    zonasTrabajo: null,
    seguridad: null,
    procedimiento: { preambulo: null, fases: [] },
    sinExtraer: false,
    motivo: null,
  };

  if (sinCabecera || sinSeccion2) {
    record.sinExtraer = true;
    record.motivo = [
      sinCabecera ? `cabecera no reconocida (${labelsFound}/8 etiquetas)` : null,
      sinSeccion2 ? 'sin la sección "2 Herramientas / Consumibles / Repuestos"' : null,
    ].filter(Boolean).join('; ');
    return record;
  }

  const endOf = (n) => {
    const nexts = [3, 4, 5, 6].filter((k) => k > n && sections[k] !== undefined).map((k) => sections[k]);
    return nexts.length ? Math.min(...nexts) : lines.length;
  };

  // Sección 1 (Medidas de seguridad, común a todo el VMI -- KTD9): se
  // guarda como un único bloque de texto tal cual aparece en el documento,
  // para mostrarlo colapsado en el detalle (R6) -- no se desglosa por
  // sub-sección (1.1, 1.2...) ni por tipo de aviso (AVISO/PELIGRO/...), a
  // diferencia de la sección 4 (procedimiento), que sí necesita esa
  // estructura para los pasos. `endOf()` no sirve aquí -- omite la sección 2
  // de su lista de "siguientes" a propósito (solo la usan las secciones
  // 3/4) -- así que se corta directo en sections[2], que existe siempre que
  // se llegue hasta aquí (sinSeccion2 ya habría retornado arriba).
  if (sections[1] !== undefined) {
    const s1 = lines.slice(sections[1] + 1, sections[2]);
    const txt = s1.map((l) => l.text.trim()).filter(Boolean);
    record.seguridad = txt.length ? txt.join('\n') : null;
  }

  // Sección 2
  const s2 = lines.slice(sections[2] + 1, endOf(2));
  const subAt = (name) => s2.findIndex((l) => norm(l.text) === norm(name) && l.x < 62);
  const subIdx = {
    herramientas: subAt('Herramientas especiales'),
    consumibles: subAt('Consumibles'),
    repuestos: subAt('Repuestos'),
  };
  const orderedSubs = Object.entries(subIdx).filter(([, i]) => i >= 0).sort((a, b) => a[1] - b[1]);
  for (let k = 0; k < orderedSubs.length; k++) {
    const [key, start] = orderedSubs[k];
    const nextStart = k + 1 < orderedSubs.length ? orderedSubs[k + 1][1] : s2.length;
    record[key] = parseSubTable(s2.slice(start + 1, nextStart));
  }

  // Sección 3
  if (sections[3] !== undefined) {
    const s3 = lines.slice(sections[3] + 1, endOf(3));
    const txt = s3
      .filter((l) => l.x < 130 && l.text.trim().length > 3 && !/^\d+\s/.test(l.text))
      .map((l) => l.text.trim());
    record.zonasTrabajo = txt.length ? [...new Set(txt)].join('; ') : null;
  }

  // Sección 4
  if (sections[4] !== undefined) {
    const s4 = lines.slice(sections[4] + 1, endOf(4));
    record.procedimiento = parseProcedimiento(s4);
  }

  return record;
}

/**
 * Conveniencia: lee el PDF y lo parsea.
 * @param {string} path
 * @param {{codigo?:string}} [opts]
 */
export async function parseVmiFile(path, opts = {}) {
  const { pdfFileToLines } = await import('./pdf-text.js');
  const nodePath = await import('node:path');
  const codigo = opts.codigo
    ?? nodePath.basename(path).replace(/\.pdf$/i, '').replace(/_A0$/i, '');
  const lines = await pdfFileToLines(path);
  return parseVmi(lines, { codigo });
}
