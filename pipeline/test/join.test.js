import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildJoinGraph, parseCarpetaSistema } from '../src/model/join.js';
import { parseMateriales } from '../src/corpus/xlsx-materiales.js';
import { parsePlan } from '../src/corpus/xlsx-plan.js';
import { fakeMaterialesWorkbook, fakePlanWorkbook, xlsx } from './helpers/xlsx-fixtures.js';

const plan = parsePlan(xlsx, fakePlanWorkbook());
const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());

const manualesDirs = [
  {
    name: 'BB21106005034 FD5 Reductor y acoplamiento',
    relPath: 'BB21106005034 FD5 Reductor y acoplamiento',
    files: [{ relPath: 'BB21106005034 FD5 Reductor y acoplamiento/manual.pdf' }],
  },
  {
    name: 'BB21106001000 BA1 Caja del vehículo',
    relPath: 'BB21106001000 BA1 Caja del vehículo',
    files: [{ relPath: 'BB21106001000 BA1 Caja del vehículo/caja.pdf' }],
  },
];

test('parseCarpetaSistema extrae código y nombre', () => {
  assert.deepEqual(
    parseCarpetaSistema('BB21106005034 FD5 Reductor y acoplamiento'),
    { codigo: 'FD5', nombre: 'Reductor y acoplamiento' },
  );
  assert.equal(parseCarpetaSistema('carpeta rara'), null);
});

test('une VMI ⇄ plan ⇄ materiales ⇄ manual por el sufijo de código', () => {
  const vmiRecords = [
    { codigo: 'VMI.3770.FD5.01.02', relPath: 'IM1/VMI.3770.FD5.01.02.pdf', ciclo: 'IM1', componente: 'REDUCTOR Y ACOPLAMIENTO' },
    { codigo: 'VMI.3770.BA1.01.01', relPath: 'IM1/VMI.3770.BA1.01.01.pdf', ciclo: 'IM1' },
  ];
  const g = buildJoinGraph({ plan, materiales, vmiRecords, manualesDirs, tocPorManual: {} });

  const fd5 = g.actividades.find((a) => a.codigo === 'FD5.01.02');
  assert.equal(fd5.sistema, 'FD5');
  assert.deepEqual(fd5.ciclos, ['IM1', 'IM2', 'IM3', 'R1', 'R2']); // del plan
  assert.equal(fd5.fuentes.plan, true);
  assert.equal(fd5.fuentes.materiales, true); // el fixture de materiales tiene FD5.01.02
  assert.equal(fd5.descripcionPlan, 'Cambiar aceite del reductor.');

  const sisFd5 = g.sistemas.find((s) => s.codigo === 'FD5');
  assert.equal(sisFd5.nombre, 'Reductor y acoplamiento'); // de la carpeta `05`
  assert.ok(sisFd5.actividades.includes('FD5.01.02'));
  assert.equal(sisFd5.manuales.length, 1);
});

test('incidencia: VMI de un sistema que no está en `05` ni en el plan', () => {
  const g = buildJoinGraph({
    plan, materiales,
    vmiRecords: [{ codigo: 'VMI.3770.ZZ9.01.01', relPath: 'R1/VMI.3770.ZZ9.01.01.pdf', ciclo: 'R1' }],
    manualesDirs, tocPorManual: {},
  });
  assert.ok(g.incidencias.some((i) => i.tipo === 'actividad-sin-sistema' && i.ref === 'ZZ9.01.01'));
});

test('incidencia: VMI sin fila en el plan', () => {
  const g = buildJoinGraph({
    plan, materiales,
    vmiRecords: [{ codigo: 'VMI.3770.FD5.09.09', relPath: 'R1/VMI.3770.FD5.09.09.pdf', ciclo: 'R1' }],
    manualesDirs, tocPorManual: {},
  });
  assert.ok(g.incidencias.some((i) => i.tipo === 'vmi-sin-fila-plan' && i.ref === 'FD5.09.09'));
});

test('incidencia inversa: actividad del plan sin VMI', () => {
  const g = buildJoinGraph({ plan, materiales, vmiRecords: [], manualesDirs, tocPorManual: {} });
  assert.ok(g.incidencias.some((i) => i.tipo === 'actividad-plan-sin-vmi' && i.ref === 'FD5.01.01'));
});

test('ficha de sistema en borrador con TOC del manual', () => {
  const toc = [{ titulo: 'Descripción técnica', pagina: 3, nivel: 1 }];
  const g = buildJoinGraph({
    plan, materiales, vmiRecords: [],
    manualesDirs,
    tocPorManual: { 'BB21106005034 FD5 Reductor y acoplamiento/manual.pdf': toc },
  });
  const ficha = g.fichasSistema.find((f) => f.codigo === 'FD5');
  assert.equal(ficha.revisado, false);
  assert.equal(ficha.cuerpo, '');
  assert.deepEqual(ficha.manuales[0].toc, toc);
});
