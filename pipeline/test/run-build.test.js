import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { runBuild, logWalkErrors } from '../src/build/run-build.js';
import { SCHEMA_VERSION } from '../src/build/manifest.js';
import { makeFakeCorpus } from './helpers/fake-corpus.js';

let tmp;
before(async () => { tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-runbuild-')); });
after(async () => { await fs.rm(tmp, { recursive: true, force: true }); });

test('logWalkErrors no escribe nada si no hay errores', () => {
  const lines = [];
  logWalkErrors('VMI (04)', [], (m) => lines.push(m));
  assert.deepEqual(lines, []);
});

test('logWalkErrors nombra el área y cada error, en vez de pasarlos por alto en silencio', () => {
  const lines = [];
  logWalkErrors('manuales (05)', ['/x/y: EACCES', '/x/z: ENOENT'], (m) => lines.push(m));
  assert.ok(lines.some((l) => l.includes('manuales (05)') && l.includes('2 error')));
  assert.ok(lines.some((l) => l.includes('EACCES')));
  assert.ok(lines.some((l) => l.includes('ENOENT')));
});

test('runBuild rechaza --prev contra una carpeta de esquema distinto, antes de tocar el corpus', async () => {
  const prevDir = path.join(tmp, 'prev-v0');
  await fs.mkdir(prevDir, { recursive: true });
  await fs.writeFile(
    path.join(prevDir, 'manifest.json'),
    JSON.stringify({ schema_version: SCHEMA_VERSION + 1, data_folder_version: 1 }),
  );

  const cfg = {
    outDir: path.join(tmp, 'out'),
    // rutas deliberadamente inexistentes: si el guard de esquema no abortara
    // antes de tocar el corpus, esto fallaría por otro motivo ("no
    // encontrado"), delatando que el guard no se ejecutó primero.
    roots: {
      plan: path.join(tmp, 'no-existe-plan'),
      vmi: path.join(tmp, 'no-existe-vmi'),
      manuales: path.join(tmp, 'no-existe-manuales'),
      materiales: path.join(tmp, 'no-existe-materiales'),
    },
  };

  await assert.rejects(runBuild({ cfg, prevDir }), (err) => {
    assert.match(err.message, new RegExp(`esquema v${SCHEMA_VERSION + 1}\\b`));
    assert.match(err.message, new RegExp(`escribe v${SCHEMA_VERSION}\\b`));
    return true;
  });
});

test('runBuild con --prev del mismo esquema no aborta por el guard (falla más adelante, por corpus inexistente)', async () => {
  const prevDir = path.join(tmp, 'prev-mismo');
  await fs.mkdir(prevDir, { recursive: true });
  await fs.writeFile(
    path.join(prevDir, 'manifest.json'),
    JSON.stringify({ schema_version: SCHEMA_VERSION, data_folder_version: 3 }),
  );

  const cfg = {
    outDir: path.join(tmp, 'out2'),
    roots: {
      plan: path.join(tmp, 'no-existe-plan-2'),
      vmi: path.join(tmp, 'no-existe-vmi-2'),
      manuales: path.join(tmp, 'no-existe-manuales-2'),
      materiales: path.join(tmp, 'no-existe-materiales-2'),
    },
  };

  // mismo esquema -> el guard no dispara; el fallo real es "no se encontró el
  // XLSX del plan" (corpus inexistente), no un mensaje de incompatibilidad.
  await assert.rejects(runBuild({ cfg, prevDir }), /no se encontr[oó]/i);
});

test('runBuild da un error con nombre de archivo si el XLSX del plan no se puede leer, en vez de un fallo opaco', async () => {
  const corpus = await makeFakeCorpus();
  // xlsx (SheetJS) es muy tolerante: un archivo vacío o texto plano no lo
  // hace lanzar, solo produce un workbook sin la hoja esperada. Para forzar
  // un fallo real de lectura hace falta un ZIP (el contenedor de un .xlsx)
  // reconocible pero corrupto -- se genera uno válido y se trunca a la mitad,
  // así falta el directorio central del ZIP.
  const planPath = path.join(corpus.root, '03 Plan mantenimiento', 'EUROLIGHT ADIF PLAN DE MANTENIMIENTO_x.XLSX');
  const xlsx = (await import('xlsx')).default;
  const wb = xlsx.utils.book_new();
  xlsx.utils.book_append_sheet(wb, xlsx.utils.aoa_to_sheet([['a', 'b'], ['1', '2']]), 'Hoja1');
  xlsx.writeFile(wb, planPath);
  const full = await fs.readFile(planPath);
  await fs.writeFile(planPath, full.subarray(0, Math.floor(full.length / 2)));

  const cfg = {
    outDir: path.join(tmp, 'out-badxlsx'),
    roots: {
      plan: path.join(corpus.root, '03 Plan mantenimiento'),
      vmi: path.join(corpus.root, '04 Instrucciones plan mantenimiento (VMI)'),
      manuales: path.join(corpus.root, '05 Manuales mantenimiento'),
      materiales: path.join(corpus.root, '06 Catalogo piezas'),
    },
  };
  try {
    await assert.rejects(runBuild({ cfg }), (err) => {
      assert.match(err.message, /no se pudo leer el XLSX del plan/);
      assert.match(err.message, /EUROLIGHT ADIF PLAN DE MANTENIMIENTO/);
      return true;
    });
  } finally {
    await corpus.cleanup();
  }
});
