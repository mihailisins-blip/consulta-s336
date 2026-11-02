import { test } from 'node:test';
import assert from 'node:assert/strict';

import { pdfToLines } from '../src/corpus/pdf-text.js';
import { pdfConTexto } from './helpers/pdf-sintetico.js';

test('pdfToLines: cada línea trae su tamaño; la negrita solo si se piden las fuentes', async () => {
  const sin = await pdfToLines(pdfConTexto());
  assert.deepEqual(sin.map((l) => [l.text, l.size]), [
    ['Titulo de fase', 18],
    ['Texto normal del paso', 11],
    ['Texto en negrita', 11],
  ]);
  assert.ok(sin.every((l) => l.negrita === undefined), 'sin `fuentes` no se resuelven los nombres de fuente');
});

test('pdfToLines con fuentes: distingue la negrita de la línea normal del mismo tamaño', async () => {
  const lineas = await pdfToLines(pdfConTexto(), { fuentes: true });
  assert.deepEqual(lineas.map((l) => [l.text, l.size, l.negrita]), [
    ['Titulo de fase', 18, true],
    ['Texto normal del paso', 11, false],
    ['Texto en negrita', 11, true],
  ]);
});
