// materialesDeNivelParaExport / materialesDeActividadParaExport (U13/R27):
// probados con datos mínimos deterministas -- necesitan un material usado
// en varias actividades del acumulado de un nivel (RDH3), caso que el
// fixture real pequeño no da la casualidad de tener. Al final, un assert
// de cordura contra el fixture real confirma que la consulta también
// funciona contra una base escrita de verdad por pipeline/.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';
import 'helpers/real_db.dart';

void main() {
  group('materialesDeNivelParaExport', () {
    late Database db;
    setUp(() {
      db = openMinimalTestDb();
      db.execute('''
        INSERT INTO nivel_ciclo (codigo,programa,tipo,orden) VALUES
          ('RDH1','horas','acumulativo',1),
          ('RDH2','horas','acumulativo',2),
          ('RDH3','horas','acumulativo',3)
      ''');
      db.execute('''
        INSERT INTO actividad (codigo) VALUES ('A1'), ('A2'), ('A3')
      ''');
      db.execute('''
        INSERT INTO actividad_nivel (actividad_codigo,nivel_codigo) VALUES
          ('A1','RDH1'), ('A2','RDH2'), ('A3','RDH3')
      ''');
      db.execute('''
        INSERT INTO catalogo (id,codigo_erp,descripcion,unidad,tipo) VALUES
          ('erp:05123','05123','Tornillo M8','UD','material'),
          ('vmi:llave','Llave fija',null,null,'herramienta')
      ''');
      db.execute('''
        INSERT INTO actividad_material (actividad_codigo,catalogo_id,cant_num,reserva) VALUES
          ('A1','erp:05123',2.5,0),
          ('A2','erp:05123',3.0,1),
          ('A1','vmi:llave',null,null)
      ''');
      addTearDown(db.dispose);
    });

    test(
      'RDH3 (acumulado A1+A2+A3) agrega la cantidad del material en A1 y A2',
      () {
        final materiales = materialesDeNivelParaExport(db, 'RDH3');
        expect(materiales, hasLength(1));
        final m = materiales.first;
        expect(m.pieza, '05123');
        expect(m.descripcion, 'Tornillo M8');
        expect(m.cantidadTotal, 5.5);
        expect(m.unidad, 'UD');
        expect(m.numActividades, 2);
        expect(m.reserva, true); // MAX(reserva): al menos un enlace lo marca
      },
    );

    test('RDH1 (solo A1) no incluye la cantidad de A2', () {
      final materiales = materialesDeNivelParaExport(db, 'RDH1');
      expect(materiales.single.cantidadTotal, 2.5);
      expect(materiales.single.numActividades, 1);
    });

    test('las herramientas (tipo != material) no aparecen en Export A', () {
      final materiales = materialesDeNivelParaExport(db, 'RDH3');
      expect(materiales.any((m) => m.descripcion == 'Llave fija'), false);
    });

    test('un nivel sin actividades -> lista vacía', () {
      // Un programa distinto ('km'), sin ningún actividad_nivel vinculado
      // -- RDH4 no serviría aquí: al ser acumulativo (orden 4 > 1,2,3)
      // incluiría igualmente A1/A2/A3 de los niveles RDH inferiores.
      db.execute("INSERT INTO nivel_ciclo (codigo,programa,tipo,orden) VALUES ('IM1','km','acumulativo',1)");
      expect(materialesDeNivelParaExport(db, 'IM1'), isEmpty);
    });
  });

  group('materialesDeActividadParaExport', () {
    late Database db;
    setUp(() {
      db = openMinimalTestDb();
      db.execute('''
        INSERT INTO catalogo (id,codigo_erp,descripcion,referencia,fabricante,unidad,tipo) VALUES
          ('erp:1','12345','Grasa Klüberlub',null,'KLUBER','g','material'),
          ('vmi:engrasador',null,'Engrasador G1/8A',null,'COMERCIAL',null,'herramienta')
      ''');
      db.execute('''
        INSERT INTO actividad_material (actividad_codigo,catalogo_id,cant,cant_num,ud,uso) VALUES
          ('A1','erp:1','200',200,'g','S'),
          ('A1','vmi:engrasador',null,null,null,null)
      ''');
      addTearDown(db.dispose);
    });

    test('incluye materiales con código ERP y herramientas de VMI sin él', () {
      final materiales = materialesDeActividadParaExport(db, 'A1');
      expect(materiales, hasLength(2));
      final grasa = materiales.firstWhere((m) => m.descripcion == 'Grasa Klüberlub');
      expect(grasa.codigoErp, '12345');
      expect(grasa.cantidadNum, 200);
      final engrasador = materiales.firstWhere((m) => m.descripcion == 'Engrasador G1/8A');
      expect(engrasador.codigoErp, isNull);
      expect(engrasador.cantidadNum, isNull);
    });

    test('una actividad sin materiales vinculados -> lista vacía', () {
      expect(materialesDeActividadParaExport(db, 'NOPE'), isEmpty);
    });
  });

  group('cordura contra el fixture real (esquema v3)', () {
    late Database db;
    setUpAll(() => db = openRealSmallFixtureDb());
    tearDownAll(() => db.dispose());

    test('FD5.01.01 real trae ACEITE REDUCTOR MOBIL 75W-90 con su código ERP (20027)', () {
      final materiales = materialesDeActividadParaExport(db, 'FD5.01.01');
      final aceite = materiales.firstWhere((m) => m.descripcion == 'ACEITE REDUCTOR MOBIL 75W-90');
      expect(aceite.codigoErp, '20027');
    });

    test('I1 (incluye FD5.01.01) trae ese mismo material agregado en Export A', () {
      final materiales = materialesDeNivelParaExport(db, 'I1');
      expect(materiales.any((m) => m.pieza == '20027'), true);
    });
  });
}
