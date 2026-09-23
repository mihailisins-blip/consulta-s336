// U10 "por ciclo" (R9/R11/R12): AE2 (acumulación por programa km) y AE3
// (desglose por lote, sin repetidas entre lotes) probados con datos
// mínimos y deterministas (helpers/minimal_db.dart) -- no dependen de que
// el fixture real de turno dé la casualidad de contener un caso que los
// ejercite (el corpus real, comprobado, marca cada actividad en TODOS sus
// niveles aplicables desde el propio Excel del plan, así que no demuestra
// por sí solo si la acumulación del código funciona o es redundante).
//
// Al final, un par de asserts de cordura contra el fixture real pequeño
// (test/fixtures/data-lotes.sqlite, esquema v2) confirman que la consulta
// también funciona contra una base escrita de verdad por pipeline/.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';
import 'helpers/real_db.dart';

const _kmNiveles = [
  ('I1', 1), ('I2', 2), ('IM1', 3), ('IM2', 4), ('IM3', 5), ('R1', 6), ('R2', 7),
];

void _seedNivelesKm(Database db) {
  for (final (codigo, orden) in _kmNiveles) {
    db.execute(
      'INSERT INTO nivel_ciclo (codigo,programa,tipo,orden) VALUES (?,?,?,?)',
      [codigo, 'km', 'acumulativo', orden],
    );
  }
}

void main() {
  group('actividadesDeNivel (AE2): un nivel km incluye los niveles anteriores', () {
    late Database db;
    setUp(() {
      db = openMinimalTestDb();
      _seedNivelesKm(db);
      // A: solo en I1 (orden 1). B: solo en IM1 (orden 3). C: solo en R2 (orden 7).
      db.execute("INSERT INTO actividad_nivel VALUES ('A','I1')");
      db.execute("INSERT INTO actividad_nivel VALUES ('B','IM1')");
      db.execute("INSERT INTO actividad_nivel VALUES ('C','R2')");
    });
    tearDown(() => db.dispose());

    test('IM2 (orden 4) incluye A (I1) y B (IM1), no C (R2)', () {
      final r = actividadesDeNivel(db, 'IM2');
      expect(r.codigos, containsAll(['A', 'B']));
      expect(r.codigos, isNot(contains('C')));
    });

    test('I1 (orden 1) incluye solo A, ni siquiera B', () {
      final r = actividadesDeNivel(db, 'I1');
      expect(r.codigos, ['A']);
    });

    test('R2 (orden 7, el último) incluye las tres -- el acumulado completo', () {
      final r = actividadesDeNivel(db, 'R2');
      expect(r.codigos, containsAll(['A', 'B', 'C']));
    });
  });

  group('actividadesDeLote (AE3): desglose por lote sin repetidas entre lotes', () {
    late Database db;
    setUp(() {
      db = openMinimalTestDb();
      db.execute(
        "INSERT INTO nivel_ciclo (codigo,programa,tipo,orden) VALUES ('IM1','km','acumulativo',3)",
      );
      for (final lote in ['IM1A', 'IM1B', 'IM1C']) {
        db.execute('INSERT INTO lote VALUES (?,?)', ['IM1', lote]);
      }
      for (final (codigo, lote) in [('X', 'IM1A'), ('Y', 'IM1B'), ('Z', 'IM1C')]) {
        db.execute("INSERT INTO actividad_nivel VALUES ('$codigo','IM1')");
        db.execute('INSERT INTO actividad_lote VALUES (?,?)', [codigo, lote]);
      }
    });
    tearDown(() => db.dispose());

    test('un nivel partido expone sus códigos de lote', () {
      expect(actividadesDeNivel(db, 'IM1').lotes, ['IM1A', 'IM1B', 'IM1C']);
    });

    test('cada lote tiene solo su propia actividad', () {
      expect(actividadesDeLote(db, 'IM1A'), ['X']);
      expect(actividadesDeLote(db, 'IM1B'), ['Y']);
      expect(actividadesDeLote(db, 'IM1C'), ['Z']);
    });

    test('la unión de los lotes es el nivel completo, sin ninguna repetida', () {
      final deTodosLosLotes = [
        ...actividadesDeLote(db, 'IM1A'),
        ...actividadesDeLote(db, 'IM1B'),
        ...actividadesDeLote(db, 'IM1C'),
      ];
      expect(deTodosLosLotes.toSet(), actividadesDeNivel(db, 'IM1').codigos.toSet());
      expect(deTodosLosLotes.length, deTodosLosLotes.toSet().length);
    });

    test('un nivel sin lotes no ofrece desglose', () {
      db.execute(
        "INSERT INTO nivel_ciclo (codigo,programa,tipo,orden) VALUES ('IM3','km','acumulativo',5)",
      );
      expect(actividadesDeNivel(db, 'IM3').lotes, isEmpty);
    });
  });

  test('un nivel desconocido lanza en vez de devolver un resultado vacío engañoso', () {
    final db = openMinimalTestDb();
    addTearDown(db.dispose);
    expect(() => actividadesDeNivel(db, 'NO-EXISTE'), throwsArgumentError);
  });

  group('sistemasDe', () {
    test('resuelve el sistema de cada actividad y omite las sin sistema', () {
      final db = openMinimalTestDb();
      addTearDown(db.dispose);
      db.execute("INSERT INTO actividad VALUES ('FD5.01.01','FD5')");
      db.execute("INSERT INTO actividad VALUES ('ZZ9.01.01',NULL)");
      final r = sistemasDe(db, ['FD5.01.01', 'ZZ9.01.01']);
      expect(r, {'FD5.01.01': 'FD5'});
    });

    test('lista vacía no toca la base', () {
      final db = openMinimalTestDb();
      addTearDown(db.dispose);
      expect(sistemasDe(db, const []), isEmpty);
    });
  });

  group('cordura contra el fixture real (esquema v2)', () {
    late Database db;
    setUpAll(() => db = openRealSmallFixtureDb());
    tearDownAll(() => db.dispose());

    test('FD5.01.01 (marcada en todo el programa km en el fixture real) aparece en IM2', () {
      final r = actividadesDeNivel(db, 'IM2');
      expect(r.codigos, contains('FD5.01.01'));
    });

    test('IM1 tiene lotes reales y FD5.01.01 cae en IM1A', () {
      final r = actividadesDeNivel(db, 'IM1');
      expect(r.lotes, containsAll(['IM1A', 'IM1B', 'IM1C']));
      expect(actividadesDeLote(db, 'IM1A'), contains('FD5.01.01'));
    });
  });
}
