// Genera un data.sqlite REAL (no sintético) pero pequeño, para los tests de
// la app Flutter que necesitan actividad_lote (esquema v2) -- app/test/
// fixtures/data.sqlite es la corrida completa real contra Z: del
// 2026-09-10, pero es de ANTES del esquema v2 y no se puede regenerar sin
// acceso a Z:. Este script reutiliza exactamente las mismas piezas que
// pipeline/test/build.test.js (los 4 VMI reales de test/fixtures/vmi/ +
// los workbooks de prueba de test/helpers/xlsx-fixtures.js), así que el
// resultado es igual de "real" en cuanto al esquema, solo más pequeño.
//
// Uso: node --experimental-sqlite scripts/gen-app-fixture.mjs <ruta-salida>

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { parsePlan } from '../src/corpus/xlsx-plan.js';
import { parseMateriales } from '../src/corpus/xlsx-materiales.js';
import { parseVmi } from '../src/corpus/vmi-parser.js';
import { buildCycleModel } from '../src/model/cycles.js';
import { buildCatalog } from '../src/model/catalog.js';
import { buildJoinGraph } from '../src/model/join.js';
import { normalizarCodigo } from '../src/model/codes.js';
import { writeDatabase } from '../src/build/sqlite-writer.js';
import { fakeMaterialesWorkbook, fakePlanWorkbook, xlsx } from '../test/helpers/xlsx-fixtures.js';

const dir = path.dirname(fileURLToPath(import.meta.url));
const vmi = (code) =>
  Object.assign(
    parseVmi(
      JSON.parse(readFileSync(path.join(dir, '..', 'test', 'fixtures', 'vmi', `${code}.lines.json`), 'utf8')),
      { codigo: code },
    ),
    { relPath: `x/${code}.pdf` },
  );

const outPath = process.argv[2];
if (!outPath) {
  console.error('uso: node scripts/gen-app-fixture.mjs <ruta-salida>');
  process.exit(1);
}

const plan = parsePlan(xlsx, fakePlanWorkbook());
const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
const vmiRecords = [
  Object.assign(vmi('VMI.3770.FD5.02.04'), { ciclo: 'IM1' }),
  Object.assign(vmi('VMI.3770.FD5.01.01'), { ciclo: 'I1' }),
  Object.assign(vmi('VMI.3770.RA1.01.01'), { ciclo: 'I1' }),
  Object.assign(vmi('VMI.3770.MC1.01.01'), { ciclo: 'I1' }),
];
const model = buildCycleModel({ plan, materiales });
const catalog = buildCatalog({ materiales, vmiRecords });
const join = buildJoinGraph({
  plan, materiales, vmiRecords,
  manualesDirs: [
    { name: 'BB21106005034 FD5 Reductor y acoplamiento', relPath: 'x', files: [{ relPath: 'x/m.pdf' }] },
  ],
  tocPorManual: { 'x/m.pdf': [{ titulo: 'Descripción funcional', pagina: 2, nivel: 1 }] },
});
const vmiByCode = new Map(vmiRecords.map((r) => [normalizarCodigo(r.codigo), r]));

const { counts } = await writeDatabase(outPath, {
  plan, materiales, model, catalog, join, vmiByCode,
  meta: { generator: 'gen-app-fixture.mjs (fixture de test, no el corpus real)' },
});
console.log(`escrito ${outPath}:`, counts);
