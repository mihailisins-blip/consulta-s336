import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { parseVmi } from '../src/corpus/vmi-parser.js';

const dir = path.dirname(fileURLToPath(import.meta.url));
const fixture = (code, ext) =>
  JSON.parse(readFileSync(path.join(dir, 'fixtures', 'vmi', `${code}.${ext}.json`), 'utf8'));
const load = (code) => fixture(code, 'lines');

// Las transcripciones traen la tipografía de cada línea (tamaño y negrita); las
// cajas son la posición de las imágenes grandes del PDF, para las figuras.
const parse = (code) => parseVmi(load(code), { codigo: code, cajas: fixture(code, 'cajas') });

const items = (r) => r.procedimiento.items;
const pasos = (r) => items(r).filter((it) => it.tipo === 'paso');
/** "tipo:n|etiqueta" de cada elemento, para comparar la forma de un procedimiento. */
const forma = (r) => items(r).map((it) => `${it.tipo}${it.n != null ? `:${it.n}` : ''}${it.etiqueta ? `:${it.etiqueta}` : ''}`);

test('cabecera: componente, tipo de actividad, operación, edición, fecha, páginas', () => {
  const r = parse('VMI.3770.FD5.01.01');
  assert.equal(r.componente, 'REDUCTOR');
  assert.equal(r.actividadTipo, 'INSPECCIÓN VISUAL');
  assert.match(r.operacion, /Inspección visual del reductor/);
  assert.match(r.operacion, /Agregar aceite si procede/); // continuación de línea
  assert.equal(r.edicion, '0');
  assert.equal(r.fecha, '30.06.2022');
  assert.equal(r.paginas, 10);
  assert.equal(r.codigoEnDoc, 'VMI.3770.FD5.01.01');
});

test('ediciones no numéricas: "--" y "A0"', () => {
  assert.equal(parse('VMI.3770.FD5.02.04').edicion, '--');
  assert.equal(parse('VMI.3770.MC1.01.01').edicion, 'A0');
});

test('inspección con "No aplica": herramientas/consumibles/repuestos vacíos, sin sinExtraer', () => {
  const r = parse('VMI.3770.FD5.01.01');
  assert.equal(r.sinExtraer, false);
  assert.equal(r.herramientas.aplica, false);
  assert.equal(r.consumibles.aplica, false);
  assert.equal(r.repuestos.aplica, false);
});

test('FD5.02.04: consumibles con tabla — primera fila Grasa Klüberlub 200 g S', () => {
  const r = parse('VMI.3770.FD5.02.04');
  assert.equal(r.sinExtraer, false);
  assert.equal(r.consumibles.aplica, true);
  assert.ok(r.consumibles.filas.length >= 5, `esperaba >=5 filas, hay ${r.consumibles.filas.length}`);
  const grasa = r.consumibles.filas[0];
  const vals = Object.values(grasa).join(' | ');
  assert.match(vals, /Grasa/);
  assert.match(vals, /Kl[uü]berlub BE 41-1501/);
  assert.match(vals, /KLUBER/);
  assert.match(vals, /200 g/);
  // la columna USO tiene S
  assert.ok(Object.values(grasa).some((v) => v === 'S' || /\bS\b/.test(v)));
});

test('FD5.02.04: herramientas especiales con tabla (Engrasador manual / G1/8A)', () => {
  const r = parse('VMI.3770.FD5.02.04');
  assert.equal(r.herramientas.aplica, true);
  const txt = r.herramientas.raw;
  assert.match(txt, /Engrasador manual/);
  assert.match(txt, /Engrasador G1\/8A/);
});

