// Normalización de códigos de actividad y de ciclo (KTD4 del plan).
//
// Las tres fuentes escriben el mismo código de tres maneras:
//   VMI (nombre de archivo):  VMI.3770.FD5.01.02
//   Excel materiales (TAREA):  3360.01.F.D5.01.02
//   Excel materiales (LISTA):  LM.3360.01.FD5.01.02
//   Plan (columna CÓDIGO):    FD5.01.02  /  BA1.01.01
// La clave de unión es el sufijo `<SIS><nn>.<nn>` una vez quitados el prefijo de
// tipo (VMI./LM.), el token de serie (3770. / 3360.01.) y los puntos internos
// del código de sistema (F.D5 -> FD5).

/**
 * @param {string} raw
 * @returns {string|null}  código normalizado en mayúsculas, o null si no encaja
 */
export function normalizarCodigo(raw) {
  if (raw == null) return null;
  let s = String(raw).trim().toUpperCase();
  if (!s) return null;

  s = s.replace(/^(VMI|LM)\./, '');            // prefijo de tipo
  s = s.replace(/^\d{3,4}(\.\d{2})?\./, '');     // token de serie 3770. / 3360.01.
  s = s.replace(/_[A-Z]\d+$/i, '');             // sufijo de revisión de archivo (_A0, _B0…)

  // colapsa el punto interno del código de sistema: "F.D5.01.02" -> "FD5.01.02"
  s = s.replace(/^([A-Z])\.([A-Z]?\d[A-Z]?)\./, '$1$2.');

  // debe quedar <sistema>.<nn>.<nn>  (sistema = 2-4 alfanum empezando por letra)
  const m = s.match(/^([A-Z]{1,3}\d[A-Z]?)\.(\d{1,3})\.(\d{1,3})$/);
  if (m) return `${m[1]}.${m[2].padStart(2, '0')}.${m[3].padStart(2, '0')}`;
  return null;
}

/**
 * Código de sistema de un código de actividad normalizado.
 * @param {string} codigoNorm  p.ej. "FD5.01.02"
 * @returns {string|null}  "FD5"
 */
export function sistemaDeCodigo(codigoNorm) {
  if (!codigoNorm) return null;
  const m = String(codigoNorm).toUpperCase().match(/^([A-Z]{1,3}\d[A-Z]?)\./);
  return m ? m[1] : null;
}

/**
 * Descompone el valor `PM` del Excel de materiales en nivel de ciclo y lote.
 *   "3360.01.IM1A" -> { nivel: "IM1", lote: "A" }
 *   "3360.01.RDH2" -> { nivel: "RDH2", lote: null }
 *   "3360.01.I1"   -> { nivel: "I1", lote: null }
 * @param {string} pm
 * @returns {{raw:string, nivel:string|null, lote:string|null}}
 */
export function parsePm(pm) {
  const raw = String(pm ?? '').trim();
  const bare = raw.replace(/^\d{3,4}(\.\d{2})?\./, '').toUpperCase();
  const m = bare.match(/^(I[12]|IM[123]|R[12]|RDH[1-7]|NS)([A-Z])?$/);
  if (!m) return { raw, nivel: bare || null, lote: null };
  return { raw, nivel: m[1], lote: m[2] || null };
}
