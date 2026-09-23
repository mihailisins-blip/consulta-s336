// Detalle de una actividad (R6/U11): cabecera, ciclos en que aplica,
// herramientas/consumibles con cantidad y uso, zona de trabajo,
// procedimiento por pasos, y medidas de seguridad colapsadas (KTD9). Solo
// lectura -- el técnico consulta, no edita (R18; la edición es Fase C).

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_session.dart';
import '../data/queries.dart';
import '../export/export_xlsx.dart';
import '../hub/por_ciclo_screen.dart';
import '../hub/por_sistema_screen.dart';
import '../hub/recientes.dart';
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
            if (detalle.zonasTrabajo != null) ...[
              const SizedBox(height: 16),
              Text('Zona de trabajo', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(detalle.zonasTrabajo!),
            ],
            if (detalle.pasos.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Procedimiento', style: Theme.of(context).textTheme.titleMedium),
              _Procedimiento(pasos: detalle.pasos),
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

  void _abrirVmi(BuildContext context, ActividadDetalle detalle) {
    final path = p.join(session.dataDir, 'pdfs', 'vmi', detalle.vmiRelPath!);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(path: path, title: detalle.codigo),
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
  const _Procedimiento({required this.pasos});

  @override
  Widget build(BuildContext context) {
    final porFase = <String, List<ActividadPaso>>{};
    for (final paso in pasos) {
      final fase = (paso.fase?.isNotEmpty ?? false) ? paso.fase! : '';
      porFase.putIfAbsent(fase, () => []).add(paso);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in porFase.entries) ...[
          if (entry.key.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(entry.key, style: Theme.of(context).textTheme.titleSmall),
          ],
          for (final paso in entry.value)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text('${paso.n}. ${paso.texto}'),
            ),
        ],
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
