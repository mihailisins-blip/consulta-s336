// Detalle de una actividad (R6/U11): cabecera, ciclos en que aplica,
// herramientas/consumibles con cantidad y uso, zona de trabajo,
// procedimiento por pasos, y medidas de seguridad colapsadas (KTD9). Solo
// lectura para el técnico (R18); el curador (R18/U14) ve además una
// sección editable para los campos reservados al simulador (R7).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_session.dart';
import '../curacion/campo_editable.dart';
import '../data/overrides.dart';
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
    final zonasImagenes = detalle.imagenes.where((i) => i.seccion == 'zonas').toList();
    final procedimientoImagenes = detalle.imagenes.where((i) => i.seccion == 'procedimiento').toList();

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
            if (detalle.zonasTrabajo != null || zonasImagenes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Zona de trabajo', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              // Con figuras, el texto (que es la lista de sus pies) sería
              // repetir lo que cada figura ya lleva como título.
              if (zonasImagenes.isEmpty) Text(detalle.zonasTrabajo!),
              if (zonasImagenes.isNotEmpty)
                _FigurasDeZona(imagenes: zonasImagenes, dataDir: session.dataDir),
            ],
            if (detalle.pasos.isNotEmpty || procedimientoImagenes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Procedimiento', style: Theme.of(context).textTheme.titleMedium),
              _Procedimiento(
                pasos: detalle.pasos,
                imagenes: procedimientoImagenes,
                dataDir: session.dataDir,
              ),
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
  final List<ActividadImagen> imagenes;
  final String dataDir;
  const _Procedimiento({required this.pasos, required this.imagenes, required this.dataDir});

  @override
  Widget build(BuildContext context) {
    // Elementos en orden de lectura (títulos, pasos, viñetas, avisos...), cada
    // figura justo antes del elemento al que precede (en el PDF la figura va
    // encima de lo que ilustra). Una figura sin elemento al que preceder -- la
    // última de la página, o un VMI sin texto reconocido -- va al final.
    final pendientes = [...imagenes]
      ..sort((a, b) => (a.antesDePaso ?? 1 << 30).compareTo(b.antesDePaso ?? 1 << 30));
    var siguiente = 0;
    final hijos = <Widget>[];
    ActividadPaso? anterior;
    for (final paso in pasos) {
      while (siguiente < pendientes.length &&
          (pendientes[siguiente].antesDePaso ?? 1 << 30) <= paso.orden) {
        hijos.add(FiguraVmi(imagen: pendientes[siguiente++], dataDir: dataDir));
      }
      hijos.add(_ElementoProcedimiento(paso: paso, anterior: anterior, esElPrimero: anterior == null));
      anterior = paso;
    }
    while (siguiente < pendientes.length) {
      hijos.add(FiguraVmi(imagen: pendientes[siguiente++], dataDir: dataDir));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos);
  }
}

/// Un elemento del procedimiento con la separación que le toca según lo que le
/// precede: los títulos y subtítulos se despegan de la lista anterior, y una
/// numeración que vuelve a empezar (1, 2, 3, 1, 2, 3) abre un bloque nuevo en
/// vez de seguir pegada al anterior.
class _ElementoProcedimiento extends StatelessWidget {
  final ActividadPaso paso;
  final ActividadPaso? anterior;
  final bool esElPrimero;
  const _ElementoProcedimiento({
    required this.paso,
    required this.anterior,
    required this.esElPrimero,
  });

