// edit_mode.dart (U14/R18): el desbloqueo de edición es un fichero
// centinela dentro de la carpeta de datos -- ausente en la copia de un
// técnico, presente en la del curador.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:consulta_s336_app/curacion/edit_mode.dart';

import 'helpers/fixture_db.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('edit-mode-'));
  tearDown(() async => tmp.delete(recursive: true));

  test('sin el centinela, no es modo edición (copia de técnico)', () async {
    final dataDir = await makeFakeDataDir(parent: tmp);
    expect(esModoEdicion(dataDir.path), false);
  });

  test('con el centinela presente, es modo edición (copia del curador)', () async {
    final dataDir = await makeFakeDataDir(parent: tmp);
    await File(p.join(dataDir.path, centinelaCurador)).writeAsString('');
    expect(esModoEdicion(dataDir.path), true);
  });
}
