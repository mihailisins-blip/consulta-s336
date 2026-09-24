// getActividadDetalle/listManualToc/programaDeNivel (U11): probados contra
// una base mínima en memoria (helpers/minimal_db.dart) para fijar el
// contrato exacto -- el fixture real pequeño (data-lotes.sqlite) no trae
// una actividad sin_extraer, así que AE1 no se puede probar contra datos
// reales aquí.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() {
    db = openMinimalTestDb();
  });
  tearDown(() => db.dispose());

  void seedSistemaYNivel() {
    db.execute("INSERT INTO sistema VALUES ('FD5', 'Reductor', null, null)");
    db.execute("INSERT INTO nivel_ciclo (codigo,programa,tipo,orden) VALUES ('IM1','km','acumulativo',3)");
  }

  test('getActividadDetalle: código desconocido -> null', () {
    expect(getActividadDetalle(db, 'NOPE'), isNull);
  });

  test('getActividadDetalle: ensambla cabecera, niveles, pasos y materiales', () {
    seedSistemaYNivel();
    db.execute('''
      INSERT INTO actividad
        (codigo,sistema_codigo,vmi_rel_path,sin_extraer,motivo,componente,actividad_tipo,
         operacion,frecuencia,edicion,descripcion_plan,zonas_trabajo,seguridad)
      VALUES
        ('FD5.02.04','FD5','x/VMI.pdf',0,null,'REDUCTOR','SUSTITUCIÓN',
         'Cambio de grasa','La indicada en el plan','--','Descripción del plan','Zona X','Texto de seguridad')
    ''');
    db.execute("INSERT INTO actividad_nivel VALUES ('FD5.02.04','IM1')");
    db.execute('''
      INSERT INTO actividad_paso VALUES
        ('FD5.02.04', 0, 'Desmontaje', 1, 'Retirar el tornillo'),
        ('FD5.02.04', 1, 'Desmontaje', 2, 'Extraer la pieza'),
        ('FD5.02.04', 2, 'Montaje', 1, 'Colocar la pieza nueva')
    ''');
    db.execute('''
      INSERT INTO catalogo (id,descripcion,fabricante,referencia,unidad,tipo,fuente) VALUES
        ('vmi:grasa','Grasa Klüberlub BE 41-1501','KLUBER',null,null,'consumible','vmi'),
        ('vmi:engrasador','Engrasador manual',null,null,null,'herramienta','vmi')
    ''');
    db.execute('''
      INSERT INTO actividad_material (actividad_codigo,catalogo_id,cant,ud,uso) VALUES
        ('FD5.02.04','vmi:grasa','200','g','S'),
        ('FD5.02.04','vmi:engrasador',null,null,null)
    ''');

    final d = getActividadDetalle(db, 'FD5.02.04')!;
    expect(d.sistemaCodigo, 'FD5');
    expect(d.componente, 'REDUCTOR');
    expect(d.seguridad, 'Texto de seguridad');
    expect(d.sinExtraer, false);
    expect(d.vmiRelPath, 'x/VMI.pdf');
    expect(d.niveles, ['IM1']);

    expect(d.pasos.map((p) => '${p.fase}:${p.n}:${p.texto}'), [
      'Desmontaje:1:Retirar el tornillo',
      'Desmontaje:2:Extraer la pieza',
      'Montaje:1:Colocar la pieza nueva',
    ]);

    final grasa = d.materiales.firstWhere((m) => m.tipo == 'consumible');
    expect(grasa.descripcion, 'Grasa Klüberlub BE 41-1501');
    expect(grasa.cant, '200');
    expect(grasa.ud, 'g');
    expect(grasa.uso, 'S');
    expect(d.materiales.any((m) => m.tipo == 'herramienta'), true);
  });

  test(
    'AE1: sin_extraer -> vmiRelPath y motivo presentes, sin pasos ni materiales',
    () {
      db.execute('''
        INSERT INTO actividad (codigo,vmi_rel_path,sin_extraer,motivo)
        VALUES ('FD5.99.99','x/VMI.pdf',1,'sin la sección 2')
      ''');
      final d = getActividadDetalle(db, 'FD5.99.99')!;
      expect(d.sinExtraer, true);
      expect(d.motivo, 'sin la sección 2');
      expect(d.vmiRelPath, 'x/VMI.pdf');
      expect(d.pasos, isEmpty);
      expect(d.materiales, isEmpty);
      expect(d.seguridad, isNull);
    },
  );

  test('listManualToc: ordenado por `orden`, vacío si el manual no tiene TOC', () {
    db.execute("INSERT INTO manual VALUES (1, 'FD5', 'x/m.pdf')");
    db.execute('''
      INSERT INTO manual_toc (manual_id,orden,titulo,pagina,nivel) VALUES
        (1, 1, 'Mantenimiento', 10, 1),
        (1, 0, 'Descripción funcional', 2, 1)
    ''');
    final toc = listManualToc(db, 1);
    expect(toc.map((t) => t.titulo), ['Descripción funcional', 'Mantenimiento']);
    expect(toc.map((t) => t.pagina), [2, 10]);

    expect(listManualToc(db, 999), isEmpty);
  });

  test('programaDeNivel: resuelve el programa o null si el nivel no existe', () {
    seedSistemaYNivel();
    expect(programaDeNivel(db, 'IM1'), 'km');
    expect(programaDeNivel(db, 'NOPE'), isNull);
  });
}
