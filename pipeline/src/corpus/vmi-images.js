// Imágenes de un VMI: localización (barata, solo operadores de página) y
// decodificación/reducción (cara, solo de las que interesan).
//
// Un VMI trae el logotipo en cabecera/pie, dos imágenes comunes de seguridad
// y, en las secciones 3 y 4, el esquema del vehículo y las figuras del
// procedimiento (render 3D con marcadores numerados). Primero se localizan
// todas las imágenes grandes (`localizarImagenes`, sin decodificar píxeles);
// vmi-figuras.js decide cuáles son de zonas/procedimiento; y solo esas se
// decodifican, se reducen y se escriben a disco (`guardarImagen`) -- el
// decodificado JPEG de pdfjs es lo más caro, no conviene hacerlo para las
// ~880 imágenes de seguridad que no se muestran.

import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { parseVmi } from './vmi-parser.js';

/** Tamaño mínimo (pt) para contar como figura: descarta logotipos y filetes. */
const MIN_W = 200;
const MIN_H = 60;

const mul = (m, n) => [
  m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
  m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
  m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
];

/**
 * Abre el PDF y localiza sus imágenes grandes, sin decodificarlas.
 * @param {Uint8Array|Buffer} data
 * @returns {Promise<{cajas: import('./vmi-figuras.js').CajaImagen[], ids: string[], doc: any}>}
 *   `cajas[i]` corresponde a `ids[i]`; `doc` queda abierto para `decodificar`.
 */
export async function localizarImagenes(data) {
  const { OPS, getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const bytes = data instanceof Uint8Array && data.constructor === Uint8Array ? data : Uint8Array.from(data);
  const doc = await getDocument({ data: bytes, isEvalSupported: false, useSystemFonts: false }).promise;
  const cajas = [];
  const ids = [];
  for (let pn = 1; pn <= doc.numPages; pn++) {
    const page = await doc.getPage(pn);
    const ol = await page.getOperatorList();
    let ctm = [1, 0, 0, 1, 0, 0];
    const pila = [];
    for (let i = 0; i < ol.fnArray.length; i++) {
      const fn = ol.fnArray[i];
      if (fn === OPS.save) pila.push(ctm.slice());
      else if (fn === OPS.restore) ctm = pila.pop() ?? [1, 0, 0, 1, 0, 0];
      else if (fn === OPS.transform) ctm = mul(ctm, ol.argsArray[i]);
      else if (fn === OPS.paintImageXObject) {
        const w = Math.abs(ctm[0]);
        const h = Math.abs(ctm[3]);
        if (w >= MIN_W && h >= MIN_H) {
          cajas.push({ page: pn, x: ctm[4], y: Math.min(ctm[5], ctm[5] + ctm[3]), w, h });
          ids.push(ol.argsArray[i][0]);
        }
      }
    }
  }
  return { cajas, ids, doc };
}

/**
 * Píxeles de la imagen `id` de la página `pn` ya normalizados a 8 bits por canal.
 * @returns {Promise<{width:number,height:number,channels:1|3|4,data:Uint8Array}>}
 */
export async function decodificar(doc, pn, id) {
  const page = await doc.getPage(pn);
  await page.getOperatorList();
  const store = id.startsWith('g_') ? page.commonObjs : page.objs;
  const obj = await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`imagen ${id} sin resolver`)), 20000);
    store.get(id, (o) => { clearTimeout(t); resolve(o); });
  });
  if (!obj?.data) throw new Error(`imagen ${id} sin datos`);
  const { width, height, kind } = obj;
  if (kind === 2) return { width, height, channels: 3, data: obj.data };
  if (kind === 3) return { width, height, channels: 4, data: obj.data };
  // kind 1: escala de grises a 1 bit por píxel, filas alineadas a byte
  const gris = new Uint8Array(width * height);
  const fila = Math.ceil(width / 8);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const bit = (obj.data[y * fila + (x >> 3)] >> (7 - (x & 7))) & 1;
      gris[y * width + x] = bit ? 255 : 0;
    }
  }
  return { width, height, channels: 1, data: gris };
}

/**
 * Reduce a `maxAncho` px y codifica en JPEG (sharp se carga bajo demanda: el
 * resto del pipeline y sus tests no lo necesitan).
 * @param {{width:number,height:number,channels:1|3|4,data:Uint8Array}} img
 * @returns {Promise<{buffer:Buffer,width:number,height:number}>}
 */
export async function codificarJpeg(img, { maxAncho = 1000, calidad = 75 } = {}) {
  const sharp = (await import('sharp')).default;
  const { data, info } = await sharp(Buffer.from(img.data.buffer, img.data.byteOffset, img.data.length), {
    raw: { width: img.width, height: img.height, channels: img.channels },
  })
    .resize({ width: Math.min(img.width, maxAncho), withoutEnlargement: true })
    .flatten({ background: '#ffffff' })
    .jpeg({ quality: calidad })
    .toBuffer({ resolveWithObject: true });
  return { buffer: data, width: info.width, height: info.height };
}

/**
 * Parsea un VMI y, además, extrae a `<outDir>/imagenes/` las figuras de sus
 * secciones 3 y 4. Un fallo con las imágenes (PDF raro, imagen que no
 * decodifica) nunca invalida el VMI: se descarta esa figura y se cuenta en
 * `fallos`, el texto del VMI se conserva igual.
 * @param {import('./pdf-text.js').PdfLine[]} lines
 * @param {Uint8Array|Buffer} bytes
 * @param {{codigo:string, outDir:string}} opts
 * @returns {Promise<{rec:any, fallos:number}>}
 */
export async function parseVmiConImagenes(lines, bytes, { codigo, outDir }) {
  let loc = null;
  try {
    loc = await localizarImagenes(bytes);
  } catch {
    loc = null;
  }
  const rec = parseVmi(lines, { codigo, cajas: loc?.cajas ?? [] });
  let fallos = 0;
  if (loc) {
    const guardadas = [];
    for (const f of rec.figuras ?? []) {
      try {
        const px = await decodificar(loc.doc, loc.cajas[f.caja].page, loc.ids[f.caja]);
        const jpg = await codificarJpeg(px);
        guardadas.push({ ...f, archivo: await guardarImagen(outDir, jpg.buffer), ancho: jpg.width, alto: jpg.height });
      } catch {
        fallos++;
      }
    }
    rec.figuras = guardadas;
    try { await loc.doc.destroy(); } catch { /* ya liberado */ }
  }
  return { rec, fallos };
}

/**
 * Escribe `buffer` en `<outDir>/imagenes/<hash>.jpg` (nombre por contenido:
 * una imagen repetida entre VMI se guarda una sola vez).
 * @returns {Promise<string>} nombre de archivo relativo a `imagenes/`
 */
export async function guardarImagen(outDir, buffer) {
  const hash = createHash('sha1').update(buffer).digest('hex').slice(0, 16);
  const nombre = `${hash}.jpg`;
  const dir = path.join(outDir, 'imagenes');
  await fs.mkdir(dir, { recursive: true });
  try {
    await fs.writeFile(path.join(dir, nombre), buffer, { flag: 'wx' });
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
  }
  return nombre;
}