  /// Hueco (px) sobre el elemento.
  double get _arriba {
    if (esElPrimero) return 8;
    switch (paso.tipo) {
      case TipoPaso.titulo:
        return 24;
      case TipoPaso.subtitulo:
        return 16;
      case TipoPaso.aviso:
        return 12;
      case TipoPaso.parrafo:
        return 8;
      case TipoPaso.paso:
        final empiezaLista = anterior != null &&
            anterior!.tipo == TipoPaso.paso &&
            (paso.n ?? 0) <= (anterior!.n ?? 0);
        return empiezaLista ? 16 : 6;
      case TipoPaso.subpaso:
      case TipoPaso.vineta:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final Widget contenido;
    switch (paso.tipo) {
      case TipoPaso.titulo:
        contenido = Text(
          paso.texto,
          style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        );
      case TipoPaso.subtitulo:
        contenido = Text(
          paso.texto,
          style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        );
      case TipoPaso.paso:
        contenido = _Marcador(marca: '${paso.n ?? ''}.', ancho: 28, texto: paso.texto, sangria: 8);
      case TipoPaso.subpaso:
        contenido = _Marcador(marca: '${paso.etiqueta ?? ''}.', ancho: 24, texto: paso.texto, sangria: 36);
      case TipoPaso.vineta:
        contenido = _Marcador(marca: '•', ancho: 16, texto: paso.texto, sangria: 16);
      case TipoPaso.parrafo:
        contenido = Padding(padding: const EdgeInsets.only(left: 8), child: Text(paso.texto));
      case TipoPaso.aviso:
        contenido = _AvisoProcedimiento(clase: paso.etiqueta ?? '', texto: paso.texto);
    }
    return Padding(padding: EdgeInsets.only(top: _arriba), child: contenido);
  }
}

/// Marca (número, letra, viñeta) en columna propia: el texto que se parte en
/// varias líneas queda alineado bajo sí mismo, no bajo la marca.
class _Marcador extends StatelessWidget {
  final String marca;
  final double ancho;
  final double sangria;
  final String texto;
  const _Marcador({
    required this.marca,
    required this.ancho,
    required this.sangria,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: sangria),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: ancho, child: Text(marca)),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

/// Aviso, precaución, nota... del procedimiento, como recuadro de color. El
/// cuerpo trae los párrafos separados por salto de línea: si hay más de uno, el
/// primero es el subtítulo del aviso ("Pares de apriete") y va en negrita.
class _AvisoProcedimiento extends StatelessWidget {
  final String clase;
  final String texto;
  const _AvisoProcedimiento({required this.clase, required this.texto});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final upper = clase.toUpperCase();
    final (Color fondo, Color tinta, IconData icono) = switch (upper) {
      'PELIGRO' => (scheme.errorContainer, scheme.onErrorContainer, Icons.warning_amber_rounded),
      'NOTA' || 'INFORMACIÓN' =>
        (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.info_outline),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.warning_amber_rounded),
    };
    final parrafos = texto.split('\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: tinta, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 18, color: tinta),
              const SizedBox(width: 6),
              Text(
                clase,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tinta,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          for (var i = 0; i < parrafos.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                parrafos[i],
                style: TextStyle(
                  color: tinta,
                  fontWeight: (parrafos.length > 1 && i == 0) ? FontWeight.w700 : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Figuras de la zona de trabajo. Hasta dos van una bajo otra; con más, se
/// reparten en dos columnas (la lectura sigue de izquierda a derecha y luego
/// baja), para que una zona con cinco o siete imágenes no sea una columna
/// interminable. Si la ventana es estrecha vuelve a una sola columna.
class _FigurasDeZona extends StatelessWidget {
  final List<ActividadImagen> imagenes;
  final String dataDir;
  const _FigurasDeZona({required this.imagenes, required this.dataDir});

  /// Ancho mínimo por columna para que la figura (y su leyenda) se lean bien.
  static const double _anchoColumnaMinimo = 360;
  static const double _hueco = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final dosColumnas =
            imagenes.length > 2 && c.maxWidth >= 2 * _anchoColumnaMinimo + _hueco;
        if (!dosColumnas) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final i in imagenes) FiguraVmi(imagen: i, dataDir: dataDir)],
          );
        }
        final ancho = ((c.maxWidth - _hueco) / 2).clamp(0.0, FiguraVmi.anchoPorDefecto);
        return Wrap(
          spacing: _hueco,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (final i in imagenes)
              SizedBox(
                width: ancho,
                child: FiguraVmi(imagen: i, dataDir: dataDir, anchoMaximo: ancho),
              ),
          ],
        );
      },
    );
  }
}

/// Figura de un VMI: título, imagen (tocar para ampliar) y, si la lleva, la
/// tabla de componentes numerados que los marcadores de la imagen citan.
class FiguraVmi extends StatelessWidget {
  final ActividadImagen imagen;
  final String dataDir;

  /// Ancho máximo de la imagen y de su leyenda.
  final double anchoMaximo;
  const FiguraVmi({
    super.key,
    required this.imagen,
    required this.dataDir,
    this.anchoMaximo = anchoPorDefecto,
  });

  static const double anchoPorDefecto = 640;

  Widget _imagen({BoxFit fit = BoxFit.contain}) => Image.file(
    File(p.join(dataDir, 'imagenes', imagen.archivo)),
    fit: fit,
    errorBuilder: (_, _, _) => const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Imagen no disponible en esta carpeta de datos.'),
    ),
  );

  void _ampliar(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(maxScale: 6, child: _imagen()),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imagen.titulo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(imagen.titulo!, style: Theme.of(context).textTheme.titleSmall),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: anchoMaximo),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _ampliar(context),
                child: _imagen(),
              ),
            ),
          ),
          if (imagen.leyenda.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: anchoMaximo),
                child: Table(
                  columnWidths: const {0: FixedColumnWidth(40)},
                  border: TableBorder.all(color: scheme.outlineVariant),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    for (final item in imagen.leyenda)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Center(
                              child: Text(item.n, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(item.nombre),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
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
