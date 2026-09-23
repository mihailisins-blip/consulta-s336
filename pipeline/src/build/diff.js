// Re-extracción no destructiva (R21 / KTD7 / AE4 del plan).
//
// Al construir una carpeta de datos nueva teniendo una anterior (--prev):
//   1. copia intactas las ediciones del curador (tabla `overrides`) y el estado
//      de revisión + cuerpo de las fichas de sistema;
//   2. compara los campos EXTRAÍDOS de ambas y registra cada diferencia en
//      `cambio_pendiente` para que el curador la revise;
//   3. si el destino de un override ya no existe en la carpeta nueva (p. ej.
//      una entrada de catálogo `vmi:` cuyo id cambió al editarse su
//      descripción de origen, o una actividad/sistema que desapareció), el
//      override se copia igualmente -- nunca se pierde -- pero se registra
//      una incidencia para que el curador lo revise en vez de desaparecer en
//      silencio.
// Nunca escribe en `overrides`. Si algo falla a mitad de la copia, se hace
// ROLLBACK de toda la transacción -- la carpeta nueva no se queda con la
// copia a medias.

import { promises as fs } from 'node:fs';
import { openDb } from './sqlite.js';

// Campos extraídos que se comparan por entidad. Clave = columnas que identifican la fila.
const COMPARABLES = {
  actividad: {
    key: ['codigo'],
    campos: ['operacion', 'frecuencia', 'edicion', 'componente', 'actividad_tipo',
      'descripcion_plan', 'observaciones_plan', 'zonas_trabajo', 'seguridad', 'marca_seguridad', 'sin_extraer'],
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

// Columna clave única por entidad, para comprobar si el destino de un override
// sigue existiendo tras la re-extracción. `actividad_material` tiene clave
// compuesta y ningún código de Fase A define todavía el formato de
// `overrides.id` para ella (esos overrides los escribirá la app de curación
// de Fase C, aún no construida), así que se deja fuera aquí a propósito --
// existeDestino() no bloquea ni marca su copia.
const KEY_COL_UNICA = { actividad: 'codigo', sistema: 'codigo', catalogo: 'id' };

function rowKey(row, keyCols) {
  return keyCols.map((c) => String(row[c] ?? '')).join('|');
}

/** ¿Sigue existiendo en `db` la fila que este override edita? */
function existeDestino(db, entidad, id) {
  const col = KEY_COL_UNICA[entidad];
  const tabla = TABLA[entidad];
  if (!col || !tabla) return true; // clave compuesta o entidad desconocida: no comprobable aquí
  return !!db.prepare(`SELECT 1 FROM ${tabla} WHERE ${col} = ?`).get(id);
}

/**
 * @param {string} newDbPath  carpeta de datos recién escrita (rw)
 * @param {string} prevDbPath  carpeta de datos anterior (ro)
 * @returns {Promise<{overridesCopiados:number, overridesHuerfanos:number, fichasCopiadas:number, cambios:number, cambiosPorEntidad:Record<string,number>}>}
 */
export async function carryOverridesAndDiff(newDbPath, prevDbPath) {
  try {
    await fs.access(prevDbPath);
  } catch {
    return { overridesCopiados: 0, overridesHuerfanos: 0, fichasCopiadas: 0, cambios: 0, cambiosPorEntidad: {} };
  }

  const prev = await openDb(prevDbPath, { readOnly: true });
  const next = await openDb(newDbPath);
  try {
    next.exec('BEGIN');

    // 1a. copiar overrides -- y detectar los que se quedan sin destino
    let overridesCopiados = 0;
    let overridesHuerfanos = 0;
    const insOv = next.prepare(
      'INSERT OR REPLACE INTO overrides (entidad,id,campo,valor,actualizado) VALUES (?,?,?,?,?)',
    );
    const insInc = next.prepare('INSERT INTO incidencia_extraccion VALUES (?,?,?)');
    for (const o of prev.prepare('SELECT * FROM overrides').all()) {
      insOv.run(o.entidad, o.id, o.campo, o.valor, o.actualizado);
      overridesCopiados++;
      if (!existeDestino(next, o.entidad, o.id)) {
        overridesHuerfanos++;
        insInc.run(
          'override-sin-destino',
          `${o.entidad}:${o.id}`,
          `El override de '${o.campo}' ('${o.valor}') se ha copiado, pero '${o.id}' ya no existe en ` +
          `'${o.entidad}' tras la re-extracción -- revisar si el origen se renombró o se eliminó.`,
        );
      }
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
    return { overridesCopiados, overridesHuerfanos, fichasCopiadas, cambios, cambiosPorEntidad };
  } catch (err) {
    try { next.exec('ROLLBACK'); } catch { /* no había transacción abierta, o la conexión ya es inválida */ }
    throw err;
  } finally {
    next.close();
    prev.close();
  }
}
