import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { parseVmi } from '../src/corpus/vmi-parser.js';

const dir = path.dirname(fileURLToPath(import.meta.url));
const load = (code) =>
  JSON.parse(readFileSync(path.join(dir, 'fixtures', 'vmi', `${code}.lines.json`), 'utf8'));

const parse = (code) => parseVmi(load(code), { codigo: code });

test('cabecera: componente, tipo de actividad, operación, edición, fecha, páginas', () => {
  const r = parse('VMI.3770.FD5.01.01');
  assert.equal(r.componente, 'REDUCTOR');
  assert.equal(r.actividadTipo, 'INSPECCIÓN VISUAL');
  assert.match(r.operacion, /Inspección visual del reductor/);
  assert.match(r.operacion, /Agregar aceite si procede/); // continuación de línea
  assert.equal(r.edicion, '0');
  assert.equal(r.fecha, '30.06.2022');
  assert.equal(r.paginas, 10);
  assert.equal(r.codigoEnDoc, 'VMI.3770.FD5.01.01');
});

test('ediciones no numéricas: "--" y "A0"', () => {
  assert.equal(parse('VMI.3770.FD5.02.04').edicion, '--');
  assert.equal(parse('VMI.3770.MC1.01.01').edicion, 'A0');
});

test('inspección con "No aplica": herramientas/consumibles/repuestos vacíos, sin sinExtraer', () => {
  const r = parse('VMI.3770.FD5.01.01');
  assert.equal(r.sinExtraer, false);
  assert.equal(r.herramientas.aplica, false);
  assert.equal(r.consumibles.aplica, false);
  assert.equal(r.repuestos.aplica, false);
});

test('FD5.02.04: consumibles con tabla — primera fila Grasa Klüberlub 200 g S', () => {
  const r = parse('VMI.3770.FD5.02.04');
  assert.equal(r.sinExtraer, false);
  assert.equal(r.consumibles.aplica, true);
  assert.ok(r.consumibles.filas.length >= 5, `esperaba >=5 filas, hay ${r.consumibles.filas.length}`);
  const grasa = r.consumibles.filas[0];
  const vals = Object.values(grasa).join(' | ');
  assert.match(vals, /Grasa/);
  assert.match(vals, /Kl[uü]berlub BE 41-1501/);
  assert.match(vals, /KLUBER/);
  assert.match(vals, /200 g/);
  // la columna USO tiene S
  assert.ok(Object.values(grasa).some((v) => v === 'S' || /\bS\b/.test(v)));
});

test('FD5.02.04: herramientas especiales con tabla (Engrasador manual / G1/8A)', () => {
  const r = parse('VMI.3770.FD5.02.04');
  assert.equal(r.herramientas.aplica, true);
  const txt = r.herramientas.raw;
  assert.match(txt, /Engrasador manual/);
  assert.match(txt, /Engrasador G1\/8A/);
});

test('FD5.02.04: procedimiento con fase Desmontaje y varios pasos', () => {
  const r = parse('VMI.3770.FD5.02.04');
  const titulos = r.procedimiento.fases.map((f) => f.titulo);
  assert.ok(titulos.some((t) => /Desmontaje/i.test(t)), `fases: ${JSON.stringify(titulos)}`);
  const total = r.procedimiento.fases.reduce((n, f) => n + f.pasos.length, 0);
  assert.ok(total >= 10, `esperaba >=10 pasos en total, hay ${total}`);
  const desm = r.procedimiento.fases.find((f) => /Desmontaje/i.test(f.titulo));
  assert.ok(desm.pasos.length >= 3);
  assert.match(desm.pasos[0].texto, /Colocar un depósito/);
});

test('FD5.01.01: procedimiento con pasos numerados y subpasos', () => {
  const r = parse('VMI.3770.FD5.01.01');
  const total = r.procedimiento.fases.reduce((n, f) => n + f.pasos.length, 0);
  assert.ok(total >= 7, `hay ${total} pasos`);
  // el paso 7 tiene un subpaso a.
  const all = r.procedimiento.fases.flatMap((f) => f.pasos);
  assert.ok(all.some((p) => p.subpasos.length > 0));
});

test('zonas de trabajo se capturan como texto', () => {
  assert.match(parse('VMI.3770.FD5.02.04').zonasTrabajo, /Localización del acoplamiento/);
  assert.match(parse('VMI.3770.RA1.01.01').zonasTrabajo, /Esquema del vehículo/);
});

test('medidas de seguridad (sección 1) se capturan como un bloque de texto único', () => {
  const seguridad = parse('VMI.3770.FD5.02.04').seguridad;
  assert.match(seguridad, /Riesgos generales asociados/);
  assert.match(seguridad, /Equipos de protección personal/);
  assert.match(seguridad, /Peligro de lesiones y daño a equipos/);
  // no debe colarse la sección 2 (empieza justo después)
  assert.doesNotMatch(seguridad, /Herramientas \/ Consumibles \/ Repuestos/);
});

test('AE1: un PDF sin la cabecera de sección 2 -> sinExtraer con motivo', () => {
  const lines = load('VMI.3770.FD5.01.01').filter(
    (l) => !/^2\s+Herramientas \/ Consumibles \/ Repuestos$/.test(l.text),
  );
  const r = parseVmi(lines, { codigo: 'VMI.3770.FD5.01.01' });
  assert.equal(r.sinExtraer, true);
  assert.match(r.motivo, /sección "2/);
  // aún así conserva el código
  assert.equal(r.codigo, 'VMI.3770.FD5.01.01');
});

test('AE1 bis: cabecera irreconocible -> sinExtraer', () => {
  const lines = load('VMI.3770.FD5.01.01').filter(
    (l) => !/^(Vehículo|Componente|Actividad|Herramientas especiales|Consumibles|Repuestos|Frecuencia|Operación):/.test(l.text),
  );
  const r = parseVmi(lines, { codigo: 'x' });
  assert.equal(r.sinExtraer, true);
  assert.match(r.motivo, /cabecera no reconocida/);
});

test('ningún campo extraído contiene el pie "Página N / M" ni "Fecha: dd.mm.aaaa"', () => {
  for (const code of ['VMI.3770.FD5.01.01', 'VMI.3770.FD5.02.04', 'VMI.3770.RA1.01.01', 'VMI.3770.MC1.01.01']) {
    const r = parse(code);
    const blob = JSON.stringify({
      op: r.operacion, frec: r.frecuencia, comp: r.componente,
      zonas: r.zonasTrabajo, seg: r.seguridad, proc: r.procedimiento, herr: r.herramientas, cons: r.consumibles,
    });
    assert.doesNotMatch(blob, /Página\s+\d+\s*\/\s*\d+/, `${code}: se coló un pie de página`);
    assert.doesNotMatch(blob, /Fecha:\s*\d{2}\.\d{2}\.\d{4}/, `${code}: se coló la fecha de pie`);
  }
});
