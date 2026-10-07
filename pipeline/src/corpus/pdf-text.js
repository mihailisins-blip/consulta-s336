// Extracción de texto posicional de un PDF, con pdfjs-dist (sin DOM, Node puro).
//
// Devuelve un flujo de "líneas" ordenado: por página, y descendente dentro de
// la página, x ascendente dentro de la línea. Cada línea trae sus `spans`
// (trozos de texto con su x) y un `text` ya unido. Esto es lo que consumen los
// parsers (vmi-parser.js), que trabajan sobre líneas, no sobre el PDF.

import { readFile } from 'node:fs/promises';

/**
 * `size` (pt) y `negrita` describen la tipografía dominante de la línea (la que
 * cubre más caracteres). `negrita` solo se rellena con `fuentes: true`: hay que
 * resolver los nombres de fuente de la página, que cuesta un `getOperatorList`.
 * @typedef {{page:number, y:number, x:number, spans:{x:number,text:string}[], text:string,
 *   size?:number, negrita?:boolean}} PdfLine
 */

/** Nombre de cada fuente de la página (id de pdfjs -> "ABCDEF+Arial-BoldMT"). */
async function nombresDeFuentes(page, items) {
  const nombres = new Map();
  try { await page.getOperatorList(); } catch { return nombres; }
  for (const it of items) {
    if (!it.fontName || nombres.has(it.fontName)) continue;
    try { nombres.set(it.fontName, page.commonObjs.get(it.fontName)?.name ?? ''); } catch { nombres.set(it.fontName, ''); }
  }
  return nombres;
}

/** Tipografía dominante de los trozos de una línea. */
function tipografiaDominante(trozos) {
  let total = 0;
  let negrita = 0;
  const porTamano = new Map();
  for (const t of trozos) {
    const n = t.text.trim().length;
    if (!n) continue;
    total += n;
    if (t.negrita) negrita += n;
    porTamano.set(t.size, (porTamano.get(t.size) ?? 0) + n);
  }
  let size;
  let mejor = 0;
  for (const [s, n] of porTamano) if (n > mejor) { size = s; mejor = n; }
  return { size, negrita: total > 0 && negrita * 2 > total };
}

/**
 * Une spans de una misma línea en un string, insertando un espacio cuando hay
 * un hueco horizontal apreciable entre trozos.
 * @param {{x:number,text:string,w?:number}[]} spans
 */
function joinSpans(spans) {
  spans.sort((a, b) => a.x - b.x);
  let out = '';
  let prevEnd = null;
  for (const s of spans) {
    const t = s.text;
    if (out === '') {
      out = t;
    } else {
      const gap = prevEnd == null ? 0 : s.x - prevEnd;
      out += gap > 1.5 && !out.endsWith(' ') && !t.startsWith(' ') ? ` ${t}` : t;
    }
    prevEnd = s.x + (s.w ?? 0);
  }
  return out.replace(/\s+/g, ' ').trim();
}

/**
 * @param {Uint8Array|Buffer} data
 * @param {{fuentes?: boolean}} [opts]  `fuentes`: detectar también la negrita
 * @returns {Promise<PdfLine[]>}
 */
export async function pdfToLines(data, { fuentes = false } = {}) {
  const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
  // pdfjs v4 rejects Node Buffer explicitly; hand it a plain Uint8Array copy.
  const bytes = data instanceof Uint8Array && data.constructor === Uint8Array
    ? data
    : Uint8Array.from(data);
  const doc = await getDocument({
    data: bytes,
    isEvalSupported: false,
    useSystemFonts: false,
  }).promise;

  /** @type {PdfLine[]} */
  const lines = [];
  for (let pn = 1; pn <= doc.numPages; pn++) {
    const page = await doc.getPage(pn);
    const tc = await page.getTextContent();
    const nombres = fuentes ? await nombresDeFuentes(page, tc.items) : new Map();
    /** @type {Map<number, {x:number,text:string,w:number,size:number,negrita:boolean}[]>} */
    const byY = new Map();
    for (const it of tc.items) {
      // @ts-ignore textItem
      if (!it.str || !it.transform) continue;
      // @ts-ignore
      const y = Math.round(it.transform[5]);
      // fusiona líneas a <=1px de distancia vertical (subíndices, kerning)
      let key = y;
      for (const k of byY.keys()) {
        if (Math.abs(k - y) <= 1) { key = k; break; }
      }
      if (!byY.has(key)) byY.set(key, []);
      // @ts-ignore
      const size = Math.round(Math.abs(it.transform[3] || it.height || 0) * 2) / 2;
      // @ts-ignore
      const negrita = /bold|black|heavy/i.test(nombres.get(it.fontName) ?? '');
      // @ts-ignore
      byY.get(key).push({ x: it.transform[4], text: it.str, w: it.width ?? 0, size, negrita });
    }
    const ys = [...byY.keys()].sort((a, b) => b - a);
    for (const y of ys) {
      const trozos = byY.get(y).sort((a, b) => a.x - b.x);
      const text = joinSpans(trozos.map((s) => ({ ...s })));
      if (text === '') continue;
      const { size, negrita } = tipografiaDominante(trozos);
      /** @type {PdfLine} */
      const linea = {
        page: pn,
        y,
        x: trozos[0].x,
        spans: trozos.map((s) => ({ x: Math.round(s.x), text: s.text })),
        text,
      };
      if (size) linea.size = size;
      if (fuentes) linea.negrita = negrita;
      lines.push(linea);
    }
  }
  await doc.destroy?.();
  return lines;
}

/**
 * @param {string} path
 * @param {{fuentes?: boolean}} [opts]
 * @returns {Promise<PdfLine[]>}
 */
export async function pdfFileToLines(path, opts) {
  return pdfToLines(await readFile(path), opts);
}

/**
 * Índice de secciones (TOC) de un PDF a partir de sus marcadores/outline (KTD8).
 * Si el PDF no trae outline devuelve `[]` — la detección por encabezados queda
 * como mejora posterior.
 * @param {Uint8Array|Buffer} data
 * @returns {Promise<Array<{titulo:string, pagina:number|null, nivel:number}>>}
 */
export async function pdfOutline(data) {
  const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const bytes = data instanceof Uint8Array && data.constructor === Uint8Array ? data : Uint8Array.from(data);
  const doc = await getDocument({ data: bytes, isEvalSupported: false, useSystemFonts: false }).promise;
  /** @type {Array<{titulo:string, pagina:number|null, nivel:number}>} */
  const out = [];
  try {
    const outline = await doc.getOutline();
    if (!outline) return out;
    const visit = async (items, nivel) => {
      for (const it of items) {
        let pagina = null;
        try {
          const dest = typeof it.dest === 'string' ? await doc.getDestination(it.dest) : it.dest;
          if (Array.isArray(dest) && dest[0]) {
            pagina = (await doc.getPageIndex(dest[0])) + 1;
          }
        } catch { /* destino no resoluble */ }
        out.push({ titulo: (it.title || '').trim(), pagina, nivel });
        if (it.items?.length) await visit(it.items, nivel + 1);
      }
    };
    await visit(outline, 1);
  } finally {
    await doc.destroy?.();
  }
  return out;
}

/** @param {string} path */
export async function pdfFileOutline(path) {
  return pdfOutline(await readFile(path));
}
