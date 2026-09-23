// Consultas de solo lectura sobre data.sqlite, compartidas por las pantallas
// del hub (U10) y el detalle (U11). Deliberadamente sin dependencias de
// Flutter -- son testeables sin montar ningún widget.

import 'package:sqlite3/sqlite3.dart';

class Sistema {
  final String codigo;
  final String? nombre;
  final int numActividades;
  const Sistema({
    required this.codigo,
    required this.nombre,
    required this.numActividades,
  });
}

class Manual {
  final int id;
  final String relPath;
  const Manual({required this.id, required this.relPath});
}

class FichaSistema {
  final String sistemaCodigo;
  final String cuerpo;
  final bool revisado;
  const FichaSistema({
    required this.sistemaCodigo,
    required this.cuerpo,
    required this.revisado,
  });
}

class SistemaDetalle {
  final Sistema sistema;
  final FichaSistema? ficha;
  final List<Manual> manuales;

  /// Códigos de actividad de este sistema, agrupados por el nivel de ciclo
  /// en que aparecen ('I1', 'IM1', ..., 'NS', ...). Una actividad puede
  /// aparecer en más de un grupo (pertenece a varios niveles).
  final Map<String, List<String>> actividadesPorCiclo;

  const SistemaDetalle({
    required this.sistema,
    required this.ficha,
    required this.manuales,
    required this.actividadesPorCiclo,
  });
}

class NivelCiclo {
  final String codigo;
  final String programa; // 'km' | 'horas' | 'ns'
  final int orden;
  final String? descripcion;
  final int? kmNum;
  final int? intervaloH;
  const NivelCiclo({
    required this.codigo,
    required this.programa,
    required this.orden,
    required this.descripcion,
    required this.kmNum,
    required this.intervaloH,
  });
}

/// Actividades acumuladas de un nivel de ciclo (R9/R12): para un programa
/// ordenado (km, horas), el conjunto es el propio nivel más todos los
/// anteriores en el mismo programa. `NS` no es acumulativo -- es un único
/// nivel de "según condición".
class ActividadesDeNivel {
  final NivelCiclo nivel;
  final List<String> codigos;
  /// Lotes (particiones disjuntas) de este nivel, si está partido --
  /// p. ej. IM1 -> [IM1A, IM1B, IM1C]. Vacío si el nivel no está partido.
  final List<String> lotes;
  const ActividadesDeNivel({
    required this.nivel,
    required this.codigos,
    required this.lotes,
  });
}

class ActividadPaso {
  final String? fase;
  final int n;
  final String texto;
  const ActividadPaso({required this.fase, required this.n, required this.texto});
}

/// Fila de la tabla de herramientas/consumibles/repuestos del detalle
/// (R6): `catalogo.tipo` distingue herramienta de consumible/material;
/// cantidad y uso (S/SC) viven en el enlace, no en la entrada de catálogo
/// (KTD5), así que salen de `actividad_material`, no de `catalogo`.
class ActividadMaterial {
  final String tipo; // 'herramienta' | 'consumible' | 'material'
  final String? descripcion;
  final String? referencia;
  final String? fabricante;
  final String? cant;
  final String? ud;
  final String? uso; // 'S' | 'SC' | null
  const ActividadMaterial({
    required this.tipo,
    required this.descripcion,
    required this.referencia,
    required this.fabricante,
    required this.cant,
    required this.ud,
    required this.uso,
  });
}

class ActividadDetalle {
  final String codigo;
  final String? edicion;
  final String? sistemaCodigo;
  final String? componente;
  final String? actividadTipo;
  final String? operacion;
  final String? frecuencia;
  final String? descripcionPlan;
  final String? zonasTrabajo;

  /// Texto de la sección 1 del VMI ("Medidas de seguridad"), null si el VMI
  /// no se pudo extraer o es de una carpeta de datos anterior a v3. Se
  /// muestra colapsado, no estructurado (R6/KTD9).
  final String? seguridad;
  final bool sinExtraer;
  final String? motivo;

  /// Ruta del VMI relativa a `<dataDir>/pdfs/vmi/`, null si no hay VMI
  /// vinculado (p. ej. una actividad que solo viene del plan).
  final String? vmiRelPath;
  final List<String> niveles;
  final List<ActividadPaso> pasos;
  final List<ActividadMaterial> materiales;

  const ActividadDetalle({
    required this.codigo,
    required this.edicion,
    required this.sistemaCodigo,
    required this.componente,
    required this.actividadTipo,
    required this.operacion,
    required this.frecuencia,
    required this.descripcionPlan,
    required this.zonasTrabajo,
    required this.seguridad,
    required this.sinExtraer,
    required this.motivo,
    required this.vmiRelPath,
    required this.niveles,
    required this.pasos,
    required this.materiales,
  });
}

