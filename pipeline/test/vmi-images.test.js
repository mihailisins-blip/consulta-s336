import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { localizarImagenes, decodificar, codificarJpeg, guardarImagen } from '../src/corpus/vmi-images.js';
import { pdfConImagenes } from './helpers/pdf-sintetico.js';

let tmp;
before(async () => { tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-img-')); });
after(async () => { await fs.rm(tmp, { recursive: true, force: true }); });

test('localizarImagenes: solo cuenta las grandes y da su posición en puntos', async () => {
  const { cajas, ids, doc } = await localizarImagenes(pdfConImagenes());
  assert.equal(cajas.length, 1, 'el logotipo de 100x10 pt se descarta');
  assert.equal(ids.length, 1);
  assert.deepEqual(
    { page: cajas[0].page, x: Math.round(cajas[0].x), y: Math.round(cajas[0].y), w: Math.round(cajas[0].w), h: Math.round(cajas[0].h) },
    { page: 1, x: 50, y: 300, w: 400, h: 200 },
  );
  await doc.destroy();
});

test('decodificar devuelve los píxeles y codificarJpeg los comprime a un JPEG válido', async () => {
  const { cajas, ids, doc } = await localizarImagenes(pdfConImagenes());
  const px = await decodificar(doc, cajas[0].page, ids[0]);
  assert.equal(px.width, 4);
  assert.equal(px.height, 2);
  assert.equal(px.channels, 3);
  const jpg = await codificarJpeg(px);
  assert.equal(jpg.buffer[0], 0xff);
  assert.equal(jpg.buffer[1], 0xd8, 'cabecera JPEG (SOI)');
  assert.equal(jpg.width, 4, 'no se amplía una imagen más pequeña que el máximo');
  await doc.destroy();
});

test('codificarJpeg reduce una imagen ancha al máximo pedido', async () => {
  const w = 2000; const h = 1000;
  const data = new Uint8Array(w * h * 3).fill(128);
  const jpg = await codificarJpeg({ width: w, height: h, channels: 3, data }, { maxAncho: 1000 });
  assert.equal(jpg.width, 1000);
  assert.equal(jpg.height, 500);
});

test('guardarImagen: nombre por contenido, una imagen repetida se guarda una sola vez', async () => {
  const buf = Buffer.from('contenido-de-prueba');
  const a = await guardarImagen(tmp, buf);
  const b = await guardarImagen(tmp, buf);
  const c = await guardarImagen(tmp, Buffer.from('otro-contenido'));
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^[0-9a-f]{16}\.jpg$/);
  assert.equal((await fs.readdir(path.join(tmp, 'imagenes'))).length, 2);
});
