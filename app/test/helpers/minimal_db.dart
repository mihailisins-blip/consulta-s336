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
    CREATE TABLE actividad (
      codigo TEXT PRIMARY KEY, sistema_codigo TEXT, vmi_rel_path TEXT,
      sin_extraer INTEGER DEFAULT 0, motivo TEXT, componente TEXT, actividad_tipo TEXT,
      operacion TEXT, frecuencia TEXT, edicion TEXT, descripcion_plan TEXT,
      zonas_trabajo TEXT, seguridad TEXT
    );
    CREATE TABLE actividad_paso (actividad_codigo TEXT, orden INTEGER, fase TEXT, paso_n INTEGER, texto TEXT);
    CREATE TABLE catalogo (
      id TEXT PRIMARY KEY, codigo_erp TEXT, descripcion TEXT, fabricante TEXT,
      referencia TEXT, unidad TEXT, tipo TEXT, fuente TEXT
    );
    CREATE TABLE actividad_material (
      actividad_codigo TEXT, catalogo_id TEXT, cant TEXT, cant_num REAL,
      ud TEXT, uso TEXT, reserva INTEGER, fuente TEXT
    );
    CREATE TABLE manual_toc (manual_id INTEGER, orden INTEGER, titulo TEXT, pagina INTEGER, nivel INTEGER);
  ''');
  return db;
}