class ManualTocEntry {
  final int orden;
  final String? titulo;
  final int? pagina;
  final int? nivel;
  const ManualTocEntry({
    required this.orden,
    required this.titulo,
    required this.pagina,
    required this.nivel,
  });
}

class CatalogoEntrada {
  final String id;
  final String? codigoErp;
  final String? descripcion;
  final String? fabricante;
  final String? unidad;
  final String tipo;
  const CatalogoEntrada({
    required this.id,
    required this.codigoErp,
    required this.descripcion,
    required this.fabricante,
    required this.unidad,
    required this.tipo,
  });
}

/// Todos los sistemas, ordenados por código, con el número de actividades
/// de cada uno (R15: la página de sistema agrupa sus actividades).
List<Sistema> listSistemas(Database db) {
  final rows = db.select('''
    SELECT s.codigo, s.nombre, count(a.codigo) AS n
    FROM sistema s
    LEFT JOIN actividad a ON a.sistema_codigo = s.codigo
    GROUP BY s.codigo
    ORDER BY s.codigo
  ''');
  return [
    for (final r in rows)
      Sistema(
        codigo: r['codigo'] as String,
        nombre: r['nombre'] as String?,
        numActividades: r['n'] as int,
      ),
  ];
}

/// Ficha, manuales y actividades (agrupadas por ciclo) de un sistema (R15).
/// Devuelve null si el código de sistema no existe.
SistemaDetalle? getSistemaDetalle(Database db, String codigo) {
  final sisRows = db.select(
    'SELECT codigo, nombre FROM sistema WHERE codigo = ?',
    [codigo],
  );
  if (sisRows.isEmpty) return null;
  final numAct = db
      .select('SELECT count(*) c FROM actividad WHERE sistema_codigo = ?', [
        codigo,
      ])
      .first['c'] as int;
  final sistema = Sistema(
    codigo: sisRows.first['codigo'] as String,
    nombre: sisRows.first['nombre'] as String?,
    numActividades: numAct,
  );

  final fichaRows = db.select(
    'SELECT cuerpo, revisado FROM ficha_sistema WHERE sistema_codigo = ?',
    [codigo],
  );
  final ficha = fichaRows.isEmpty
      ? null
      : FichaSistema(
          sistemaCodigo: codigo,
          cuerpo: fichaRows.first['cuerpo'] as String? ?? '',
          revisado: (fichaRows.first['revisado'] as int) != 0,
        );

  final manualRows = db.select(
    'SELECT id, rel_path FROM manual WHERE sistema_codigo = ? ORDER BY id',
    [codigo],
  );
  final manuales = [
    for (final r in manualRows)
      Manual(id: r['id'] as int, relPath: r['rel_path'] as String),
  ];

  final actRows = db.select(
    '''
    SELECT an.nivel_codigo, a.codigo
    FROM actividad a
    JOIN actividad_nivel an ON an.actividad_codigo = a.codigo
    WHERE a.sistema_codigo = ?
    ORDER BY an.nivel_codigo, a.codigo
    ''',
    [codigo],
  );
  final porCiclo = <String, List<String>>{};
  for (final r in actRows) {
    final nivel = r['nivel_codigo'] as String;
    (porCiclo[nivel] ??= []).add(r['codigo'] as String);
  }

  return SistemaDetalle(
    sistema: sistema,
    ficha: ficha,
    manuales: manuales,
    actividadesPorCiclo: porCiclo,
  );
}

/// Niveles de un programa ('km' | 'horas'), en orden.
List<NivelCiclo> listNiveles(Database db, String programa) {
  final rows = db.select(
    'SELECT codigo, programa, orden, descripcion, km_num, intervalo_h '
    'FROM nivel_ciclo WHERE programa = ? ORDER BY orden',
    [programa],
  );
  return [for (final r in rows) _nivelFromRow(r)];
}

NivelCiclo _nivelFromRow(Row r) => NivelCiclo(
  codigo: r['codigo'] as String,
  programa: r['programa'] as String,
  orden: r['orden'] as int,
  descripcion: r['descripcion'] as String?,
  kmNum: r['km_num'] as int?,
  intervaloH: r['intervalo_h'] as int?,
);

