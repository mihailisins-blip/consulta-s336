import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { buildCatalog } from '../src/model/catalog.js';
import { parseMateriales } from '../src/corpus/xlsx-materiales.js';
import { parseVmi } from '../src/corpus/vmi-parser.js';
import { fakeMaterialesWorkbook, xlsx } from './helpers/xlsx-fixtures.js';

const dir = path.dirname(fileURLToPath(import.meta.url));
const vmi = (code) =>
  parseVmi(JSON.parse(readFileSync(path.join(dir, 'fixtures', 'vmi', `${code}.lines.json`), 'utf8')), { codigo: code });

test('AE5: el aceite PIEZA 20027 es una sola entrada, referenciada por FD5.01.01 y FD5.01.02', () => {
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const cat = buildCatalog({ materiales, vmiRecords: [] });

  const aceite = cat.entradas.filter((e) => e.codigoErp === '20027');
  assert.equal(aceite.length, 1, 'una sola entrada para 20027');
  assert.match(aceite[0].descripcion, /MOBIL/);
  assert.equal(aceite[0].unidad, 'UD');

  const enlaces20027 = cat.enlaces.filter((e) => e.entradaId === 'erp:20027');
  const acts = enlaces20027.map((e) => e.actividad).sort();
  assert.ok(acts.includes('FD5.01.01'));
  assert.ok(acts.includes('FD5.01.02'));
  // cantidad y unidad viajan en el enlace, no en la entrada
  const l = enlaces20027.find((e) => e.actividad === 'FD5.01.02');
  assert.equal(l.cantNum, 2);
  assert.equal(l.ud, 'UD');
  assert.equal(l.reserva, true);
});

test('una herramienta de un VMI que no está en el Excel -> entrada con codigoErp vacío', () => {
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const cat = buildCatalog({ materiales, vmiRecords: [vmi('VMI.3770.FD5.02.04')] });

  const engras = cat.entradas.find((e) => /Engrasador/i.test(e.descripcion));
  assert.ok(engras, 'debería existir una entrada "Engrasador…"');
  assert.equal(engras.codigoErp, null);
  assert.equal(engras.tipo, 'herramienta');
  assert.equal(engras.fuente, 'vmi');
});

test('el uso S/SC de un VMI llega al enlace del consumible', () => {
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const cat = buildCatalog({ materiales, vmiRecords: [vmi('VMI.3770.FD5.02.04')] });
  // el VMI FD5.02.04 tiene "Grasa Klüberlub BE 41-1501 … S" en consumibles
  const enl = cat.enlaces.filter((e) => e.actividad === 'FD5.02.04' && e.uso === 'S');
  assert.ok(enl.length >= 1, 'algún enlace de FD5.02.04 con uso S');
});

test('métricas del catálogo', () => {
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const cat = buildCatalog({ materiales, vmiRecords: [vmi('VMI.3770.FD5.02.04'), vmi('VMI.3770.FD5.01.01')] });
  assert.equal(cat.metricas.entradas, cat.entradas.length);
  assert.equal(cat.metricas.conCodigoErp + cat.metricas.sinCodigoErp, cat.metricas.entradas);
  assert.ok(cat.metricas.conCodigoErp >= 5); // fixture: 5+ piezas distintas
  assert.ok(cat.metricas.sinCodigoErp >= 1); // los engrasadores
  assert.equal(cat.metricas.enlaces, cat.enlaces.length);
});

test('buscaErp no fusiona una descripción corta y genérica con una entrada ERP no relacionada', () => {
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  // "Grasa" a secas no tiene relación con la "GRASA RENOLIT HLT2-KB" (PIEZA
  // 23193) del fixture -- no debería fusionarse con ella solo por empezar
  // por la misma palabra genérica.
  const vmiRecords = [{
    codigo: 'VMI.3770.ZZ9.01.01',
    consumibles: {
      aplica: true,
      filas: [{ Descripción: 'Grasa', Referencia: '', Fabricante: '', Cantidad: '50 g', Uso: 'S' }],
    },
  }];
  const cat = buildCatalog({ materiales, vmiRecords });

  const grasaGenerica = cat.entradas.find((e) => e.descripcion === 'Grasa');
  assert.ok(grasaGenerica, 'debería crear una entrada propia para "Grasa"');
  assert.equal(grasaGenerica.codigoErp, null, 'no debería haberse fusionado con ningún PIEZA existente');
  assert.equal(grasaGenerica.fuente, 'vmi');

  const renolit = cat.entradas.find((e) => e.codigoErp === '23193');
  assert.equal(renolit.aliases.includes('Grasa'), false, '"Grasa" no debería colarse como alias de la grasa Renolit');
});

test('buscaErp sigue fusionando cuando la descripción del VMI SÍ engloba la del ERP', () => {
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const vmiRecords = [{
    codigo: 'VMI.3770.ZZ9.01.02',
    consumibles: {
      aplica: true,
      filas: [{ Descripción: 'ACEITE REDUCTOR MOBIL 75W-90 sintético', Referencia: '', Fabricante: '', Cantidad: '1 L', Uso: 'S' }],
    },
  }];
  const cat = buildCatalog({ materiales, vmiRecords });
  const aceite = cat.entradas.find((e) => e.codigoErp === '20027');
  assert.ok(aceite.aliases.includes('ACEITE REDUCTOR MOBIL 75W-90 sintético'));
});

test('dos grafías del mismo PIEZA -> una entrada, la segunda como alias', () => {
  const wb = fakeMaterialesWorkbook([
    ['3360.01.R1', '3360.01.F.D5.01.03', 'LM.3360.01.FD5.01.03', '20027', 'ACEITE REDUCTOR MOBIL 75W90 (variante)', '1', 'UD', 'No'],
  ]);
  const cat = buildCatalog({ materiales: parseMateriales(xlsx, wb), vmiRecords: [] });
  const e = cat.entradas.find((x) => x.codigoErp === '20027');
  assert.equal(cat.entradas.filter((x) => x.codigoErp === '20027').length, 1);
  assert.ok(e.aliases.includes('ACEITE REDUCTOR MOBIL 75W90 (variante)'));
});
