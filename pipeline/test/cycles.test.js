import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildCycleModel, actividadesDeNivel, RDH_INTERVALOS_H } from '../src/model/cycles.js';
import { parseMateriales } from '../src/corpus/xlsx-materiales.js';
import { parsePlan } from '../src/corpus/xlsx-plan.js';
import { fakeMaterialesWorkbook, fakePlanWorkbook, xlsx } from './helpers/xlsx-fixtures.js';

function model() {
  const plan = parsePlan(xlsx, fakePlanWorkbook());
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  return { plan, materiales, model: buildCycleModel({ plan, materiales }) };
}

test('dos programas: km (I1..R2) y horas (RDH1..RDH7) con sus intervalos', () => {
  const { model: m } = model();
  assert.deepEqual(m.programas.km.niveles.map((n) => n.codigo), ['I1', 'I2', 'IM1', 'IM2', 'IM3', 'R1', 'R2']);
  assert.equal(m.programas.km.tipo, 'acumulativo');
  assert.equal(m.programas.km.niveles.find((n) => n.codigo === 'IM1').kmNum, 100000);
  assert.deepEqual(m.programas.horas.niveles.map((n) => n.codigo), Object.keys(RDH_INTERVALOS_H));
  assert.equal(m.programas.horas.niveles.find((n) => n.codigo === 'RDH3').intervaloH, 2000);
});

test('NS describe tareas según condición e incluye el programa por horas', () => {
  const { model: m } = model();
  assert.equal(m.ns.descripcion, 'Tareas según condición');
  assert.equal(m.ns.incluyePrograma, 'horas');
});

test('lotes: niveles partidos se agrupan desde la columna PM', () => {
  const { model: m } = model();
  assert.deepEqual(m.lotes.IM1, ['IM1A', 'IM1B', 'IM1C']);
  assert.deepEqual(m.lotes.IM2, ['IM2D']); // el fixture solo trae IM2D
  assert.ok(!m.lotes.IM3); // IM3 sin lotes
  assert.ok(!m.lotes.RDH2);
});

test('actividadesDeNivel para un nivel km sale de la matriz del plan', () => {
  const { plan, model: m } = model();
  const im1 = actividadesDeNivel(m, plan, 'IM1');
  assert.equal(im1.parcial, false);
  assert.equal(im1.fuente, 'plan');
  assert.deepEqual(im1.codigos, ['BA1.01.01', 'BA1.04.01', 'FD5.01.01', 'FD5.01.02']);
  const r2 = actividadesDeNivel(m, plan, 'R2');
  assert.ok(r2.codigos.includes('BA1.01.02')); // solo aparece en R1,R2
});

test('actividadesDeNivel para RDH se deriva del Excel de materiales (parcial)', () => {
  const { plan, model: m } = model();
  const rdh2 = actividadesDeNivel(m, plan, 'RDH2');
  assert.equal(rdh2.parcial, true);
  assert.equal(rdh2.fuente, 'materiales');
  assert.deepEqual(rdh2.codigos, ['FC1.02.04']);
});

test('actividadesDeNivel NS = plan(NS) ∪ RDH*', () => {
  const { plan, model: m } = model();
  const ns = actividadesDeNivel(m, plan, 'NS');
  assert.ok(ns.codigos.includes('GC2.01.03')); // marcada NS en el plan
  assert.ok(ns.codigos.includes('FC1.02.04')); // vía RDH2
  assert.ok(ns.codigos.includes('FC1.04.10')); // vía RDH3
  assert.equal(ns.parcial, true);
});
