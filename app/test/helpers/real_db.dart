// Abre el data.sqlite REAL de test/fixtures/ (ver fixtures/README.md) --
// reutilizable por cualquier test de la app que necesite consultar contra
// contenido real en vez de una base vacía o sintética.

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Ruta al data.sqlite real de fixtures, relativa a la raíz del paquete
/// (donde `flutter test` se ejecuta).
String get realFixtureDbPath =>
    p.join('test', 'fixtures', 'data.sqlite');

/// Abre el data.sqlite real de fixtures en solo lectura.
Database openRealFixtureDb() =>
    sqlite3.open(realFixtureDbPath, mode: OpenMode.readOnly);
