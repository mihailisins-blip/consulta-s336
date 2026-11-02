// Pestaña "Plan": el plan de mantenimiento con el mismo formato de tabla que
// el documento oficial (PDF/Excel) -- código, descripción, marca de
// seguridad, una X por ciclo y observaciones, agrupado por subsistema --
// con filtros por texto y sistema. El filtro por ciclo se hace pulsando el
// título de la columna (se pueden marcar varios: quedan las filas con X en
// alguno de ellos). Pulsar el código abre la ficha de la actividad.
//
// Convive con "Por sistema" y "Por ciclo": no los sustituye todavía (la
// ficha del sistema y sus manuales, el acumulado por nivel, el desglose por
// lote y la exportación de materiales siguen allí).

import 'package:flutter/material.dart';

import '../app_session.dart';
import '../data/queries.dart';
import '../detalle/actividad_detalle.dart';
import 'por_sistema_screen.dart' show formatearNombreSistema;

const _azulOscuro = Color(0xFF2E4A68);
const _fondo = Color(0xFFEEF1F5);
const _borde = Color(0xFFD9DEE5);
const _lineaFila = Color(0xFFE3E7EC);
const _fondoGrupo = Color(0xFFDCE3EB);
const _columnaActiva = Color(0xFFEAF1FA);
const _textoSecundario = Color(0xFF4A5563);
const _enlace = Color(0xFF1F5FAF);
const _rojoSeguridad = Color(0xFFC0262D);

const _anchoCodigo = 134.0;
const _anchoSeg = 44.0;
const _anchoCiclo = 60.0;
const _anchoObs = 240.0;

/// Por debajo de este ancho la tabla se desplaza en horizontal en vez de
/// apretar la descripción.
const anchoMinimoTablaPlan = 1180.0;

class PlanScreen extends StatefulWidget {
  final AppSession session;
  const PlanScreen({super.key, required this.session});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final List<FilaPlan> _filas;
  late final Map<String, String> _subsistemas;
  late final List<Sistema> _sistemas;
  final _texto = TextEditingController();
  String? _sistema;
  final Set<String> _ciclos = {};

