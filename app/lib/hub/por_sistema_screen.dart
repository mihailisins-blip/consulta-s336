// Navegación "por sistema" (R13/R15): lista de sistemas -> ficha del
// sistema + sus manuales de `05` + sus actividades agrupadas por ciclo. El
// técnico solo consulta (R18); el curador (U15) ve el editor de la ficha
// en su lugar -- ver curacion/revision_fichas.dart.
//
// La lista tiene un buscador local (por código o nombre, en memoria sobre
// los ~95 sistemas -- no toca el índice FTS5, que es el buscador global de
// U9) y un conmutador lista/por-área (cosmético, sin requisito propio).

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_session.dart';
import '../curacion/revision_fichas.dart';
import '../data/queries.dart';
import '../detalle/actividad_detalle.dart';
import '../detalle/pdf_viewer.dart';
import 'recientes.dart';

/// Área funcional por letra inicial del código de sistema (p. ej. "ED3" ->
/// "E" -> Bogie y suspensión) -- SOLO para agrupar la vista "por área"
/// (Opción 2 de los mockups). Es una categorización propia de la UI,
/// inferida de los códigos y nombres reales observados en el corpus; no
/// sale de ningún dato del pipeline (`sistema` no tiene columna de área).
/// El orden del mapa es el orden en que se muestran los grupos -- sigue el
/// mismo orden de letras que ya usa el propio esquema de códigos.
const Map<String, String> _areasPorLetra = {
  'A': 'Puesta a tierra y protección',
  'B': 'Carrocería',
  'C': 'Ventanas y acabados',
  'D': 'Confort e interior',
  'E': 'Bogie y suspensión',
  'F': 'Tracción y motor',
  'G': 'Control del vehículo',
  'H': 'Alimentación auxiliar',
  'J': 'Seguridad y comunicaciones',
  'K': 'Señalización e iluminación',
  'L': 'Climatización',
  'M': 'Arenado y engrase',
  'N': 'Puertas',
  'P': 'Videovigilancia',
  'Q': 'Equipo neumático',
  'R': 'Frenos',
  'S': 'Enganche y topes',
  'T': 'Armarios eléctricos',
  'U': 'Cableado',
};

String _areaDe(String codigo) =>
    _areasPorLetra[codigo.isEmpty ? '' : codigo[0].toUpperCase()] ?? 'Otros';

class PorSistemaScreen extends StatefulWidget {
  final AppSession session;
  const PorSistemaScreen({super.key, required this.session});

  @override
  State<PorSistemaScreen> createState() => _PorSistemaScreenState();
}

// Anchos de columna compartidos entre la cabecera y cada fila -- así se
// alinean exactamente, y el recuadro de actividades (dentro de su columna)
// sale del mismo tamaño en todas las filas en vez de ajustarse al número
// de dígitos (Chip lo hacía: "3" y "67" salían de ancho distinto).
const double _colAvatar = 44;
const double _colActividades = 84;
const double _colChevron = 28;

class _PorSistemaScreenState extends State<PorSistemaScreen> {
  String _query = '';
  bool _porArea = false;

  void _abrirSistema(BuildContext context, Sistema s, String nombre) {
    widget.session.recientes.registrar(
      RecienteEntry(tipo: 'sistema', id: s.codigo, titulo: '${s.codigo} — $nombre'),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SistemaDetalleScreen(session: widget.session, codigo: s.codigo),
      ),
    );
  }

  Widget _cabeceraColumnas(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          const SizedBox(width: _colAvatar),
          Expanded(child: Text('Sistema', style: style)),
          SizedBox(
            width: _colActividades,
            child: Text(
              'Actividades',
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: _colChevron),
        ],
      ),
    );
  }

  Widget _fila(Sistema s) {
    final nombre = _tituloSistema(s);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _abrirSistema(context, s, nombre),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: _colAvatar,
              child: CircleAvatar(
                radius: 16,
                child: Text(s.codigo, style: const TextStyle(fontSize: 10)),
              ),
            ),
            Expanded(child: Text(nombre)),
            SizedBox(
              width: _colActividades,
              child: Center(
                child: Container(
                  width: 40,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${s.numActividades}',
                    style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer),
                  ),
                ),
              ),
            ),
            SizedBox(width: _colChevron, child: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todos = listSistemas(widget.session.db);
    final q = _query.trim().toLowerCase();
    final filtrados = q.isEmpty
        ? todos
        : todos
              .where(
                (s) => s.codigo.toLowerCase().contains(q) || _tituloSistema(s).toLowerCase().contains(q),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Por sistema'),
        actions: [
          IconButton(
            icon: Icon(_porArea ? Icons.view_list_outlined : Icons.category_outlined),
            tooltip: _porArea ? 'Ver como lista' : 'Agrupar por área',
            onPressed: () => setState(() => _porArea = !_porArea),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar sistema por código o nombre…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          _cabeceraColumnas(context),
          const Divider(height: 1),
          Expanded(
            child: filtrados.isEmpty
                ? const Center(child: Text('Ningún sistema coincide con la búsqueda.'))
                : _porArea ? _listaPorArea(filtrados) : _listaPlana(filtrados),
          ),
        ],
      ),
    );
  }

  Widget _listaPlana(List<Sistema> sistemas) => ListView.separated(
    itemCount: sistemas.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, i) => _fila(sistemas[i]),
  );

  Widget _listaPorArea(List<Sistema> sistemas) {
    final porArea = <String, List<Sistema>>{};
    for (final s in sistemas) {
      porArea.putIfAbsent(_areaDe(s.codigo), () => []).add(s);
    }
    final areasOrdenadas = [
      ..._areasPorLetra.values.where(porArea.containsKey),
      if (porArea.containsKey('Otros')) 'Otros',
    ];
    return ListView(
      children: [
        for (final area in areasOrdenadas) ...[
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              area,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          for (final s in porArea[area]!) _fila(s),
        ],
      ],
    );
  }
}

