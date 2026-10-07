// SistemaDetalleScreen: "Actividades por ciclo" se muestra como una
// tarjeta de ancho fijo por ciclo (_TarjetaCiclo), con las actividades
// apiladas en filas de alto fijo -- reemplaza el Wrap de chips de ancho
// variable de antes, que no alineaba entre ciclos con distinto número de
// actividades.

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

  testWidgets('una tarjeta por ciclo, con sus actividades dentro; tocar una navega al detalle', (tester) async {
    db.execute("INSERT INTO sistema VALUES ('FD5', 'Reductor y acoplamiento', null, null)");
    db.execute('''
      INSERT INTO actividad (codigo,sistema_codigo,vmi_rel_path,sin_extraer,componente,actividad_tipo,operacion,frecuencia,edicion)
      VALUES
        ('FD5.01.01','FD5','x/a.pdf',0,'REDUCTOR','INSPECCIÓN','Op 1','La indicada en el plan','--'),
        ('FD5.02.04','FD5','x/b.pdf',0,'REDUCTOR','SUSTITUCIÓN','Op 2','La indicada en el plan','--')
    ''');
    db.execute("INSERT INTO actividad_nivel VALUES ('FD5.01.01','I1')");
    db.execute("INSERT INTO actividad_nivel VALUES ('FD5.01.01','IM1')");
    db.execute("INSERT INTO actividad_nivel VALUES ('FD5.02.04','IM1')");

    final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
    await tester.pumpWidget(wrap(SistemaDetalleScreen(session: session, codigo: 'FD5')));
    await tester.pumpAndSettle();

    expect(find.text('I1'), findsOneWidget);
    expect(find.text('IM1'), findsOneWidget);
    expect(find.text('FD5.01.01'), findsNWidgets(2)); // aparece en la tarjeta de I1 y en la de IM1
    expect(find.text('FD5.02.04'), findsOneWidget); // solo en IM1

    await tester.tap(find.text('FD5.02.04'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'FD5.02.04'), findsOneWidget);
  });
}
