import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compararVmi, esMejorVmi, rangoEdicion, rangoFecha } from '../src/model/vmi-version.js';
import { buildVmiByCode } from '../src/build/run-build.js';
import { buildJoinGraph } from '../src/model/join.js';
import { parseMateriales } from '../src/corpus/xlsx-materiales.js';
import { parsePlan } from '../src/corpus/xlsx-plan.js';
import { fakeMaterialesWorkbook, fakePlanWorkbook, xlsx } from './helpers/xlsx-fixtures.js';

const vmi = (relPath, edicion, fecha, extra = {}) => ({
  codigo: relPath.split('/').pop().replace(/\.pdf$/i, '').replace(/_A\d+$/i, ''),
  relPath,
  ciclo: relPath.split('/')[0],
  edicion,
  fecha,
  ...extra,
});

test('rangoEdicion: sin edición / "--" < numérica < letra+número', () => {
  const orden = ['--', '0', '1', 'A0', 'A1', 'B0'];
  for (let i = 1; i < orden.length; i++) {
    assert.ok(
      compararVmi({ edicion: orden[i] }, { edicion: orden[i - 1] }) > 0,
      `${orden[i]} debería ganar a ${orden[i - 1]}`,
    );
  }
  assert.deepEqual(rangoEdicion(null), rangoEdicion('--'));
});

test('rangoFecha: DD.MM.AAAA comparable', () => {
  assert.ok(rangoFecha('30.04.2024') > rangoFecha('31.05.2023'));
  assert.equal(rangoFecha(null), 0);
});

test('desempate: sufijo _A0 del nombre y luego la fecha más reciente', () => {
  const base = vmi('I1/VMI.3770.HE6.01.01.pdf', 'A0', '30.04.2024');
  const a0 = vmi('I1/VMI.3770.HE6.01.01_A0.pdf', 'A0', '30.04.2024');
  assert.ok(esMejorVmi(a0, base));
  assert.ok(!esMejorVmi(base, a0));

  const vieja = vmi('I1/VMI.3770.HE6.01.01.pdf', '0', '30.06.2022');
  const nueva = vmi('I2/VMI.3770.HE6.01.01.pdf', '0', '01.01.2023');
  assert.ok(esMejorVmi(nueva, vieja));
  // con todo igual se queda el que ya estaba
  assert.ok(!esMejorVmi({ ...vieja }, vieja));
});

test('un ejemplar sin extraer nunca gana a uno extraído', () => {
  const extraido = vmi('I1/VMI.3770.HE6.01.01.pdf', '0', '30.06.2022');
  const fallido = vmi('I1/VMI.3770.HE6.01.01_A0.pdf', null, null, { sinExtraer: true });
  assert.ok(!esMejorVmi(fallido, extraido));
  assert.ok(esMejorVmi(extraido, fallido));
});

test('buildVmiByCode elige la edición más alta aunque aparezca después', () => {
  const recs = [
    vmi('I1/VMI.3770.HE6.01.01.pdf', '0', '30.06.2022'),
    vmi('I1/VMI.3770.HE6.01.01_A0.pdf', 'A0', '30.04.2024'),
    vmi('I1/VMI.3770.DC3.01.01_A0.pdf', 'A0', '31.05.2023'),
    vmi('I2/VMI.3770.DC3.01.01.pdf', '--', '30.11.2022'),
  ];
  const m = buildVmiByCode(recs);
  assert.equal(m.get('HE6.01.01').relPath, 'I1/VMI.3770.HE6.01.01_A0.pdf');
  assert.equal(m.get('DC3.01.01').relPath, 'I1/VMI.3770.DC3.01.01_A0.pdf');
});

test('buildJoinGraph: la actividad apunta al PDF y la edición del mejor ejemplar', () => {
  const plan = parsePlan(xlsx, fakePlanWorkbook());
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const recs = [
    vmi('I1/VMI.3770.FD5.01.02.pdf', '0', '30.06.2022', { componente: 'viejo' }),
    vmi('I2/VMI.3770.FD5.01.02_A0.pdf', 'A0', '30.04.2024', { componente: 'nuevo' }),
  ];
  const { actividades } = buildJoinGraph({ plan, materiales, vmiRecords: recs });
  const a = actividades.find((x) => x.codigo === 'FD5.01.02');
  assert.equal(a.vmiRelPath, 'I2/VMI.3770.FD5.01.02_A0.pdf');
  assert.equal(a.edicion, 'A0');
  assert.equal(a.componente, 'nuevo');
  assert.deepEqual(a.ciclosCarpeta, ['I1', 'I2']);
});
