// Elección entre varios ejemplares del mismo VMI (mismo código normalizado).
//
// El corpus puede traer el mismo VMI más de una vez: en varias subcarpetas de
// ciclo, y también en revisiones distintas -- `VMI.3770.HE6.01.01.pdf`
// (Edición 0) junto a `VMI.3770.HE6.01.01_A0.pdf` (Edición A0). Gana la
// edición más alta, no el primero que aparece en el recorrido:
//
//   1. un ejemplar extraído siempre gana a uno sin extraer;
//   2. la edición de la portada: sin edición / "--" < numérica (0, 1…) <
//      letra+número (A0 < A1 < B0);
//   3. desempate: el sufijo de revisión del nombre de archivo (sin sufijo <
//      _A0 < _A1 < _B0);
//   4. desempate: la fecha de la portada (DD.MM.AAAA) más reciente.
//
// Con todo igual se queda el que ya estaba (el primero del recorrido).

/**
 * Rango comparable de una edición de portada.
 * @param {string|null|undefined} edicion
 * @returns {number[]}
 */
export function rangoEdicion(edicion) {
  const s = String(edicion ?? '').trim().toUpperCase();
  let m = s.match(/^([A-Z])\s*\.?\s*(\d+)$/);
  if (m) return [2, m[1].charCodeAt(0), Number(m[2])];
  m = s.match(/^(\d+)$/);
  if (m) return [1, 0, Number(m[1])];
  return [0, 0, 0];
}

/**
 * Rango del sufijo de revisión del nombre de archivo (`_A0`, `_B1`…).
 * @param {string|null|undefined} relPath
 * @returns {number[]}
 */
export function rangoSufijo(relPath) {
  const base = String(relPath ?? '').split('/').pop().replace(/\.pdf$/i, '');
  const m = base.match(/_([A-Z])(\d+)$/i);
  return m ? [1, m[1].toUpperCase().charCodeAt(0), Number(m[2])] : [0, 0, 0];
}

/**
 * Fecha de portada DD.MM.AAAA como número AAAAMMDD (0 si no se reconoce).
 * @param {string|null|undefined} fecha
 */
export function rangoFecha(fecha) {
  const m = String(fecha ?? '').match(/(\d{1,2})[./-](\d{1,2})[./-](\d{4})/);
  return m ? Number(m[3]) * 10000 + Number(m[2]) * 100 + Number(m[1]) : 0;
}

/** @param {number[]} a @param {number[]} b */
function cmp(a, b) {
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}

/**
 * Compara dos ejemplares del mismo VMI. Positivo si `a` es mejor que `b`.
 * @param {{sinExtraer?:boolean, edicion?:string|null, fecha?:string|null, relPath?:string|null}} a
 * @param {{sinExtraer?:boolean, edicion?:string|null, fecha?:string|null, relPath?:string|null}} b
 */
export function compararVmi(a, b) {
  if (!!a.sinExtraer !== !!b.sinExtraer) return a.sinExtraer ? -1 : 1;
  return cmp(rangoEdicion(a.edicion), rangoEdicion(b.edicion))
    || cmp(rangoSufijo(a.relPath), rangoSufijo(b.relPath))
    || rangoFecha(a.fecha) - rangoFecha(b.fecha);
}

/**
 * true si `nuevo` debe sustituir a `actual` como ejemplar de referencia.
 * @param {any} nuevo
 * @param {any} actual
 */
export function esMejorVmi(nuevo, actual) {
  return compararVmi(nuevo, actual) > 0;
}
