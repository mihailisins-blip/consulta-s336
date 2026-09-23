// Construye una carpeta de datos falsa en un directorio temporal: un
// manifest.json real (misma forma que pipeline/src/build/manifest.js) y un
// data.sqlite genuino y válido (creado con sqlite3, no un archivo vacío).
//
// Reutilizable por data_folder_test.dart hoy, y por los futuros tests de
// Fase C (overrides, revisión de fichas) que necesiten una carpeta de datos
// de partida sin depender del CLI Node de pipeline/.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/data/data_folder.dart';

/// Crea una carpeta de datos válida (manifest + data.sqlite reales) dentro
/// de un subdirectorio temporal nuevo bajo [parent].
Future<Directory> makeFakeDataDir({
  required Directory parent,
  int schemaVersion = kExpectedSchemaVersion,
  int dataFolderVersion = 1,
  Map<String, dynamic> counts = const {},
  List<String> avisos = const [],
}) async {
  final dir = await parent.createTemp('data-');
  await File(p.join(dir.path, 'manifest.json')).writeAsString(
    jsonEncode({
      'schema_version': schemaVersion,
      'data_folder_version': dataFolderVersion,
      'build_date': DateTime.now().toIso8601String(),
      'generator': 'test-fixture',
      'sources': <String, dynamic>{},
      'counts': counts,
      'avisos': avisos,
    }),
  );
  // data.sqlite real y válido, no un archivo vacío -- sqlite3.open() falla
  // en un archivo que exista pero no sea un SQLite genuino.
  final db = sqlite3.open(p.join(dir.path, 'data.sqlite'));
  db.dispose();
  return dir;
}
