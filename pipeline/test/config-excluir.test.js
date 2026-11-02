import { test } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadConfig, rutaExcluida } from '../src/config.js';

async function conConfig(obj, fn) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-cfg-'));
  try {
    const p = path.join(dir, 'config.json');
    await fs.writeFile(p, JSON.stringify(obj));
    return await fn(p);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
}

test('loadConfig: excluirVmi vacío por defecto', async () => {
  await conConfig({ cdromRoot: '.' }, async (p) => {
    assert.deepEqual((await loadConfig(p)).excluirVmi, []);
  });
});

test('loadConfig: excluirVmi normaliza barras y espacios', async () => {
  await conConfig({ cdromRoot: '.', excluirVmi: [' Revision Horas Disel 4\\ ', './I1/sub/'] }, async (p) => {
    assert.deepEqual((await loadConfig(p)).excluirVmi, ['Revision Horas Disel 4', 'I1/sub']);
  });
});

test('loadConfig: excluirVmi que no es lista de textos da un error claro', async () => {
  await conConfig({ cdromRoot: '.', excluirVmi: 'Revision' }, async (p) => {
    await assert.rejects(loadConfig(p), /excluirVmi/);
  });
});

test('rutaExcluida: la carpeta y todo lo que cuelga de ella, sin distinguir mayúsculas', () => {
  const ex = ['Revision Horas Disel 4'];
  assert.equal(rutaExcluida('Revision Horas Disel 4/VMI.3770.FC1.01.02. Actividad 10.pdf', ex), true);
  assert.equal(rutaExcluida('revision horas disel 4/x/y.pdf', ex), true);
  assert.equal(rutaExcluida('Revision Horas Disel 40/a.pdf', ex), false);
  assert.equal(rutaExcluida('I1/VMI.3770.FD5.01.01.pdf', ex), false);
  assert.equal(rutaExcluida('I1/VMI.3770.FD5.01.01.pdf', []), false);
});
