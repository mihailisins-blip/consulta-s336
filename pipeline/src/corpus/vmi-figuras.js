// Asociación de las imágenes de un VMI con su contexto (puro, sin PDF ni E/S).
//
// Entrada: las líneas ya limpias de vmi-parser.js, los índices de sección y las
// "cajas" de imagen (posición y tamaño en puntos de cada imagen grande de la
// página -- ver vmi-images.js). Salida: por cada imagen de la sección 3 (zonas
// de trabajo) o de la 4 (procedimiento), su pie de figura, la leyenda de
// componentes numerados que la acompaña ("01 Amortiguador vertical primario
// 02 Elementos de fijación M16") y, en el procedimiento, el paso al que
// precede -- la figura se dibuja antes de los pasos que ilustra.
//
// Las imágenes de la sección 1 (medidas de seguridad, común a todos los VMI)
// y las de cabecera/pie (logotipo) se ignoran a propósito.

const reStep = /^(\d{1,3})\.\s+(.+)$/;
// Marcadores de leyenda observados en el corpus: "01 ", "1 " (numéricos, con o
// sin cero) y "C " (una letra mayúscula). Los pasos llevan punto ("1. ").
const reLegendStart = /^(?:\d{1,3}|[A-Z])\s+\S/;
/** Rótulos de los recuadros de aviso de la plantilla (en mayúsculas). */
export const CALLOUTS = new Set(['AVISO', 'PELIGRO', 'INFORMACIÓN', 'NOTA', 'ATENCIÓN', 'PRECAUCIÓN']);

/** Orden de lectura: página ascendente, y descendente dentro de la página. */
const key = (page, y) => page * 100000 - y;

/**
 * Pie/leyenda máximos que se buscan bajo una figura (pt): más allá no es suyo.
 */
const MAX_CAPTION_GAP = 60;
const MAX_LEGEND_GAP = 40;

/**
 * Sigue una secuencia de marcadores consecutivos dentro de `t` (que empieza
 * con un espacio): `marca(k)` da el patrón del k-ésimo marcador. El primero
 * tiene que abrir el texto -- si no, no es una leyenda.
 */
function leerSecuencia(t, marca, primeras) {
  const marcas = [];
  let desde = 0;
  for (let k = 0; ; k++) {
    const patron = marca(k, marcas);
    if (patron == null) break; // se acabó el abecedario (A-Z)
    const re = new RegExp(`\\s(${patron})\\s`, 'g');
    re.lastIndex = desde;
    const m = re.exec(t);
    if (!m || (k === 0 && m.index !== 0)) break;
    marcas.push({ n: m[1], ini: m.index, fin: m.index + m[0].length });
    desde = m.index + m[0].length;
  }
  if (marcas.length < primeras) return null;
  const items = marcas.map((m, i) => ({
    n: m.n,
    nombre: t.slice(m.fin, i + 1 < marcas.length ? marcas[i + 1].ini : t.length).trim(),
  }));
  return items.every((it) => it.nombre) ? items : null;
}

/** Leyenda de referencias de pieza "0NN" que crecen sin ser correlativas. */
function leerPiezas(t) {
  const marcas = [];
  let ultima = -1;
  const re = /\s(0\d{2})\s/g;
  for (let m = re.exec(t); m; m = re.exec(t)) {
    if (marcas.length === 0 && m.index !== 0) break;
    const v = Number(m[1]);
    if (v <= ultima) { re.lastIndex = m.index + 1; continue; } // un número dentro del nombre
    ultima = v;
    marcas.push({ n: m[1], ini: m.index, fin: m.index + m[0].length });
    re.lastIndex = m.index + m[0].length - 1; // el espacio final abre el marcador siguiente
  }
  const items = marcas.map((m, i) => ({
    n: m.n,
    nombre: t.slice(m.fin, i + 1 < marcas.length ? marcas[i + 1].ini : t.length).trim(),
  }));
  return items.length && items.every((it) => it.nombre) ? items : null;
}

/**
 * Lee una leyenda de componentes: "01 Nombre 02 Nombre ...", "1 Nombre 2
 * Nombre ...", "08 Nombre 09 Nombre" (la numeración CONTINÚA desde la figura
 * anterior del mismo procedimiento: no tiene por qué empezar en 01) o "C
 * Nombre" (marcador de una letra). La numeración correlativa evita partir un
 * nombre que contenga un número ("Tornillo 12 mm" no corta en "12" salvo que
 * toque el 12.º elemento).
 * @param {string} texto
 * @returns {{n:string, nombre:string}[] | null}
 */
export function parseLeyenda(texto) {
  const t = ` ${texto.replace(/\s+/g, ' ').trim()}`;
  // Referencias de pieza de tres cifras ("002 Cuerpo 004 Anillo ... 021 Junta"):
  // son los números del despiece, no correlativos -- basta que crezcan.
  if (/^\s0\d{2}\s/.test(t)) return leerPiezas(t);
  const ini = t.match(/^\s(\d{1,2})\s/);
  if (ini) {
    const n0 = Number(ini[1]);
    // el cero a la izquierda es opcional: en el origen hay leyendas que mezclan
    // "1 Display ... 02 Botones" (GC3.01.01)
    const patron = (v) => (v < 10 ? `0?${v}` : String(v));
    return leerSecuencia(t, (k) => (n0 + k <= 99 ? patron(n0 + k) : null), 1);
  }
  // letras consecutivas desde la que abra el texto (p. ej. "C Mirilla...")
  const inicial = t.match(/^\s([A-Z])\s/);
  if (!inicial) return null;
  const base = inicial[1].charCodeAt(0);
  return leerSecuencia(t, (k) => (base + k <= 90 ? String.fromCharCode(base + k) : null), 1);
}

