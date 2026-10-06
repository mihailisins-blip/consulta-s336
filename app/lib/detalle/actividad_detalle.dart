// Detalle de una actividad (R6/U11): cabecera, ciclos en que aplica,
// herramientas/consumibles con cantidad y uso, zona de trabajo,
// procedimiento por pasos, y medidas de seguridad colapsadas (KTD9). Solo
// lectura para el técnico (R18); el curador (R18/U14) ve además una
// sección editable para los campos reservados al simulador (R7).

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_session.dart';
import '../curacion/campo_editable.dart';
import '../data/figuras.dart';
import '../data/overrides.dart';
import '../data/queries.dart';
import '../export/export_xlsx.dart';
import '../hub/por_ciclo_screen.dart';
import '../hub/por_sistema_screen.dart';
import '../hub/recientes.dart';
import 'figura_vmi.dart';
import 'pdf_viewer.dart';

class ActividadDetalleScreen extends StatelessWidget {
  final AppSession session;
  final String codigo;

  const ActividadDetalleScreen({super.key, required this.session, required this.codigo});

  @override
  Widget build(BuildContext context) {
    final detalle = getActividadDetalle(session.db, codigo);
    if (detalle == null) {
      return Scaffold(
        appBar: AppBar(title: Text(codigo)),
        body: const Center(child: Text('Actividad no encontrada.')),
      );
    }
    // Diferido a después del build (no durante) -- llamarlo aquí mismo
    // dispararía notifyListeners() mientras HubScreen (que sigue montado,
    // debajo, en la pila del Navigator) está reconstruyendo su propio
    // ListenableBuilder sobre este mismo RecientesController, lo que
    // incumple el contrato de build() de Flutter en cada navegación.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      session.recientes.registrar(
        RecienteEntry(tipo: 'actividad', id: detalle.codigo, titulo: detalle.codigo),
      );
    });

    final herramientas = detalle.materiales.where((m) => m.tipo == 'herramienta').toList();
    final consumibles = detalle.materiales.where((m) => m.tipo != 'herramienta').toList();
    // Figuras de las secciones 3 y 4, recortadas del VMI copiado a pdfs/
    // (sin VMI vinculado no hay de dónde recortarlas).
    final figuras = detalle.vmiRelPath == null
        ? const <ActividadFigura>[]
        : getActividadFiguras(session.db, codigo);
    final figurasZonas = figuras.where((f) => f.seccion == 'zonas').toList();
    final figurasProc = figuras.where((f) => f.seccion == 'procedimiento').toList();
    Widget figura(ActividadFigura f) => FiguraVmi(
          key: ValueKey('figura-${f.pagina}-${f.y1}'),
          pdfPath: _vmiPath(detalle),
          titulo: detalle.codigo,
          figura: f,
        );

    return Scaffold(
      appBar: AppBar(title: Text(detalle.codigo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(detalle.codigo, style: Theme.of(context).textTheme.headlineSmall),
              if (detalle.edicion != null) ...[
                const SizedBox(width: 8),
                Chip(label: Text('ed. ${detalle.edicion}')),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (detalle.sistemaCodigo != null)
                ActionChip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: Text(detalle.sistemaCodigo!),
                  onPressed: () => _abrirSistema(context, detalle.sistemaCodigo!),
                ),
              if (detalle.componente != null) Chip(label: Text(detalle.componente!)),
              if (detalle.actividadTipo != null) Chip(label: Text(detalle.actividadTipo!)),
            ],
          ),
          if (detalle.operacion != null) ...[
            const SizedBox(height: 12),
            Text(detalle.operacion!, style: Theme.of(context).textTheme.bodyLarge),
          ],
          if (detalle.frecuencia != null) ...[
            const SizedBox(height: 4),
            Text(
              'Frecuencia: ${detalle.frecuencia}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (detalle.niveles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Ciclos en que aplica', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final nivel in detalle.niveles)
                  ActionChip(
                    label: Text(nivel),
                    onPressed: () => _abrirCiclo(context, nivel),
                  ),
              ],
            ),
          ],
          if (detalle.sinExtraer) ...[
            const SizedBox(height: 16),
            _AvisoSinExtraer(motivo: detalle.motivo),
          ] else ...[
            if (herramientas.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Herramientas', style: Theme.of(context).textTheme.titleMedium),
              _ListaMateriales(materiales: herramientas),
            ],
            if (consumibles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Consumibles y repuestos', style: Theme.of(context).textTheme.titleMedium),
              _ListaMateriales(materiales: consumibles),
            ],
            if (detalle.zonasTrabajo != null || figurasZonas.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Zona de trabajo', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (detalle.zonasTrabajo != null) Text(detalle.zonasTrabajo!),
              for (final f in figurasZonas) figura(f),
            ],
            if (detalle.pasos.isNotEmpty || figurasProc.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Procedimiento', style: Theme.of(context).textTheme.titleMedium),
              _Procedimiento(pasos: detalle.pasos, figuras: figurasProc, figura: figura),
            ],
          ],
          if (detalle.seguridad != null) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              // Colapsado por defecto -- KTD9: es un bloque común, no algo
              // que estorbe la lectura del procedimiento.
              initiallyExpanded: false,
              tilePadding: EdgeInsets.zero,
              title: const Text('Medidas de seguridad'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(detalle.seguridad!),
                ),
              ],
            ),
          ],
          if (detalle.vmiRelPath != null || detalle.materiales.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (detalle.vmiRelPath != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Abrir PDF original (VMI)'),
                    onPressed: () => _abrirVmi(context, detalle),
                  ),
                if (detalle.materiales.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Exportar herramientas y materiales'),
                    onPressed: () => _exportar(context, detalle),
                  ),
              ],
            ),
          ],
          // R7/U14: reservados para el futuro simulador de tiempos, sin
          // lógica asociada aquí -- solo visibles y editables para el
          // curador (R18), nunca para el técnico.
          if (session.editMode) ...[
            const SizedBox(height: 16),
            Text('Datos del curador', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                CampoEditable(
                  etiqueta: 'Duración',
                  valorInicial: detalle.duracion,
                  onGuardar: (v) => guardarOverride(session.db, 'actividad', detalle.codigo, 'duracion', v),
                ),
                CampoEditable(
                  etiqueta: 'Zona',
                  valorInicial: detalle.zona,
                  onGuardar: (v) => guardarOverride(session.db, 'actividad', detalle.codigo, 'zona', v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _abrirSistema(BuildContext context, String sistemaCodigo) {
    session.recientes.registrar(
      RecienteEntry(tipo: 'sistema', id: sistemaCodigo, titulo: sistemaCodigo),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SistemaDetalleScreen(session: session, codigo: sistemaCodigo),
      ),
    );
  }

  void _abrirCiclo(BuildContext context, String nivelCodigo) {
    session.recientes.registrar(RecienteEntry(tipo: 'ciclo', id: nivelCodigo, titulo: nivelCodigo));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PorCicloScreen(session: session, nivelInicial: nivelCodigo),
      ),
    );
  }

  String _vmiPath(ActividadDetalle detalle) =>
      p.join(session.dataDir, 'pdfs', 'vmi', detalle.vmiRelPath!);

  void _abrirVmi(BuildContext context, ActividadDetalle detalle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(path: _vmiPath(detalle), title: detalle.codigo),
      ),
    );
  }

  Future<void> _exportar(BuildContext context, ActividadDetalle detalle) async {
    final materiales = materialesDeActividadParaExport(session.db, detalle.codigo);
    final bytes = xlsxBytesDeActividad(detalle.codigo, materiales);
    await exportarYGuardar(
      context,
      nombreSugerido: 'materiales_${detalle.codigo}.xlsx',
      bytes: bytes,
    );
  }
}

