import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { runBuild, logWalkErrors, buildVmiByCode } from '../src/build/run-build.js';
import { SCHEMA_VERSION, readManifest } from '../src/build/manifest.js';
import { makeFakeCorpus } from './helpers/fake-corpus.js';
import { fakePlanWorkbook, fakeMaterialesWorkbook, xlsx } from './helpers/xlsx-fixtures.js';

let tmp;
before(async () => { tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-runbuild-')); });
after(async () => { await fs.rm(tmp, { recursive: true, force: true }); });

test('buildVmiByCode: ante un código duplicado, prefiere el ejemplar que sí se pudo extraer', () => {
  const map = buildVmiByCode([
    { codigo: 'VMI.3770.FD5.01.02', sinExtraer: true, ciclo: 'I1' },
    { codigo: 'VMI.3770.FD5.01.02', sinExtraer: false, ciclo: 'IM1' },
  ]);
  assert.equal(map.get('FD5.01.02').sinExtraer, false);
  assert.equal(map.get('FD5.01.02').ciclo, 'IM1');
});

test('buildVmiByCode: si ambos duplicados están sin extraer, conserva el primero', () => {
  const map = buildVmiByCode([
    { codigo: 'VMI.3770.FD5.01.02', sinExtraer: true, ciclo: 'I1' },
    { codigo: 'VMI.3770.FD5.01.02', sinExtraer: true, ciclo: 'IM1' },
  ]);
  assert.equal(map.get('FD5.01.02').ciclo, 'I1');
});

test('buildVmiByCode: si ambos duplicados sí se extrajeron, conserva el primero (no lo vuelve a sustituir)', () => {
  const map = buildVmiByCode([
    { codigo: 'VMI.3770.FD5.01.02', sinExtraer: false, ciclo: 'I1' },
    { codigo: 'VMI.3770.FD5.01.02', sinExtraer: false, ciclo: 'IM1' },
  ]);
  assert.equal(map.get('FD5.01.02').ciclo, 'I1');
});

test('buildVmiByCode: un código no normalizable se descarta sin lanzar', () => {
  const map = buildVmiByCode([{ codigo: 'no es un código VMI', sinExtraer: false }]);
  assert.equal(map.size, 0);
});

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

/**
 * Construye un PDF mínimo pero genuinamente válido (una página en blanco,
 * sin texto): calcula los offsets del xref a partir del cuerpo ya montado,
 * en vez de darlos por buenos a mano. pdfjs-dist lo abre sin problema; al no
 * traer ningún texto, vmi-parser.js lo marca sinExtraer por su cuenta (no
 * hace falta que encaje en la plantilla VMI para probar el pipeline real de
 * lectura de PDF).
 */
function minimalPdfBytes() {
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> >>',
  ];
  let body = '%PDF-1.4\n';
  const offsets = [0];
  objs.forEach((o, i) => {
    offsets.push(body.length);
    body += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xrefStart = body.length;
  let xref = `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`;
  for (let i = 1; i <= objs.length; i++) xref += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
  body += xref;
  body += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF`;
  return Buffer.from(body, 'latin1');
}

/** Corpus falso con XLSX reales (parseables) para que runBuild llegue hasta el final. */
async function buildRealCorpus(dir) {
  const roots = {
    plan: path.join(dir, '03 Plan mantenimiento'),
    vmi: path.join(dir, '04 Instrucciones plan mantenimiento (VMI)'),
    manuales: path.join(dir, '05 Manuales mantenimiento'),
    materiales: path.join(dir, '06 Catalogo piezas'),
  };
  await fs.mkdir(roots.plan, { recursive: true });
  await fs.mkdir(path.join(roots.vmi, 'I1'), { recursive: true });
  await fs.mkdir(path.join(roots.vmi, 'NS'), { recursive: true });
  await fs.mkdir(roots.manuales, { recursive: true });
  await fs.mkdir(roots.materiales, { recursive: true });

  xlsx.writeFile(fakePlanWorkbook(), path.join(roots.plan, 'plan.xlsx'));
  xlsx.writeFile(fakeMaterialesWorkbook(), path.join(roots.materiales, 'materiales.xlsx'));

  // un VMI real: PDF válido y legible, pero sin contenido -- no encaja en la
  // plantilla y vmi-parser.js lo marca sinExtraer por su cuenta.
  await fs.writeFile(path.join(roots.vmi, 'I1', 'VMI.3770.FD5.01.01.pdf'), minimalPdfBytes());
  // un "VMI" cuyos bytes no son un PDF en absoluto -- este SÍ dispara el
  // try/catch de run-build.js: pdfToLines lanza, se degrada a sinExtraer con
  // motivo "error al leer el PDF", y el resto del lote sigue igualmente.
  await fs.writeFile(path.join(roots.vmi, 'NS', 'VMI.3770.FC1.02.04.pdf'), 'esto no es un PDF en absoluto');

  return { roots };
}

test('runBuild: un PDF ilegible se degrada a sinExtraer y no aborta el resto del lote (pMap + try/catch reales)', async () => {
  const corpusDir = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-realcorpus-'));
  try {
    const { roots } = await buildRealCorpus(corpusDir);
    const res = await runBuild({ cfg: { outDir: path.join(tmp, 'out-real'), bundlePdfs: false, roots }, log: () => {} });

    assert.equal(res.sinExtraer.length, 2, 'los dos VMI (el PDF vacío y el que no es un PDF) deberían quedar sinExtraer');

    const porBytesMalos = res.sinExtraer.find((s) => s.relPath.includes('FC1.02.04'));
    assert.ok(porBytesMalos, 'debería listar el archivo que no es un PDF');
    assert.match(
      porBytesMalos.motivo, /error al leer el PDF/,
      'el archivo que no es un PDF debe fallar en pdfToLines (try/catch de run-build.js), no en vmi-parser',
    );

    const porPlantilla = res.sinExtraer.find((s) => s.relPath.includes('FD5.01.01'));
    assert.ok(porPlantilla, 'debería listar el PDF válido pero vacío');
    assert.doesNotMatch(
      porPlantilla.motivo, /error al leer el PDF/,
      'el PDF válido pero vacío falla al no encajar en la plantilla, no al leerse',
    );
  } finally {
    await fs.rm(corpusDir, { recursive: true, force: true });
  }
});

test('runBuild: dataFolderVersion se incrementa al re-extraer con --prev (dos builds reales encadenados)', async () => {
  const corpusDir = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-realcorpus2-'));
  try {
    const { roots } = await buildRealCorpus(corpusDir);
    const outDir1 = path.join(tmp, 'out-v1');
    const outDir2 = path.join(tmp, 'out-v2');

    const res1 = await runBuild({ cfg: { outDir: outDir1, bundlePdfs: false, roots }, log: () => {} });
    assert.equal(res1.dataFolderVersion, 1);

    const res2 = await runBuild({
      cfg: { outDir: outDir2, bundlePdfs: false, roots }, prevDir: outDir1, log: () => {},
    });
    assert.equal(res2.dataFolderVersion, 2);

    const manifest2 = await readManifest(outDir2);
    assert.equal(manifest2.data_folder_version, 2);
  } finally {
    await fs.rm(corpusDir, { recursive: true, force: true });
  }
});
