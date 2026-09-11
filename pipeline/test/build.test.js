import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { writeDatabase } from '../src/build/sqlite-writer.js';
import { selectAndCopyPdfs, esVmiIndividual } from '../src/build/pdf-select-copy.js';
import { writeManifest, readManifest } from '../src/build/manifest.js';
import { parsePlan } from '../src/corpus/xlsx-plan.js';
import { parseMateriales } from '../src/corpus/xlsx-materiales.js';
import { parseVmi } from '../src/corpus/vmi-parser.js';
import { buildCycleModel } from '../src/model/cycles.js';
import { buildCatalog } from '../src/model/catalog.js';
import { buildJoinGraph } from '../src/model/join.js';
import { normalizarCodigo } from '../src/model/codes.js';
import { fakeMaterialesWorkbook, fakePlanWorkbook, xlsx } from './helpers/xlsx-fixtures.js';
import { makeFakeCorpus } from './helpers/fake-corpus.js';

const dir = path.dirname(fileURLToPath(import.meta.url));
const vmi = (code) =>
  parseVmi(JSON.parse(readFileSync(path.join(dir, 'fixtures', 'vmi', `${code}.lines.json`), 'utf8')), { codigo: code });

let tmp;
before(async () => { tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-build-')); });
after(async () => { await fs.rm(tmp, { recursive: true, force: true }); });

test('esVmiIndividual excluye los compendios', () => {
  assert.equal(esVmiIndividual('VMI.3770.FD5.01.01.pdf'), true);
  assert.equal(esVmiIndividual('I1.pdf'), false);
  assert.equal(esVmiIndividual('NS.pdf'), false);
  assert.equal(esVmiIndividual('Menu VMIs.pdf'), false);
});

test('writeDatabase: data.sqlite abre y la búsqueda FTS devuelve la actividad', async () => {
  const plan = parsePlan(xlsx, fakePlanWorkbook());
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  const vmiRecords = [
    Object.assign(vmi('VMI.3770.FD5.02.04'), { relPath: 'IM1/VMI.3770.FD5.02.04.pdf', ciclo: 'IM1' }),
    Object.assign(vmi('VMI.3770.FD5.01.01'), { relPath: 'I1/VMI.3770.FD5.01.01.pdf', ciclo: 'I1' }),
  ];
  const model = buildCycleModel({ plan, materiales });
  const catalog = buildCatalog({ materiales, vmiRecords });
  const join = buildJoinGraph({
    plan, materiales, vmiRecords,
    manualesDirs: [{ name: 'BB21106005034 FD5 Reductor y acoplamiento', relPath: 'x', files: [{ relPath: 'x/m.pdf' }] }],
    tocPorManual: { 'x/m.pdf': [{ titulo: 'Descripción funcional', pagina: 2, nivel: 1 }] },
  });
  const vmiByCode = new Map(vmiRecords.map((r) => [normalizarCodigo(r.codigo), r]));

  const dbPath = path.join(tmp, 'data.sqlite');
  const { counts } = await writeDatabase(dbPath, { plan, materiales, model, catalog, join, vmiByCode });
  assert.ok(counts.actividades >= 2);
  assert.ok(counts.busqueda >= counts.actividades);

  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync(dbPath, { readOnly: true });
  const hit = db.prepare(
    "SELECT tipo, ref FROM busqueda WHERE busqueda MATCH ? ORDER BY rank LIMIT 3",
  ).all('semiacoplamiento OR reengras*');
  assert.ok(hit.length >= 1, 'la búsqueda debería devolver algo');
  assert.ok(hit.some((r) => r.tipo === 'actividad' && r.ref === 'FD5.02.04'));

  // acento-insensible: "inspeccion" encuentra "Inspección"
  const hit2 = db.prepare("SELECT ref FROM busqueda WHERE busqueda MATCH ?").all('inspeccion');
  assert.ok(hit2.length >= 1);

  // procedimiento y materiales poblados
  assert.ok(db.prepare('SELECT count(*) c FROM actividad_paso WHERE actividad_codigo = ?').get('FD5.02.04').c >= 10);
  assert.ok(db.prepare('SELECT count(*) c FROM actividad_material').get().c >= 5);
  assert.equal(db.prepare('SELECT revisado FROM ficha_sistema WHERE sistema_codigo = ?').get('FD5').revisado, 0);
  db.close();
});

test('actividad_nivel: los niveles RDH se pueblan desde materiales (R9/R10/R12/AE3)', async () => {
  const plan = parsePlan(xlsx, fakePlanWorkbook());
  const materiales = parseMateriales(xlsx, fakeMaterialesWorkbook());
  // FC1.02.04 (RDH2) tiene VMI en este build; FC1.04.10 (RDH3, también en el
  // fixture de materiales) no -- no debe generar una fila de actividad_nivel
  // colgante para una tarea que no es una actividad real de este build.
  const vmiRecords = [
    { codigo: 'VMI.3770.FC1.02.04', relPath: 'NS/VMI.3770.FC1.02.04.pdf', ciclo: 'NS',
      componente: null, actividadTipo: null, operacion: 'Cambio de aceite motor', edicion: null, sinExtraer: false },
  ];
  const model = buildCycleModel({ plan, materiales });
  const catalog = buildCatalog({ materiales, vmiRecords });
  const join = buildJoinGraph({ plan, materiales, vmiRecords, manualesDirs: [], tocPorManual: {} });
  const vmiByCode = new Map(vmiRecords.map((r) => [normalizarCodigo(r.codigo), r]));

  const dbPath = path.join(tmp, 'data-rdh.sqlite');
  await writeDatabase(dbPath, { plan, materiales, model, catalog, join, vmiByCode });

  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync(dbPath, { readOnly: true });
  assert.ok(
    db.prepare('SELECT 1 FROM actividad_nivel WHERE actividad_codigo = ? AND nivel_codigo = ?').get('FC1.02.04', 'RDH2'),
    'FC1.02.04 debería quedar vinculada al nivel RDH2',
  );
  assert.equal(
    db.prepare('SELECT 1 FROM actividad_nivel WHERE actividad_codigo = ?').get('FC1.04.10'),
    undefined,
    'FC1.04.10 no tiene VMI en este build: no debe dejar una fila de actividad_nivel colgante',
  );
  db.close();
});

test('selectAndCopyPdfs: copia los VMI individuales y excluye los mega-PDF', async () => {
  const corpus = await makeFakeCorpus();
  const outDir = path.join(tmp, 'out1');
  const roots = {
    vmi: path.join(corpus.root, '04 Instrucciones plan mantenimiento (VMI)'),
    manuales: path.join(corpus.root, '05 Manuales mantenimiento'),
    esquemas: path.join(corpus.root, '07 Esquemas'),
  };
  const res = await selectAndCopyPdfs({ roots, outDir });
  await corpus.cleanup();

  assert.ok(res.copiados >= 4);
  await fs.access(path.join(outDir, 'pdfs', 'vmi', 'I1', 'VMI.3770.FD5.01.01.pdf')); // copiado
  await assert.rejects(fs.access(path.join(outDir, 'pdfs', 'vmi', 'NS', 'NS.pdf'))); // excluido
  assert.ok(res.excluidos.some((e) => e.endsWith('NS/NS.pdf')));
  assert.ok(res.excluidos.some((e) => e.includes('Menu VMIs.pdf')));
  // manuales y esquemas sí
  await fs.access(path.join(outDir, 'pdfs', 'esquemas', 'esquema-general.PDF'));
});

test('writeManifest: schema_version y data_folder_version presentes; --prev incrementa', async () => {
  const d1 = path.join(tmp, 'v1');
  const m1 = await writeManifest(d1, { dataFolderVersion: 1, sources: { plan_xlsx: 'plan.xlsx' }, counts: { actividades: 437 } });
  assert.equal(m1.schema_version, 1);
  assert.equal(m1.data_folder_version, 1);
  assert.match(m1.build_date, /^\d{4}-\d{2}-\d{2}T/);

  const prev = await readManifest(d1);
  const d2 = path.join(tmp, 'v2');
  const m2 = await writeManifest(d2, { dataFolderVersion: (prev.data_folder_version ?? 0) + 1 });
  assert.equal(m2.data_folder_version, 2);
});
