// Regenera las transcripciones de VMI reales que usan los tests del parser
// (test/fixtures/vmi/<código>.lines.json) y la posición de sus imágenes
// (<código>.cajas.json), con la tipografía de cada línea (tamaño y negrita) que
// el parser del procedimiento necesita. Requiere el corpus (unidad Z:).
//
// Uso: node --experimental-sqlite scripts/gen-vmi-fixtures.mjs <carpeta-VMI-del-corpus>
//   p. ej. "...\CDROM LOC ADIF ED.2\04 Instrucciones plan mantenimiento (VMI)"

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { pdfToLines } from '../src/corpus/pdf-text.js';
import { localizarImagenes } from '../src/corpus/vmi-images.js';

const FIXTURES = {
  'VMI.3770.FD5.02.04': 'R1/VMI.3770.FD5.02.04.pdf',
  'VMI.3770.FD5.01.01': 'I1/VMI.3770.FD5.01.01.pdf',
  'VMI.3770.RA1.01.01': 'I1/VMI.3770.RA1.01.01.pdf',
  'VMI.3770.MC1.01.01': 'I1/VMI.3770.MC1.01.01_A0.pdf',
  // casos de formato del procedimiento: viñetas y avisos (DA1), subtítulos y
  // listas que reinician la numeración (DF3), figuras con pie, texto entre
  // pasos y tabla (GC3)
  'VMI.3770.DA1.01.01': 'I1/VMI.3770.DA1.01.01.pdf',
  'VMI.3770.DF3.01.01': 'I1/VMI.3770.DF3.01.01.pdf',
  'VMI.3770.GC3.01.01': 'I1/VMI.3770.GC3.01.01_A0.pdf',
};

const raiz = process.argv[2];
if (!raiz) {
  console.error('uso: node --experimental-sqlite scripts/gen-vmi-fixtures.mjs <carpeta-VMI-del-corpus>');
  process.exit(1);
}
const out = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'test', 'fixtures', 'vmi');
mkdirSync(out, { recursive: true });

for (const [codigo, rel] of Object.entries(FIXTURES)) {
  const bytes = readFileSync(path.join(raiz, ...rel.split('/')));
  const lines = await pdfToLines(bytes, { fuentes: true });
  const loc = await localizarImagenes(bytes);
  await loc.doc.destroy();
  writeFileSync(path.join(out, `${codigo}.lines.json`), JSON.stringify(lines));
  writeFileSync(path.join(out, `${codigo}.cajas.json`), JSON.stringify(loc.cajas));
  console.log(`${codigo}: ${lines.length} líneas, ${loc.cajas.length} imágenes grandes`);
}
