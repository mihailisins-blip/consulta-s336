// Acceso a `data.sqlite` (KTD3 / R14 / R16). Fase B (esta) es solo lectura
// -- la edición del curador (tabla `overrides`) es Fase C / U14, aún no
// construida; abrir en modo lectura evita bloqueos accidentales y coincide
// con lo que la app hace hoy: los técnicos solo consultan (R18).

import 'package:sqlite3/sqlite3.dart';

/// Abre `data.sqlite` en modo solo lectura.
///
/// El `Database` devuelto es responsabilidad de quien lo abre: hay que
/// llamar a `.dispose()` cuando ya no se necesite (p. ej. al cerrar la app).
Database openDataDb(String dbPath) {
  return sqlite3.open(dbPath, mode: OpenMode.readOnly);
}
