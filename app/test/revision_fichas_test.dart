// revision_fichas.dart (R20/U15): guardarFicha persiste el cuerpo y el
// estado de revisión directamente en `ficha_sistema` -- diff.js (Fase A)
// ya traspasa esas dos columnas intactas entre re-extracciones, así que
// esto es lo único que faltaba: que la app pudiera escribirlas.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;

import 'package:consulta_s336_app/curacion/revision_fichas.dart';
import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() => db = openMinimalTestDb());
  tearDown(() => db.dispose());

  void seedSistemaConFichaBorrador() {
    db.execute("INSERT INTO sistema VALUES ('FD5', 'Reductor', null, null)");
    db.execute("INSERT INTO ficha_sistema VALUES ('FD5', '', 0)");
  }

  test('guardarFicha marca revisado:true y persiste el cuerpo (INSERT OR REPLACE sobre una ficha existente)', () {
    seedSistemaConFichaBorrador();

    guardarFicha(db, 'FD5', cuerpo: 'Reductor de dos etapas...', revisado: true);

    final detalle = getSistemaDetalle(db, 'FD5')!;
    expect(detalle.ficha!.revisado, true);
    expect(detalle.ficha!.cuerpo, 'Reductor de dos etapas...');
  });

  test('guardarFicha sin fila previa la crea (defensivo -- el pipeline siempre la crea, pero no se asume)', () {
    db.execute("INSERT INTO sistema VALUES ('FD5', 'Reductor', null, null)");

    guardarFicha(db, 'FD5', cuerpo: 'Primera síntesis', revisado: false);

    final detalle = getSistemaDetalle(db, 'FD5')!;
    expect(detalle.ficha!.revisado, false);
    expect(detalle.ficha!.cuerpo, 'Primera síntesis');
  });

  test('guardarFicha puede volver a marcar como borrador tras haber sido revisada', () {
    seedSistemaConFichaBorrador();
    guardarFicha(db, 'FD5', cuerpo: 'texto', revisado: true);
    guardarFicha(db, 'FD5', cuerpo: 'texto corregido', revisado: false);

    final detalle = getSistemaDetalle(db, 'FD5')!;
    expect(detalle.ficha!.revisado, false);
    expect(detalle.ficha!.cuerpo, 'texto corregido');
  });
}
