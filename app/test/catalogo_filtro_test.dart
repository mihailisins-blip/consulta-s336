// U12 "filtro actividad<->material" (R17): AE7 probado con datos mínimos
// deterministas -- necesita un material usado en varias actividades de
// ciclos distintos, y el fixture real pequeño no da la casualidad de
// tenerlo (cada herramienta real ahí solo aparece en una actividad). Al
// final, un assert de cordura contra el fixture real confirma que la
// consulta también funciona contra una base escrita de verdad por
// pipeline/.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';
import 'helpers/real_db.dart';

void main() {
  test(
    'AE7: filtrar por "Engrasador G1/8A" devuelve todas las actividades que lo usan, en cualquier ciclo',
    () {
      final db = openMinimalTestDb();
      addTearDown(db.dispose);
      db.execute('''
        INSERT INTO catalogo (id,descripcion,tipo) VALUES
          ('vmi:engrasador g1 8a','Engrasador G1/8A','herramienta'),
          ('vmi:grasa','Grasa Klüberlub BE 41-1501','consumible')
      ''');
      db.execute('''
        INSERT INTO actividad (codigo,operacion) VALUES
          ('FD5.01.01','Inspección visual del reductor'),
          ('FD5.02.04','Sustitución del semiacoplamiento'),
          ('RA1.01.01','Comprobación del pantógrafo')
      ''');
      db.execute('''
        INSERT INTO actividad_material (actividad_codigo,catalogo_id,cant,ud,uso) VALUES
          ('FD5.01.01','vmi:engrasador g1 8a',null,null,null),
          ('FD5.02.04','vmi:engrasador g1 8a',null,null,null),
          ('FD5.02.04','vmi:grasa','200','g','S'),
          ('RA1.01.01','vmi:grasa','50','g','SC')
      ''');

      final usos = actividadesQueUsan(db, 'vmi:engrasador g1 8a');
      expect(usos.map((u) => u.actividadCodigo), ['FD5.01.01', 'FD5.02.04']);
      expect(usos.every((u) => u.uso == null), true);

      final usosGrasa = actividadesQueUsan(db, 'vmi:grasa');
      expect(usosGrasa.map((u) => u.actividadCodigo), ['FD5.02.04', 'RA1.01.01']);
      expect(usosGrasa.firstWhere((u) => u.actividadCodigo == 'FD5.02.04').cant, '200');
      expect(usosGrasa.firstWhere((u) => u.actividadCodigo == 'RA1.01.01').uso, 'SC');
    },
  );

  test('una entrada de catálogo sin actividades vinculadas -> lista vacía', () {
    final db = openMinimalTestDb();
    addTearDown(db.dispose);
    db.execute("INSERT INTO catalogo (id,descripcion,tipo) VALUES ('vmi:sin-uso','Sin uso','herramienta')");
    expect(actividadesQueUsan(db, 'vmi:sin-uso'), isEmpty);
  });

  group('cordura contra el fixture real (esquema v3)', () {
    late Database db;
    setUpAll(() => db = openRealSmallFixtureDb());
    tearDownAll(() => db.dispose());

    test('"Engrasador G1/8A" real está vinculado a FD5.02.04', () {
      final usos = actividadesQueUsan(db, 'vmi:engrasador g1 8a');
      expect(usos.map((u) => u.actividadCodigo), contains('FD5.02.04'));
    });
  });
}