/// Nombre a mostrar para [s], o el propio código si no hay nombre.
String _tituloSistema(Sistema s) => s.nombre != null ? _formatearNombreSistema(s.nombre!) : s.codigo;

/// Los nombres de sistema vienen del nombre de la carpeta de `05` tal cual
/// (join.js) -- algunos ya están en formato correcto ("Caja del vehículo"),
/// otros llegan GRITADOS EN MAYÚSCULAS ("SUELO", "CONFORT"). Normaliza estos
/// últimos a mayúscula inicial + minúsculas, dejando intactos tanto los que
/// ya vienen bien como los acrónimos independientes cortos (p. ej. "CCTV",
/// "TWC") que perderían sentido en minúsculas -- heurística: una sola
/// palabra, sin espacios, de 4 letras o menos.
String _formatearNombreSistema(String nombre) {
  final t = nombre.trim();
  if (t.isEmpty || t != t.toUpperCase()) return t;
  if (!t.contains(' ') && t.length <= 4) return t;
  return t[0].toUpperCase() + t.substring(1).toLowerCase();
}

class SistemaDetalleScreen extends StatelessWidget {
  final AppSession session;
  final String codigo;
  const SistemaDetalleScreen({super.key, required this.session, required this.codigo});

  @override
  Widget build(BuildContext context) {
    final detalle = getSistemaDetalle(session.db, codigo);
    if (detalle == null) {
      return Scaffold(
        appBar: AppBar(title: Text(codigo)),
        body: const Center(child: Text('Sistema no encontrado.')),
      );
    }
    final s = detalle.sistema;
    final ciclosOrdenados = detalle.actividadesPorCiclo.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text('${s.codigo}${s.nombre != null ? ' — ${_formatearNombreSistema(s.nombre!)}' : ''}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // R20: el técnico ve siempre la ficha (esté revisada o no) --
          // solo el curador (R18/U15) ve el editor en su lugar.
          if (session.editMode) ...[
            FichaEditor(db: session.db, sistemaCodigo: codigo, fichaInicial: detalle.ficha),
            const SizedBox(height: 16),
          ] else if (detalle.ficha != null) ...[
            Row(
              children: [
                Icon(
                  detalle.ficha!.revisado ? Icons.check_circle : Icons.edit_note,
                  size: 18,
                  color: detalle.ficha!.revisado ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(detalle.ficha!.revisado ? 'Ficha revisada' : 'Ficha en borrador'),
              ],
            ),
            if (detalle.ficha!.cuerpo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detalle.ficha!.cuerpo),
            ],
            const SizedBox(height: 16),
          ],
          if (detalle.manuales.isNotEmpty) ...[
            Text('Manuales', style: Theme.of(context).textTheme.titleMedium),
            for (final m in detalle.manuales) ...[
              ListTile(
                dense: true,
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(p.basename(m.relPath)),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _abrirManual(context, m),
              ),
              // Índice del manual (R16/KTD8): cada entrada del TOC salta
              // directamente a su página; vacío si el PDF no traía
              // outline/marcadores utilizables (degradación anotada en el
              // plan, no un error).
              for (final t in listManualToc(session.db, m.id))
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: ListTile(
                    dense: true,
                    title: Text(t.titulo ?? '(sin título)'),
                    trailing: t.pagina != null ? Text('p. ${t.pagina}') : null,
                    onTap: () => _abrirManual(context, m, pagina: t.pagina),
                  ),
                ),
            ],
            const SizedBox(height: 16),
          ],
          Text('Actividades por ciclo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (ciclosOrdenados.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin actividades vinculadas a un ciclo.'),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final ciclo in ciclosOrdenados)
                  _TarjetaCiclo(
                    ciclo: ciclo,
                    actividades: detalle.actividadesPorCiclo[ciclo]!,
                    onTapActividad: (c) => _abrirActividad(context, c),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void _abrirManual(BuildContext context, Manual manual, {int? pagina}) {
    final path = p.join(session.dataDir, 'pdfs', 'manuales', manual.relPath);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          path: path,
          title: p.basename(manual.relPath),
          initialPageNumber: pagina ?? 1,
        ),
      ),
    );
  }

  void _abrirActividad(BuildContext context, String codigoActividad) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActividadDetalleScreen(session: session, codigo: codigoActividad),
      ),
    );
  }
}

/// Una tarjeta de ancho fijo por ciclo, con sus actividades apiladas como
/// filas de alto fijo -- en vez del Wrap de chips de ancho variable de
/// antes, que no alineaba entre ciclos con distinto número de actividades.
class _TarjetaCiclo extends StatelessWidget {
  final String ciclo;
  final List<String> actividades;
  final ValueChanged<String> onTapActividad;
  const _TarjetaCiclo({
    required this.ciclo,
    required this.actividades,
    required this.onTapActividad,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              ciclo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final c in actividades) ...[
            SizedBox(
              height: 32,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onTapActividad(c),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  child: Text(c, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
