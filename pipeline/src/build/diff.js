// Re-extracción no destructiva (R21 / KTD7 / AE4 del plan).
//
// Al construir una carpeta de datos nueva teniendo una anterior (--prev):
//   1. copia intactas las ediciones del curador (tabla `overrides`) y el estado
//      de revisión + cuerpo de las fichas de sistema;
//   2. compara los campos EXTRAÍDOS de ambas y registra cada diferencia en
//      `cambio_pendiente` para que el curador la revise.
// Nunca escribe en `overrides`.

import { promises as fs } from 'node:fs';
import { openDb } from './sqlite.js';

// Campos extraídos que se comparan por entidad. Clave = columnas que identifican la fila.
const COMPARABLES = {
  actividad: {
    key: ['codigo'],
    campos: ['operacion', 'frecuencia', 'edicion', 'componente', 'actividad_tipo',
      'descripcion_plan', 'observaciones_plan', 'zonas_trabajo', 'marca_seguridad', 'sin_extraer'],
  },
  sistema: { key: ['codigo'], campos: ['nombre'] },
  catalogo: { key: ['id'], campos: ['descripcion', 'unidad', 'fabricante', 'referencia'] },
  actividad_material: {
    key: ['actividad_codigo', 'catalogo_id'],
    campos: ['cant', 'cant_num', 'ud', 'uso', 'reserva'],
  },
};

const TABLA = {
  actividad: 'actividad',
  sistema: 'sistema',
  catalogo: 'catalogo',
  actividad_material: 'actividad_material',
};

function rowKey(row, keyCols) {
  return keyCols.map((c) => String(row[c] ?? '')).join('|');
}

/**
 * @param {string} newDbPath  carpeta de datos recién escrita (rw)
 * @param {string} prevDbPath  carpeta de datos anterior (ro)
 * @returns {Promise<{overridesCopiados:number, fichasCopiadas:number, cambios:number, cambiosPorEntidad:Record<string,number>}>}
 */
export async function carryOverridesAndDiff(newDbPath, prevDbPath) {
  try {
    await fs.access(prevDbPath);
  } catch {
    return { overridesCopiados: 0, fichasCopiadas: 0, cambios: 0, cambiosPorEntidad: {} };
  }

  const prev = await openDb(prevDbPath, { readOnly: true });
  const next = await openDb(newDbPath);
  next.exec('BEGIN');

  // 1a. copiar overrides
  let overridesCopiados = 0;
  const insOv = next.prepare(
    'INSERT OR REPLACE INTO overrides (entidad,id,campo,valor,actualizado) VALUES (?,?,?,?,?)',
  );
  for (const o of prev.prepare('SELECT * FROM overrides').all()) {
    insOv.run(o.entidad, o.id, o.campo, o.valor, o.actualizado);
    overridesCopiados++;
  }

  // 1b. copiar revisado + cuerpo de fichas (solo para sistemas que siguen existiendo)
  let fichasCopiadas = 0;
  const upFicha = next.prepare('UPDATE ficha_sistema SET cuerpo = ?, revisado = ? WHERE sistema_codigo = ?');
  for (const f of prev.prepare('SELECT * FROM ficha_sistema').all()) {
    const exists = next.prepare('SELECT 1 FROM ficha_sistema WHERE sistema_codigo = ?').get(f.sistema_codigo);
    if (exists) { upFicha.run(f.cuerpo, f.revisado, f.sistema_codigo); fichasCopiadas++; }
  }

  // 2. diff de campos extraídos
  const insCambio = next.prepare(
    'INSERT INTO cambio_pendiente (entidad,id,campo,valor_antes,valor_despues,revisado) VALUES (?,?,?,?,?,0)',
  );
  let cambios = 0;
  /** @type {Record<string,number>} */
  const cambiosPorEntidad = {};

  for (const [entidad, spec] of Object.entries(COMPARABLES)) {
    const tabla = TABLA[entidad];
    const prevRows = new Map(prev.prepare(`SELECT * FROM ${tabla}`).all().map((r) => [rowKey(r, spec.key), r]));
    const nextRows = next.prepare(`SELECT * FROM ${tabla}`).all();
    for (const nr of nextRows) {
      const k = rowKey(nr, spec.key);
      const pr = prevRows.get(k);
      if (!pr) continue; // fila nueva: no es un "cambio de origen" que confunda al curador
      for (const campo of spec.campos) {
        const antes = pr[campo];
        const despues = nr[campo];
        if (String(antes ?? '') !== String(despues ?? '')) {
          insCambio.run(entidad, k.split('|').join(' / '), campo,
            antes == null ? null : String(antes), despues == null ? null : String(despues));
          cambios++;
          cambiosPorEntidad[entidad] = (cambiosPorEntidad[entidad] ?? 0) + 1;
        }
      }
    }
  }

  next.exec('COMMIT');
  next.close();
  prev.close();
  return { overridesCopiados, fichasCopiadas, cambios, cambiosPorEntidad };
}
