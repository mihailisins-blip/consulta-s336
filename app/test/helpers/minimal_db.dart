// Base de datos en memoria con SOLO las tablas que lib/data/queries.dart
// necesita, para probar la lógica de las consultas (acumulación por
// programa, desglose por lote) de forma determinista, sin depender de si
// el fixture real de turno (test/fixtures/) da la casualidad de contener
// un caso que la ejercite. Complementa a real_db.dart -- no lo sustituye:
// search_service_test.dart y otros siguen probando contra contenido real.

import 'package:sqlite3/sqlite3.dart';

Database openMinimalTestDb() {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE sistema (codigo TEXT PRIMARY KEY, nombre TEXT, carpeta_manual TEXT, fuente_nombre TEXT);
    CREATE TABLE manual (id INTEGER PRIMARY KEY, sistema_codigo TEXT, rel_path TEXT);
    CREATE TABLE ficha_sistema (sistema_codigo TEXT PRIMARY KEY, cuerpo TEXT, revisado INTEGER DEFAULT 0);
    CREATE TABLE nivel_ciclo (
      codigo TEXT PRIMARY KEY, programa TEXT, tipo TEXT, orden INTEGER,
      descripcion TEXT, km_num INTEGER, intervalo_h INTEGER
    );
    CREATE TABLE lote (nivel TEXT, codigo TEXT);
    CREATE TABLE actividad_nivel (actividad_codigo TEXT, nivel_codigo TEXT);
    CREATE TABLE actividad_lote (actividad_codigo TEXT, lote_codigo TEXT);
    CREATE TABLE actividad (codigo TEXT PRIMARY KEY, sistema_codigo TEXT);
  ''');
  return db;
}
