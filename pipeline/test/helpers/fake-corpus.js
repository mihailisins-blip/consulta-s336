// Construye un corpus falso mínimo en un directorio temporal, con la misma
// forma de carpetas que el CDROM real. Los archivos van vacíos (o con el
// contenido que se pase) — walk.js solo inventaría, no parsea.

import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/** @type {Record<string, string[] | Record<string,string[]>>} */
const DEFAULT_LAYOUT = {
  '03 Plan mantenimiento': [
    'EUROLIGHT ADIF PLAN DE MANTENIMIENTO_x.pdf',
    'EUROLIGHT ADIF PLAN DE MANTENIMIENTO_x.XLSX',
  ],
  '04 Instrucciones plan mantenimiento (VMI)': {
    I1: ['VMI.3770.FD5.01.01.pdf', 'VMI.3770.RA1.01.01.pdf', 'Menu VMIs.pdf'],
    IM1: ['VMI.3770.FD5.01.02.pdf'],
    NS: ['VMI.3770.FC1.01.02.pdf', 'NS.pdf'],
  },
  '05 Manuales mantenimiento': {
    'BB21106005034 FD5 Reductor y acoplamiento': ['BB21106005034 FD5 Reductor y acoplamiento.pdf'],
    'BB21106015000 RA1 Equipo de freno': ['manual freno.pdf', 'anexo.tif'],
  },
  '06 Catalogo piezas': ['Listas de materiales.xlsx', 'CatalogoLOC ADIF.pdf', 'notas.rar'],
  '07 Esquemas': ['esquema-general.PDF'],
};

/**
 * @param {object} [opts]
 * @param {Record<string, any>} [opts.layout]
 * @returns {Promise<{root: string, cleanup: () => Promise<void>}>}
 */
export async function makeFakeCorpus(opts = {}) {
  const layout = opts.layout ?? DEFAULT_LAYOUT;
  const base = await fs.mkdtemp(path.join(os.tmpdir(), 'cs336-fixture-'));
  const root = path.join(base, 'CDROM LOC ADIF ED.2');

  /** @param {string} dir @param {string[]|Record<string,any>} spec */
  async function build(dir, spec) {
    await fs.mkdir(dir, { recursive: true });
    if (Array.isArray(spec)) {
      for (const name of spec) await fs.writeFile(path.join(dir, name), '');
    } else {
      for (const [child, childSpec] of Object.entries(spec)) {
        await build(path.join(dir, child), childSpec);
      }
    }
  }

  for (const [top, spec] of Object.entries(layout)) {
    await build(path.join(root, top), spec);
  }

  return {
    root,
    cleanup: () => fs.rm(base, { recursive: true, force: true }),
  };
}
