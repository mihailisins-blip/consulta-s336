// RevisionScreen y su acceso desde el hub (R21/R18): el curador ve y
// marca los cambios de origen; el acceso solo aparece con el centinela
// de curador. E/S de archivos solo síncrona (ver la nota de
// widget_test.dart sobre E/S async + pumpAndSettle).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/app_session.dart';
import 'package:consulta_s336_app/curacion/edit_mode.dart';
import 'package:consulta_s336_app/curacion/revision_cambios.dart';
import 'package:consulta_s336_app/curacion/revision_screen.dart';
import 'package:consulta_s336_app/hub/hub_screen.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/minimal_db.dart';

void main() {
  late Database db;
  late Directory dataDir;
  setUp(() {
    db = openMinimalTestDb();
    dataDir = Directory.systemTemp.createTempSync('revision-');
    db.execute("INSERT INTO actividad (codigo, sistema_codigo) VALUES ('FD5.02.04', 'FD5')");
    db.execute('''
      INSERT INTO cambio_pendiente (entidad,id,campo,valor_antes,valor_despues,revisado) VALUES
        ('actividad', 'FD5.02.04', 'edicion', 'A', 'B', 0),
        ('sistema', 'FD5', 'nombre', 'Reductor', 'Reductora', 0)
    ''');
    db.execute("INSERT INTO incidencia_extraccion VALUES ('vmi-sin-fila-plan', 'FD5.02.04', 'ruta/VMI.pdf')");
  });
  tearDown(() {
    db.dispose();
    dataDir.deleteSync(recursive: true);
  });

  AppSession session() =>
      AppSession(db: db, dataDir: dataDir.path, recientes: RecientesController(), editMode: true);

  testWidgets('lista los cambios pendientes y marcar uno lo saca de la lista', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RevisionScreen(session: session())));

    expect(find.text('Cambios de origen (2)'), findsOneWidget);
    expect(find.text('actividad · FD5.02.04 · edicion'), findsOneWidget);
    expect(find.text('Antes: A\nAhora: B'), findsOneWidget);
    // Solo el cambio de actividad ofrece abrirla; el de sistema no.
    expect(find.byTooltip('Abrir actividad'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    expect(find.text('Cambios de origen (1)'), findsOneWidget);
    expect(find.text('actividad · FD5.02.04 · edicion'), findsNothing);
    expect(contarCambiosSinRevisar(db), 1);
  });

  testWidgets('"Marcar todos como revisados" vacía la lista', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RevisionScreen(session: session())));

    await tester.tap(find.text('Marcar todos como revisados'));
    await tester.pump();

    expect(find.text('No hay cambios de origen pendientes de revisar.'), findsOneWidget);
    expect(contarCambiosSinRevisar(db), 0);
  });

  testWidgets('la pestaña de incidencias las muestra', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RevisionScreen(session: session())));

    await tester.tap(find.text('Incidencias (1)'));
    await tester.pumpAndSettle();

    expect(find.text('vmi-sin-fila-plan · ruta/VMI.pdf'), findsOneWidget);
  });

  testWidgets('el hub solo ofrece "Revisión" en la copia del curador', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HubScreen(db: db, dataDir: dataDir.path)));
    expect(find.textContaining('Revisión'), findsNothing);

    File(p.join(dataDir.path, centinelaCurador)).writeAsStringSync('');
    await tester.pumpWidget(MaterialApp(home: HubScreen(key: UniqueKey(), db: db, dataDir: dataDir.path)));
    expect(find.text('Revisión (2)'), findsOneWidget);
  });
}
