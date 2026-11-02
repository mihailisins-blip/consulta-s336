// _AgrupadoPorSistemaView (hub/por_ciclo_screen.dart): cabecera de
// columnas ("Sistema" / "Actividad" / "Descripción") en una sola línea, y
// las actividades de un mismo sistema apiladas en columna -- ya no en un
// Wrap que las ponía una junto a otra hasta llenar el ancho.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/app_session.dart';
import 'package:consulta_s336_app/hub/por_ciclo_screen.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() => db = openMinimalTestDb());
  tearDown(() => db.dispose());

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets(
    'cabecera de columnas visible, actividades del mismo sistema en columna, con descripción',
    (tester) async {
      db.execute('''
        INSERT INTO nivel_ciclo (codigo,programa,tipo,orden,descripcion,km_num,intervalo_h)
        VALUES ('IM1','km','normal',1,null,null,null)
      ''');
      db.execute('''
        INSERT INTO actividad (codigo,sistema_codigo,vmi_rel_path,sin_extraer,componente,actividad_tipo,operacion,frecuencia,edicion) VALUES
          ('EC1.02.01','EC1','x/a.pdf',0,'EJE','INSPECCIÓN','Inspeccionar visualmente las ruedas.','La indicada en el plan','--'),
          ('EC1.03.01','EC1','x/b.pdf',0,'EJE','COMPROBACIÓN','Comprobar visualmente el estado de las tapas.','La indicada en el plan','--'),
          ('BA1.04.01','BA1','x/c.pdf',0,'CAJA','INSPECCIÓN','Inspeccionar las escaleras y pasamanos en general.','La indicada en el plan','--')
      ''');
      db.execute("INSERT INTO actividad_nivel VALUES ('EC1.02.01','IM1')");
      db.execute("INSERT INTO actividad_nivel VALUES ('EC1.03.01','IM1')");
      db.execute("INSERT INTO actividad_nivel VALUES ('BA1.04.01','IM1')");

      final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
      await tester.pumpWidget(wrap(PorCicloScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('Sistema'), findsOneWidget);
      expect(find.text('Actividad'), findsOneWidget);
      expect(find.text('Descripción'), findsOneWidget);

      expect(find.text('EC1'), findsOneWidget);
      expect(find.text('BA1'), findsOneWidget);
      expect(find.text('EC1.02.01'), findsOneWidget);
      expect(find.text('EC1.03.01'), findsOneWidget);
      expect(find.text('BA1.04.01'), findsOneWidget);
      expect(find.text('Inspeccionar las escaleras y pasamanos en general.'), findsOneWidget);

      // EC1.03.01 aparece por debajo de EC1.02.01 -- misma columna X, más abajo en Y.
      final y1 = tester.getTopLeft(find.text('EC1.02.01')).dy;
      final y2 = tester.getTopLeft(find.text('EC1.03.01')).dy;
      final x1 = tester.getTopLeft(find.text('EC1.02.01')).dx;
      final x2 = tester.getTopLeft(find.text('EC1.03.01')).dx;
      expect(y2, greaterThan(y1));
      expect(x1, x2);

      await tester.tap(find.text('BA1.04.01'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'BA1.04.01'), findsOneWidget);
    },
  );
}
