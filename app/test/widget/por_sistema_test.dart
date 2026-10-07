// PorSistemaScreen: el nombre de sistema llega tal cual de la carpeta de
// `05` (join.js) -- algunos gritados en mayúsculas ("SUELO"), otros ya
// correctos ("Caja del vehículo"), y algún acrónimo independiente corto
// ("CCTV") que debe quedarse intacto. Cubre la normalización cosmética de
// _formatearNombreSistema a través de la pantalla real, no de forma
// aislada -- es una función privada del archivo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/app_session.dart';
import 'package:consulta_s336_app/hub/por_sistema_screen.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() => db = openMinimalTestDb());
  tearDown(() => db.dispose());

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets(
    'los nombres gritados en mayúsculas se muestran en mayúscula inicial; ya correctos y acrónimos cortos quedan igual',
    (tester) async {
      db.execute("INSERT INTO sistema VALUES ('CC1', 'SUELO', null, null)");
      db.execute("INSERT INTO sistema VALUES ('BA1', 'Caja del vehículo', null, null)");
      db.execute("INSERT INTO sistema VALUES ('PB1', 'CCTV', null, null)");

      final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
      await tester.pumpWidget(wrap(PorSistemaScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('Suelo'), findsOneWidget);
      expect(find.text('SUELO'), findsNothing);
      expect(find.text('Caja del vehículo'), findsOneWidget);
      expect(find.text('CCTV'), findsOneWidget);
    },
  );

  testWidgets('el buscador filtra por código o por nombre, en memoria', (tester) async {
    db.execute("INSERT INTO sistema VALUES ('ED3', 'Amortiguadores', null, null)");
    db.execute("INSERT INTO sistema VALUES ('RA1', 'Equipo de freno', null, null)");

    final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
    await tester.pumpWidget(wrap(PorSistemaScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Amortiguadores'), findsOneWidget);
    expect(find.text('Equipo de freno'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'freno');
    await tester.pumpAndSettle();

    expect(find.text('Amortiguadores'), findsNothing);
    expect(find.text('Equipo de freno'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ED3');
    await tester.pumpAndSettle();

    expect(find.text('Amortiguadores'), findsOneWidget);
    expect(find.text('Equipo de freno'), findsNothing);

    await tester.enterText(find.byType(TextField), 'no-existe-nada');
    await tester.pumpAndSettle();

    expect(find.text('Ningún sistema coincide con la búsqueda.'), findsOneWidget);
  });

  testWidgets('la cabecera de columnas ("Sistema" / "Actividades") se muestra sobre la lista', (tester) async {
    db.execute("INSERT INTO sistema VALUES ('ED3', 'Amortiguadores', null, null)");

    final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
    await tester.pumpWidget(wrap(PorSistemaScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Sistema'), findsOneWidget);
    expect(find.text('Actividades'), findsOneWidget);
  });

  testWidgets('el conmutador "por área" agrupa los sistemas bajo su cabecera de área', (tester) async {
    db.execute("INSERT INTO sistema VALUES ('ED3', 'Amortiguadores', null, null)");
    db.execute("INSERT INTO sistema VALUES ('RA1', 'Equipo de freno', null, null)");

    final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
    await tester.pumpWidget(wrap(PorSistemaScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Bogie y suspensión'), findsNothing);
    expect(find.text('Frenos'), findsNothing);

    await tester.tap(find.byTooltip('Agrupar por área'));
    await tester.pumpAndSettle();

    expect(find.text('Bogie y suspensión'), findsOneWidget);
    expect(find.text('Frenos'), findsOneWidget);
    expect(find.text('Amortiguadores'), findsOneWidget);
    expect(find.text('Equipo de freno'), findsOneWidget);
  });
}
