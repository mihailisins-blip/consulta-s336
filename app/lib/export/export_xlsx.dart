// Exportaciones a .xlsx (U13 / R27 / KTD6): como máximo dos vistas --
// materiales de un ciclo con su código ERP, y herramientas/materiales de
// una actividad -- sin reimportación de estado (R27).
//
// No se usa el paquete `excel`: fija `archive` en la rama 3.x, y `pdfrx`
// (U11) fuerza la rama 4.x -- son incompatibles entre sí, ninguna versión
// de `excel` lo resuelve (comprobado con `flutter pub get`). En vez de un
// dependency_override sin verificar o traer una librería comercial
// (Syncfusion XlsIO) solo para dos hojas planas, esta función escribe el
// OOXML mínimo a mano con el ZipEncoder de `archive` (ya en el árbol de
// dependencias vía pdfrx_engine, declarado explícito en pubspec.yaml).
//
// La parte que construye los bytes (`buildXlsxBytes` y las dos funciones
// de dominio) es Dart puro, testeable sin Flutter; solo `exportarYGuardar`
// (el diálogo "Guardar como" del sistema, vía `file_selector`) depende de
// un BuildContext.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/queries.dart';

const _mimeTypeXlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Genera un `.xlsx` de una sola hoja: fila de cabecera en negrita,
/// autofiltro y fila de cabecera fija (freeze pane) -- KTD6. `rows` acepta
/// `String` (se escribe como texto -- así un `PIEZA` con ceros a la
/// izquierda como `05123` no se reinterpreta como número), `num` (se
/// escribe como celda numérica -- así una cantidad con decimales se
/// escribe como número, no como texto) o `null` (celda vacía).
List<int> buildXlsxBytes({
  required String sheetName,
  required List<String> headers,
  required List<List<Object?>> rows,
}) {
  final archive = Archive();
  void addFile(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addFile('[Content_Types].xml', _contentTypesXml);
  addFile('_rels/.rels', _rootRelsXml);
  addFile('xl/workbook.xml', _workbookXml(sheetName));
  addFile('xl/_rels/workbook.xml.rels', _workbookRelsXml);
  addFile('xl/styles.xml', _stylesXml);
  addFile('xl/worksheets/sheet1.xml', _sheetXml(headers, rows));

  return ZipEncoder().encode(archive);
}

/// Export A (R27): materiales del acumulado de un nivel de ciclo.
List<int> xlsxBytesDeNivel(String nivelCodigo, List<MaterialDeNivelExport> materiales) {
  return buildXlsxBytes(
    sheetName: 'Materiales $nivelCodigo',
    headers: const [
      'PIEZA',
      'Descripción',
      'Cantidad total',
      'Unidad',
      'Reserva',
      'Nº actividades',
    ],
    rows: [
      for (final m in materiales)
        [
          m.pieza,
          m.descripcion,
          m.cantidadTotal,
          m.unidad,
          m.reserva ? 'Sí' : 'No',
          m.numActividades,
        ],
    ],
  );
}

/// Export B (R27): herramientas y materiales de una actividad.
List<int> xlsxBytesDeActividad(
  String codigoActividad,
  List<ActividadMaterialExport> materiales,
) {
  return buildXlsxBytes(
    sheetName: codigoActividad,
    headers: const [
      'Descripción',
      'Referencia',
      'Fabricante',
      'Código ERP',
      'Cantidad',
      'Unidad',
      'Uso',
    ],
    rows: [
      for (final m in materiales)
        [
          m.descripcion,
          m.referencia,
          m.fabricante,
          m.codigoErp,
          m.cantidadNum ?? m.cantidadTexto,
          m.unidad,
          m.uso,
        ],
    ],
  );
}

/// Pide al usuario dónde guardar (diálogo nativo del sistema, R27) y
/// escribe los bytes ahí. No hace nada si el usuario cancela; confirma con
/// un SnackBar si guarda.
Future<void> exportarYGuardar(
  BuildContext context, {
  required String nombreSugerido,
  required List<int> bytes,
}) async {
  final location = await getSaveLocation(
    suggestedName: nombreSugerido,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Excel', extensions: ['xlsx']),
    ],
  );
  if (location == null) return; // cancelado por el usuario
  final file = XFile.fromData(
    Uint8List.fromList(bytes),
    mimeType: _mimeTypeXlsx,
    name: nombreSugerido,
  );
  await file.saveTo(location.path);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Exportado a ${location.path}')),
  );
}