/// Conjunto acumulado de actividades de [nivelCodigo] (R9/R12/AE2/AE3): el
/// propio nivel más todos los anteriores del mismo programa. Para 'NS'
/// (no acumulativo) es solo ese nivel.
ActividadesDeNivel actividadesDeNivel(Database db, String nivelCodigo) {
  final nivelRows = db.select(
    'SELECT codigo, programa, orden, descripcion, km_num, intervalo_h '
    'FROM nivel_ciclo WHERE codigo = ?',
    [nivelCodigo],
  );
  if (nivelRows.isEmpty) {
    throw ArgumentError('nivel de ciclo desconocido: $nivelCodigo');
  }
  final nivel = _nivelFromRow(nivelRows.first);

  final ResultSet codRows;
  if (nivel.programa == 'ns') {
    codRows = db.select(
      '''
      SELECT DISTINCT actividad_codigo AS codigo FROM actividad_nivel
      WHERE nivel_codigo = ?
      ORDER BY actividad_codigo
      ''',
      [nivelCodigo],
    );
  } else {
    codRows = db.select(
      '''
      SELECT DISTINCT an.actividad_codigo AS codigo
      FROM actividad_nivel an
      JOIN nivel_ciclo nc ON nc.codigo = an.nivel_codigo
      WHERE nc.programa = ? AND nc.orden <= ?
      ORDER BY an.actividad_codigo
      ''',
      [nivel.programa, nivel.orden],
    );
  }
  final codigos = [for (final r in codRows) r['codigo'] as String];

  final loteRows = db.select(
    'SELECT codigo FROM lote WHERE nivel = ? ORDER BY codigo',
    [nivelCodigo],
  );
  final lotes = [for (final r in loteRows) r['codigo'] as String];

  return ActividadesDeNivel(nivel: nivel, codigos: codigos, lotes: lotes);
}

/// Actividades de un lote concreto (p. ej. 'IM1A') -- R11/R12/AE3: el
/// desglose por lote de un nivel partido. Requiere esquema v2 (tabla
/// actividad_lote); una carpeta de datos v1 no tiene esta tabla y no debería
/// llegar aquí (loadDataFolder ya la habría rechazado por incompatible).
List<String> actividadesDeLote(Database db, String loteCodigo) {
  final rows = db.select(
    'SELECT actividad_codigo FROM actividad_lote WHERE lote_codigo = ? ORDER BY actividad_codigo',
    [loteCodigo],
  );
  return [for (final r in rows) r['actividad_codigo'] as String];
}

/// Código de sistema de cada actividad en [codigos] (para agrupar una
/// lista de actividades por sistema, p. ej. la vista "por ciclo").
/// Una actividad sin sistema resoluble (incidencia `actividad-sin-sistema`
/// en join.js) simplemente no aparece en el mapa devuelto.
Map<String, String> sistemasDe(Database db, List<String> codigos) {
  if (codigos.isEmpty) return const {};
  final placeholders = List.filled(codigos.length, '?').join(',');
  final rows = db.select(
    'SELECT codigo, sistema_codigo FROM actividad WHERE codigo IN ($placeholders) AND sistema_codigo IS NOT NULL',
    codigos,
  );
  return {
    for (final r in rows) r['codigo'] as String: r['sistema_codigo'] as String,
  };
}

/// Programa ('km' | 'horas' | 'ns') de un nivel de ciclo, o null si el
/// código no existe -- para deep-linkear a "por ciclo" desde un nivel
/// concreto sin que el llamador tenga que adivinar a qué programa pertenece.
String? programaDeNivel(Database db, String nivelCodigo) {
  final rows = db.select(
    'SELECT programa FROM nivel_ciclo WHERE codigo = ?',
    [nivelCodigo],
  );
  return rows.isEmpty ? null : rows.first['programa'] as String;
}

