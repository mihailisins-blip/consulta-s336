// Visor de PDF embebido con salto a página (U11 / KTD8 / R16). Abre un VMI
// original o un manual de `05` ya copiado a `<dataDir>/pdfs/...` -- nunca
// un PDF en vivo desde el corpus, que puede no estar accesible (R14 es
// explícito: solo texto extraído/curado va a búsqueda, pero el propio PDF
// original SÍ se abre aquí, a diferencia de la búsqueda).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfViewerScreen extends StatelessWidget {
  final String path;
  final String title;

  /// Página en la que abrir el visor (1-based). Cuando no hay un salto
  /// concreto (p. ej. el VMI original, o un manual sin TOC utilizable) se
  /// deja en 1 -- degradación anotada en el plan, no un error (KTD8).
  final int initialPageNumber;

  const PdfViewerScreen({
    super.key,
    required this.path,
    required this.title,
    this.initialPageNumber = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (!File(path).existsSync()) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No se encuentra el PDF en:\n$path', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfViewer.file(path, initialPageNumber: initialPageNumber),
    );
  }
}
