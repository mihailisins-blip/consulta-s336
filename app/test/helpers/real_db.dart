// Abre el data.sqlite REAL de test/fixtures/ (ver fixtures/README.md) --
// reutilizable por cualquier test de la app que necesite consultar contra
// contenido real en vez de una base vacía o sintética.

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Ruta al data.sqlite real de fixtures, relativa a la raíz del paquete
/// (donde `flutter test` se ejecuta). Corrida real completa contra Z: del
/// 2026-09-10 -- esquema v1 (sin actividad_lote ni actividad_nivel para
/// RDH; ver fixtures/README.md).
String get realFixtureDbPath =>
    p.join('test', 'fixtures', 'data.sqlite');

/// Abre el data.sqlite real (grande, esquema v1) de fixtures en solo lectura.
Database openRealFixtureDb() =>
    sqlite3.open(realFixtureDbPath, mode: OpenMode.readOnly);

/// Ruta al fixture real pequeño (esquema v3, generado por
/// pipeline/scripts/gen-app-fixture.mjs a partir de los mismos VMI/XLSX
/// reales que usan los tests de pipeline/ -- ver fixtures/README.md).
String get realSmallFixtureDbPath =>
    p.join('test', 'fixtures', 'data-lotes.sqlite');

/// Abre el fixture real pequeño (esquema v3, con actividad_lote y
/// actividad.seguridad) en solo lectura.
Database openRealSmallFixtureDb() =>
    sqlite3.open(realSmallFixtureDbPath, mode: OpenMode.readOnly);
