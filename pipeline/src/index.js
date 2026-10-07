#!/usr/bin/env node
// CLI de extracción del corpus S336.
//
//   node src/index.js build --config <ruta> [--prev <carpeta-datos-anterior>] [--dry-run]
//
// Fase A (unidades U1..U7):
//   U1  inventario del corpus            <- este archivo + corpus/walk.js
//   U2  parser de VMI                    corpus/vmi-parser.js
//   U3  parsers de los XLSX              corpus/xlsx-plan.js, corpus/xlsx-materiales.js
//   U4  catálogo normalizado            model/catalog.js
//   U5  grafo de unión + fichas         model/join.js, model/cycles.js
//   U6  escritura de la carpeta de datos build/*
//   U7  re-extracción con diff          build/diff.js

import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { loadConfig, validateRoots } from './config.js';
import { inventory } from './corpus/walk.js';

/** @param {string[]} argv */
export function parseArgs(argv) {
  const args = { command: null, config: null, prev: null, dryRun: false, conToc: false, reanudar: false, help: false };
  const rest = argv.slice();
  if (rest[0] && !rest[0].startsWith('-')) args.command = rest.shift();
  while (rest.length) {
    const tok = rest.shift();
    switch (tok) {
      case '--config':
      case '-c':
        args.config = rest.shift() ?? null;
        break;
      case '--prev':
        args.prev = rest.shift() ?? null;
        break;
      case '--dry-run':
        args.dryRun = true;
        break;
      case '--con-toc':
        args.conToc = true;
        break;
      case '--reanudar':
        args.reanudar = true;
        break;
      case '-h':
      case '--help':
        args.help = true;
        break;
      default:
        throw new Error(`Argumento no reconocido: ${tok}`);
    }
  }
  return args;
}

const USAGE = `consulta-s336 pipeline

Uso:
  node src/index.js build --config <ruta.json> [--prev <carpeta-datos>] [--dry-run]

Opciones:
  --config, -c   Archivo de configuración (obligatorio). Declara 'cdromRoot' y 'outDir'.
  --prev         Carpeta de datos anterior, para la re-extracción con diff (U7).
  --dry-run      Solo inventario; no escribe la carpeta de datos.
  --reanudar     Continúa una extracción interrumpida en la misma carpeta de datos:
                 los VMI ya terminados (guardados en <carpeta>/.cache-vmi) y los PDF
                 ya copiados no se vuelven a leer de la red. Sin este flag la
                 carpeta de datos se reconstruye desde cero.
  --help, -h     Esta ayuda.
`;

/**
 * Imprime el inventario del corpus de forma legible.
 * @param {Awaited<ReturnType<typeof inventory>>} inv
 */
export function printInventory(inv, log = console.log) {
  log('Inventario del corpus');
  log('=====================');
  for (const [name, r] of Object.entries(inv.roots)) {
    const t = r.byType;
    log(`\n[${name}]  ${r.path}`);
    log(`  ${r.count} archivos  (pdf ${t.pdf}, xlsx ${t.xlsx}, xls ${t.xls}, otro ${t.otro})`);
    const subs = Object.entries(r.bySubdir).filter(([k]) => k !== '.');
    if (subs.length) {
      for (const [sub, s] of subs.sort((a, b) => a[0].localeCompare(b[0]))) {
        log(`    ${sub.padEnd(40)} ${String(s.count).padStart(4)}  (pdf ${s.byType.pdf})`);
      }
    }
  }
  const tt = inv.totals.byType;
  log(`\nTOTAL: ${inv.totals.files} archivos  (pdf ${tt.pdf}, xlsx ${tt.xlsx}, xls ${tt.xls}, otro ${tt.otro})`);
  if (inv.errors.length) {
    log(`\nAVISOS (${inv.errors.length}):`);
    for (const e of inv.errors) log(`  - ${e}`);
  }
}

/**
 * @param {ReturnType<typeof parseArgs>} args
 * @returns {Promise<number>} exit code
 */
export async function run(args, log = console.log, errLog = console.error) {
  if (args.help || !args.command) {
    log(USAGE);
    return args.help ? 0 : 1;
  }
  if (args.command !== 'build') {
    errLog(`Comando no reconocido: ${args.command}`);
    log(USAGE);
    return 1;
  }
  if (!args.config) {
    errLog('Falta --config <ruta.json>');
    return 1;
  }

  const cfg = await loadConfig(args.config);
  const check = await validateRoots(cfg);
  if (!check.ok) {
    errLog('Configuración inválida: no se encuentran una o más raíces del corpus.');
    for (const m of check.missing) errLog(`  falta: ${m}`);
    for (const p of check.problems) errLog(`  problema: ${p}`);
    return 2;
  }

  const rootsToScan = { ...cfg.roots };
  // 'esquemas' es opcional: solo se inventaría si existe
  const inv = await inventory(rootsToScan);
  printInventory(inv, log);

  if (args.dryRun) {
    log('\n--dry-run: no se escribe la carpeta de datos.');
    return 0;
  }

  log('\nExtrayendo el corpus...\n');
  const { runBuild } = await import('./build/run-build.js');
  const res = await runBuild({
    cfg, prevDir: args.prev, conToc: args.conToc, reanudar: args.reanudar, log: (m) => log(m),
  });

  log(`\nCarpeta de datos v${res.dataFolderVersion} escrita en ${cfg.outDir}`);
  log(`  esquema v${res.schemaVersion}  ·  ${JSON.stringify(res.counts)}`);
  if (res.incidencias.length) {
    log(`\nIncidencias de unión (${res.incidencias.length}) — revisar:`);
    const porTipo = {};
    for (const i of res.incidencias) (porTipo[i.tipo] ??= []).push(i.ref);
    for (const [tipo, refs] of Object.entries(porTipo)) {
      log(`  ${tipo} (${refs.length}): ${refs.slice(0, 8).join(', ')}${refs.length > 8 ? '…' : ''}`);
    }
  }
  if (res.sinExtraer.length) {
    log(`\nVMI sin extraer (${res.sinExtraer.length}):`);
    for (const s of res.sinExtraer.slice(0, 15)) log(`  ${s.relPath} :: ${s.motivo}`);
  }
  return 0;
}

/* c8 ignore start */
const isMain = !!process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  (async () => {
    try {
      const args = parseArgs(process.argv.slice(2));
      const code = await run(args);
      process.exit(code);
    } catch (err) {
      console.error(`Error: ${err.message}`);
      process.exit(1);
    }
  })();
}
/* c8 ignore stop */
