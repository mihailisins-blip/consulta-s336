// Figuras de un VMI en el detalle de actividad: las de zonas de trabajo con su
// título, y las del procedimiento justo antes del paso al que preceden, con
// su tabla de componentes. No se comprueba el contenido de la imagen (Image.file
// carga de forma asíncrona fuera del reloj falso de testWidgets) sino lo que la
// rodea: títulos, leyenda y posición.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/app_session.dart';
import 'package:consulta_s336_app/data/queries.dart';
import 'package:consulta_s336_app/detalle/actividad_detalle.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() {
    db = openMinimalTestDb();
    db.execute('''
      INSERT INTO actividad (codigo,sistema_codigo,vmi_rel_path,sin_extraer,componente,actividad_tipo,operacion,frecuencia,edicion,zonas_trabajo)
      VALUES ('ED3.01.03','ED3','x/a.pdf',0,'AMORTIGUADORES','SUSTITUCIÓN','Sustituir amortiguadores','La indicada en el plan','--',
              'Esquema del vehículo; Localización de los amortiguadores')
    ''');
  });
  tearDown(() => db.dispose());

  Future<void> abrir(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
    await tester.pumpWidget(
      MaterialApp(home: ActividadDetalleScreen(session: session, codigo: 'ED3.01.03')),
    );
    await tester.pumpAndSettle();
  }

  test('getActividadDetalle lee las figuras y su leyenda; un JSON roto no tumba el detalle', () {
    db.execute('''
      INSERT INTO actividad_imagen VALUES
        ('ED3.01.03','procedimiento',0,'a.jpg',1000,572,'Amortiguador','[{"n":"01","nombre":"Cuerpo"},{"n":"02","nombre":"Fijación M16"}]',0),
        ('ED3.01.03','procedimiento',1,'b.jpg',1000,572,'Roto','esto no es json',2)
    ''');
    final d = getActividadDetalle(db, 'ED3.01.03')!;
    expect(d.imagenes, hasLength(2));
    expect(d.imagenes[0].leyenda.map((l) => '${l.n}=${l.nombre}'), ['01=Cuerpo', '02=Fijación M16']);
    expect(d.imagenes[0].antesDePaso, 0);
    expect(d.imagenes[1].leyenda, isEmpty);
  });

  testWidgets('zonas de trabajo: cada figura con su título, sin repetir el texto de la zona', (tester) async {
    db.execute('''
      INSERT INTO actividad_imagen VALUES
        ('ED3.01.03','zonas',0,'a.jpg',1000,519,'Esquema del vehículo',null,null),
        ('ED3.01.03','zonas',1,'b.jpg',1000,572,'Localización de los amortiguadores',null,null)
    ''');
    await abrir(tester);

    expect(find.text('Zona de trabajo'), findsOneWidget);
    expect(find.text('Esquema del vehículo'), findsOneWidget);
    expect(find.text('Localización de los amortiguadores'), findsOneWidget);
    expect(
      find.text('Esquema del vehículo; Localización de los amortiguadores'),
      findsNothing,
      reason: 'el texto de la zona es la lista de pies: con figuras sería repetirlos',
    );
  });

  testWidgets('sin figuras, la zona de trabajo sigue mostrando su texto como antes', (tester) async {
    await abrir(tester);
    expect(find.text('Esquema del vehículo; Localización de los amortiguadores'), findsOneWidget);
  });

  testWidgets('procedimiento: la figura va justo antes de su paso, con la tabla de componentes', (tester) async {
    db.execute('''
      INSERT INTO actividad_paso (actividad_codigo,orden,fase,paso_n,texto) VALUES
        ('ED3.01.03',0,'Sustitución',1,'Quitar los elementos de fijación.'),
        ('ED3.01.03',1,'Sustitución',2,'Colocar el amortiguador nuevo.'),
        ('ED3.01.03',2,'Sustitución',3,'Aplicar la marca de par.')
    ''');
    db.execute('''
      INSERT INTO actividad_imagen VALUES
        ('ED3.01.03','procedimiento',0,'a.jpg',1000,572,'Amortiguador vertical primario',
         '[{"n":"01","nombre":"Amortiguador vertical primario"},{"n":"02","nombre":"Elementos de fijación M16"}]',1)
    ''');
    await abrir(tester);

    expect(find.text('Elementos de fijación M16'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);

    final y1 = tester.getTopLeft(find.text('Quitar los elementos de fijación.')).dy;
    final yFigura = tester.getTopLeft(find.text('Amortiguador vertical primario').first).dy;
    final y2 = tester.getTopLeft(find.text('Colocar el amortiguador nuevo.')).dy;
    expect(y1, lessThan(yFigura));
    expect(yFigura, lessThan(y2), reason: 'antes_de_paso=1: entre el paso 1 y el paso 2');
  });

  testWidgets('una figura que no precede a ningún paso se dibuja al final del procedimiento', (tester) async {
    db.execute('''
      INSERT INTO actividad_paso (actividad_codigo,orden,fase,paso_n,texto)
      VALUES ('ED3.01.03',0,'Sustitución',1,'Único paso.')
    ''');
    db.execute('''
      INSERT INTO actividad_imagen VALUES ('ED3.01.03','procedimiento',0,'a.jpg',1000,572,'Figura final',null,5)
    ''');
    await abrir(tester);

    final yPaso = tester.getTopLeft(find.text('Único paso.')).dy;
    final yFigura = tester.getTopLeft(find.text('Figura final')).dy;
    expect(yFigura, greaterThan(yPaso));
  });
}