/// Detalle completo de una actividad para el panel de U11 (R6): cabecera,
/// niveles en que aplica, tablas de herramientas/consumibles/repuestos con
/// cantidad y uso, y el procedimiento paso a paso. Null si el código no
/// existe.
ActividadDetalle? getActividadDetalle(Database db, String codigo) {
  final rows = db.select('SELECT * FROM actividad WHERE codigo = ?', [codigo]);
  if (rows.isEmpty) return null;
  final r = rows.first;

  final nivelRows = db.select(
    'SELECT DISTINCT nivel_codigo FROM actividad_nivel WHERE actividad_codigo = ? ORDER BY nivel_codigo',
    [codigo],
  );
  final niveles = [for (final nr in nivelRows) nr['nivel_codigo'] as String];

  final pasoRows = db.select(
    'SELECT fase, paso_n, texto FROM actividad_paso WHERE actividad_codigo = ? ORDER BY orden',
    [codigo],
  );
  final pasos = [
    for (final pr in pasoRows)
      ActividadPaso(
        fase: pr['fase'] as String?,
        n: pr['paso_n'] as int,
        texto: pr['texto'] as String,
      ),
  ];

  final matRows = db.select(
    '''
    SELECT c.tipo, c.descripcion, c.referencia, c.fabricante, am.cant, am.ud, am.uso
    FROM actividad_material am
    JOIN catalogo c ON c.id = am.catalogo_id
    WHERE am.actividad_codigo = ?
    ORDER BY c.tipo, c.descripcion
    ''',
    [codigo],
  );
  final materiales = [
    for (final mr in matRows)
      ActividadMaterial(
        tipo: mr['tipo'] as String,
        descripcion: mr['descripcion'] as String?,
        referencia: mr['referencia'] as String?,
        fabricante: mr['fabricante'] as String?,
        cant: mr['cant'] as String?,
        ud: mr['ud'] as String?,
        uso: mr['uso'] as String?,
      ),
  ];

  return ActividadDetalle(
    codigo: r['codigo'] as String,
    edicion: r['edicion'] as String?,
    sistemaCodigo: r['sistema_codigo'] as String?,
    componente: r['componente'] as String?,
    actividadTipo: r['actividad_tipo'] as String?,
    operacion: r['operacion'] as String?,
    frecuencia: r['frecuencia'] as String?,
    descripcionPlan: r['descripcion_plan'] as String?,
    zonasTrabajo: r['zonas_trabajo'] as String?,
    seguridad: r['seguridad'] as String?,
    sinExtraer: (r['sin_extraer'] as int) != 0,
    motivo: r['motivo'] as String?,
    vmiRelPath: r['vmi_rel_path'] as String?,
    niveles: niveles,
    pasos: pasos,
    materiales: materiales,
  );
}

/// Índice de secciones de un manual (R16/KTD8): vacío si el PDF no traía
/// outline/marcadores utilizable -- el visor entonces abre en la página 1
/// (AE de degradación anotada en el plan, no un error).
List<ManualTocEntry> listManualToc(Database db, int manualId) {
  final rows = db.select(
    'SELECT orden, titulo, pagina, nivel FROM manual_toc WHERE manual_id = ? ORDER BY orden',
    [manualId],
  );
  return [
    for (final r in rows)
      ManualTocEntry(
        orden: r['orden'] as int,
        titulo: r['titulo'] as String?,
        pagina: r['pagina'] as int?,
        nivel: r['nivel'] as int?,
      ),
  ];
}

/// Una actividad que usa una entrada de catálogo concreta, con la
/// cantidad y el uso (S/SC) de ESE enlace -- pueden variar entre
/// actividades para la misma entrada (KTD5).
class ActividadUso {
  final String actividadCodigo;
  final String? descripcionActividad;
  final String? cant;
  final String? ud;
  final String? uso;
  const ActividadUso({
    required this.actividadCodigo,
    required this.descripcionActividad,
    required this.cant,
    required this.ud,
    required this.uso,
  });
}

/// Actividades que usan una entrada de catálogo concreta (R17/AE7): el
/// filtro bidireccional actividad<->material, en el sentido
/// material->actividades. Cualquier ciclo -- no se restringe a uno.
List<ActividadUso> actividadesQueUsan(Database db, String catalogoId) {
  final rows = db.select(
    '''
    SELECT am.actividad_codigo, a.operacion, a.descripcion_plan, am.cant, am.ud, am.uso
    FROM actividad_material am
    JOIN actividad a ON a.codigo = am.actividad_codigo
    WHERE am.catalogo_id = ?
    ORDER BY am.actividad_codigo
    ''',
    [catalogoId],
  );
  return [
    for (final r in rows)
      ActividadUso(
        actividadCodigo: r['actividad_codigo'] as String,
        descripcionActividad:
            (r['operacion'] as String?) ?? (r['descripcion_plan'] as String?),
        cant: r['cant'] as String?,
        ud: r['ud'] as String?,
        uso: r['uso'] as String?,
      ),
  ];
}

/// Todas las entradas del catálogo, ordenadas por descripción.
List<CatalogoEntrada> listCatalogo(Database db) {
  final rows = db.select(
    'SELECT id, codigo_erp, descripcion, fabricante, unidad, tipo '
    'FROM catalogo ORDER BY descripcion',
  );
  return [
    for (final r in rows)
      CatalogoEntrada(
        id: r['id'] as String,
        codigoErp: r['codigo_erp'] as String?,
        descripcion: r['descripcion'] as String?,
        fabricante: r['fabricante'] as String?,
        unidad: r['unidad'] as String?,
        tipo: r['tipo'] as String,
      ),
  ];
}
