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

import { asociarImagenes, CALLOUTS, claveDeLinea } from './vmi-figuras.js';

const HEADER_LABELS = [
  'Vehículo', 'Componente', 'Actividad',
  'Herramientas especiales', 'Consumibles', 'Repuestos',
  'Frecuencia', 'Operación',
];

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

// Tipografía de la plantilla (medida en el corpus, KTD9): título de fase 18 pt,
// subtítulo 12 pt negrita, cuerpo 11 pt, viñeta "●" a 8 pt. Dos líneas del
// mismo párrafo distan ~15 pt; entre párrafos, viñetas o pasos, 18 pt o más.
const TAM_TITULO = 17;
const TAM_SUBTITULO = 11.5;
const SALTO_PARRAFO = 17;
// "●" es el símbolo de la plantilla; "ü" es la marca de verificación de Wingdings
// ("ü MODO R: ...") y va siempre seguida de espacio.
const reViñeta = /^(?:[●•▪]\s*|ü\s+)(.*)$/;

/**
 * Tipos de elemento del procedimiento: `titulo` (fase), `subtitulo`, `paso`
 * (con `n`), `subpaso` (con `etiqueta` = letra), `vineta`, `parrafo` y `aviso`
 * (con `etiqueta` = AVISO, PRECAUCIÓN...). Es una lista plana en orden de
 * lectura: la app la dibuja tal cual, y las figuras se intercalan por posición.
 * `fase` es el título vigente; `clave` la posición de lectura de su primera línea.
 * @typedef {{tipo:string, texto:string, n?:number, etiqueta?:string, fase:string|null,
 *   clave:number}} ElementoProcedimiento
 */

/**
 * Sección 4. Sin la tipografía de las líneas (fixtures antiguos, PDF que no la
 * da) cae a las reglas por texto: palabra clave de fase y primera línea
 * sustantiva.
 * @param {PdfLine[]} lines
 * @param {Set<object>} [consumidas]  pies y leyendas de figura, que no son texto del procedimiento
 * @returns {{items: ElementoProcedimiento[]}}
 */