test('FD5.02.04: título de la operación, subtítulos Desmontaje/Montaje y varios pasos', () => {
  const r = parse('VMI.3770.FD5.02.04');
  const it = items(r);
  assert.equal(it.find((x) => x.tipo === 'titulo').texto, 'Cambio de grasa en el semiacoplamiento del lado del reductor');
  const subtitulos = it.filter((x) => x.tipo === 'subtitulo').map((x) => x.texto);
  assert.deepEqual(subtitulos, ['Desmontaje', 'Montaje']);
  assert.ok(pasos(r).length >= 40, `esperaba >=40 pasos en total, hay ${pasos(r).length}`);
  const desmontaje = it.findIndex((x) => x.texto === 'Desmontaje');
  assert.equal(it[desmontaje + 1].tipo, 'paso');
  assert.match(it[desmontaje + 1].texto, /Colocar un depósito/);
  // la numeración se reinicia en el Montaje: es otra lista, tras su subtítulo
  const montaje = it.findIndex((x) => x.texto === 'Montaje');
  assert.equal(it[montaje + 1].n, 1);
});

test('FD5.02.04: los subpasos "a." quedan como elementos propios, tras su paso', () => {
  const f = forma(parse('VMI.3770.FD5.02.04'));
  const i = f.indexOf('paso:4');
  assert.deepEqual(f.slice(i, i + 3), ['paso:4', 'subpaso:a', 'paso:5']);
});

test('FD5.01.01: procedimiento con pasos numerados y subpasos', () => {
  const r = parse('VMI.3770.FD5.01.01');
  assert.equal(pasos(r).length, 8);
  // el paso 7 tiene un subpaso a.
  const f = forma(r);
  assert.deepEqual(f.slice(f.indexOf('paso:7'), f.indexOf('paso:7') + 3), ['paso:7', 'subpaso:a', 'paso:8']);
});

test('sin tipografía en las líneas (transcripción antigua), los títulos de fase se reconocen por su palabra clave', () => {
  const lines = load('VMI.3770.FD5.02.04').map(({ size, negrita, ...resto }) => resto);
  const r = parseVmi(lines, { codigo: 'VMI.3770.FD5.02.04' });
  const titulos = items(r).filter((x) => x.tipo === 'titulo').map((x) => x.texto);
  assert.ok(titulos.some((t) => /Desmontaje/.test(t)), `títulos: ${JSON.stringify(titulos)}`);
  assert.ok(titulos.some((t) => /Montaje/.test(t)));
  assert.ok(pasos(r).length >= 40);
});

// --- formato del procedimiento: casos reales reportados ---

test('DA1.01.01: los párrafos, listas numeradas y viñetas son elementos separados, no texto pegado al paso 4', () => {
  const r = parse('VMI.3770.DA1.01.01');
  const f = forma(r);
  assert.deepEqual(f.slice(0, 9), [
    'titulo', 'aviso:NOTA', 'parrafo', 'parrafo', 'subtitulo',
    'paso:1', 'paso:2', 'paso:3', 'paso:4',
  ]);
  // el paso 4 es solo su texto: lo que viene detrás (consejos con viñetas) no se le pega
  assert.equal(pasos(r)[3].texto, 'Suelo de la cabina.');
  const it = items(r);
  assert.equal(it[4].texto, 'TRABAJOS DE LIMPIEZA:');
  assert.equal(it[9].tipo, 'subtitulo');
  assert.match(it[9].texto, /^CONSEJOS PARA LA LIMPIEZA DE LOS CRISTALES/);
  // cada viñeta es suya (una de ellas ocupa varias líneas del PDF y sigue siendo una)
  const vinetas = it.filter((x) => x.tipo === 'vineta');
  assert.equal(vinetas.length, 9);
  assert.match(vinetas[0].texto, /^Para la limpieza se utilizará un paño suave y limpio\. .* seco del plástico\.$/);
  assert.ok(vinetas.every((v) => !v.texto.includes('●')), 'la viñeta es el marcador, no parte del texto');
  // el aviso de precaución (rótulo a un lado, cuerpo en negrita) con su texto
  const precaucion = it.find((x) => x.tipo === 'aviso' && x.etiqueta === 'PRECAUCIÓN');
  assert.equal(precaucion.texto, 'No retirar la película protectora hasta que sea necesario.');
});

test('DA1.01.01: el aviso NOTA es solo su línea en negrita; los párrafos que siguen no son del aviso', () => {
  const [, nota, p1, p2] = items(parse('VMI.3770.DA1.01.01'));
  assert.equal(nota.texto, 'La limpieza interior se realizará con la locomotora parada y frenada.');
  assert.match(p1.texto, /^Conectar el interruptor de la batería .* de iluminación\.$/);
  assert.match(p2.texto, /^Conectar la iluminación de los pasillos/);
});

