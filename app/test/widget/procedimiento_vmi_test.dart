// Formato del procedimiento de un VMI en el detalle de actividad: cada elemento
// (título, subtítulo, paso, subpaso, viñeta, párrafo, aviso) se dibuja con su
// estilo y su separación, y las figuras de la zona de trabajo pasan a dos
// columnas cuando hay más de dos. Se comprueban posiciones relativas (y, x),
// no píxeles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/app_session.dart';
import 'package:consulta_s336_app/detalle/actividad_detalle.dart';
import 'package:consulta_s336_app/hub/recientes.dart';

import '../helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() {
    db = openMinimalTestDb();
    db.execute('''
      INSERT INTO actividad (codigo,sistema_codigo,vmi_rel_path,sin_extraer,componente,actividad_tipo,operacion,frecuencia,edicion)
      VALUES ('DF3.01.01','DF3','x/a.pdf',0,'EXTINTORES','INSPECCIÓN VISUAL','Inspeccionar los extintores','La indicada en el plan','0')
    ''');
  });
  tearDown(() => db.dispose());

  Future<void> abrir(WidgetTester tester, {double ancho = 1200}) async {
    await tester.binding.setSurfaceSize(Size(ancho, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = AppSession(db: db, dataDir: r'C:\no-existe', recientes: RecientesController());
    await tester.pumpWidget(
      MaterialApp(home: ActividadDetalleScreen(session: session, codigo: 'DF3.01.01')),
    );
    await tester.pumpAndSettle();
  }

  /// Inserta elementos del procedimiento en orden: (tipo, n, etiqueta, texto).
  void sembrar(List<(String, int?, String?, String)> elementos) {
    final stmt = db.prepare(
      'INSERT INTO actividad_paso (actividad_codigo,orden,fase,paso_n,texto,tipo,etiqueta) '
      "VALUES ('DF3.01.01',?,null,?,?,?,?)",
    );
    for (var i = 0; i < elementos.length; i++) {
      final (tipo, n, etiqueta, texto) = elementos[i];
      stmt.execute([i, n, texto, tipo, etiqueta]);
    }
    stmt.dispose();
  }

  double y(WidgetTester tester, String texto) => tester.getTopLeft(find.text(texto)).dy;
  double x(WidgetTester tester, String texto) => tester.getTopLeft(find.text(texto)).dx;

  testWidgets('dos listas 1-2-3 separadas por un subtítulo: el subtítulo abre hueco, no van seguidas', (tester) async {
    sembrar([
      ('subtitulo', null, null, 'Extintor'),
      ('paso', 1, null, 'Comprobar el extintor.'),
      ('paso', 2, null, 'Comprobar la fijación.'),
      ('paso', 3, null, 'Comprobar la caducidad.'),
      ('subtitulo', null, null, 'Mascara de gas'),
      ('paso', 1, null, 'Comprobar la máscara.'),
      ('paso', 2, null, 'Comprobar el envase.'),
    ]);
    await abrir(tester);

    final entrePasos = y(tester, 'Comprobar la fijación.') - y(tester, 'Comprobar el extintor.');
    final hastaSubtitulo = y(tester, 'Mascara de gas') - y(tester, 'Comprobar la caducidad.');
    expect(hastaSubtitulo, greaterThan(entrePasos + 8), reason: 'el subtítulo se despega de la lista anterior');
    expect(find.text('Extintor'), findsOneWidget);
    expect(find.text('1.'), findsNWidgets(2), reason: 'la marca de cada paso va en su propia columna');
  });

  testWidgets('una numeración que vuelve a empezar sin subtítulo abre un bloque nuevo, no sigue pegada', (tester) async {
    sembrar([
      ('paso', 1, null, 'Primero A.'),
      ('paso', 2, null, 'Segundo A.'),
      ('paso', 3, null, 'Tercero A.'),
      ('paso', 1, null, 'Primero B.'),
      ('paso', 2, null, 'Segundo B.'),
    ]);
    await abrir(tester);

    final normal = y(tester, 'Segundo A.') - y(tester, 'Primero A.');
    final reinicio = y(tester, 'Primero B.') - y(tester, 'Tercero A.');
    expect(reinicio, greaterThan(normal + 6));
    expect(y(tester, 'Segundo B.') - y(tester, 'Primero B.'), closeTo(normal, 0.5));
  });

  testWidgets('el texto de un paso largo se parte alineado bajo sí mismo, no bajo la marca', (tester) async {
    sembrar([
      ('paso', 4, null, 'Texto muy largo ${'palabra ' * 80}fin.'),
    ]);
    await abrir(tester);

    // la marca y el texto están en columnas distintas: el texto empieza a la derecha de "4."
    expect(find.text('4.'), findsOneWidget);
    final marca = tester.getTopLeft(find.text('4.'));
    final texto = tester.getTopLeft(find.textContaining('Texto muy largo'));
    expect(texto.dx, greaterThan(marca.dx + 10));
    expect(texto.dy, closeTo(marca.dy, 1));
  });

  testWidgets('viñetas y subpasos son elementos propios, con su marca', (tester) async {
    sembrar([
      ('paso', 1, null, 'Revisar el cristal.'),
      ('subpaso', null, 'a', 'Sin grietas.'),
      ('subtitulo', null, null, 'CONSEJOS:'),
      ('vineta', null, null, 'Usar un paño suave.'),
      ('vineta', null, null, 'No usar papel.'),
    ]);
    await abrir(tester);

    expect(find.text('a.'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
    expect(x(tester, 'Sin grietas.'), greaterThan(x(tester, 'Revisar el cristal.')), reason: 'el subpaso va sangrado');
    expect(y(tester, 'No usar papel.'), greaterThan(y(tester, 'Usar un paño suave.')));
  });

  testWidgets('avisos: rótulo y cuerpo; con subtítulo, los dos párrafos', (tester) async {
    sembrar([
      ('aviso', null, 'INFORMACIÓN', 'Pares de apriete\nLos pares están en los planos del componente.'),
      ('paso', 1, null, 'Apretar.'),
      ('aviso', null, 'PRECAUCIÓN', 'Ante cualquier incidencia, sustituir.'),
    ]);
    await abrir(tester);

    expect(find.text('INFORMACIÓN'), findsOneWidget);
    expect(find.text('Pares de apriete'), findsOneWidget);
    expect(find.text('Los pares están en los planos del componente.'), findsOneWidget);
    expect(find.text('PRECAUCIÓN'), findsOneWidget);
    expect(find.text('Ante cualquier incidencia, sustituir.'), findsOneWidget);
    // el aviso va como recuadro propio, antes del paso, y el siguiente después
    expect(y(tester, 'Apretar.'), greaterThan(y(tester, 'Los pares están en los planos del componente.')));
    expect(y(tester, 'Ante cualquier incidencia, sustituir.'), greaterThan(y(tester, 'Apretar.')));
  });

  testWidgets('el pie de una figura es su título: no sale también como encabezado del procedimiento', (tester) async {
    // lo que antes se duplicaba (GC3.01.01): el pie "Puertas del armario BT" hacía de título de fase
    sembrar([
      ('paso', 1, null, 'Desbloquear los cierres.'),
    ]);
    db.execute('''
      INSERT INTO actividad_imagen VALUES
        ('DF3.01.01','procedimiento',0,'a.jpg',1000,572,'Puertas del armario BT','[{"n":"01","nombre":"Puertas"}]',0)
    ''');
    await abrir(tester);

    expect(find.text('Puertas del armario BT'), findsOneWidget);
  });

  group('figuras de la zona de trabajo', () {
    void sembrarZonas(int cuantas) {
      for (var i = 0; i < cuantas; i++) {
        db.execute(
          "INSERT INTO actividad_imagen VALUES ('DF3.01.01','zonas',?,?,1000,500,?,null,null)",
          [i, 'z$i.jpg', 'Zona $i'],
        );
      }
    }

    testWidgets('hasta dos figuras van una debajo de otra', (tester) async {
      sembrarZonas(2);
      await abrir(tester);

      expect(x(tester, 'Zona 1'), x(tester, 'Zona 0'));
      expect(y(tester, 'Zona 1'), greaterThan(y(tester, 'Zona 0')));
    });

    testWidgets('con más de dos se reparten en dos columnas (la siguiente va a la derecha)', (tester) async {
      sembrarZonas(5);
      await abrir(tester);

      expect(y(tester, 'Zona 1'), y(tester, 'Zona 0'), reason: 'la segunda, a la derecha de la primera');
      expect(x(tester, 'Zona 1'), greaterThan(x(tester, 'Zona 0') + 300));
      expect(y(tester, 'Zona 2'), greaterThan(y(tester, 'Zona 0')), reason: 'la tercera abre la fila siguiente');
      expect(x(tester, 'Zona 2'), x(tester, 'Zona 0'));
      expect(y(tester, 'Zona 3'), y(tester, 'Zona 2'));
      expect(find.textContaining('Zona '), findsNWidgets(5 + 1), reason: 'las 5 figuras y el rótulo de la sección');
    });

    testWidgets('en una ventana estrecha, aunque sean más de dos, vuelven a una columna', (tester) async {
      sembrarZonas(4);
      await abrir(tester, ancho: 700);

      expect(x(tester, 'Zona 1'), x(tester, 'Zona 0'));
      expect(y(tester, 'Zona 1'), greaterThan(y(tester, 'Zona 0')));
    });
  });
}
