import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'data/data_folder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConsultaS336App());
}

class ConsultaS336App extends StatelessWidget {
  /// Solo para tests: sustituye la carga real de la carpeta de datos por un
  /// resultado ya construido. Un widget test que dispara E/S real de
  /// archivos (`loadDataFolder`) dentro de un `FutureBuilder` y luego llama
  /// a `pumpAndSettle()` no es fiable -- se queda colgado indefinidamente
  /// (`data_folder_test.dart` ya prueba esa E/S real de forma directa).
  /// Nunca se pasa desde el arranque real de la app.
  final DataFolderResult? resultOverride;

  const ConsultaS336App({super.key, this.resultOverride});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Consulta S336',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: _DataFolderGate(resultOverride: resultOverride),
    );
  }
}

/// Punto de entrada real de la app: resuelve y valida la carpeta de datos
/// antes de mostrar nada más (R25 / AE6). U10 sustituirá el marcador de
/// posición de "carpeta cargada" por el panel-hub real.
class _DataFolderGate extends StatefulWidget {
  final DataFolderResult? resultOverride;
  const _DataFolderGate({this.resultOverride});

  @override
  State<_DataFolderGate> createState() => _DataFolderGateState();
}

class _DataFolderGateState extends State<_DataFolderGate> {
  late final Future<DataFolderResult> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.resultOverride != null
        ? Future.value(widget.resultOverride)
        : loadDataFolder(resolveDataDir(allowDebugOverride: kDebugMode));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DataFolderResult>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final result = snapshot.data!;
        return switch (result) {
          DataFolderReady() => _DataReadyPlaceholder(result: result),
          DataFolderMissing() => _DataFolderProblemScreen(
            title: 'No se encuentra la carpeta de datos',
            message:
                'Se esperaba en:\n${result.expectedPath}\n\n'
                'Coloca la carpeta "data" junto al ejecutable, o pide una al curador.',
          ),
          DataFolderVersionMismatch() => _DataFolderProblemScreen(
            title: 'Carpeta de datos incompatible',
            message:
                'Esta versión de la app espera el esquema v$kExpectedSchemaVersion, '
                'pero la carpeta de datos es v${result.manifest.schemaVersion}.\n\n'
                'Actualiza la app o pide una carpeta de datos compatible al curador.',
          ),
          DataFolderCorrupt() => _DataFolderProblemScreen(
            title: 'Carpeta de datos dañada',
            message: result.reason,
          ),
        };
      },
    );
  }
}

class _DataFolderProblemScreen extends StatelessWidget {
  final String title;
  final String message;
  const _DataFolderProblemScreen({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marcador de posición hasta que U10 construya el panel-hub real (búsqueda
/// global + por sistema / por ciclo / catálogo / recientes).
class _DataReadyPlaceholder extends StatelessWidget {
  final DataFolderReady result;
  const _DataReadyPlaceholder({required this.result});

  @override
  Widget build(BuildContext context) {
    final m = result.manifest;
    return Scaffold(
      appBar: AppBar(title: const Text('Consulta S336')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Carpeta de datos v${m.dataFolderVersion} cargada',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(result.dataDir, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final entry in m.counts.entries)
              Text('${entry.key}: ${entry.value}'),
          ],
        ),
      ),
    );
  }
}
