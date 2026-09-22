import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { classifyType, walkDir, summarize, byImmediateSubdir, inventory } from '../src/corpus/walk.js';
import { makeFakeCorpus } from './helpers/fake-corpus.js';

test('classifyType clasifica por extensión, case-insensitive', () => {
  assert.equal(classifyType('a.pdf'), 'pdf');
  assert.equal(classifyType('a.PDF'), 'pdf');
  assert.equal(classifyType('Listas.XLSX'), 'xlsx');
  assert.equal(classifyType('Indice.xls'), 'xls');
  assert.equal(classifyType('anexo.tif'), 'otro');
  assert.equal(classifyType('notas.rar'), 'otro');
  assert.equal(classifyType('sin-extension'), 'otro');
});

let corpus;
before(async () => {
  corpus = await makeFakeCorpus();
});
after(async () => {
  await corpus.cleanup();
});

test('walkDir recorre recursivamente y devuelve rutas relativas con "/"', async () => {
  const vmiDir = path.join(corpus.root, '04 Instrucciones plan mantenimiento (VMI)');
  const { files, errors } = await walkDir(vmiDir);
  assert.equal(errors.length, 0);
  assert.equal(files.length, 6); // 3 en I1, 1 en IM1, 2 en NS
  const rels = files.map((f) => f.relPath);
  assert.ok(rels.includes('I1/VMI.3770.FD5.01.01.pdf'));
  assert.ok(rels.includes('NS/VMI.3770.FC1.01.02.pdf'));
  assert.ok(rels.every((r) => !r.includes('\\')));
});

test('un archivo con extensión inesperada se lista como "otro" y no rompe el recorrido', async () => {
  const cat = path.join(corpus.root, '06 Catalogo piezas');
  const { files } = await walkDir(cat);
  const rar = files.find((f) => f.name === 'notas.rar');
  assert.ok(rar, 'notas.rar debería estar listado');
  assert.equal(rar.type, 'otro');
  // el resto sigue: xlsx y pdf presentes
  assert.ok(files.some((f) => f.type === 'xlsx'));
  assert.ok(files.some((f) => f.type === 'pdf'));
});

test('walkDir sobre una ruta inexistente devuelve un error nombrándola, sin lanzar', async () => {
  const missing = path.join(corpus.root, 'NO EXISTE');
  const { files, errors } = await walkDir(missing);
  assert.equal(files.length, 0);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /NO EXISTE/);
});

test('summarize cuenta por tipo', () => {
  const files = [
    { type: 'pdf' }, { type: 'pdf' }, { type: 'xlsx' }, { type: 'otro' },
  ];
  assert.deepEqual(summarize(files), { count: 4, byType: { pdf: 2, xlsx: 1, xls: 0, otro: 1 } });
});

test('byImmediateSubdir agrupa por la primera carpeta', () => {
  const files = [
    { relPath: 'I1/a.pdf', type: 'pdf' },
    { relPath: 'I1/b.pdf', type: 'pdf' },
    { relPath: 'NS/c.pdf', type: 'pdf' },
    { relPath: 'suelto.pdf', type: 'pdf' },
  ];
  const g = byImmediateSubdir(files);
  assert.equal(g.I1.count, 2);
  assert.equal(g.NS.count, 1);
  assert.equal(g['.'].count, 1);
});

test('inventory produce conteos por raíz y totales', async () => {
  const roots = {
    plan: path.join(corpus.root, '03 Plan mantenimiento'),
    vmi: path.join(corpus.root, '04 Instrucciones plan mantenimiento (VMI)'),
    manuales: path.join(corpus.root, '05 Manuales mantenimiento'),
    materiales: path.join(corpus.root, '06 Catalogo piezas'),
  };
  const inv = await inventory(roots);
  assert.equal(inv.roots.plan.count, 2);
  assert.equal(inv.roots.vmi.count, 6);
  assert.equal(inv.roots.vmi.byType.pdf, 6);
  assert.equal(inv.roots.manuales.count, 3); // 2 pdf + 1 tif
  assert.equal(inv.roots.manuales.byType.otro, 1);
  assert.equal(inv.roots.materiales.byType.xlsx, 1);
  assert.equal(inv.totals.files, 2 + 6 + 3 + 3);
  // la vista por subcarpeta de vmi ve los ciclos
  assert.ok(inv.roots.vmi.bySubdir.I1);
  assert.ok(inv.roots.vmi.bySubdir.NS);
});