class _ListaMateriales extends StatelessWidget {
  final List<ActividadMaterial> materiales;
  const _ListaMateriales({required this.materiales});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final m in materiales)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(m.descripcion ?? '(sin descripción)'),
            subtitle: _subtitulo(m) == null ? null : Text(_subtitulo(m)!),
            trailing: _trailing(m).isEmpty ? null : Text(_trailing(m)),
          ),
      ],
    );
  }

  String? _subtitulo(ActividadMaterial m) {
    final partes = [m.referencia, m.fabricante].whereType<String>().toList();
    return partes.isEmpty ? null : partes.join(' · ');
  }

  String _trailing(ActividadMaterial m) {
    final partes = <String>[
      if (m.cant != null) [m.cant, m.ud].whereType<String>().join(' '),
      if (m.uso != null) m.uso!,
    ];
    return partes.join(' · ');
  }
}

class _Procedimiento extends StatelessWidget {
  final List<ActividadPaso> pasos;

  /// Figuras de la sección 4, cada una justo antes del paso
  /// `antesPasoOrden` (índice en [pasos]), o al final si es null.
  final List<ActividadFigura> figuras;
  final Widget Function(ActividadFigura) figura;
  const _Procedimiento({required this.pasos, required this.figuras, required this.figura});

  @override
  Widget build(BuildContext context) {
    // El índice de cada paso en `pasos` es su `orden`, que es a lo que
    // apunta `antesPasoOrden`.
    final porFase = <String, List<int>>{};
    for (var i = 0; i < pasos.length; i++) {
      final fase = (pasos[i].fase?.isNotEmpty ?? false) ? pasos[i].fase! : '';
      porFase.putIfAbsent(fase, () => []).add(i);
    }
    final finales = figuras.where((f) => f.antesPasoOrden == null || f.antesPasoOrden! >= pasos.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in porFase.entries) ...[
          if (entry.key.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(entry.key, style: Theme.of(context).textTheme.titleSmall),
          ],
          for (final i in entry.value) ...[
            for (final f in figuras.where((f) => f.antesPasoOrden == i)) figura(f),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text('${pasos[i].n}. ${pasos[i].texto}'),
            ),
          ],
        ],
        for (final f in finales) figura(f),
      ],
    );
  }
}

class _AvisoSinExtraer extends StatelessWidget {
  final String? motivo;
  const _AvisoSinExtraer({required this.motivo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Este VMI no se pudo extraer automáticamente'
                '${motivo != null ? ' ($motivo)' : ''}. '
                'Consulta el PDF original más abajo.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
