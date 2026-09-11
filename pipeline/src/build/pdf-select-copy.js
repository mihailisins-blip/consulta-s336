// Selección y copia de PDFs a la carpeta de datos (R24 del plan).
//
// Incluye: los VMI individuales de `04`, los manuales de `05`, los esquemas de
// `07`. Excluye los mega-PDF pre-fusionados por ciclo (`I1.pdf`, `NS.pdf`,
// `Menu VMIs.pdf`…): en `04` solo se copia lo que empieza por `VMI.`.

import { promises as fs } from 'node:fs';
import path from 'node:path';
import { walkDir } from '../corpus/walk.js';

/** ¿este archivo de `04` es un VMI individual (no un compendio)? */
export function esVmiIndividual(name) {
  return /^VMI\.[0-9]/i.test(name);
}

/**
 * @param {object} args
 * @param {Record<string,string>} args.roots  { vmi, manuales, esquemas? } -> ruta absoluta
 * @param {string} args.outDir  carpeta de datos
 * @param {(m:string)=>void} [args.log]
 * @returns {Promise<{copiados:number, excluidos:string[], fallidos:string[], bytes:number, porArea:Record<string,{copiados:number,bytes:number}>}>}
 */
export async function selectAndCopyPdfs({ roots, outDir, log = () => {} }) {
  const pdfsDir = path.join(outDir, 'pdfs');
  await fs.rm(pdfsDir, { recursive: true, force: true });
  await fs.mkdir(pdfsDir, { recursive: true });

  let copiados = 0;
  let bytes = 0;
  const excluidos = [];
  // Un PDF que no se pueda copiar (bloqueado, permiso denegado, ruta
  // demasiado larga…) no debe abortar los cientos que sí se pueden -- se
  // registra aquí y se sigue, igual que un VMI que no se puede parsear se
  // marca sinExtraer en vez de abortar el build (R2/AE1).
  const fallidos = [];
  /** @type {Record<string,{copiados:number,bytes:number}>} */
  const porArea = {};

  const areas = [
    ['vmi', roots.vmi, (f) => f.type === 'pdf' && esVmiIndividual(path.basename(f.name))],
    ['manuales', roots.manuales, (f) => f.type === 'pdf'],
    ['esquemas', roots.esquemas, (f) => f.type === 'pdf'],
  ];

  for (const [area, root, keep] of areas) {
    if (!root) continue;
    porArea[area] = { copiados: 0, bytes: 0 };
    const { files } = await walkDir(root);
    for (const f of files) {
      const dest = path.join(pdfsDir, area, f.relPath);
      if (!keep(f)) {
        if (f.type === 'pdf') excluidos.push(`${area}/${f.relPath}`);
        continue;
      }
      try {
        await fs.mkdir(path.dirname(dest), { recursive: true });
        await fs.copyFile(path.join(root, f.relPath), dest);
        copiados++;
        bytes += f.size;
        porArea[area].copiados++;
        porArea[area].bytes += f.size;
      } catch (e) {
        fallidos.push(`${area}/${f.relPath}: ${e.code || e.message}`);
      }
    }
    log(`  ${area}: ${porArea[area].copiados} PDFs, ${(porArea[area].bytes / 1e6).toFixed(1)} MB`);
  }

  if (fallidos.length) log(`  aviso: ${fallidos.length} PDF(s) no se pudieron copiar (ver 'fallidos')`);

  return { copiados, excluidos, fallidos, bytes, porArea };
}
