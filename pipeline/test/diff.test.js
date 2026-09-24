import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { carryOverridesAndDiff } from '../src/build/diff.js';
import { writeDatabase } from '../src/build/sqlite-writer.js';
import { parsePlan } from '../src/corpus/xlsx-plan.js';
import { parseMateriales } from '../src/corpus/xlsx-materiales.js';
import { parseVmi } from '../src/corpus/vmi-parser.js';
import { buildCycleModel } from '../src/model/cycles.js';
import { buildCatalog } from '../src/model/catalog.js';
import { buildJoinGraph } from '../src/model/join.js';
import { normalizarCodigo } from '../src/model/codes.js';
import { fakeMaterialesWorkbook, fakePlanWorkbook, xlsx } from './helpers/xlsx-fixtures.js';

const dir = path.dirname(fileURLToPath(import.meta.url));
const vmi = (code) =>
  Object.assign(
    parseVmi(JSON.parse(readFileSync(path.join(dir, 'fixtures', 'vmi', `${code}.lines.json`), 'utf8')), { codigo: code }),
    { relPath: `x/${code}.pdf`, ciclo: 'IM1' },
  );

let tmp;
before(async () => { tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-diff-')); });
after(async () => { await fs.rm(tmp, { recursive: true, force: true }); });

async function build(dbPath, vmiRecords) {
  const plan = parsePlan(xlsx, fakePlanWorkbook());
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const model = buildCycleModel({ plan, materiales });
  const catalog = buildCatalog({ materiales, vmiRecords });
  const join = buildJoinGraph({ plan, materiales, vmiRecords, manualesDirs: [], tocPorManual: {} });
  const vmiByCode = new Map(vmiRecords.map((r) => [normalizarCodigo(r.codigo), r]));
  await writeDatabase(dbPath, { plan, materiales, model, catalog, join, vmiByCode });
}

test('sin --prev (o carpeta anterior inexistente) el diff es un no-op', async () => {
  const res = await carryOverridesAndDiff(path.join(tmp, 'nope.sqlite'), path.join(tmp, 'tampoco.sqlite'));
  assert.deepEqual(res, { overridesCopiados: 0, overridesHuerfanos: 0, fichasCopiadas: 0, cambios: 0, cambiosPorEntidad: {} });
});

test('AE4: un override de "duración" sobrevive a la re-extracción; un cambio de origen se marca', async () => {
  const v1 = path.join(tmp, 'v1.sqlite');
  const v2 = path.join(tmp, 'v2.sqlite');

  // v1: base
  await build(v1, [vmi('VMI.3770.FD5.02.04')]);

  // el curador edita: pone una duración en la actividad (override) y marca la ficha FD5 como revisada
  const { DatabaseSync } = await import('node:sqlite');
  const d1 = new DatabaseSync(v1);
  d1.prepare("INSERT INTO overrides VALUES ('actividad','FD5.02.04','duracion','90 min', ?)").run(new Date().toISOString());
  d1.prepare("UPDATE ficha_sistema SET revisado = 1, cuerpo = 'texto del curador' WHERE sistema_codigo = 'FD5'").run();
  d1.close();

  // v2: re-extracción con un VMI en el que ha cambiado la operación (simulado)
  const rec = vmi('VMI.3770.FD5.02.04');
  rec.operacion = 'Cambio de grasa — REVISIÓN 2025';
  await build(v2, [rec]);

  const res = await carryOverridesAndDiff(v2, v1);
  assert.equal(res.overridesCopiados, 1);
  assert.ok(res.fichasCopiadas >= 1);
  assert.ok(res.cambios >= 1);

  const d2 = new DatabaseSync(v2, { readOnly: true });
  // override traspasado intacto
  const ov = d2.prepare("SELECT valor FROM overrides WHERE entidad='actividad' AND id='FD5.02.04' AND campo='duracion'").get();
  assert.equal(ov.valor, '90 min');
  // el "extraído" de la actividad NO se ha tocado por el override (sigue el nuevo valor)
  const act = d2.prepare("SELECT operacion FROM actividad WHERE codigo='FD5.02.04'").get();
  assert.match(act.operacion, /REVISIÓN 2025/);
  // hay un cambio_pendiente por la operación, sin revisar
  const cp = d2.prepare("SELECT * FROM cambio_pendiente WHERE entidad='actividad' AND campo='operacion'").get();
  assert.ok(cp, 'debería haber un cambio_pendiente para operacion');
  assert.equal(cp.revisado, 0);
  assert.match(cp.valor_despues, /REVISIÓN 2025/);
  // la ficha revisada se conserva
  const ficha = d2.prepare("SELECT revisado, cuerpo FROM ficha_sistema WHERE sistema_codigo='FD5'").get();
  assert.equal(ficha.revisado, 1);
  assert.equal(ficha.cuerpo, 'texto del curador');
  d2.close();
});

test('un VMI sin cambios no genera cambio_pendiente', async () => {
  const v1 = path.join(tmp, 'a1.sqlite');
  const v2 = path.join(tmp, 'a2.sqlite');
  await build(v1, [vmi('VMI.3770.FD5.01.01')]);
  await build(v2, [vmi('VMI.3770.FD5.01.01')]);
  const res = await carryOverridesAndDiff(v2, v1);
  assert.equal(res.cambios, 0);
});

test('override sin destino: se copia igual (KTD7) pero se marca huérfano con una incidencia', async () => {
  const v1 = path.join(tmp, 'orph1.sqlite');
  const v2 = path.join(tmp, 'orph2.sqlite');

  await build(v1, [vmi('VMI.3770.FD5.02.04')]);
  const { DatabaseSync } = await import('node:sqlite');
  const d1 = new DatabaseSync(v1);
  d1.prepare("INSERT INTO overrides VALUES ('actividad','FD5.02.04','duracion','90 min', ?)").run(new Date().toISOString());
  d1.close();

  // v2: re-extracción sin ese VMI -- la actividad 'FD5.02.04' ya no existe
  await build(v2, [vmi('VMI.3770.FD5.01.01')]);

  const res = await carryOverridesAndDiff(v2, v1);
  assert.equal(res.overridesCopiados, 1);
  assert.equal(res.overridesHuerfanos, 1);

  const d2 = new DatabaseSync(v2, { readOnly: true });
  // el override se copia igualmente -- KTD7: la re-extracción nunca lo pierde
  const ov = d2.prepare(
    "SELECT valor FROM overrides WHERE entidad='actividad' AND id='FD5.02.04' AND campo='duracion'",
  ).get();
  assert.equal(ov.valor, '90 min');
  // pero se registra una incidencia para que el curador lo revise, en vez de desaparecer en silencio
  const inc = d2.prepare("SELECT * FROM incidencia_extraccion WHERE tipo='override-sin-destino'").get();
  assert.ok(inc, 'debería haber una incidencia por el override huérfano');
  assert.equal(inc.ref, 'actividad:FD5.02.04');
  d2.close();
});

test('AE3/R11/R12: la pertenencia a lote cambiada entre extracciones se marca cambio_pendiente', async () => {
  const v1 = path.join(tmp, 'lote1.sqlite');
  const v2 = path.join(tmp, 'lote2.sqlite');

  // v1: FD5.01.01 cae en IM1A por defecto (el fixture de materiales la
  // pone ahí -- comprobado aparte contra el build real).
  await build(v1, [vmi('VMI.3770.FD5.01.01')]);

  // v2: misma actividad, pero simula que el curador reasignó su lote en
  // el origen entre una extracción y la siguiente -- ahora cae en IM1B.
  await build(v2, [vmi('VMI.3770.FD5.01.01')]);
  const { DatabaseSync } = await import('node:sqlite');
  const d2b = new DatabaseSync(v2);
  d2b.exec("DELETE FROM actividad_lote WHERE actividad_codigo = 'FD5.01.01'");
  d2b.prepare("INSERT INTO actividad_lote VALUES ('FD5.01.01','IM1B')").run();
  d2b.close();

  const res = await carryOverridesAndDiff(v2, v1);
  assert.equal(res.cambiosPorEntidad.actividad_lote, 1);

  const d2 = new DatabaseSync(v2, { readOnly: true });
  const cp = d2.prepare(
    "SELECT * FROM cambio_pendiente WHERE entidad='actividad_lote' AND id='FD5.01.01'",
  ).get();
  assert.ok(cp, 'debería haber un cambio_pendiente para la pertenencia a lote de FD5.01.01');
  assert.equal(cp.campo, 'lote_codigo');
  assert.equal(cp.valor_antes, 'IM1A');
  assert.equal(cp.valor_despues, 'IM1B');
  assert.equal(cp.revisado, 0);
  d2.close();
});

test('un fallo a mitad de la copia hace ROLLBACK: no deja overrides a medio copiar ni deja el handle bloqueado', async () => {
  const v1 = path.join(tmp, 'fail1.sqlite');
  const v2 = path.join(tmp, 'fail2.sqlite');

  await build(v1, [vmi('VMI.3770.FD5.02.04')]);
  const { DatabaseSync } = await import('node:sqlite');
  const d1 = new DatabaseSync(v1);
  d1.prepare("INSERT INTO overrides VALUES ('actividad','FD5.02.04','duracion','90 min', ?)").run(new Date().toISOString());
  // corrompe v1 a propósito: el paso 1b (fichas) fallará porque la tabla ya no
  // existe, DESPUÉS de que el paso 1a (overrides) ya haya escrito en `next`.
  d1.exec('DROP TABLE ficha_sistema');
  d1.close();

  await build(v2, [vmi('VMI.3770.FD5.02.04')]);

  await assert.rejects(carryOverridesAndDiff(v2, v1));

  // el ROLLBACK debe haber deshecho la copia parcial de overrides (paso 1a ya
  // había corrido) y el handle debe haberse cerrado -- v2 se reabre sin bloqueo.
  const d2 = new DatabaseSync(v2, { readOnly: true });
  const ov = d2.prepare("SELECT * FROM overrides WHERE entidad='actividad' AND id='FD5.02.04'").get();
  assert.equal(ov, undefined, 'el override no debería haber quedado copiado tras el ROLLBACK');
  d2.close();
});
