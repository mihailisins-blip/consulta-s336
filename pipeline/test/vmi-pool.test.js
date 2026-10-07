import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { crearPoolVmi, tamanoPoolPorDefecto } from '../src/corpus/vmi-pool.js';
import { pdfConImagenes } from './helpers/pdf-sintetico.js';

let tmp;
before(async () => { tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-pool-')); });
after(async () => { await fs.rm(tmp, { recursive: true, force: true }); });

test('tamanoPoolPorDefecto: entre 1 y 6 workers', () => {
  const n = tamanoPoolPorDefecto();
  assert.ok(n >= 1 && n <= 6);
});

test('copia el PDF desde los bytes leídos y deja caché; reanudar la reutiliza sin leer el origen, y la invalida si falta la copia', async () => {
  const pool = crearPoolVmi(1);
  try {
    const origen = path.join(tmp, 'origen.pdf');
    const bytes = pdfConImagenes();
    await fs.writeFile(origen, bytes);
    const job = {
      file: origen,
      codigo: 'X',
      outDir: tmp,
      copiarA: path.join(tmp, 'pdfs', 'vmi', 'X.pdf'),
      cacheFile: path.join(tmp, '.cache-vmi', 'x.json'),
      tamano: bytes.length,
    };

    const primera = await pool.run({ ...job, usarCache: false });
    assert.equal(primera.desdeCache, false);
    assert.deepEqual(primera.copia, { ok: true, bytes: bytes.length });
    assert.equal((await fs.readFile(job.copiarA)).length, bytes.length, 'la copia se escribe desde los bytes leídos');

    // el origen desaparece: solo la caché puede responder
    await fs.rm(origen);
    const reanudada = await pool.run({ ...job, usarCache: true });
    assert.equal(reanudada.desdeCache, true);
    assert.deepEqual(reanudada.rec, primera.rec);

    // sin la copia en disco la caché ya no vale: intenta leer el origen (que no está)
    await fs.rm(job.copiarA);
    await assert.rejects(pool.run({ ...job, usarCache: true }), /ENOENT|no such file/i);
  } finally {
    await pool.close();
  }
});

test('un fallo en un VMI (archivo inexistente o PDF roto) rechaza solo ese trabajo; el pool sigue sirviendo los demás', async () => {
  const pool = crearPoolVmi(1); // un solo worker: los tres trabajos pasan por la cola
  try {
    const roto = path.join(tmp, 'roto.pdf');
    await fs.writeFile(roto, 'esto no es un PDF');
    const resultados = await Promise.allSettled([
      pool.run({ file: path.join(tmp, 'no-existe.pdf'), codigo: 'A', outDir: tmp }),
      pool.run({ file: roto, codigo: 'B', outDir: tmp }),
      pool.run({ file: path.join(tmp, 'tampoco.pdf'), codigo: 'C', outDir: tmp }),
    ]);
    assert.deepEqual(resultados.map((r) => r.status), ['rejected', 'rejected', 'rejected']);
    assert.match(resultados[0].reason.message, /ENOENT|no such file/i);
  } finally {
    await pool.close();
  }
});