test('DF3.01.01: dos listas 1-2-3 van separadas por su subtítulo y por el aviso, no seguidas', () => {
  const r = parse('VMI.3770.DF3.01.01');
  assert.deepEqual(forma(r), [
    'aviso:INFORMACIÓN', 'titulo', 'subtitulo',
    'paso:1', 'paso:2', 'paso:3', 'aviso:PRECAUCIÓN',
    'subtitulo', 'paso:1', 'paso:2', 'paso:3',
  ]);
  const it = items(r);
  assert.deepEqual(it.filter((x) => x.tipo === 'subtitulo').map((x) => x.texto), ['Extintor', 'Mascara de gas']);
  // ni la precaución ni el subtítulo siguiente se pegan al tercer paso
  assert.equal(it[5].texto, 'Comprobar visualmente la caducidad del extintor (01). En caso necesario sustituir.');
  assert.match(it[6].texto, /^Ante cualquier incidencia, SUSTITUIR INMEDIATAMENTE/);
});

test('DF3.01.01: un aviso con subtítulo en negrita lo separa del párrafo (primer párrafo = subtítulo del aviso)', () => {
  const [aviso] = items(parse('VMI.3770.DF3.01.01'));
  const [subtitulo, cuerpo, ...resto] = aviso.texto.split('\n');
  assert.equal(subtitulo, 'Pares de apriete');
  assert.match(cuerpo, /^Los pares de apriete están indicados .* durante la instalación o el montaje\.$/);
  assert.deepEqual(resto, []);
});

test('GC3.01.01: el pie de la figura no se repite como título de fase, y los pasos 4 y 5 no arrastran la sección siguiente', () => {
  const r = parse('VMI.3770.GC3.01.01');
  const it = items(r);
  const f = forma(r);
  // ni "Puertas del armario BT" ni "Panel de relés armario BT" salen como texto: son los pies de las figuras
  assert.ok(!it.some((x) => /Puertas del armario BT|Panel de relés armario BT/.test(x.texto)));
  assert.deepEqual(r.figuras.filter((x) => x.seccion === 'procedimiento').map((x) => x.titulo), [
    'Puertas del armario BT', 'Panel de relés armario BT', 'Interfaz de visualización y botones de BCU',
  ]);
  // los 5 primeros pasos, y a continuación el título (en 3 líneas) de la sección siguiente
  assert.deepEqual(f.slice(0, 6), ['paso:1', 'paso:2', 'paso:3', 'paso:4', 'paso:5', 'titulo']);
  assert.equal(it[4].texto, 'Abrir el panel de interruptores (01).');
  assert.match(it[5].texto, /^Comprobar en el display del BCU si hay mensajes de fallo almacenados .* \(B91\)$/);
  // la explicación bajo ese título son párrafos, y la lista 1-5 que sigue es una lista nueva
  assert.deepEqual(f.slice(6, 9), ['parrafo', 'parrafo', 'parrafo']);
  assert.deepEqual(f.slice(9, 14), ['paso:1', 'paso:2', 'paso:3', 'paso:4', 'paso:5']);
});

test('GC3.01.01: cada figura queda justo antes del elemento que le sigue en el PDF', () => {
  const r = parse('VMI.3770.GC3.01.01');
  const antes = r.figuras.filter((x) => x.seccion === 'procedimiento').map((x) => x.antesDePaso);
  // sobre el paso 1; entre el paso 3 y el 4; tras el último elemento
  assert.deepEqual(antes, [0, 3, items(r).length]);
});

test('el pie y la leyenda de componentes de una figura no se cuentan como texto del procedimiento', () => {
  const r = parse('VMI.3770.DF3.01.01');
  assert.ok(!items(r).some((x) => /Extintor y marcara de gas|Soporte extintor/.test(x.texto)));
  const [fig] = r.figuras.filter((x) => x.seccion === 'procedimiento');
  assert.equal(fig.titulo, 'Extintor y marcara de gas');
  assert.equal(fig.leyenda.length, 6);
});

