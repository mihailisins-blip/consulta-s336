// Figuras del VMI (esquema v5): el pipeline no extrae la imagen, solo dónde
// está -- página y recuadro en puntos PDF -- dentro del VMI copiado a
// `<dataDir>/pdfs/vmi/`. La app la recorta del PDF al mostrarla
// (detalle/figura_vmi.dart), así que vale igual para un raster que para un
// dibujo vectorial.
import 'package:sqlite3/sqlite3.dart';

/// Una fila de la leyenda bajo la figura: el número o letra que señala la
/// figura y el elemento al que corresponde ("002", "Cuerpo de acoplamiento").
class LeyendaEntrada {
  final String codigo;
  final String texto;
  const LeyendaEntrada({required this.codigo, required this.texto});
}

class ActividadFigura {
  /// 'zonas' (sección 3 del VMI) o 'procedimiento' (sección 4).
  final String seccion;

  /// `orden` (índice en `ActividadDetalle.pasos`) del primer paso que va
  /// después de la figura; null si va tras el último paso (o es de zonas).
  final int? antesPasoOrden;

  /// Página del VMI, 1-based.
  final int pagina;

  /// Recuadro en puntos PDF, origen abajo-izquierda. x0/x1 null = todo el
  /// ancho útil de la página.
  final double? x0;
  final double y0;
  final double? x1;
  final double y1;
  final String? pie;
  final List<LeyendaEntrada> leyenda;

  const ActividadFigura({
    required this.seccion,
    required this.antesPasoOrden,
    required this.pagina,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.pie,
    this.leyenda = const [],
  });
}

/// Figuras de [codigo] en orden de documento. Devuelve [] si la carpeta de
/// datos no tiene la tabla (no debería pasar con el esquema v5 exigido, pero
/// los fixtures de test más antiguos no la traen).
List<ActividadFigura> getActividadFiguras(Database db, String codigo) {
  bool hayTabla(String nombre) =>
      db.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [nombre]).isNotEmpty;
  if (!hayTabla('actividad_figura')) return const [];
  final rows = db.select(
    '''
    SELECT orden, seccion, antes_paso_orden, pagina, x0, y0, x1, y1, pie
    FROM actividad_figura WHERE actividad_codigo = ? ORDER BY orden
    ''',
    [codigo],
  );
  // La leyenda llegó después que las figuras: una carpeta v5 extraída antes
  // no la trae, y entonces las figuras se muestran sin ella.
  final leyendas = <int, List<LeyendaEntrada>>{};
  if (hayTabla('actividad_figura_leyenda')) {
    final leyRows = db.select(
      '''
      SELECT figura_orden, codigo, texto FROM actividad_figura_leyenda
      WHERE actividad_codigo = ? ORDER BY figura_orden, orden
      ''',
      [codigo],
    );
    for (final r in leyRows) {
      leyendas
          .putIfAbsent(r['figura_orden'] as int, () => [])
          .add(LeyendaEntrada(codigo: r['codigo'] as String, texto: r['texto'] as String));
    }
  }
  return [
    for (final r in rows)
      ActividadFigura(
        seccion: r['seccion'] as String,
        antesPasoOrden: r['antes_paso_orden'] as int?,
        pagina: r['pagina'] as int,
        x0: (r['x0'] as num?)?.toDouble(),
        y0: (r['y0'] as num).toDouble(),
        x1: (r['x1'] as num?)?.toDouble(),
        y1: (r['y1'] as num).toDouble(),
        pie: r['pie'] as String?,
        leyenda: leyendas[r['orden'] as int] ?? const [],
      ),
  ];
}
