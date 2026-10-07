import { test } from 'node:test';
import assert from 'node:assert/strict';

import { asociarImagenes, claveDeLinea, parseLeyenda } from '../src/corpus/vmi-figuras.js';

const L = (page, y, x, text) => ({ page, y, x, text, spans: [{ x, text }] });

// Disposición real de VMI.3770.ED3.01.03 (R1): la sección 3 ocupa la página 5
// con dos figuras y un pie bajo cada una; la 4 empieza en la página 6 con una
// figura, su pie, la leyenda de componentes y después los pasos.
const lines = [
  L(2, 751, 56, '1 Medidas de seguridad'),
  L(5, 751, 56, '3 Zonas de trabajo'),
  L(5, 459, 57, 'Esquema del vehículo'),
  L(5, 152, 57, 'Localización de los amortiguadores'),
  L(6, 751, 56, '4 Procedimiento'),
  L(6, 701, 57, 'Sustitución de los amortiguadores de bogie'),
  L(6, 670, 57, 'Amortiguador vertical primario'),
  L(6, 362, 57, 'Amortiguador vertical primario'),
  L(6, 339, 57, '01 Amortiguador vertical primario 02 Elementos de fijación M16'),
  L(6, 308, 57, '1. Quitar los elementos de fijación (02) del amortiguador vertical primario (01).'),
  L(6, 289, 57, '2. Quitar el amortiguador vertical primario (01).'),
  L(7, 380, 57, 'Tabla final'),
  L(7, 340, 57, '3. Colocar el nuevo amortiguador.'),
];
const sections = { 1: 0, 3: 1, 4: 4 };
const endOf = (n) => ({ 1: 1, 3: 4, 4: lines.length }[n]);

const cajas = [
  { page: 2, x: 43, y: 290, w: 496, h: 284 }, // seguridad: se ignora
  { page: 5, x: 57, y: 473, w: 496, h: 258 }, // esquema del vehículo
  { page: 5, x: 57, y: 166, w: 496, h: 284 }, // localización
  { page: 6, x: 43, y: 376, w: 496, h: 284 }, // figura del procedimiento
  { page: 7, x: 43, y: 400, w: 496, h: 300 }, // figura tras el paso 2, sin pie
];

test('zonas de trabajo: cada figura toma el pie que tiene debajo', () => {
  const f = asociarImagenes({ lines, sections, endOf, cajas });
  const zonas = f.filter((x) => x.seccion === 'zonas');
  assert.equal(zonas.length, 2);
  assert.equal(zonas[0].titulo, 'Esquema del vehículo');
  assert.equal(zonas[1].titulo, 'Localización de los amortiguadores');
  assert.equal(zonas[0].leyenda, null);
  assert.equal(zonas[0].antesDePaso, null);
});

test('las imágenes de la sección 1 (seguridad) no se asocian', () => {
  const f = asociarImagenes({ lines, sections, endOf, cajas });
  assert.ok(!f.some((x) => x.page === 2));
});

test('procedimiento: pie y leyenda de componentes, y la posición de lectura de la figura', () => {
  const f = asociarImagenes({ lines, sections, endOf, cajas });
  const proc = f.filter((x) => x.seccion === 'procedimiento');
  assert.equal(proc.length, 2);
  assert.equal(proc[0].titulo, 'Amortiguador vertical primario');
  assert.deepEqual(proc[0].leyenda, [
    { n: '01', nombre: 'Amortiguador vertical primario' },
    { n: '02', nombre: 'Elementos de fijación M16' },
  ]);
  // la figura está sobre el paso 1 y bajo la línea 'Amortiguador vertical primario' (y=670)
  assert.ok(proc[0].clave > claveDeLinea(lines[6]), 'la clave es el borde superior de la figura');
  assert.ok(proc[0].clave < claveDeLinea(lines[9]), 'y precede al paso 1');
  // `antesDePaso` lo fija el parser, que es quien conoce los elementos del texto
  assert.equal(proc[0].antesDePaso, null);
});

test('el pie y la leyenda de cada figura se marcan como consumidos; el texto de los pasos, no', () => {
  const consumidas = new Set();
  asociarImagenes({ lines, sections, endOf, cajas, consumidas });
  assert.ok(consumidas.has(lines[7]), 'pie de la figura del procedimiento');
  assert.ok(consumidas.has(lines[8]), 'leyenda de componentes');
  assert.ok(consumidas.has(lines[11]), 'pie "Tabla final" (sin leyenda)');
  assert.ok(!consumidas.has(lines[9]), 'un paso no es pie ni leyenda');
  assert.ok(!consumidas.has(lines[6]), 'texto que está sobre la figura');
});

