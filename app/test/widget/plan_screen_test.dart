// PlanScreen: la tabla con formato de plan muestra grupos por subsistema,
// la marca de seguridad y las X; el filtro por ciclo se hace pulsando el
// título de la columna (varios a la vez), y "Quitar filtros" lo deshace.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/app_session.dart';
import 'package:consulta_s336_app/hub/plan_screen.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() {
    db = openMinimalTestDb();
    db.execute("INSERT INTO sistema VALUES ('ED3', 'AMORTIGUADORES', null, null), ('FD5', 'Reductor y acoplamiento', null, null)");
    db.execute('CREATE TABLE subsistema (codigo TEXT PRIMARY KEY, nombre TEXT)');
    db.execute("INSERT INTO subsistema VALUES ('ED3.01', 'Amortiguadores de primaria y secundaria'), ('FD5.01', 'Reductor')");
    db.execute('''
      INSERT INTO actividad (codigo, sistema_codigo, descripcion_plan, marca_seguridad) VALUES
        ('ED3.01.03', 'ED3', 'Sustituir amortiguadores primarios y secundarios.', 0),
        ('FD5.01.01', 'FD5', 'Inspección visual del reductor.', 1)
    ''');
    db.execute('''
      INSERT INTO actividad_nivel VALUES
        ('ED3.01.03','R1'), ('ED3.01.03','R2'), ('FD5.01.01','I1'), ('FD5.01.01','R1')
    ''');
  });
  tearDown(() => db.dispose());

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
    await tester.pumpWidget(MaterialApp(home: PlanScreen(session: session)));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra grupos por subsistema, descripción, marca de seguridad y X', (tester) async {
    await abrir(tester);
    expect(find.text('ED3.01 · Amortiguadores de primaria y secundaria'), findsOneWidget);
    expect(find.text('FD5.01 · Reductor'), findsOneWidget);
    expect(find.text('Sustituir amortiguadores primarios y secundarios.'), findsOneWidget);
    expect(find.text('!'), findsNWidgets(2)); // título de la columna + FD5.01.01
    expect(find.text('X'), findsNWidgets(4));
    expect(find.text('2 de 2 actividades'), findsOneWidget);
  });

  testWidgets('pulsar el título de un ciclo filtra; varios se suman; otra vez lo quita', (tester) async {
    await abrir(tester);

    await tester.tap(find.byKey(const Key('plan-ciclo-I1')));
    await tester.pumpAndSettle();
    expect(find.text('ED3.01.03'), findsNothing);
    expect(find.text('FD5.01.01'), findsOneWidget);
    expect(find.text('1 de 2 actividades · ciclos I1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-ciclo-R2')));
    await tester.pumpAndSettle();
    expect(find.text('ED3.01.03'), findsOneWidget);
    expect(find.text('2 de 2 actividades · ciclos I1, R2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-ciclo-I1')));
    await tester.tap(find.byKey(const Key('plan-ciclo-R2')));
    await tester.pumpAndSettle();
    expect(find.text('2 de 2 actividades'), findsOneWidget);
  });

  testWidgets('buscar filtra por texto y "Quitar filtros" lo deshace todo', (tester) async {
    await abrir(tester);

    await tester.enterText(find.byKey(const Key('plan-buscar')), 'reductor');
    await tester.tap(find.byKey(const Key('plan-ciclo-R1')));
    await tester.pumpAndSettle();
    expect(find.text('ED3.01.03'), findsNothing);
    expect(find.text('FD5.01.01'), findsOneWidget);

    await tester.tap(find.text('Quitar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('ED3.01.03'), findsOneWidget);
    expect(find.text('2 de 2 actividades'), findsOneWidget);
  });

  testWidgets('sin la tabla subsistema (carpeta de datos anterior) agrupa solo con el código', (tester) async {
    db.execute('DROP TABLE subsistema');
    await abrir(tester);
    expect(find.text('ED3.01'), findsOneWidget);
    expect(find.text('FD5.01'), findsOneWidget);
  });
}
