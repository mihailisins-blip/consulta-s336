// overrides.dart (U14/R19/KTD7): compone `override ?? extraído` para los
// campos editables por el curador -- duracion/zona de actividad (R7) y
// codigo_erp de catálogo (R8) -- y verifica que el extraído en sí nunca se
// toca al guardar un override, solo la tabla `overrides` aparte.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/data/overrides.dart';
import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() => db = openMinimalTestDb());
  tearDown(() => db.dispose());

  void seedSistemaYNivel() {
    db.execute("INSERT INTO sistema VALUES ('FD5', 'Reductor', null, null)");
  }

  test('overrideValor: sin override devuelve null', () {
    expect(overrideValor(db, 'actividad', 'FD5.02.04', 'duracion'), isNull);
  });

  test('guardarOverride + overrideValor: se guarda y se lee de vuelta', () {
    guardarOverride(db, 'actividad', 'FD5.02.04', 'duracion', '90 min');
    expect(overrideValor(db, 'actividad', 'FD5.02.04', 'duracion'), '90 min');
  });

  test('guardarOverride dos veces sobre el mismo campo reemplaza, no duplica', () {
    guardarOverride(db, 'actividad', 'FD5.02.04', 'zona', 'Bajo bastidor');
    guardarOverride(db, 'actividad', 'FD5.02.04', 'zona', 'Sala de máquinas');
    expect(overrideValor(db, 'actividad', 'FD5.02.04', 'zona'), 'Sala de máquinas');
    final filas = db.select("SELECT * FROM overrides WHERE entidad='actividad' AND id='FD5.02.04' AND campo='zona'");
    expect(filas, hasLength(1));
  });

  test('getActividadDetalle compone duracion/zona: override ?? extraído, y el extraído no cambia al guardar', () {
    seedSistemaYNivel();
    db.execute('''
      INSERT INTO actividad
        (codigo,sistema_codigo,vmi_rel_path,sin_extraer,componente,actividad_tipo,operacion,frecuencia,edicion,duracion,zona)
      VALUES
        ('FD5.02.04','FD5','x/VMI.pdf',0,'REDUCTOR','SUSTITUCIÓN','Cambio de grasa','La indicada en el plan','--',null,null)
    ''');

    // sin override: ambos campos null (el extraído nunca los rellena hoy --
    // R7 los reserva para el curador).
    var d = getActividadDetalle(db, 'FD5.02.04')!;
    expect(d.duracion, isNull);
    expect(d.zona, isNull);

    guardarOverride(db, 'actividad', 'FD5.02.04', 'duracion', '45 min');
    d = getActividadDetalle(db, 'FD5.02.04')!;
    expect(d.duracion, '45 min');
    expect(d.zona, isNull);

    // el extraído (columna `duracion` de la tabla `actividad`) sigue null --
    // el override vive aparte, la re-extracción nunca lo pisa (KTD7).
    final extraido = db.select("SELECT duracion FROM actividad WHERE codigo='FD5.02.04'").first;
    expect(extraido['duracion'], isNull);
  });

  test('listCatalogo compone codigo_erp: override ?? extraído, y el extraído no cambia al guardar', () {
    db.execute('''
      INSERT INTO catalogo (id,codigo_erp,descripcion,fabricante,unidad,tipo)
      VALUES ('cat:1','20027','Grasa Klüberlub BE 41-1501','Klüber','KG','material')
    ''');

    var entradas = listCatalogo(db);
    expect(entradas.single.codigoErp, '20027');

    guardarOverride(db, 'catalogo', 'cat:1', 'codigo_erp', '99999');
    entradas = listCatalogo(db);
    expect(entradas.single.codigoErp, '99999');

    final extraido = db.select("SELECT codigo_erp FROM catalogo WHERE id='cat:1'").first;
    expect(extraido['codigo_erp'], '20027');
  });

  test('materialesDeActividadParaExport (U13) también compone el override de codigo_erp', () {
    seedSistemaYNivel();
    db.execute('''
      INSERT INTO actividad (codigo,sistema_codigo,vmi_rel_path,sin_extraer,componente,actividad_tipo,operacion,frecuencia,edicion)
      VALUES ('FD5.02.04','FD5','x/VMI.pdf',0,'REDUCTOR','SUSTITUCIÓN','Cambio de grasa','La indicada en el plan','--')
    ''');
    db.execute('''
      INSERT INTO catalogo (id,codigo_erp,descripcion,fabricante,unidad,tipo)
      VALUES ('cat:1','20027','Grasa Klüberlub BE 41-1501','Klüber','KG','material')
    ''');
    db.execute('''
      INSERT INTO actividad_material (actividad_codigo,catalogo_id,cant,cant_num,ud,uso,reserva,fuente)
      VALUES ('FD5.02.04','cat:1','200','200','g','S',0,'materiales')
    ''');

    guardarOverride(db, 'catalogo', 'cat:1', 'codigo_erp', '00042');
    final materiales = materialesDeActividadParaExport(db, 'FD5.02.04');
    expect(materiales.single.codigoErp, '00042');
  });
}
