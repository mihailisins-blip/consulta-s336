// Smoke tests de main.dart: la app real (ConsultaS336App), con el resultado
// de cargar la carpeta de datos ya construido en vez de una ruta real.
//
// Deliberadamente NO se usa E/S ASÍNCRONA de archivos aquí (a diferencia de
// data_folder_test.dart, que sí la prueba): combinar dart:io async dentro de
// un FutureBuilder con pumpAndSettle() no es fiable en un widget test -- se
// queda colgado indefinidamente en vez de fallar rápido. Comprobado de
// nuevo (2026-09-23) que el problema no es solo dentro del FutureBuilder --
// incluso `await Directory.systemTemp.createTemp(...)` + `File.writeAsBytes`
// en el CUERPO del test, antes de pumpWidget, cuelga `pumpAndSettle()` más
// abajo (aislado con `--plain-name`: sin la E/S async pasa en ~1s, con ella
// nunca termina). El caso "listo" SÍ abre el data.sqlite real de fixtures/
// (HubScreen lo necesita de verdad para consultar) -- lo que se inyecta es
// el *resultado* de loadDataFolder, no la carga de archivos en sí. El caso
// "data.sqlite corrupto" usa `pubspec.yaml` (ya existe, ruta síncrona) como
// archivo "no es una base de datos válida" en vez de crear uno nuevo.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:consulta_s336_app/data/data_folder.dart';
import 'package:consulta_s336_app/main.dart';

import 'helpers/real_db.dart';

const _manifestBase = (
  buildDate: '2026-09-01T00:00:00.000Z',
  sources: <String, dynamic>{},
);

void main() {
  testWidgets(
    'con una carpeta de datos válida, la app llega al hub (búsqueda + accesos)',
    (tester) async {
      final result = DataFolderReady(
        dataDir: r'C:\ruta\a\data',
        dbPath: realFixtureDbPath,
        manifest: DataManifest(
          schemaVersion: kExpectedSchemaVersion,
          dataFolderVersion: 5,
          buildDate: _manifestBase.buildDate,
          sources: _manifestBase.sources,
          counts: const {'actividades': 438},
          avisos: const [],
        ),
      );

      await tester.pumpWidget(ConsultaS336App(resultOverride: result));
      await tester.pumpAndSettle();

      expect(find.text('Consulta S336'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Por sistema'), findsOneWidget);
      expect(find.text('Por ciclo'), findsOneWidget);
      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('Últimas consultadas'), findsOneWidget);
    },
  );

  testWidgets(
    'sin carpeta de datos, muestra el aviso con la ruta esperada',
    (tester) async {
      const result = DataFolderMissing(r'C:\ruta\que\no\existe\data');

      await tester.pumpWidget(const ConsultaS336App(resultOverride: result));
      await tester.pumpAndSettle();

      expect(find.textContaining('No se encuentra'), findsOneWidget);
      expect(find.textContaining(r'C:\ruta\que\no\existe\data'), findsOneWidget);
    },
  );

  testWidgets(
    'con schema_version incompatible, muestra el aviso de incompatibilidad y no llega al hub (AE6)',
    (tester) async {
      final result = DataFolderVersionMismatch(
        DataManifest(
          schemaVersion: 99,
          dataFolderVersion: 1,
          buildDate: _manifestBase.buildDate,
          sources: _manifestBase.sources,
          counts: const {},
          avisos: const [],
        ),
      );

      await tester.pumpWidget(ConsultaS336App(resultOverride: result));
      await tester.pumpAndSettle();

      expect(find.textContaining('incompatible'), findsOneWidget);
      expect(find.textContaining('v99'), findsOneWidget);
      expect(find.text('Consulta S336'), findsNothing);
    },
  );

  testWidgets(
    'con una carpeta de datos dañada, muestra el motivo',
    (tester) async {
      const result = DataFolderCorrupt('manifest.json no es JSON válido');

      await tester.pumpWidget(const ConsultaS336App(resultOverride: result));
      await tester.pumpAndSettle();

      expect(find.textContaining('dañada'), findsOneWidget);
      expect(find.textContaining('manifest.json no es JSON válido'), findsOneWidget);
    },
  );

  testWidgets(
    'con manifest.json válido pero data.sqlite corrupto, muestra el aviso en vez de crashear',
    (tester) async {
      // sqlite3.open() no lanza por sí solo para un archivo corrupto --
      // SQLite lo abre de forma perezosa; hace falta un archivo real que
      // exista pero no sea una base de datos válida para ejercitar de
      // verdad el try/catch de _buildReady (comprobado aparte con un
      // script suelto: hasta la apertura + un SELECT 1 dispara
      // SqliteException(26) recién en la query, no en open()). Se usa
      // `pubspec.yaml` (ya existe, cwd síncrono) en vez de crear un
      // archivo nuevo -- ver la nota de cabecera: `createTemp`/
      // `writeAsBytes` colgaban `pumpAndSettle()` más abajo, aunque esa
      // E/S corriera antes de pumpWidget, no dentro de un FutureBuilder.
      final badDbPath = p.join(Directory.current.path, 'pubspec.yaml');

      final result = DataFolderReady(
        dataDir: Directory.current.path,
        dbPath: badDbPath,
        manifest: DataManifest(
          schemaVersion: kExpectedSchemaVersion,
          dataFolderVersion: 1,
          buildDate: _manifestBase.buildDate,
          sources: _manifestBase.sources,
          counts: const {},
          avisos: const [],
        ),
      );

      await tester.pumpWidget(ConsultaS336App(resultOverride: result));
      await tester.pumpAndSettle();

      expect(find.textContaining('dañada'), findsOneWidget);
      expect(find.textContaining('No se pudo abrir data.sqlite'), findsOneWidget);
      expect(find.text('Consulta S336'), findsNothing);
    },
  );
}
