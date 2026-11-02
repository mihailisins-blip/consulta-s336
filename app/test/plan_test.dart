// Tabla del plan (pestaña "Plan"): listPlan compone la marca de seguridad
// como `override ?? extraído`, agrupa por subsistema y lee los nombres de
// subsistema si la carpeta de datos los trae; filtrarPlan combina texto,
// sistema y ciclos (alguno de los marcados).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/data/overrides.dart';
import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() {
    db = openMinimalTestDb();
    db.execute('''
      INSERT INTO actividad (codigo, sistema_codigo, descripcion_plan, operacion, marca_seguridad, observaciones_plan) VALUES
        ('ED3.01.01', 'ED3', 'Inspeccionar condición y verificar ausencia de fugas de aceite.', null, 1, null),
        ('ED3.01.03', 'ED3', 'Sustituir amortiguadores primarios y secundarios.', null, 0, null),
        ('FD5.01.01', 'FD5', null, 'Inspección visual del reductor.', 0, 'Después de los primeros 7.000 km')
    ''');
    db.execute('''
      INSERT INTO actividad_nivel VALUES
        ('ED3.01.01','I1'), ('ED3.01.01','R1'), ('ED3.01.01','R2'),
        ('ED3.01.03','R1'), ('ED3.01.03','R2'),
        ('FD5.01.01','I1'), ('FD5.01.01','IM1')
    ''');
  });
  tearDown(() => db.dispose());

  test('listPlan: una fila por actividad, con subsistema, ciclos y descripción del plan (u operación si falta)', () {
    final filas = listPlan(db);
    expect(filas.map((f) => f.codigo), ['ED3.01.01', 'ED3.01.03', 'FD5.01.01']);
    final ed3 = filas[1];
    expect(ed3.subsistemaCodigo, 'ED3.01');
    expect(ed3.ciclos, {'R1', 'R2'});
    expect(ed3.descripcion, 'Sustituir amortiguadores primarios y secundarios.');
    expect(filas[2].descripcion, 'Inspección visual del reductor.');
    expect(filas[2].observaciones, 'Después de los primeros 7.000 km');
  });

  test('listPlan: la marca de seguridad es override ?? extraído', () {
    expect(listPlan(db).firstWhere((f) => f.codigo == 'ED3.01.01').marcaSeguridad, isTrue);
    expect(listPlan(db).firstWhere((f) => f.codigo == 'FD5.01.01').marcaSeguridad, isFalse);

    guardarOverride(db, 'actividad', 'ED3.01.01', 'marca_seguridad', '0');
    guardarOverride(db, 'actividad', 'FD5.01.01', 'marca_seguridad', '1');
    final filas = listPlan(db);
    expect(filas.firstWhere((f) => f.codigo == 'ED3.01.01').marcaSeguridad, isFalse);
    expect(filas.firstWhere((f) => f.codigo == 'FD5.01.01').marcaSeguridad, isTrue);
    // el extraído no se toca
    expect(db.select("SELECT marca_seguridad FROM actividad WHERE codigo='ED3.01.01'").first['marca_seguridad'], 1);
  });

  test('nombresSubsistema: vacío si la carpeta de datos no trae la tabla; los nombres si la trae', () {
    expect(nombresSubsistema(db), isEmpty);
    db.execute('CREATE TABLE subsistema (codigo TEXT PRIMARY KEY, nombre TEXT)');
    db.execute("INSERT INTO subsistema VALUES ('ED3.01', 'Amortiguadores de primaria y secundaria'), ('FD5.01', null)");
    expect(nombresSubsistema(db), {'ED3.01': 'Amortiguadores de primaria y secundaria'});
  });

  group('filtrarPlan', () {
    late List<FilaPlan> filas;
    setUp(() => filas = listPlan(db));
    List<String> codigos(List<FilaPlan> l) => [for (final f in l) f.codigo];

    test('sin filtros devuelve todo', () {
      expect(codigos(filtrarPlan(filas)), hasLength(3));
    });

    test('por sistema', () {
      expect(codigos(filtrarPlan(filas, sistema: 'FD5')), ['FD5.01.01']);
    });

    test('por texto, sin distinguir mayúsculas ni tildes, también en código y observaciones', () {
      expect(codigos(filtrarPlan(filas, texto: 'INSPECCION')), ['ED3.01.01', 'FD5.01.01']);
      expect(codigos(filtrarPlan(filas, texto: 'ed3.01.03')), ['ED3.01.03']);
      expect(codigos(filtrarPlan(filas, texto: '7.000')), ['FD5.01.01']);
    });

    test('por ciclos: la fila debe tener X en alguno de los marcados', () {
      expect(codigos(filtrarPlan(filas, ciclos: {'IM1'})), ['FD5.01.01']);
      expect(codigos(filtrarPlan(filas, ciclos: {'IM1', 'R2'})), ['ED3.01.01', 'ED3.01.03', 'FD5.01.01']);
      expect(codigos(filtrarPlan(filas, ciclos: {'NS'})), isEmpty);
    });

    test('los filtros se combinan', () {
      expect(codigos(filtrarPlan(filas, sistema: 'ED3', ciclos: {'I1'})), ['ED3.01.01']);
    });
  });
}
