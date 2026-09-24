// Fusión de dos entradas del catálogo en una (R22/KTD5/U15): el curador
// elige una superviviente y una perdedora; todos los enlaces
// actividad<->material y los alias de la perdedora pasan a la
// superviviente, y la perdedora se borra. Se guarda un registro en
// `fusion_catalogo` (esquema v4) para poder deshacer la fusión más tarde.
//
// `actividad_material` y `catalogo_alias` no tienen clave primaria propia,
// así que el registro de deshacer usa el `rowid` implícito de SQLite para
// identificar exactamente qué filas se movieron -- reasignarlas de vuelta
// en `deshacerFusion` es entonces un UPDATE directo por rowid, sin
// ambigüedad aunque otra fila con el mismo contenido se añadiera después
// a la superviviente.
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

class FusionCatalogoException implements Exception {
  final String mensaje;
  FusionCatalogoException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Una fusión aún no deshecha, para ofrecer "deshacer" en la UI (R22).
class FusionPendiente {
  final int id;
  final String supervivienteId;
  final String? supervivienteDescripcion;
  final String? perdedorDescripcion;
  final String fecha;
  const FusionPendiente({
    required this.id,
    required this.supervivienteId,
    required this.supervivienteDescripcion,
    required this.perdedorDescripcion,
    required this.fecha,
  });
}

/// Fusiones que todavía se pueden deshacer, más recientes primero.
List<FusionPendiente> listFusionesPendientes(Database db) {
  final rows = db.select('''
    SELECT f.id, f.superviviente_id, f.perdedor_json, f.fecha, c.descripcion AS superviviente_descripcion
    FROM fusion_catalogo f
    LEFT JOIN catalogo c ON c.id = f.superviviente_id
    WHERE f.deshecha = 0
    ORDER BY f.id DESC
  ''');
  return [
    for (final r in rows)
      FusionPendiente(
        id: r['id'] as int,
        supervivienteId: r['superviviente_id'] as String,
        supervivienteDescripcion: r['superviviente_descripcion'] as String?,
        perdedorDescripcion:
            (jsonDecode(r['perdedor_json'] as String) as Map)['catalogo']['descripcion'] as String?,
        fecha: r['fecha'] as String,
      ),
  ];
}

/// Fusiona [perdedorId] en [supervivienteId]: reasigna sus enlaces de
/// actividad y sus alias, añade su descripción como alias de la
/// superviviente (para no perder cómo se conocía), la borra del catálogo
/// y de su fila en el índice de búsqueda, y deja un registro para poder
/// deshacer la fusión.
void fusionarCatalogo(Database db, {required String supervivienteId, required String perdedorId}) {
  if (supervivienteId == perdedorId) {
    throw FusionCatalogoException('no se puede fusionar una entrada consigo misma');
  }
  final supervivienteRows = db.select('SELECT 1 FROM catalogo WHERE id = ?', [supervivienteId]);
  if (supervivienteRows.isEmpty) {
    throw FusionCatalogoException('entrada superviviente desconocida: $supervivienteId');
  }
  final perdedorRows = db.select('SELECT * FROM catalogo WHERE id = ?', [perdedorId]);
  if (perdedorRows.isEmpty) {
    throw FusionCatalogoException('entrada perdedora desconocida: $perdedorId');
  }
  final perdedor = perdedorRows.first;

  db.execute('BEGIN');
  try {
    final enlaceRowids = [
      for (final r in db.select('SELECT rowid AS rid FROM actividad_material WHERE catalogo_id = ?', [perdedorId]))
        r['rid'] as int,
    ];
    final aliasRowids = [
      for (final r in db.select('SELECT rowid AS rid FROM catalogo_alias WHERE catalogo_id = ?', [perdedorId]))
        r['rid'] as int,
    ];

    final ins = db.prepare(
      'INSERT INTO fusion_catalogo (superviviente_id, perdedor_id, perdedor_json, fecha, deshecha) VALUES (?,?,?,?,0)',
    );
    ins.execute([
      supervivienteId,
      perdedorId,
      jsonEncode({
        'catalogo': Map<String, dynamic>.from(perdedor),
        'enlace_rowids': enlaceRowids,
        'alias_rowids': aliasRowids,
      }),
      DateTime.now().toIso8601String(),
    ]);
    ins.dispose();

    for (final rid in enlaceRowids) {
      db.execute('UPDATE actividad_material SET catalogo_id = ? WHERE rowid = ?', [supervivienteId, rid]);
    }
    for (final rid in aliasRowids) {
      db.execute('UPDATE catalogo_alias SET catalogo_id = ? WHERE rowid = ?', [supervivienteId, rid]);
    }
    if ((perdedor['descripcion'] as String?)?.isNotEmpty ?? false) {
      db.execute('INSERT INTO catalogo_alias (catalogo_id, alias) VALUES (?, ?)', [
        supervivienteId,
        perdedor['descripcion'] as String,
      ]);
    }
    db.execute('DELETE FROM catalogo WHERE id = ?', [perdedorId]);
    // La fila de búsqueda de la perdedora ya no lleva a ningún sitio --
    // limitación conocida: si se deshace la fusión, esta entrada queda sin
    // indexar hasta la siguiente re-extracción (el índice FTS solo lo
    // escribe el pipeline, no la app).
    db.execute("DELETE FROM busqueda WHERE tipo = 'catalogo' AND ref = ?", [perdedorId]);

    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

/// Deshace la fusión con id [fusionId]: restaura la entrada de catálogo
/// perdedora tal y como estaba y re-apunta sus enlaces y alias originales
/// (por rowid) de vuelta a ella. Falla si la fusión ya estaba deshecha o
/// si `fusionId` no existe.
void deshacerFusion(Database db, int fusionId) {
  final rows = db.select('SELECT * FROM fusion_catalogo WHERE id = ?', [fusionId]);
  if (rows.isEmpty) {
    throw FusionCatalogoException('fusión desconocida: $fusionId');
  }
  final fusion = rows.first;
  if ((fusion['deshecha'] as int) != 0) {
    throw FusionCatalogoException('la fusión $fusionId ya estaba deshecha');
  }

  final snapshot = jsonDecode(fusion['perdedor_json'] as String) as Map<String, dynamic>;
  final catalogoPerdedor = (snapshot['catalogo'] as Map).cast<String, dynamic>();
  final enlaceRowids = (snapshot['enlace_rowids'] as List).cast<int>();
  final aliasRowids = (snapshot['alias_rowids'] as List).cast<int>();
  final perdedorId = fusion['perdedor_id'] as String;

  db.execute('BEGIN');
  try {
    db.execute(
      'INSERT INTO catalogo (id,codigo_erp,descripcion,fabricante,referencia,unidad,tipo,fuente) VALUES (?,?,?,?,?,?,?,?)',
      [
        catalogoPerdedor['id'],
        catalogoPerdedor['codigo_erp'],
        catalogoPerdedor['descripcion'],
        catalogoPerdedor['fabricante'],
        catalogoPerdedor['referencia'],
        catalogoPerdedor['unidad'],
        catalogoPerdedor['tipo'],
        catalogoPerdedor['fuente'],
      ],
    );
    for (final rid in enlaceRowids) {
      db.execute('UPDATE actividad_material SET catalogo_id = ? WHERE rowid = ?', [perdedorId, rid]);
    }
    for (final rid in aliasRowids) {
      db.execute('UPDATE catalogo_alias SET catalogo_id = ? WHERE rowid = ?', [perdedorId, rid]);
    }
    db.execute('UPDATE fusion_catalogo SET deshecha = 1 WHERE id = ?', [fusionId]);
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}