function parseProcedimiento(lines, consumidas = new Set()) {
  const util = lines.filter((l) => l.text.trim() && !consumidas.has(l));
  const hayTipografia = util.some((l) => l.size != null);
  const hayNegrita = util.some((l) => l.negrita != null);
  /** @type {(ElementoProcedimiento & {x?:number})[]} */
  const items = [];
  let fase = null;
  let abierto = null;      // elemento al que pueden sumarse líneas de continuación
  let aviso = null;        // { item, regulares, titular, parrafos }: aviso con el cuerpo aún abierto
  let yPrev = null;        // línea anterior (para medir el salto vertical)
  let visto = false;       // ya hubo un título o un paso
  let ultimoPaso = 0;      // número del último paso numerado

  const nuevo = (tipo, linea, texto, extra = {}) => {
    const it = { tipo, texto, fase, clave: claveDeLinea(linea), x: linea.x, ...extra };
    items.push(it);
    if (tipo === 'titulo' || tipo === 'paso') visto = true;
    return it;
  };
  // título de fase por texto (palabra clave de operación), para cuando no hay tipografía
  const tituloPorTexto = (t, x) => x < 95 && t.length <= 70 && !/[.;:]$/.test(t) && rePhaseKeyword.test(t);

  for (let i = 0; i < util.length; i++) {
    const l = util[i];
    const t = l.text.trim();
    const x = l.x;
    const prev = yPrev;
    const gap = prev && prev.page === l.page ? prev.y - l.y : Infinity;
    const mismaPagina = gap !== Infinity;
    const siguiente = util[i + 1]?.text.trim() ?? '';
    const siguiente2 = util[i + 2]?.text.trim() ?? '';
    yPrev = l;

    // --- aviso: título (AVISO, PRECAUCIÓN...) y su cuerpo ---
    if (CALLOUTS.has(t.toUpperCase())) {
      abierto = null;
      const it = nuevo('aviso', l, '', { etiqueta: t.toUpperCase() });
      aviso = { item: it, regulares: false, titular: false, parrafos: 0 };
      continue;
    }
    if (aviso) {
      // El cuerpo del aviso va en negrita en la plantilla. Si abre con un
      // subtítulo en negrita (corto y sin punto final: "Pares de apriete"), el
      // párrafo normal que le sigue es también del aviso. Cualquier otra línea
      // normal ya es texto del procedimiento.
      const estructural = (reStep.test(t) && x < 70) || reViñeta.test(t)
        || (hayTipografia ? l.size >= TAM_TITULO : tituloPorTexto(t, x));
      const esNegrita = hayNegrita ? !!l.negrita : true;
      let sigue = mismaPagina && !estructural && gap <= 30;
      if (sigue && aviso.parrafos > 0 && hayNegrita) {
        if (aviso.regulares) sigue = gap <= SALTO_PARRAFO;
        else if (!esNegrita) sigue = aviso.titular && aviso.parrafos === 1;
      }
      if (sigue) {
        if (aviso.parrafos === 0) {
          aviso.item.texto = t;
          aviso.parrafos = 1;
          aviso.titular = esNegrita && t.length <= 45 && !/[.:;]$/.test(t);
          aviso.regulares = hayNegrita && !esNegrita;
        } else if (gap > SALTO_PARRAFO || (hayNegrita && !esNegrita && !aviso.regulares)) {
          aviso.item.texto += `\n${t}`;
          aviso.parrafos++;
          if (hayNegrita && !esNegrita) aviso.regulares = true;
        } else {
          aviso.item.texto += ` ${t}`;
        }
        continue;
      }
      aviso = null;
    }

    // --- paso y subpaso ---
    // Un paso va pegado al margen; pero junto a una captura de pantalla puede ir
    // a la derecha de la imagen (x ~ 240-280): vale si es el número que toca.
    const pasoM = t.match(reStep);
    if (pasoM && (x < 70 || Number(pasoM[1]) === ultimoPaso + 1)) {
      ultimoPaso = Number(pasoM[1]);
      abierto = nuevo('paso', l, pasoM[2].trim(), { n: ultimoPaso });
      continue;
    }
    const subM = t.match(reSubstep);
    if (subM && x >= 62 && items.some((it) => it.tipo === 'paso')) {
      abierto = nuevo('subpaso', l, subM[2].trim(), { etiqueta: subM[1] });
      continue;
    }

    // --- viñeta ---
    const vinM = t.match(reViñeta);
    if (vinM) {
      abierto = nuevo('vineta', l, vinM[1].trim());
      continue;
    }

    // --- título de fase (18 pt; líneas seguidas del mismo tamaño son un título) ---
    const esTitulo = hayTipografia
      ? l.size >= TAM_TITULO
      : tituloPorTexto(t, x) || (!visto && x < 95 && t.length <= 70 && !/[.;:]$/.test(t) && /[a-záéíóú]/.test(t));
    if (esTitulo) {
      const ant = items[items.length - 1];
      const continua = hayTipografia && ant?.tipo === 'titulo' && prev && prev.page === l.page
        && prev.size === l.size && gap <= 24;
      if (continua) {
        ant.texto += ` ${t}`;
        ant.fase = ant.texto;
        fase = ant.texto;
      } else {
        fase = t;
        nuevo('titulo', l, t);
      }
      abierto = null;
      continue;
    }

    // --- subtítulo: negrita 12 pt, o un rótulo de lista terminado en ":" que va en
    // MAYÚSCULAS ("CONSEJOS PARA LA LIMPIEZA:") o en negrita ("Test del compresor:").
    // Antes que los bloques de piezas: "Desmontaje" también va seguido de una
    // leyenda "002 Cuerpo..." cuando la imagen no se pudo asociar. ---
    const soloMayus = t === t.toUpperCase() && /[A-ZÁÉÍÓÚÑ]/.test(t);
    const esRotulo = /:$/.test(t) && t.length <= 90 && (soloMayus || (l.negrita && t.length <= 60));
    const esSubtitulo = hayTipografia
      && ((l.size >= TAM_SUBTITULO && l.size < TAM_TITULO) || esRotulo);
    if (esSubtitulo) {
      nuevo('subtitulo', l, t);
      abierto = null;
      continue;
    }

    if (rePartRef.test(t)) continue; // "002 Cuerpo de acoplamiento" — se ignora para R6
    // encabezado de bloque de piezas: título a la izquierda seguido de líneas "NNN ..."
    if (x < 75 && (rePartRef.test(siguiente) || rePartRef.test(siguiente2))) continue;

    // --- texto: continuación del elemento abierto, o párrafo nuevo ---
    if (abierto && mismaPagina && gap <= SALTO_PARRAFO) {
      abierto.texto += ` ${t}`;
      continue;
    }
    // un renglón sangrado al principio de página sigue el paso o la viñeta que
    // quedó abierto (la continuación va ~24 pt a la derecha de su marcador)
    if (abierto && !mismaPagina && abierto.tipo !== 'parrafo' && x >= abierto.x + 15) {
      abierto.texto += ` ${t}`;
      continue;
    }
    abierto = nuevo('parrafo', l, t);
  }

  const finales = items.filter((it) => it.texto || it.tipo === 'titulo');
  for (const it of finales) {
    it.texto = it.texto.replace(/[ \t]+/g, ' ').trim();
    delete it.x;
  }
  return { items: finales };
}

/**
 * @param {PdfLine[]} rawLines  salida de pdf-text.js
 * @param {{codigo:string, cajas?:import('./vmi-figuras.js').CajaImagen[]}} opts
 *   `cajas`: posición de las imágenes grandes del PDF (vmi-images.js); si se
 *   pasan, el registro trae además `figuras` (imágenes de zonas de trabajo y
 *   de procedimiento con su pie, leyenda y paso al que preceden).
 */
export function parseVmi(rawLines, { codigo, cajas = [] }) {
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
    procedimiento: { items: [] },
    figuras: [],
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

  // Imágenes de las secciones 3 y 4 (con su pie y leyenda). Son un añadido al
  // texto: si su asociación fallara por un caso raro, el VMI se queda sin
  // figuras pero NO deja de extraerse. Va antes que el procedimiento porque el
  // pie y la leyenda de cada figura no son texto del procedimiento.
  const consumidas = new Set();
  try {
    record.figuras = cajas.length ? asociarImagenes({ lines, sections, endOf, cajas, consumidas }) : [];
  } catch {
    record.figuras = [];
    consumidas.clear();
  }

  // Sección 4
  if (sections[4] !== undefined) {
    const s4 = lines.slice(sections[4] + 1, endOf(4));
    record.procedimiento = parseProcedimiento(s4, consumidas);
  }

  // Cada figura del procedimiento se dibuja justo antes del primer elemento que
  // la sigue en el documento: `antesDePaso` es su posición (`orden` en la BD).
  const { items } = record.procedimiento;
  for (const f of record.figuras) {
    if (f.seccion === 'procedimiento') f.antesDePaso = items.filter((it) => it.clave < f.clave).length;
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
  const lines = await pdfFileToLines(path, { fuentes: true });
  return parseVmi(lines, { codigo });
}
