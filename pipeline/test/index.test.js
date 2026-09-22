import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseArgs, run } from '../src/index.js';
import { makeFakeCorpus } from './helpers/fake-corpus.js';

test('parseArgs lee comando y flags', () => {
  const a = parseArgs(['build', '--config', 'c.json', '--prev', 'd', '--dry-run']);
  assert.equal(a.command, 'build');
  assert.equal(a.config, 'c.json');
  assert.equal(a.prev, 'd');
  assert.equal(a.dryRun, true);
});

test('parseArgs acepta -c y -h', () => {
  assert.equal(parseArgs(['build', '-c', 'x']).config, 'x');
  assert.equal(parseArgs(['-h']).help, true);
});

test('parseArgs lanza en argumento desconocido', () => {
  assert.throws(() => parseArgs(['build', '--nope']), /no reconocido/i);
});

/** captura las líneas que run() imprime */
function capture() {
  const lines = [];
  return { log: (...a) => lines.push(a.join(' ')), text: () => lines.join('\n') };
}

let corpus;
before(async () => {
  corpus = await makeFakeCorpus();
});
after(async () => {
  await corpus.cleanup();
});

async function writeConfig(obj) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-cfg-'));
  const p = path.join(dir, 'config.json');
  await fs.writeFile(p, JSON.stringify(obj, null, 2));
  return p;
}

test('run build --dry-run sobre un corpus falso imprime los conteos esperados', async () => {
  const cfg = await writeConfig({ cdromRoot: corpus.root, outDir: './data' });
  const out = capture();
  const code = await run(parseArgs(['build', '--config', cfg, '--dry-run']), out.log, out.log);
  assert.equal(code, 0);
  const t = out.text();
  assert.match(t, /\[vmi\]/);
  assert.match(t, /6 archivos/);           // los 6 VMI del fixture
  assert.match(t, /TOTAL: \d+ archivos/);
  assert.match(t, /--dry-run: no se escribe/);
});

test('run build aborta con código 2 y nombra la raíz que falta', async () => {
  const cfg = await writeConfig({
    cdromRoot: corpus.root,
    roots: { vmi: '/ruta/que/no/existe/vmi' },
    outDir: './data',
  });
  const out = capture();
  const code = await run(parseArgs(['build', '--config', cfg]), out.log, out.log);
  assert.equal(code, 2);
  assert.match(out.text(), /vmi/);
  assert.match(out.text(), /no se encuentran/i);
});

test('run sin --config devuelve 1', async () => {
  const out = capture();
  const code = await run(parseArgs(['build']), out.log, out.log);
  assert.equal(code, 1);
  assert.match(out.text(), /Falta --config/);
});

test('run con comando desconocido devuelve 1 y muestra ayuda', async () => {
  const out = capture();
  const code = await run(parseArgs(['frobnicate']), out.log, out.log);
  assert.equal(code, 1);
  assert.match(out.text(), /Uso:/);
});
