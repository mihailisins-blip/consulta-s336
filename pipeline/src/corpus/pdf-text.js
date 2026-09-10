// Extracción de texto posicional de un PDF, con pdfjs-dist (sin DOM, Node puro).
//
// Devuelve un flujo de "líneas" ordenado: por página, y descendente dentro de
// la página, x ascendente dentro de la línea. Cada línea trae sus `spans`
// (trozos de texto con su x) y un `text` ya unido. Esto es lo que consumen los
// parsers (vmi-parser.js), que trabajan sobre líneas, no sobre el PDF.

import { readFile } from 'node:fs/promises';

/** @typedef {{page:number, y:number, x:number, spans:{x:number,text:string}[], text:string}} PdfLine */

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
 * @returns {Promise<PdfLine[]>}
 */
export async function pdfToLines(data) {
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
    /** @type {Map<number, {x:number,text:string,w:number}[]>} */
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
      byY.get(key).push({ x: it.transform[4], text: it.str, w: it.width ?? 0 });
    }
    const ys = [...byY.keys()].sort((a, b) => b - a);
    for (const y of ys) {
      const spans = byY.get(y).sort((a, b) => a.x - b.x);
      const text = joinSpans(spans.map((s) => ({ ...s })));
      if (text === '') continue;
      lines.push({
        page: pn,
        y,
        x: spans[0].x,
        spans: spans.map((s) => ({ x: Math.round(s.x), text: s.text })),
        text,
      });
    }
  }
  await doc.destroy?.();
  return lines;
}

/**
 * @param {string} path
 * @returns {Promise<PdfLine[]>}
 */
export async function pdfFileToLines(path) {
  return pdfToLines(await readFile(path));
}
