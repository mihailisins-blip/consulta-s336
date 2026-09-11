import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { runBuild } from '../src/build/run-build.js';
import { SCHEMA_VERSION } from '../src/build/manifest.js';

let tmp;
before(async () => { tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-runbuild-')); });
after(async () => { await fs.rm(tmp, { recursive: true, force: true }); });

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
