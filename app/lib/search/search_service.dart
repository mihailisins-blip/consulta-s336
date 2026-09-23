// Buscador global mixto sobre el índice FTS5 `busqueda` (R14, SC1/SC2):
// resultados de actividad, sistema y catálogo sobre el texto YA
// extraído/curado -- nunca abriendo ni leyendo un PDF. `busqueda` se llena
// en tiempo de build (pipeline/, KTD7: cada campo compuesto override ??
// extraído); este servicio solo lee.

import 'package:sqlite3/sqlite3.dart';

enum SearchResultType { actividad, sistema, catalogo }

class SearchResult {
  final SearchResultType tipo;
  final String id;
  final String titulo;

  /// Etiquetas cortas de contexto -- nunca un campo que exija abrir el PDF
  /// original: sistema + ciclos para una actividad, el propio código para
  /// un sistema, el código ERP (si lo hay) para una entrada de catálogo.
  final List<String> chips;

  const SearchResult({
    required this.tipo,
    required this.id,
    required this.titulo,
    required this.chips,
  });

  @override
  String toString() => 'SearchResult($tipo, $id, "$titulo", chips: $chips)';
}

class SearchService {
  final Database _db;
  const SearchService(this._db);

  /// Busca [query] en el índice FTS5 y devuelve como mucho [limit]
  /// resultados mezclados, ordenados por relevancia (`rank` de FTS5). Una
  /// query en blanco no toca la base y devuelve una lista vacía.
  List<SearchResult> search(String query, {int limit = 25}) {
    final term = query.trim();
    if (term.isEmpty) return const [];

    final rows = _matchSafely(term, limit);
    return [for (final row in rows) _toResult(row)];
  }

  /// `_toFtsQuery` deja pasar tal cual una query que ya "parece" usar
  /// sintaxis FTS5 (operadores, comillas, paréntesis) -- pero un término de
  /// búsqueda real puede tener un paréntesis o comilla sueltos sin ser
  /// intencionadamente sintaxis FTS5 (p. ej. copiar una descripción de
  /// catálogo como "ACEITE MD ULS 15W/40 (BIDON 208L)"), lo que FTS5
  /// rechaza como error de sintaxis. Si el MATCH falla, se reintenta como
  /// frase literal -- FTS5 siempre acepta una cadena entrecomillada, sea
  /// cual sea su contenido -- en vez de dejar que la excepción se propague
  /// hasta el TextField de búsqueda.
  ResultSet _matchSafely(String term, int limit) {
    const sql =
        'SELECT tipo, ref, titulo FROM busqueda WHERE busqueda MATCH ? ORDER BY rank LIMIT ?';
    try {
      return _db.select(sql, [_toFtsQuery(term), limit]);
    } on SqliteException {
      return _db.select(sql, [_literalPhrase(term), limit]);
    }
  }

  String _literalPhrase(String term) => '"${term.replaceAll('"', '""')}"';

  SearchResult _toResult(Row row) {
    final tipo = _tipoFrom(row['tipo'] as String);
    final ref = row['ref'] as String;
    return SearchResult(
      tipo: tipo,
      id: ref,
      titulo: row['titulo'] as String,
      chips: _chipsFor(tipo, ref),
    );
  }

  static SearchResultType _tipoFrom(String raw) => switch (raw) {
    'actividad' => SearchResultType.actividad,
    'sistema' => SearchResultType.sistema,
    'catalogo' => SearchResultType.catalogo,
    _ => throw ArgumentError(
      "tipo de resultado de búsqueda desconocido: '$raw' -- ¿nuevo tipo en pipeline/sqlite-writer.js sin actualizar aquí?",
    ),
  };

  List<String> _chipsFor(SearchResultType tipo, String ref) {
    switch (tipo) {
      case SearchResultType.actividad:
        final act = _db.select(
          'SELECT sistema_codigo FROM actividad WHERE codigo = ?',
          [ref],
        );
        final sistemaCodigo = act.isNotEmpty
            ? act.first['sistema_codigo'] as String?
            : null;
        final niveles = _db.select(
          'SELECT nivel_codigo FROM actividad_nivel WHERE actividad_codigo = ? ORDER BY nivel_codigo',
          [ref],
        );
        return [
          ?sistemaCodigo,
          for (final n in niveles) n['nivel_codigo'] as String,
        ];
      case SearchResultType.sistema:
        return [ref];
      case SearchResultType.catalogo:
        final cat = _db.select(
          'SELECT codigo_erp FROM catalogo WHERE id = ?',
          [ref],
        );
        final erp = cat.isNotEmpty ? cat.first['codigo_erp'] as String? : null;
        return erp != null ? [erp] : const [];
    }
  }

  /// FTS5 admite sus propios operadores (`OR`, `AND`, `NOT`, `*`, `"frase"`).
  /// Si la query ya parece usarlos se pasa tal cual; si no, cada palabra se
  /// trata como prefijo simple, para que "reengras" encuentre "reengrasar".
  String _toFtsQuery(String term) {
    if (RegExp(r'[*"()]|\bOR\b|\bAND\b|\bNOT\b').hasMatch(term)) return term;
    final tokens = term.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return tokens.map((t) => '$t*').join(' ');
  }
}
