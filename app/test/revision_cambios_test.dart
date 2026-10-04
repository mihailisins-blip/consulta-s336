// revision_cambios.dart (R21/KTD7): la app por fin lee `cambio_pendiente`
// e `incidencia_extraccion`, que diff.js / join.js (Fase A) ya escribían
// pero nadie mostraba. Datos mínimos deterministas (helpers/minimal_db.dart)
// -- ningún fixture real trae una re-extracción con --prev.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/curacion/revision_cambios.dart';

import 'helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() => db = openMinimalTestDb());
  tearDown(() => db.dispose());

  void seedCambios() {
    // Mismas formas de `id` que escribe diff.js.
    db.execute('''
      INSERT INTO cambio_pendiente (entidad,id,campo,valor_antes,valor_despues,revisado) VALUES
        ('actividad', 'FD5.02.04', 'edicion', 'A', 'B', 0),
        ('actividad_material', 'FD5.02.04 / vmi:grasa', 'cant', '1', '2', 0),
        ('actividad_lote', 'FD5.02.03', 'lote_codigo', 'L1', 'L1,L2', 0),
        ('sistema', 'FD5', 'nombre', 'Reductor', 'Reductora', 1),
        ('catalogo', 'vmi:grasa', 'unidad', null, 'kg', 0)
    ''');
  }

  test('listCambiosPendientes devuelve solo los no revisados por defecto', () {
    seedCambios();
    final cambios = listCambiosPendientes(db);
    expect(cambios, hasLength(4));
    expect(cambios.every((c) => !c.revisado), true);
    expect(contarCambiosSinRevisar(db), 4);
  });

  test('con incluirRevisados, los revisados van al final', () {
    seedCambios();
    final cambios = listCambiosPendientes(db, incluirRevisados: true);
    expect(cambios, hasLength(5));
    expect(cambios.last.entidad, 'sistema');
    expect(cambios.last.revisado, true);
  });

  test('valores null de origen llegan como null, no como texto', () {
    seedCambios();
    final c = listCambiosPendientes(db).singleWhere((c) => c.entidad == 'catalogo');
    expect(c.valorAntes, isNull);
    expect(c.valorDespues, 'kg');
  });

  test('marcarCambioRevisado marca y desmarca una sola fila por rowid', () {
    seedCambios();
    final c = listCambiosPendientes(db).first;

    marcarCambioRevisado(db, c.rowid);
    expect(contarCambiosSinRevisar(db), 3);
    expect(listCambiosPendientes(db).map((x) => x.rowid), isNot(contains(c.rowid)));

    marcarCambioRevisado(db, c.rowid, revisado: false);
    expect(contarCambiosSinRevisar(db), 4);
  });

  test('marcarTodosRevisados deja el contador a cero', () {
    seedCambios();
    marcarTodosRevisados(db);
    expect(contarCambiosSinRevisar(db), 0);
    expect(listCambiosPendientes(db), isEmpty);
  });

  test('actividadCodigo resuelve la actividad afectada según la entidad', () {
    seedCambios();
    final porEntidad = {
      for (final c in listCambiosPendientes(db, incluirRevisados: true)) c.entidad: c.actividadCodigo,
    };
    expect(porEntidad['actividad'], 'FD5.02.04');
    expect(porEntidad['actividad_material'], 'FD5.02.04');
    expect(porEntidad['actividad_lote'], 'FD5.02.03');
    expect(porEntidad['sistema'], isNull);
    expect(porEntidad['catalogo'], isNull);
  });

  test('listIncidencias ordena por tipo y ref; existeActividad distingue códigos sin fila', () {
    db.execute("INSERT INTO actividad (codigo, sistema_codigo) VALUES ('ED3.01.03', 'ED3')");
    db.execute('''
      INSERT INTO incidencia_extraccion VALUES
        ('vmi-sin-fila-plan', 'ED3.01.03', 'ruta/VMI.pdf'),
        ('actividad-plan-sin-vmi', 'ZZ9.99.99', 'sin VMI')
    ''');

    final incs = listIncidencias(db);
    expect(incs.map((i) => i.tipo), ['actividad-plan-sin-vmi', 'vmi-sin-fila-plan']);
    expect(existeActividad(db, 'ED3.01.03'), true);
    expect(existeActividad(db, 'ZZ9.99.99'), false);
  });
}
