// Construye workbooks sintéticos mínimos con la misma forma que los XLSX reales,
// para los tests de xlsx-plan.js / xlsx-materiales.js / cycles.js.

import xlsx from 'xlsx';

/** @param {string[][]} aoa */
function sheet(aoa) {
  return xlsx.utils.aoa_to_sheet(aoa);
}

/** Workbook con la forma de `06 Listas de materiales.xlsx`. */
export function fakeMaterialesWorkbook(extraRows = []) {
  const rows = [
    ['PM', 'TAREA', 'LISTA', 'PIEZA', 'DESCRIPCION', 'CANT', 'UD', 'RESERVA'],
    ['3360.01.IM1A', '3360.01.F.D5.01.01', 'LM.3360.01.FD5.01.01', '20027', 'ACEITE REDUCTOR MOBIL 75W-90', '2', 'UD', 'No'],
    ['3360.01.IM1A', '3360.01.F.D5.01.02', 'LM.3360.01.FD5.01.02', '20027', 'ACEITE REDUCTOR MOBIL 75W-90', '2', 'UD', 'Sí'],
    ['3360.01.IM1B', '3360.01.T.B1.02.01', 'LM.3360.01.TB1.02.01', '22689', 'FILTRO AIRE ARMARIO', '1', 'UD', 'No'],
    ['3360.01.IM1C', '3360.01.F.C1.04.04', 'LM.3360.01.FC1.04.04', '33443', 'KIT ANALISIS GASOLEOS', '1', 'BT', 'Sí'],
    ['3360.01.IM2D', '3360.01.Q.E3.01.01', 'LM.3360.01.QE3.01.01', '23193', 'GRASA RENOLIT HLT2-KB', '0,50', 'KG', 'No'],
    ['3360.01.RDH2', '3360.01.F.C1.02.04', 'LM.3360.01.FC1.02.04', '22333', 'ACEITE MD ULS 15W/40 (BIDON 208L)', '530', 'L', 'Sí'],
    ['3360.01.RDH3', '3360.01.F.C1.04.10', 'LM.3360.01.FC1.04.10', '23191', 'FILTRO SECUNDARIO COMBUSTIBLE', '2', 'UD', 'Sí'],
    ['3360.01.I1', '3360.01.F.D5.01.01', 'LM.3360.01.FD5.01.01', '20027', 'ACEITE REDUCTOR MOBIL 75W-90', '2', 'UD', 'No'],
    ...extraRows,
  ];
  const wb = xlsx.utils.book_new();
  xlsx.utils.book_append_sheet(wb, sheet(rows), 'Hoja2');
  return wb;
}

/** Workbook con la forma del `03` PLAN DE MANTENIMIENTO. */
export function fakePlanWorkbook() {
  const ciclos = [
    ['CICLOS DE OPERACIONES DE MANTENIMIENTO'],
    ['', '', 'CICLO', 'DESCRIPCIÓN', '', '', 'KM MEDIOS', '', 'TIEMPO MEDIO'],
    ['', '', 'I1', 'Inspección Inicial 1', '', '', '25.000 (+10%)', '', ''],
    ['', '', 'I2', 'Inspección Inicial 2', '', '', '50000', '', ''],
    ['', '', 'IM1', 'Inspección Media Nivel 1', '', '', '100000', '', ''],
    ['', '', 'IM2', 'Inspección Media Nivel 2', '', '', '200000', '', ''],
    ['', '', 'IM3', 'Inspección Media Nivel 3', '', '', '400000', '', ''],
    ['', '', 'R1', 'Revisión General 1', '', '', '1600000', '', '10 Años'],
    ['', '', 'R2', 'Revisión General 2', '', '', '3200000', '', '20 Años'],
    ['', '', 'NS', 'Tareas según condición', '', '', '', '', ''],
  ];
  const pes = [
    ['OPERACIONES DE PUESTA EN SERVICIO'],
    ['CÓDIGO', 'DESCRIPCIÓN', '', '', '', '', 'INTERVALO'],
    ['FC1.04.08', 'Reemplazar filtro de succión.', '', '', '', '', 'Después de 100 horas de funcionamiento'],
    ['FD5.01.01', 'Inspección visual del reductor.', '', '', '', '', 'Después de los primeros 7.000 Km'],
    ['--', 'Añadir CCAC.', '', '', '', '', 'Aplicar únicamente en el sistema…'],
  ];
  // PLAN MANTENIMIENTO: cabecera en la fila 6 (índice 5)
  const plan = [
    ['PLAN DE MANTENIMIENTO'],
    [], [], [],
    [],
    ['CÓDIGO', 'DESCRIPCIÓN DE LAS OPERACIONES', 'MARCA SEG.', 'I1', 'I2', 'IM1', 'IM2', 'IM3', 'R1', 'R2', 'NS', 'OBSERVACIONES'],
    ['B', 'CAJA DEL VEHÍCULO'],
    ['BA1', 'CAJA'],
    ['BA1.01', 'Bastidor y estructura caja'],
    ['BA1.01.01', 'Inspeccionar los componentes accesibles', '!', '', '', 'X', 'X', 'X', 'X', 'X', '', ''],
    ['BA1.01.02', 'Inspeccionar visualmente posibles grietas', '', '', '', '', '', '', 'X', 'X', '', ''],
    ['BA1.04.01', 'Inspeccionar escaleras y pasamanos.', '!', 'X', 'X', 'X', 'X', 'X', 'X', 'X', '', ''],
    ['F', 'SISTEMAS DE TRACCIÓN'],
    ['FD5', 'REDUCTOR Y ACOPLAMIENTO'],
    ['FD5.01', 'Reductor'],
    ['FD5.01.01', 'Inspección visual del reductor.', '', 'X', 'X', 'X', 'X', 'X', 'X', 'X', '', ''],
    ['FD5.01.02', 'Cambiar aceite del reductor.', '', '', '', 'X', 'X', 'X', 'X', 'X', '', ''],
    ['GC2', 'MANDOS DE CONDUCCIÓN'],
    ['GC2.01.03', 'Efectuar revisión general del pupitre', '', '', '', '', '', '', '', '', 'X', 'Cada 12 años.'],
  ];
  const wb = xlsx.utils.book_new();
  xlsx.utils.book_append_sheet(wb, sheet(ciclos), 'CICLOS');
  xlsx.utils.book_append_sheet(wb, sheet(pes), 'PUESTA EN SERVICIO');
  xlsx.utils.book_append_sheet(wb, sheet(plan), 'PLAN MANTENIMIENTO');
  return wb;
}

export { xlsx };
