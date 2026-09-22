// Acceso compartido a node:sqlite (Node >=22 con --experimental-sqlite).

/**
 * @param {string} path
 * @param {{readOnly?:boolean}} [opts]
 * @returns {Promise<import('node:sqlite').DatabaseSync>}
 */
export async function openDb(path, opts = {}) {
  let DatabaseSync;
  try {
    ({ DatabaseSync } = await import('node:sqlite'));
  } catch (err) {
    throw new Error(
      'No se pudo cargar node:sqlite. Ejecuta el pipeline con Node >=22 y el flag ' +
      '--experimental-sqlite (p. ej. `npm run build` o ' +
      `\`node --experimental-sqlite src/index.js build …\`). Detalle: ${err.message}`,
    );
  }
  return new DatabaseSync(path, opts);
}
