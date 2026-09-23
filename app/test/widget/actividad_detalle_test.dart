// ActividadDetalleScreen (U11 / R6): contra el fixture real pequeño
// (data-lotes.sqlite, esquema v3) para FD5.02.04 -- consumibles con
// cantidad/uso, procedimiento por fases, medidas de seguridad colapsadas
// por defecto (KTD9). El caso AE1 (sin_extraer) se prueba aquí también,
// pero contra datos mínimos deterministas (helpers/minimal_db.dart) -- el
// fixture real no trae ninguna actividad sin_extraer, así que no hay forma
// de ejercitar ese estado contra contenido real. La lógica de consulta de
// AE1 ya se prueba por separado en queries_actividad_detalle_test.dart;
// esto prueba que la UI realmente la respeta (aviso visible, tablas
// ausentes), no solo que la query devuelve los datos correctos.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/detalle/actividad_detalle.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/minimal_db.dart';
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

  testWidgets(
    'AE1: sin_extraer muestra el aviso con el motivo y el enlace al PDF, sin tablas ni procedimiento',
    (tester) async {
      final minimalDb = openMinimalTestDb();
      addTearDown(minimalDb.dispose);
      minimalDb.execute('''
        INSERT INTO actividad
          (codigo,sistema_codigo,vmi_rel_path,sin_extraer,motivo,componente,actividad_tipo,operacion,frecuencia,edicion)
        VALUES
          ('FD5.99.99','FD5','x/VMI.3770.FD5.99.99.pdf',1,'sin la sección "2 Herramientas / Consumibles / Repuestos"',
           'REDUCTOR','SUSTITUCIÓN','Operación de prueba','La indicada en el plan','0')
      ''');

      await tester.pumpWidget(
        wrap(
          ActividadDetalleScreen(
            db: minimalDb,
            dataDir: r'C:\no-existe',
            codigo: 'FD5.99.99',
            recientes: RecientesController(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no se pudo extraer automáticamente'),
        findsOneWidget,
      );
      expect(
        find.textContaining('sin la sección "2 Herramientas'),
        findsOneWidget,
      );
      expect(find.text('Abrir PDF original (VMI)'), findsOneWidget);

      // AE1: solo el aviso y el enlace al PDF -- nada de tablas ni
      // procedimiento, aunque la actividad tenga cabecera (código,
      // sistema, componente...).
      expect(find.text('Herramientas'), findsNothing);
      expect(find.text('Consumibles y repuestos'), findsNothing);
      expect(find.text('Procedimiento'), findsNothing);
      expect(find.text('Exportar herramientas y materiales'), findsNothing);
    },
  );
}