test('FD5.02.04: leyenda con referencias de pieza de 3 cifras (despiece, no correlativas) y su subtítulo', () => {
  const r = parse('VMI.3770.FD5.02.04');
  const [fig] = r.figuras.filter((x) => x.seccion === 'procedimiento');
  assert.deepEqual(fig.leyenda.map((l) => l.n), ['002', '004', '021', '022', '025', '027', '029']);
  assert.equal(fig.leyenda[0].nombre, 'Cuerpo de acoplamiento');
  // "Desmontaje" queda como subtítulo (antes se perdía por parecer cabecera de un bloque de piezas)
  assert.ok(items(r).some((x) => x.tipo === 'subtitulo' && x.texto === 'Desmontaje'));
});

test('los avisos con texto normal (sin negrita) y las listas con "ü" de Wingdings se reconocen', () => {
  const r = parse('VMI.3770.RA1.01.01');
  const it = items(r);
  const modos = it.filter((x) => /^MODO [RPG]:/.test(x.texto));
  assert.ok(modos.length >= 3);
  assert.ok(modos.every((x) => x.tipo === 'vineta'));
  assert.ok(it.some((x) => x.tipo === 'subtitulo' && x.texto === 'Test del compresor:'));
});

test('zonas de trabajo se capturan como texto', () => {
  assert.match(parse('VMI.3770.FD5.02.04').zonasTrabajo, /Localización del acoplamiento/);
  assert.match(parse('VMI.3770.RA1.01.01').zonasTrabajo, /Esquema del vehículo/);
});

test('medidas de seguridad (sección 1) se capturan como un bloque de texto único', () => {
  const seguridad = parse('VMI.3770.FD5.02.04').seguridad;
  assert.match(seguridad, /Riesgos generales asociados/);
  assert.match(seguridad, /Equipos de protección personal/);
  assert.match(seguridad, /Peligro de lesiones y daño a equipos/);
  // no debe colarse la sección 2 (empieza justo después)
  assert.doesNotMatch(seguridad, /Herramientas \/ Consumibles \/ Repuestos/);
});

test('AE1: un PDF sin la cabecera de sección 2 -> sinExtraer con motivo', () => {
  const lines = load('VMI.3770.FD5.01.01').filter(
    (l) => !/^2\s+Herramientas \/ Consumibles \/ Repuestos$/.test(l.text),
  );
  const r = parseVmi(lines, { codigo: 'VMI.3770.FD5.01.01' });
  assert.equal(r.sinExtraer, true);
  assert.match(r.motivo, /sección "2/);
  // aún así conserva el código
  assert.equal(r.codigo, 'VMI.3770.FD5.01.01');
});

test('AE1 bis: cabecera irreconocible -> sinExtraer', () => {
  const lines = load('VMI.3770.FD5.01.01').filter(
    (l) => !/^(Vehículo|Componente|Actividad|Herramientas especiales|Consumibles|Repuestos|Frecuencia|Operación):/.test(l.text),
  );
  const r = parseVmi(lines, { codigo: 'x' });
  assert.equal(r.sinExtraer, true);
  assert.match(r.motivo, /cabecera no reconocida/);
});

test('ningún campo extraído contiene el pie "Página N / M" ni "Fecha: dd.mm.aaaa"', () => {
  for (const code of ['VMI.3770.FD5.01.01', 'VMI.3770.FD5.02.04', 'VMI.3770.RA1.01.01', 'VMI.3770.MC1.01.01']) {
    const r = parse(code);
    const blob = JSON.stringify({
      op: r.operacion, frec: r.frecuencia, comp: r.componente,
      zonas: r.zonasTrabajo, seg: r.seguridad, proc: r.procedimiento, herr: r.herramientas, cons: r.consumibles,
    });
    assert.doesNotMatch(blob, /Página\s+\d+\s*\/\s*\d+/, `${code}: se coló un pie de página`);
    assert.doesNotMatch(blob, /Fecha:\s*\d{2}\.\d{2}\.\d{4}/, `${code}: se coló la fecha de pie`);
  }
});
