// Una figura del VMI (zona de trabajo o paso del procedimiento), recortada
// del PDF original ya copiado a `<dataDir>/pdfs/vmi/` con el recuadro que
// guarda el pipeline (data/figuras.dart). Al pulsarla abre el VMI en esa
// página, para verla a pantalla completa con zoom.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/figuras.dart';
import 'pdf_viewer.dart';

/// Margen lateral (pt) cuando la figura ocupa todo el ancho de la página.
const double _margenPt = 30;

/// Resolución del recorte: 2 px por punto PDF (144 ppp), nítido a tamaño de
/// lectura sin disparar la memoria con 30 figuras en un mismo detalle.
const double _escala = 2;

class FiguraVmi extends StatefulWidget {
  final String pdfPath;
  final String titulo;
  final ActividadFigura figura;

  const FiguraVmi({super.key, required this.pdfPath, required this.titulo, required this.figura});

  @override
  State<FiguraVmi> createState() => _FiguraVmiState();
}

class _FiguraVmiState extends State<FiguraVmi> {
  ui.Image? _image;
  bool _fallo = false;

  @override
  void initState() {
    super.initState();
    if (File(widget.pdfPath).existsSync()) {
      _render();
    } else {
      _fallo = true;
    }
  }

  Future<void> _render() async {
    PdfDocument? doc;
    try {
      await pdfrxFlutterInitialize();
      doc = await PdfDocument.openFile(widget.pdfPath);
      final f = widget.figura;
      if (f.pagina < 1 || f.pagina > doc.pages.length) throw StateError('página fuera de rango');
      final page = doc.pages[f.pagina - 1];
      final x0 = f.x0 ?? _margenPt;
      final x1 = f.x1 ?? page.width - _margenPt;
      // PDF: origen abajo-izquierda; render(): píxeles desde arriba-izquierda.
      final top = math.max(0.0, page.height - f.y1);
      final bottom = math.min(page.height, page.height - f.y0);
      final pdfImage = await page.render(
        x: (x0 * _escala).round(),
        y: (top * _escala).round(),
        width: ((x1 - x0) * _escala).round(),
        height: ((bottom - top) * _escala).round(),
        fullWidth: page.width * _escala,
        fullHeight: page.height * _escala,
      );
      if (pdfImage == null) throw StateError('render vacío');
      final image = await pdfImage.createImage();
      pdfImage.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) setState(() => _fallo = true);
    } finally {
      await doc?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _abrir(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PdfViewerScreen(path: widget.pdfPath, title: widget.titulo, initialPageNumber: widget.figura.pagina),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pie = widget.figura.pie;
    final Widget cuerpo;
    if (_image != null) {
      cuerpo = ConstrainedBox(
        // a lo ancho de la columna de lectura, sin que un esquema apaisado
        // ocupe una pantalla entera de un monitor ancho
        constraints: const BoxConstraints(maxWidth: 720),
        child: RawImage(image: _image, fit: BoxFit.contain, width: double.infinity),
      );
    } else if (_fallo) {
      cuerpo = Container(
        height: 56,
        alignment: Alignment.center,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Text('Figura en la página ${widget.figura.pagina} del VMI'),
      );
    } else {
      cuerpo = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => _abrir(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cuerpo,
            if (pie != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(pie, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
