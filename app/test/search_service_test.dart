// Contra el data.sqlite real de test/fixtures/ (ver fixtures/README.md) --
// no una base sintética. Los resultados exactos que se comprueban aquí se
// verificaron primero contra ese archivo real (node --experimental-sqlite)
// antes de escribir las aserciones, así que reflejan contenido genuino del
// corpus, no una suposición sobre el que "debería" haber.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/search/search_service.dart';

import 'helpers/real_db.dart';

void main() {
  late Database db;
  late SearchService service;

  setUpAll(() {
    db = openRealFixtureDb();
    service = SearchService(db);
  });
  tearDownAll(() => db.dispose());

  test('query en blanco no toca la base y devuelve una lista vacía', () {
    expect(service.search(''), isEmpty);
    expect(service.search('   '), isEmpty);
  });

  test(
    'buscar "reengrasar" devuelve actividades reales de reengrase, con sistema y ciclos en los chips',
    () {
      final results = service.search('reengrasar');
      final byId = {for (final r in results) r.id: r};

      // FD5.02.03 "Reengrasar el semiacoplamiento..." y FC2.01.02
      // "Reengrasar los rodamientos." son actividades reales del corpus
      // cuyo título literal contiene "reengrasar" -- deben estar, con el
      // tipo correcto y los chips (sistema + ciclos) poblados desde
      // actividad/actividad_nivel, no vacíos.
      for (final id in ['FD5.02.03', 'FC2.01.02']) {
        final r = byId[id];
        expect(r, isNotNull, reason: '"$id" debería aparecer buscando "reengrasar"');
        expect(r!.tipo, SearchResultType.actividad);
        expect(r.chips, isNotEmpty, reason: '$id debería traer al menos el chip de sistema');
      }

      final fd5 = byId['FD5.02.03']!;
      expect(fd5.titulo, contains('semiacoplamiento'));
      expect(fd5.chips.first, 'FD5', reason: 'el primer chip es el código de sistema');
    },
  );

  test(
    'ningún resultado expone una ruta de PDF -- la búsqueda solo lee texto extraído/curado (R14)',
    () {
      final results = service.search('reengrasar');
      expect(results, isNotEmpty);
      // SearchResult no tiene ningún campo de ruta de archivo por diseño;
      // esto confirma en tiempo de ejecución que ningún chip/título
      // contiene algo que parezca una ruta a un PDF.
      for (final r in results) {
        expect(r.titulo, isNot(contains('.pdf')));
        for (final chip in r.chips) {
          expect(chip, isNot(contains('.pdf')));
        }
      }
    },
  );

  test(
    'buscar un código de sistema (FD5) devuelve el sistema y sus actividades',
    () {
      final results = service.search('FD5');
      final tipos = results.map((r) => r.tipo).toSet();

      expect(tipos, contains(SearchResultType.sistema));
      expect(tipos, contains(SearchResultType.actividad));

      final sistemaFd5 = results.firstWhere(
        (r) => r.tipo == SearchResultType.sistema && r.id == 'FD5',
      );
      expect(sistemaFd5.titulo, contains('Reductor y acoplamiento'));
      expect(sistemaFd5.chips, ['FD5']);

      final actividadFd5 = results.firstWhere(
        (r) => r.tipo == SearchResultType.actividad && r.id == 'FD5.01.01',
      );
      expect(actividadFd5.chips.first, 'FD5');
      // programa km acumulativo completo (R9): I1..R2, los 7 niveles.
      expect(
        actividadFd5.chips.skip(1),
        ['I1', 'I2', 'IM1', 'IM2', 'IM3', 'R1', 'R2'],
      );
    },
  );

  test(
    'buscar una referencia de material (Klüber) devuelve entradas de catálogo, con y sin código ERP',
    () {
      final results = service.search('kluber');
      final catalogo = results.where((r) => r.tipo == SearchResultType.catalogo).toList();
      expect(catalogo, isNotEmpty);

      final conErp = catalogo.firstWhere((r) => r.id == 'erp:23197');
      expect(conErp.titulo, contains('KLUBER'));
      expect(conErp.chips, ['23197'], reason: 'el chip es el código ERP cuando existe');

      final sinErp = catalogo.firstWhere(
        (r) => r.id == 'vmi:grasa kluberlub be 41 1501',
      );
      expect(sinErp.titulo, contains('Klüberlub'));
      expect(
        sinErp.chips,
        isEmpty,
        reason: 'sin código ERP (entrada solo-VMI) no hay chip que mostrar, no uno vacío inventado',
      );
    },
  );

  test('el límite acota el número de resultados', () {
    final unbounded = service.search('a', limit: 1000);
    final bounded = service.search('a', limit: 3);
    expect(bounded.length, lessThanOrEqualTo(3));
    expect(unbounded.length, greaterThan(bounded.length));
  });
}
