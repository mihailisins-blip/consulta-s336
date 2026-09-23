// Smoke tests de main.dart: la app real (ConsultaS336App), con el resultado
// de cargar la carpeta de datos ya construido en vez de una ruta real.
//
// Deliberadamente NO se usa E/S real de archivos aquí (a diferencia de
// data_folder_test.dart, que sí la prueba): combinar dart:io real dentro de
// un FutureBuilder con pumpAndSettle() no es fiable en un widget test -- se
// queda colgado indefinidamente en vez de fallar rápido. Estos tests solo
// prueban que la UI renderiza cada DataFolderResult correctamente.

import 'package:flutter_test/flutter_test.dart';

import 'package:consulta_s336_app/data/data_folder.dart';
import 'package:consulta_s336_app/main.dart';

const _manifestBase = (
  buildDate: '2026-09-01T00:00:00.000Z',
  sources: <String, dynamic>{},
);

void main() {
  testWidgets(
    'con una carpeta de datos válida, la app llega a la pantalla de "cargada" (AE6, caso compatible)',
    (tester) async {
      final result = DataFolderReady(
        dataDir: r'C:\ruta\a\data',
        dbPath: r'C:\ruta\a\data\data.sqlite',
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

      expect(find.textContaining('v5 cargada'), findsOneWidget);
      expect(find.textContaining('438'), findsOneWidget);
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
    'con schema_version incompatible, muestra el aviso de incompatibilidad y no la de "cargada" (AE6)',
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
      expect(find.textContaining('cargada'), findsNothing);
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
}
