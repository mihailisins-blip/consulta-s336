// Revisión de lo que deja una re-extracción (R21/KTD7): diff.js (Fase A)
// registra en `cambio_pendiente` cada campo extraído que cambió en el
// origen respecto a la carpeta anterior, y tanto join.js como diff.js
// registran en `incidencia_extraccion` lo que no se pudo enlazar por
// código (KTD4) o los overrides que se quedaron sin destino. Hasta ahora
// la app no leía ninguna de las dos -- el curador tenía que abrir
// data.sqlite a mano para revisarlas.
//
// `cambio_pendiente` no tiene clave primaria propia, así que, igual que
// fusion_catalogo.dart, se identifica cada fila por el `rowid` implícito
// de SQLite. `incidencia_extraccion` no tiene columna de "revisado" (y
// añadirla sería un cambio de esquema): se lista solo para consulta, y
// cada re-extracción la vuelve a calcular entera de todos modos.
import 'package:sqlite3/sqlite3.dart';

/// Una diferencia de origen detectada por la re-extracción (una fila de
/// `cambio_pendiente`).
class CambioPendiente {
  final int rowid;
  final String entidad;

  /// Clave de la fila afectada tal y como la escribe diff.js: el código de
  /// actividad/sistema, el id de catálogo, o `actividad / catalogo_id` para
  /// `actividad_material` (clave compuesta unida con ' / ').
  final String id;
  final String campo;
  final String? valorAntes;
  final String? valorDespues;
  final bool revisado;

  const CambioPendiente({
    required this.rowid,
    required this.entidad,
    required this.id,
    required this.campo,
    required this.valorAntes,
    required this.valorDespues,
    required this.revisado,
  });

  /// Código de la actividad a la que afecta el cambio, si afecta a una
  /// (para poder abrir su detalle desde la revisión); null para cambios
  /// de sistema o de catálogo.
  String? get actividadCodigo => switch (entidad) {
    'actividad' || 'actividad_lote' => id,
    'actividad_material' => id.split(' / ').first,
    _ => null,
  };
}

/// Una fila de `incidencia_extraccion`.
class Incidencia {
  final String tipo;
  final String ref;
  final String? detalle;
  const Incidencia({required this.tipo, required this.ref, required this.detalle});
}

/// Cambios de origen, los no revisados primero y, dentro de cada grupo,
/// por entidad e id. Con [incluirRevisados] a false solo devuelve los
/// pendientes.
List<CambioPendiente> listCambiosPendientes(Database db, {bool incluirRevisados = false}) {
  final rows = db.select('''
    SELECT rowid AS rid, entidad, id, campo, valor_antes, valor_despues, revisado
    FROM cambio_pendiente
    ${incluirRevisados ? '' : 'WHERE revisado = 0'}
    ORDER BY revisado, entidad, id, campo
  ''');
  return [
    for (final r in rows)
      CambioPendiente(
        rowid: r['rid'] as int,
        entidad: r['entidad'] as String,
        id: r['id'] as String,
        campo: r['campo'] as String,
        valorAntes: r['valor_antes'] as String?,
        valorDespues: r['valor_despues'] as String?,
        revisado: (r['revisado'] as int? ?? 0) != 0,
      ),
  ];
}

/// Número de cambios de origen aún sin revisar (para el aviso del hub).
int contarCambiosSinRevisar(Database db) =>
    db.select('SELECT count(*) AS c FROM cambio_pendiente WHERE revisado = 0').first['c'] as int;

/// Marca (o desmarca) como revisado el cambio con [rowid].
void marcarCambioRevisado(Database db, int rowid, {bool revisado = true}) {
  db.execute('UPDATE cambio_pendiente SET revisado = ? WHERE rowid = ?', [revisado ? 1 : 0, rowid]);
}

/// Marca como revisados todos los cambios pendientes de una vez.
void marcarTodosRevisados(Database db) {
  db.execute('UPDATE cambio_pendiente SET revisado = 1 WHERE revisado = 0');
}

/// Incidencias de extracción, agrupables por tipo (ordenadas por tipo y ref).
List<Incidencia> listIncidencias(Database db) {
  final rows = db.select('SELECT tipo, ref, detalle FROM incidencia_extraccion ORDER BY tipo, ref');
  return [
    for (final r in rows)
      Incidencia(
        tipo: r['tipo'] as String,
        ref: r['ref'] as String,
        detalle: r['detalle'] as String?,
      ),
  ];
}

/// true si [codigo] es una actividad de esta carpeta de datos -- para
/// ofrecer abrir su detalle solo cuando de verdad existe (p. ej. una
/// incidencia `actividad-plan-sin-vmi` nombra un código que no tiene fila).
bool existeActividad(Database db, String codigo) =>
    db.select('SELECT 1 FROM actividad WHERE codigo = ?', [codigo]).isNotEmpty;