test('una figura posterior a dos pasos queda tras ellos, aunque no tenga leyenda', () => {
  const f = asociarImagenes({ lines, sections, endOf, cajas });
  const ultima = f.filter((x) => x.seccion === 'procedimiento')[1];
  assert.equal(ultima.titulo, 'Tabla final');
  assert.ok(ultima.clave < claveDeLinea(lines[11]), 'sobre su pie');
  assert.ok(ultima.clave > claveDeLinea(lines[10]), 'bajo el paso 2');
});

test('orden de lectura estable y contiguo, y `caja` apunta a la imagen original', () => {
  const f = asociarImagenes({ lines, sections, endOf, cajas });
  assert.deepEqual(f.map((x) => x.orden), [0, 1, 2, 3]);
  assert.deepEqual(f.map((x) => x.caja), [1, 2, 3, 4]);
});

test('parseLeyenda: numeración correlativa, sin partir nombres que llevan números', () => {
  assert.deepEqual(parseLeyenda('01 Tornillo 12 mm 02 Arandela'), [
    { n: '01', nombre: 'Tornillo 12 mm' },
    { n: '02', nombre: 'Arandela' },
  ]);
  assert.equal(parseLeyenda('Texto sin numeración'), null);
});

test('parseLeyenda: la numeración puede continuar desde la figura anterior (no empieza en 01)', () => {
  assert.deepEqual(parseLeyenda('08 Elementos de fijación M6 09 Elementos de fijación M6'), [
    { n: '08', nombre: 'Elementos de fijación M6' },
    { n: '09', nombre: 'Elementos de fijación M6' },
  ]);
  // varias líneas unidas, como en HE1.04.09: 04..08
  assert.deepEqual(
    parseLeyenda('04 Elementos de fijación 05 Tornillo de desmontaje 06 Disco protector 07 Eje de motor 08 Tornillo auxiliar')
      .map((x) => x.n),
    ['04', '05', '06', '07', '08'],
  );
  assert.deepEqual(parseLeyenda('3 Arandela 4 Tuerca').map((x) => x.n), ['3', '4']);
});

test('parseLeyenda: marcadores de un dígito, de una letra, y texto que no abre con marcador', () => {
  assert.deepEqual(parseLeyenda('1 Reductora 2 Mirilla de nivel aceite'), [
    { n: '1', nombre: 'Reductora' },
    { n: '2', nombre: 'Mirilla de nivel aceite' },
  ]);
  assert.deepEqual(parseLeyenda('C Mirilla de nivel de aceite'), [
    { n: 'C', nombre: 'Mirilla de nivel de aceite' },
  ]);
  assert.equal(parseLeyenda('Colocar 1 tornillo 2 arandelas'), null, 'una frase no es una leyenda');
});

test('regresión NS/FC1.01.19: una leyenda con letras que llegan a la Z no rompe (el abecedario acaba ahí)', () => {
  assert.deepEqual(parseLeyenda('Y Motor Z Eje'), [
    { n: 'Y', nombre: 'Motor' },
    { n: 'Z', nombre: 'Eje' },
  ]);
  assert.deepEqual(parseLeyenda('Z Único'), [{ n: 'Z', nombre: 'Único' }]);
});

test('caso real FD5.01.01: pie cortado en origen ("re") se descarta, y la leyenda de un dígito se lee', () => {
  const ls = [
    L(6, 751, 44, '4 Procedimiento'),
    L(6, 523, 44, '4. En caso de daños consultar el manual.'),
    L(6, 217, 43, 're'),
    L(6, 194, 47, '1 Reductora 2 Mirilla de nivel aceite'),
    L(6, 163, 44, '5. Poner el reductor fuera de servicio.'),
  ];
  const f = asociarImagenes({
    lines: ls,
    sections: { 4: 0 },
    endOf: () => ls.length,
    cajas: [{ page: 6, x: 43, y: 231, w: 496, h: 284 }],
  });
  assert.equal(f.length, 1);
  assert.equal(f[0].titulo, null);
  assert.deepEqual(f[0].leyenda, [
    { n: '1', nombre: 'Reductora' },
    { n: '2', nombre: 'Mirilla de nivel aceite' },
  ]);
  assert.ok(f[0].clave > claveDeLinea(ls[1]), 'bajo el paso 4');
  assert.ok(f[0].clave < claveDeLinea(ls[4]), 'sobre el paso 5');
});

test('sin imágenes, no hay figuras', () => {
  assert.deepEqual(asociarImagenes({ lines, sections, endOf, cajas: [] }), []);
});