  @override
  void initState() {
    super.initState();
    _filas = listPlan(widget.session.db);
    _subsistemas = nombresSubsistema(widget.session.db);
    _sistemas = listSistemas(widget.session.db).where((s) => s.numActividades > 0).toList();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _alternarCiclo(String c) => setState(() {
    if (!_ciclos.remove(c)) _ciclos.add(c);
  });

  void _quitarFiltros() => setState(() {
    _texto.clear();
    _sistema = null;
    _ciclos.clear();
  });

  void _abrir(String codigo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActividadDetalleScreen(session: widget.session, codigo: codigo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles = filtrarPlan(_filas, texto: _texto.text, sistema: _sistema, ciclos: _ciclos);
    final ciclosActivos = [for (final c in ciclosPlan) if (_ciclos.contains(c)) c];
    final resumen = '${visibles.length} de ${_filas.length} actividades'
        '${ciclosActivos.isEmpty ? '' : ' · ciclos ${ciclosActivos.join(', ')}'}';

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _azulOscuro,
        foregroundColor: Colors.white,
        toolbarHeight: 72,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CONSULTA S336', style: TextStyle(fontSize: 12, letterSpacing: 1, color: Color(0xFFC9D4E1))),
            SizedBox(height: 2),
            Text('Plan de mantenimiento', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filtros(),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(resumen, style: const TextStyle(fontSize: 14, color: Color(0xFF3E4A57))),
                const Text(
                  'X = la actividad se hace en ese ciclo · ! = marca de seguridad · '
                  'pulsa el título de un ciclo para filtrar (puedes marcar varios)',
                  style: TextStyle(fontSize: 12, color: _textoSecundario),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _tabla(visibles)),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    const etiqueta = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textoSecundario);
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFFC7CED8)),
    );
    final decoracion = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: borde,
      enabledBorder: borde,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _borde),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Buscar', style: etiqueta),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('plan-buscar'),
                  controller: _texto,
                  onChanged: (_) => setState(() {}),
                  decoration: decoracion.copyWith(hintText: 'Código o texto de la actividad'),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sistema', style: etiqueta),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  key: const Key('plan-sistema'),
                  initialValue: _sistema,
                  isExpanded: true,
                  decoration: decoracion,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos los sistemas')),
                    for (final s in _sistemas)
                      DropdownMenuItem<String?>(
                        value: s.codigo,
                        child: Text(
                          s.nombre != null ? '${s.codigo} · ${formatearNombreSistema(s.nombre!)}' : s.codigo,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _sistema = v),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _quitarFiltros,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E2A36),
                side: const BorderSide(color: Color(0xFFC7CED8)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('Quitar filtros'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabla(List<FilaPlan> visibles) {
    // filas y títulos de grupo intercalados, en el orden del documento
    final items = <Object>[];
    String? grupo;
    for (final f in visibles) {
      if (f.subsistemaCodigo != grupo) {
        grupo = f.subsistemaCodigo;
        items.add(_Grupo(grupo, _subsistemas[grupo]));
      }
      items.add(f);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _borde),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final ancho = box.maxWidth < anchoMinimoTablaPlan ? anchoMinimoTablaPlan : box.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: ancho,
              height: box.maxHeight,
              child: Column(
                children: [
                  _cabecera(),
                  Expanded(
                    child: items.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Ninguna actividad cumple los filtros.',
                              style: TextStyle(color: _textoSecundario),
                            ),
                          )
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final it = items[i];
                              return it is _Grupo ? _filaGrupo(it) : _fila(it as FilaPlan);
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cabecera() {
    const blanco = TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14);
    return Container(
      color: _azulOscuro,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: _anchoCodigo, child: Padding(padding: EdgeInsets.all(12), child: Text('Código', style: blanco))),
          const Expanded(child: Padding(padding: EdgeInsets.all(12), child: Text('Descripción', style: blanco))),
          const SizedBox(width: _anchoSeg, child: Center(child: Text('!', style: blanco))),
          for (final c in ciclosPlan) _tituloCiclo(c),
          const SizedBox(width: _anchoObs, child: Padding(padding: EdgeInsets.all(12), child: Text('Observaciones', style: blanco))),
        ],
      ),
    );
  }

  Widget _tituloCiclo(String c) {
    final activo = _ciclos.contains(c);
    return SizedBox(
      width: _anchoCiclo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Semantics(
          button: true,
          selected: activo,
          label: 'Filtrar por ciclo $c',
          excludeSemantics: true,
          child: Material(
            color: activo ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              key: Key('plan-ciclo-$c'),
              borderRadius: BorderRadius.circular(6),
              hoverColor: const Color(0xFF3D5C7F),
              onTap: () => _alternarCiclo(c),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    c,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: activo ? _azulOscuro : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaGrupo(_Grupo g) {
    return Container(
      color: _fondoGrupo,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        g.nombre != null ? '${g.codigo} · ${g.nombre}' : g.codigo,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }

  Widget _fila(FilaPlan f) {
    // IntrinsicHeight + stretch: el resaltado de una columna de ciclo activa
    // cubre toda la altura de la fila aunque la descripción ocupe varias líneas
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _lineaFila))),
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _anchoCodigo,
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: TextButton(
                onPressed: () => _abrir(f.codigo),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  foregroundColor: _enlace,
                  textStyle: const TextStyle(fontSize: 14, decoration: TextDecoration.underline),
                ),
                child: Text(f.codigo),
              ),
            ),
          ),
          Expanded(
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.all(12),
              child: Text(f.descripcion ?? '', style: const TextStyle(fontSize: 14)),
            ),
          ),
          SizedBox(
            width: _anchoSeg,
            child: Center(
              child: f.marcaSeguridad
                  ? const Tooltip(
                      message: 'Marca de seguridad',
                      child: Text('!', style: TextStyle(color: _rojoSeguridad, fontWeight: FontWeight.w700, fontSize: 16)),
                    )
                  : null,
            ),
          ),
          for (final c in ciclosPlan)
            Container(
              width: _anchoCiclo,
              constraints: const BoxConstraints(minHeight: 48),
              color: _ciclos.contains(c) ? _columnaActiva : null,
              alignment: Alignment.center,
              child: f.ciclos.contains(c)
                  ? const Text('X', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))
                  : null,
            ),
          Container(
            width: _anchoObs,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(12),
            child: Text(f.observaciones ?? '', style: const TextStyle(fontSize: 13, color: _textoSecundario)),
          ),
        ],
        ),
      ),
    );
  }
}

class _Grupo {
  final String codigo;
  final String? nombre;
  const _Grupo(this.codigo, this.nombre);
}
