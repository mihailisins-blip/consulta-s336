// Ediciones del curador (U14/R19/KTD7): la tabla `overrides` ya existe en el
// esquema desde Fase A (pipeline/src/build/sqlite-writer.js) porque
// diff.js (U7) ya la traspasa intacta entre re-extracciones -- U14 es quien
// primero LEE y ESCRIBE en ella desde la app. Cada campo mostrado en la UI
// se compone como `override ?? extraído`; la re-extracción nunca toca esta
// tabla (eso ya lo garantiza diff.js).
import 'package:sqlite3/sqlite3.dart';

/// Valor editado por el curador para `entidad.id.campo`, o null si no hay
/// override -- en cuyo caso la vista debe usar el valor extraído.
String? overrideValor(Database db, String entidad, String id, String campo) {
  final rows = db.select(
    'SELECT valor FROM overrides WHERE entidad = ? AND id = ? AND campo = ?',
    [entidad, id, campo],
  );
  return rows.isEmpty ? null : rows.first['valor'] as String?;
}

/// Guarda (o reemplaza) el override de `entidad.id.campo`.
void guardarOverride(Database db, String entidad, String id, String campo, String valor) {
  db.execute(
    'INSERT OR REPLACE INTO overrides (entidad, id, campo, valor, actualizado) VALUES (?,?,?,?,?)',
    [entidad, id, campo, valor, DateTime.now().toIso8601String()],
  );
}
