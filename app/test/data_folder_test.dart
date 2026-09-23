import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:consulta_s336_app/data/data_folder.dart';

import 'helpers/fixture_db.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cs336-datafolder-');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('carpeta de datos ausente -> DataFolderMissing con la ruta esperada', () async {
    final missingDir = p.join(tmp.path, 'no-existe');
    final result = await loadDataFolder(missingDir);
    expect(result, isA<DataFolderMissing>());
    expect((result as DataFolderMissing).expectedPath, missingDir);
  });

  test(
    'schema_version incompatible -> DataFolderVersionMismatch, no abre la BD (AE6/R25)',
    () async {
      final dir = await makeFakeDataDir(
        parent: tmp,
        schemaVersion: kExpectedSchemaVersion + 1,
      );
      final result = await loadDataFolder(dir.path);
      expect(result, isA<DataFolderVersionMismatch>());
      expect(
        (result as DataFolderVersionMismatch).manifest.schemaVersion,
        kExpectedSchemaVersion + 1,
      );
    },
  );

  test('schema_version compatible -> DataFolderReady con la ruta de la BD', () async {
    final dir = await makeFakeDataDir(
      parent: tmp,
      dataFolderVersion: 3,
      counts: {'actividades': 438},
    );
    final result = await loadDataFolder(dir.path);
    expect(result, isA<DataFolderReady>());
    final ready = result as DataFolderReady;
    expect(ready.manifest.dataFolderVersion, 3);
    expect(ready.manifest.counts['actividades'], 438);
    expect(File(ready.dbPath).existsSync(), true);
  });

  test('manifest.json corrupto (no es JSON) -> DataFolderCorrupt, no lanza', () async {
    final dir = await tmp.createTemp('data-corrupt-');
    await File(p.join(dir.path, 'manifest.json')).writeAsString('esto no es JSON');
    await File(p.join(dir.path, 'data.sqlite')).writeAsBytes(const []);
    final result = await loadDataFolder(dir.path);
    expect(result, isA<DataFolderCorrupt>());
  });

  test(
    'manifest.json con schema_version no numérico -> DataFolderCorrupt, no lanza',
    () async {
      final dir = await tmp.createTemp('data-badshape-');
      await File(p.join(dir.path, 'manifest.json')).writeAsString(
        '{"schema_version": "uno", "data_folder_version": 1}',
      );
      await File(p.join(dir.path, 'data.sqlite')).writeAsBytes(const []);
      final result = await loadDataFolder(dir.path);
      expect(result, isA<DataFolderCorrupt>());
    },
  );

  test('data.sqlite ausente aunque manifest.json exista -> DataFolderMissing', () async {
    final dir = await tmp.createTemp('data-nodb-');
    await File(p.join(dir.path, 'manifest.json')).writeAsString(
      '{"schema_version": $kExpectedSchemaVersion, "data_folder_version": 1}',
    );
    final result = await loadDataFolder(dir.path);
    expect(result, isA<DataFolderMissing>());
  });

  test('resolveDataDir sin override -> junto al ejecutable (R24)', () {
    final dataDir = resolveDataDir();
    expect(p.basename(dataDir), 'datos');
    expect(p.dirname(dataDir), p.dirname(Platform.resolvedExecutable));
  });

  test('resolveDataDir con allowDebugOverride:false ignora la variable de entorno', () {
    // CONSULTA_S336_DATA_DIR no está definida en esta corrida de test, así
    // que esto solo confirma la ruta por defecto -- ver también el test de
    // arriba. El propio mecanismo de --dart-define no es override-able en
    // tiempo de ejecución de test sin recompilar, así que el contrato real
    // (solo debug) se aplica en main.dart, no aquí.
    final dataDir = resolveDataDir(allowDebugOverride: false);
    expect(p.basename(dataDir), 'datos');
  });
}