/**
 * @typedef {{page:number, x:number, y:number, w:number, h:number}} CajaImagen
 *   y = borde inferior, w/h = tamaño mostrado (puntos del PDF, origen abajo-izquierda)
 * @typedef {{seccion:'zonas'|'procedimiento', orden:number, caja:number, page:number,
 *   clave:number, titulo:string|null, leyenda:{n:string,nombre:string}[]|null,
 *   antesDePaso:number|null}} Figura
 *   `clave`: posición de lectura del borde superior de la figura (la misma
 *   escala que `claveDeLinea`), para saber qué elementos del texto la preceden.
 *   `antesDePaso` lo rellena el parser, que es quien conoce los elementos.
 */

/** Posición de lectura de una línea; comparable con `Figura.clave`. */
export const claveDeLinea = (l) => key(l.page, l.y);

/**
 * @param {object} args
 * @param {{page:number,y:number,x:number,text:string}[]} args.lines  líneas limpias
 * @param {Record<number, number>} args.sections  índice de línea de cada sección
 * @param {(n:number)=>number} args.endOf  índice de línea donde acaba la sección n
 * @param {CajaImagen[]} args.cajas
 * @param {Set<object>} [args.consumidas]  recibe las líneas que son pie o leyenda de
 *   una figura, para que el parser del procedimiento no las repita como texto
 * @returns {Figura[]}
 */
export function asociarImagenes({ lines, sections, endOf, cajas, consumidas = new Set() }) {
  const rango = (n) => {
    if (sections[n] === undefined) return null;
    const ini = sections[n];
    const fin = endOf(n);
    return {
      desde: key(lines[ini].page, lines[ini].y),
      hasta: fin < lines.length ? key(lines[fin].page, lines[fin].y) : Infinity,
      lineas: lines.slice(ini + 1, fin),
    };
  };
  const zonas = rango(3);
  const proc = rango(4);

  const ordenadas = cajas
    .map((c, i) => ({ c, i }))
    .sort((a, b) => (a.c.page - b.c.page) || ((b.c.y + b.c.h) - (a.c.y + a.c.h)));

  /** @type {Figura[]} */
  const figuras = [];
  ordenadas.forEach(({ c, i }, pos) => {
    const k = key(c.page, c.y + c.h);
    const enZonas = zonas && k >= zonas.desde && k < zonas.hasta && k < (proc?.desde ?? Infinity);
    const enProc = proc && k >= proc.desde && k < proc.hasta;
    if (!enZonas && !enProc) return;
    const rangoLineas = enProc ? proc.lineas : zonas.lineas;

    // texto bajo la figura, en la misma página, hasta la siguiente figura
    const siguiente = ordenadas.slice(pos + 1).find((o) => o.c.page === c.page);
    const techo = siguiente ? siguiente.c.y + siguiente.c.h : -Infinity;
    const debajo = rangoLineas
      .filter((l) => l.page === c.page && l.y < c.y && l.y > techo)
      .sort((a, b) => b.y - a.y);

    let titulo = null;
    let leyenda = null;
    let i0 = 0;
    const primera = debajo[0];
    if (primera && c.y - primera.y <= MAX_CAPTION_GAP
        && !reLegendStart.test(primera.text.trim())
        && !reStep.test(primera.text.trim()) && !CALLOUTS.has(primera.text.trim().toUpperCase())) {
      // un pie de 1-2 caracteres ("re", cortado en origen) no es un título,
      // pero sigue siendo la línea del pie: la leyenda empieza después
      const texto = primera.text.trim();
      titulo = texto.length >= 3 ? texto : null;
      i0 = 1;
      consumidas.add(primera);
    }
    const partes = [];
    const lineasLeyenda = [];
    let yPrev = i0 === 1 ? primera.y : c.y;
    for (const l of debajo.slice(i0)) {
      const t = l.text.trim();
      if (reStep.test(t) && l.x < 70) break;
      if (CALLOUTS.has(t.toUpperCase())) break;
      if (yPrev - l.y > MAX_LEGEND_GAP) break;
      if (partes.length === 0 && !reLegendStart.test(t)) break;
      partes.push(t);
      lineasLeyenda.push(l);
      yPrev = l.y;
    }
    if (partes.length) leyenda = parseLeyenda(partes.join(' '));
    // solo si se entendió como leyenda: si no, es texto del procedimiento
    if (leyenda) for (const l of lineasLeyenda) consumidas.add(l);

    figuras.push({
      seccion: enProc ? 'procedimiento' : 'zonas',
      orden: figuras.length,
      caja: i,
      page: c.page,
      clave: k,
      titulo,
      leyenda,
      antesDePaso: null,
    });
  });
  return figuras;
}
