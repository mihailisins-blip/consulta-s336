// export_xlsx.dart (U13/R27/KTD6): verifica el OOXML escrito a mano
// byte a byte -- decodifica el .zip con ZipDecoder (no con el paquete
// `excel`, que no es compatible con `archive` 4.x -- ver el comentario en
// export_xlsx.dart) e inspecciona el XML de la hoja directamente. Esto es
// más preciso que un ida-y-vuelta por una librería de alto nivel: prueba
// exactamente lo que un lector real (Excel) recibiría.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:consulta_s336_app/data/queries.dart';
import 'package:consulta_s336_app/export/export_xlsx.dart';

String _readEntry(List<int> xlsxBytes, String path) {
  final archive = ZipDecoder().decodeBytes(xlsxBytes);
  final file = archive.files.firstWhere((f) => f.name == path);
  return utf8.decode(file.content as List<int>);
}

void main() {
  test('buildXlsxBytes: cabecera en negrita, filas, celda vacía omitida, autofiltro y freeze pane', () {
    final bytes = buildXlsxBytes(
      sheetName: 'Test',
      headers: const ['A', 'B'],
      rows: const [
        ['x', 1],
        [null, 2.5],
      ],
    );
    final sheet = _readEntry(bytes, 'xl/worksheets/sheet1.xml');

    expect(sheet, contains('<c r="A1" t="inlineStr" s="1"><is><t>A</t></is></c>'));
    expect(sheet, contains('<c r="B1" t="inlineStr" s="1"><is><t>B</t></is></c>'));
    expect(sheet, contains('<c r="A2" t="inlineStr"><is><t>x</t></is></c>'));
    expect(sheet, contains('<c r="B2"><v>1</v></c>'));
    // fila 3: A es null -> la celda se omite del todo, no se escribe vacía
    expect(sheet, isNot(contains('r="A3"')));
    expect(sheet, contains('<c r="B3"><v>2.5</v></c>'));
    expect(sheet, contains('<autoFilter ref="A1:B1"/>'));
    expect(sheet, contains('state="frozen"'));
  });

  test('un texto con & < > " se escapa correctamente en el XML', () {
    final bytes = buildXlsxBytes(
      sheetName: 'Test',
      headers: const ['Col'],
      rows: const [
        ['Tuercas & tornillos <M8> "grandes"'],
      ],
    );
    final sheet = _readEntry(bytes, 'xl/worksheets/sheet1.xml');
    expect(
      sheet,
      contains('<t>Tuercas &amp; tornillos &lt;M8&gt; &quot;grandes&quot;</t>'),
    );
  });

  test('un PIEZA con cero a la izquierda se escribe como texto (celda inlineStr), no como número', () {
    final bytes = xlsxBytesDeNivel('RDH3', const [
      MaterialDeNivelExport(
        pieza: '05123',
        descripcion: 'Tornillo',
        cantidadTotal: 4,
        unidad: 'UD',
        reserva: false,
        numActividades: 2,
      ),
    ]);
    final sheet = _readEntry(bytes, 'xl/worksheets/sheet1.xml');
    // columna A = PIEZA
    expect(sheet, contains('<c r="A2" t="inlineStr"><is><t>05123</t></is></c>'));
  });

  test('Export A: reserva se escribe como Sí/No, cantidad total como número', () {
    final bytes = xlsxBytesDeNivel('RDH3', const [
      MaterialDeNivelExport(
        pieza: '05123',
        descripcion: 'Tornillo',
        cantidadTotal: 5.5,
        unidad: 'UD',
        reserva: true,
        numActividades: 2,
      ),
    ]);
    final sheet = _readEntry(bytes, 'xl/worksheets/sheet1.xml');
    // C = Cantidad total (número), E = Reserva (texto)
    expect(sheet, contains('<c r="C2"><v>5.5</v></c>'));
    expect(sheet, contains('<c r="E2" t="inlineStr"><is><t>Sí</t></is></c>'));
  });

  test('Export B: una cantidad con decimales se escribe como número', () {
    final bytes = xlsxBytesDeActividad('FD5.02.04', const [
      ActividadMaterialExport(
        descripcion: 'Grasa',
        referencia: null,
        fabricante: null,
        codigoErp: null,
        cantidadNum: 0.5,
        cantidadTexto: null,
        unidad: 'g',
        uso: 'S',
      ),
    ]);
    final sheet = _readEntry(bytes, 'xl/worksheets/sheet1.xml');
    // E = Cantidad
    expect(sheet, contains('<c r="E2"><v>0.5</v></c>'));
  });

  test(
    'Export B de una actividad sin materiales de 06 incluye sus herramientas de VMI con código ERP vacío',
    () {
      final bytes = xlsxBytesDeActividad('FD5.02.04', const [
        ActividadMaterialExport(
          descripcion: 'Engrasador G1/8A',
          referencia: null,
          fabricante: 'COMERCIAL',
          codigoErp: null,
          cantidadNum: null,
          cantidadTexto: null,
          unidad: null,
          uso: null,
        ),
      ]);
      final sheet = _readEntry(bytes, 'xl/worksheets/sheet1.xml');
      expect(sheet, contains('<c r="A2" t="inlineStr"><is><t>Engrasador G1/8A</t></is></c>'));
      // D = Código ERP: sin celda porque es null, no una celda vacía
      expect(sheet, isNot(contains('r="D2"')));
    },
  );

  test('el nombre de hoja se sanea: sin caracteres prohibidos y máximo 31 caracteres', () {
    final bytes = buildXlsxBytes(
      sheetName: 'A:B/C*D?E[F]G-nombre-demasiado-largo-para-una-hoja',
      headers: const ['X'],
      rows: const [],
    );
    final workbook = _readEntry(bytes, 'xl/workbook.xml');
    final match = RegExp(r'<sheet name="([^"]*)"').firstMatch(workbook)!;
    final name = match.group(1)!;
    expect(name.length, lessThanOrEqualTo(31));
    expect(name, isNot(contains(RegExp(r'[:\\/?*\[\]]'))));
  });
}
