// Pool de workers para parsear VMI en paralelo (ver vmi-worker.js).

import os from 'node:os';
import { Worker } from 'node:worker_threads';

/** Tamaño por defecto: deja un par de núcleos libres y acota la memoria (cada worker decodifica imágenes de ~7 MB). */
export function tamanoPoolPorDefecto() {
  return Math.min(6, Math.max(1, os.availableParallelism() - 2));
}

/**
 * @param {number} [n]
 * @returns {{run:(job:{file:string,codigo:string,outDir:string})=>Promise<{rec:any,fallos:number}>, close:()=>Promise<void>}}
 */
export function crearPoolVmi(n = tamanoPoolPorDefecto()) {
  const url = new URL('./vmi-worker.js', import.meta.url);
  /** @type {{worker:Worker, ocupado:boolean, actual:null|{resolve:Function,reject:Function}}[]} */
  const slots = Array.from({ length: n }, () => {
    const slot = { worker: new Worker(url), ocupado: false, actual: null };
    slot.worker.on('message', (msg) => {
      const { resolve, reject } = slot.actual;
      slot.actual = null;
      slot.ocupado = false;
      // `copia` viaja también en el error: un PDF que no se pudo parsear sí se copió
      if (msg.error) reject(Object.assign(new Error(msg.error), { copia: msg.copia }));
      else resolve({ rec: msg.rec, fallos: msg.fallos, copia: msg.copia, desdeCache: !!msg.desdeCache });
      siguiente();
    });
    // un fallo del propio worker (no del PDF) lo deja fuera de servicio y hace
    // fallar solo el trabajo que tenía en curso
    slot.worker.on('error', (err) => {
      const actual = slot.actual;
      slot.actual = null;
      slot.muerto = true;
      actual?.reject(err);
      siguiente();
    });
    return slot;
  });
  const cola = [];
  let nextId = 0;

  function siguiente() {
    if (slots.every((s) => s.muerto)) {
      while (cola.length) cola.shift().reject(new Error('todos los workers de VMI han fallado'));
      return;
    }
    const libre = slots.find((s) => !s.ocupado && !s.muerto);
    if (!libre || cola.length === 0) return;
    const { job, resolve, reject } = cola.shift();
    libre.ocupado = true;
    libre.actual = { resolve, reject };
    libre.worker.postMessage({ id: nextId++, ...job });
  }

  return {
    run: (job) => new Promise((resolve, reject) => {
      cola.push({ job, resolve, reject });
      siguiente();
    }),
    close: async () => {
      await Promise.all(slots.map((s) => s.worker.terminate()));
      // Node 24 en Windows: si el proceso termina mientras aún se desmonta un
      // worker que acaba de salir, se cierra con una violación de acceso
      // (0xC0000005); con un worker vacío le pasa a ~50 % de los procesos que
      // terminan al instante. Un margen lo reduce mucho pero no lo elimina
      // (con máquina muy cargada aún ~5 %). En una extracción real no se nota
      // (tras cerrar el pool aún se escribe la base de datos), pero sí al final
      // de un test o de un script corto: un fallo de archivo sin ningún
      // subtest fallido en vmi-pool/run-build es esto, no un error de lógica.
      await new Promise((resolve) => setTimeout(resolve, 1000));
    },
  };
}
