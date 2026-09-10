import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizarCodigo, sistemaDeCodigo, parsePm } from '../src/model/codes.js';
import { parseMateriales, parseCantidad } from '../src/corpus/xlsx-materiales.js';
import { parsePlan } from '../src/corpus/xlsx-plan.js';
import { fakeMaterialesWorkbook, fakePlanWorkbook, xlsx } from './helpers/xlsx-fixtures.js';

test('normalizarCodigo unifica las tres grafías por el sufijo', () => {
  assert.equal(normalizarCodigo('VMI.3770.FD5.01.02'), 'FD5.01.02');
  assert.equal(normalizarCodigo('3360.01.F.D5.01.02'), 'FD5.01.02');
  assert.equal(normalizarCodigo('LM.3360.01.FD5.01.02'), 'FD5.01.02');
  assert.equal(normalizarCodigo('FD5.01.02'), 'FD5.01.02');
  assert.equal(normalizarCodigo('BA1.01.01'), 'BA1.01.01');
  assert.equal(normalizarCodigo('VMI.3770.FC1.01.02_A0'), 'FC1.01.02');
  assert.equal(normalizarCodigo('VMI.3770.JD2.02.02_B0'), 'JD2.02.02'); // sufijo de revisión _B0
  assert.equal(normalizarCodigo('MC (Sección 2)'), null);
  assert.equal(normalizarCodigo(''), null);
  // rellena ceros: 1.1 -> 01.01
  assert.equal(normalizarCodigo('3360.01.Q.E3.1.1'), 'QE3.01.01');
});

test('sistemaDeCodigo', () => {
  assert.equal(sistemaDeCodigo('FD5.01.02'), 'FD5');
  assert.equal(sistemaDeCodigo('BA1.01.01'), 'BA1');
  assert.equal(sistemaDeCodigo('QA4.02.01'), 'QA4');
});

test('parsePm descompone nivel y lote', () => {
  assert.deepEqual(parsePm('3360.01.IM1A'), { raw: '3360.01.IM1A', nivel: 'IM1', lote: 'A' });
  assert.deepEqual(parsePm('3360.01.RDH2'), { raw: '3360.01.RDH2', nivel: 'RDH2', lote: null });
  assert.deepEqual(parsePm('3360.01.I1'), { raw: '3360.01.I1', nivel: 'I1', lote: null });
});

test('parseCantidad: coma decimal española, texto -> null', () => {
  assert.equal(parseCantidad('0,50'), 0.5);
  assert.equal(parseCantidad('200'), 200);
  assert.equal(parseCantidad('530'), 530);
  assert.equal(parseCantidad('Según necesidad'), null);
  assert.equal(parseCantidad(null), null);
});

test('parseMateriales: columnas, código ERP como texto, cantidad, reserva, nivel/lote', () => {
  const { filas, avisos } = parseMateriales(xlsx, fakeMaterialesWorkbook());
  assert.equal(avisos.length, 0);
  assert.ok(filas.length >= 8);
  const grasa = filas.find((f) => f.descripcion.includes('GRASA RENOLIT'));
  assert.equal(grasa.pieza, '23193');
  assert.equal(grasa.cant, '0,50');
  assert.equal(grasa.cantNum, 0.5);
  assert.equal(grasa.ud, 'KG');
  assert.equal(grasa.reserva, false);
  assert.equal(grasa.nivel, 'IM2');
  assert.equal(grasa.lote, 'D');
  assert.equal(grasa.tarea, 'QE3.01.01');
  // reserva "Sí" -> true
  assert.equal(filas.find((f) => f.tarea === 'FD5.01.02' && f.pieza === '20027').reserva, true);
});

test('parseMateriales conserva un código PIEZA con cero a la izquierda', () => {
  const wb = fakeMaterialesWorkbook([
    ['3360.01.R1', '3360.01.F.F1.01.01', 'LM.3360.01.FF1.01.01', '05123', 'PIEZA CON CERO', '1', 'UD', 'No'],
  ]);
  const { filas } = parseMateriales(xlsx, wb);
  assert.equal(filas.find((f) => f.descripcion === 'PIEZA CON CERO').pieza, '05123');
});

test('parsePlan: CICLOS con km medios', () => {
  const p = parsePlan(xlsx, fakePlanWorkbook());
  assert.equal(p.avisos.length, 0);
  const i1 = p.ciclos.find((c) => c.codigo === 'I1');
  assert.equal(i1.descripcion, 'Inspección Inicial 1');
  assert.equal(i1.kmNum, 25000);
  const r1 = p.ciclos.find((c) => c.codigo === 'R1');
  assert.equal(r1.kmNum, 1600000);
  assert.equal(r1.tiempoMedio, '10 Años');
  assert.ok(p.ciclos.some((c) => c.codigo === 'NS'));
});

test('parsePlan: PUESTA EN SERVICIO (código normalizado, "--" -> null)', () => {
  const p = parsePlan(xlsx, fakePlanWorkbook());
  assert.equal(p.puestaEnServicio.length, 3);
  const fd5 = p.puestaEnServicio.find((x) => x.codigo === 'FD5.01.01');
  assert.match(fd5.intervalo, /7\.000 Km/);
  assert.equal(p.puestaEnServicio.find((x) => x.codigoRaw === '--').codigo, null);
});

test('parsePlan: PLAN MANTENIMIENTO matriz actividad × ciclo', () => {
  const p = parsePlan(xlsx, fakePlanWorkbook());
  assert.deepEqual(p.grupos.map((g) => g.codigo).sort(), ['B', 'F']);
  assert.ok(p.sistemas.some((s) => s.codigo === 'FD5' && s.nombre === 'REDUCTOR Y ACOPLAMIENTO'));

  const act = Object.fromEntries(p.actividades.map((a) => [a.codigo, a]));
  assert.deepEqual(act['BA1.01.01'].ciclos, ['IM1', 'IM2', 'IM3', 'R1', 'R2']);
  assert.equal(act['BA1.01.01'].marcaSeguridad, true);
  assert.deepEqual(act['BA1.01.02'].ciclos, ['R1', 'R2']);
  assert.equal(act['FD5.01.02'].sistema, 'FD5');
  assert.deepEqual(act['GC2.01.03'].ciclos, ['NS']);
  assert.equal(act['GC2.01.03'].observaciones, 'Cada 12 años.');
  // subsistemas (BA1.01, FD5.01) no entran como actividades
  assert.ok(!act['BA1.01']);
});