const _contentTypesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';

const _rootRelsXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

const _workbookRelsXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

// Estilos mínimos: xf 0 = normal, xf 1 = cabecera en negrita (s="1" en las
// celdas de _sheetXml). `fills` incluye el índice 1 (gray125) aunque no se
// use -- es el índice reservado por convención de la spec; omitirlo hace
// que algunos lectores muestren un aviso de reparación.
const _stylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><sz val="11"/><name val="Calibri"/><b/></font>'
    '</fonts>'
    '<fills count="2">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '</fills>'
    '<borders count="1">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>'
    '</cellStyleXfs>'
    '<cellXfs count="2">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    '</styleSheet>';

String _workbookXml(String sheetName) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="${_escXml(_nombreDeHoja(sheetName))}" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>';

/// El nombre de hoja de Excel no admite `: \ / ? * [ ]` ni pasar de 31
/// caracteres -- un código de actividad o nivel real nunca los trae, pero
/// se sanea igual para no producir un .xlsx inválido con datos inesperados.
String _nombreDeHoja(String name) {
  final saneado = name.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ');
  return saneado.length > 31 ? saneado.substring(0, 31) : saneado;
}

String _sheetXml(List<String> headers, List<List<Object?>> rows) {
  final lastCol = _colLetter(headers.isEmpty ? 0 : headers.length - 1);
  final lastRow = rows.length + 1;
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<dimension ref="A1:$lastCol$lastRow"/>')
    ..write('<sheetViews><sheetView workbookViewId="0">')
    ..write('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>')
    ..write('</sheetView></sheetViews>')
    ..write('<sheetData>');

  sb.write('<row r="1">');
  for (var i = 0; i < headers.length; i++) {
    sb.write(
      '<c r="${_colLetter(i)}1" t="inlineStr" s="1"><is><t>${_escXml(headers[i])}</t></is></c>',
    );
  }
  sb.write('</row>');

  for (var ri = 0; ri < rows.length; ri++) {
    final rowNum = ri + 2;
    sb.write('<row r="$rowNum">');
    final row = rows[ri];
    for (var ci = 0; ci < row.length; ci++) {
      final value = row[ci];
      if (value == null) continue;
      final ref = '${_colLetter(ci)}$rowNum';
      if (value is num) {
        sb.write('<c r="$ref"><v>${_numToXml(value)}</v></c>');
      } else {
        sb.write('<c r="$ref" t="inlineStr"><is><t>${_escXml(value.toString())}</t></is></c>');
      }
    }
    sb.write('</row>');
  }

  sb
    ..write('</sheetData>')
    ..write('<autoFilter ref="A1:${lastCol}1"/>')
    ..write('</worksheet>');
  return sb.toString();
}

String _numToXml(num n) => n.toString();

/// Convierte un índice de columna 0-based a letra(s) de Excel (0->A,
/// 25->Z, 26->AA...) -- conversión base-26 biyectiva estándar.
String _colLetter(int index) {
  var i = index;
  var s = '';
  while (true) {
    s = String.fromCharCode(65 + (i % 26)) + s;
    i = i ~/ 26 - 1;
    if (i < 0) break;
  }
  return s;
}

/// XML 1.0 prohíbe estos bytes de control en cualquier posición del texto
/// -- ni siquiera son legales como referencia de carácter numérica
/// (`&#x01;` tampoco vale). TAB/LF/CR (0x09/0x0A/0x0D) sí son legales y no
/// se tocan. Si el texto extraído de un PDF trae alguno de los ilegales
/// (artefacto conocido de la extracción de texto de PDF), hay que
/// quitarlo antes de escapar el resto -- si no, el .xlsx queda con XML
/// inválido que Excel repara o rechaza, aunque escribir el archivo en sí
/// no falle y la app reporte éxito igualmente.
final _illegalXmlChars = RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]');

String _escXml(String s) => s
    .replaceAll(_illegalXmlChars, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll("'", '&apos;')
    .replaceAll('"', '&quot;');
