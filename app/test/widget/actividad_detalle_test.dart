// ActividadDetalleScreen (U11 / R6): contra el fixture real pequeño
// (data-lotes.sqlite, esquema v3) para FD5.02.04 -- consumibles con
// cantidad/uso, procedimiento por fases, medidas de seguridad colapsadas
// por defecto (KTD9). El caso AE1 (sin_extraer) se prueba en
// queries_actividad_detalle_test.dart contra datos mínimos deterministas,
// no aquí -- el fixture real no trae ninguna actividad sin_extraer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/detalle/actividad_detalle.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/real_db.dart';

void main() {
  late Database db;
  setUp(() => db = openRealSmallFixtureDb());
  tearDown(() => db.dispose());

  Widget wrap(Widget child) => MaterialApp(home: child);

  /// FD5.02.04 tiene 44 pasos de procedimiento más las tablas de
  /// herramientas/consumibles -- más contenido del que cabe en el viewport
  /// de test por defecto (800x600). `ListView` solo materializa los
  /// elementos dentro del viewport + cacheExtent aunque reciba una lista
  /// fija de `children`, así que sin agrandar la superficie `find.text()`
  /// no encuentra nada más allá de lo que "cabría" en pantalla.
  Future<void> agrandarViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 8000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets(
    'FD5.02.04: consumible con cantidad y uso, procedimiento por fases',
    (tester) async {
      await agrandarViewport(tester);
      await tester.pumpWidget(
        wrap(
          ActividadDetalleScreen(
            db: db,
            dataDir: r'C:\no-existe',
            codigo: 'FD5.02.04',
            recientes: RecientesController(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grasa Klüberlub BE 41-1501'), findsOneWidget);
      expect(find.text('200 g · S'), findsOneWidget);

      expect(find.text('Desmontaje'), findsOneWidget);
      expect(find.text('Montaje'), findsOneWidget);

      expect(find.text('Abrir PDF original (VMI)'), findsOneWidget);
    },
  );

  testWidgets(
    'medidas de seguridad: arranca colapsado, se expande al tocarlo',
    (tester) async {
      await agrandarViewport(tester);
      await tester.pumpWidget(
        wrap(
          ActividadDetalleScreen(
            db: db,
            dataDir: r'C:\no-existe',
            codigo: 'FD5.02.04',
            recientes: RecientesController(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medidas de seguridad'), findsOneWidget);
      expect(find.textContaining('Riesgos generales asociados'), findsNothing);

      await tester.tap(find.text('Medidas de seguridad'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Riesgos generales asociados'), findsOneWidget);
    },
  );

  testWidgets('código desconocido -> "Actividad no encontrada"', (tester) async {
    await tester.pumpWidget(
      wrap(
        ActividadDetalleScreen(
          db: db,
          dataDir: r'C:\no-existe',
          codigo: 'NOPE.00.00',
          recientes: RecientesController(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Actividad no encontrada.'), findsOneWidget);
  });
}
