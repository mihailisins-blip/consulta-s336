import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';

import 'data/data_folder.dart';
import 'data/db.dart';
import 'hub/hub_screen.dart';

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
/// antes de mostrar nada más (R25 / AE6), luego abre data.sqlite y muestra
/// el panel-hub (U10).
class _DataFolderGate extends StatefulWidget {
  final DataFolderResult? resultOverride;
  const _DataFolderGate({this.resultOverride});

  @override
  State<_DataFolderGate> createState() => _DataFolderGateState();
}

class _DataFolderGateState extends State<_DataFolderGate> {
  late final Future<DataFolderResult> _future;
  Database? _db;

  @override
  void initState() {
    super.initState();
    _future = widget.resultOverride != null
        ? Future.value(widget.resultOverride)
        : loadDataFolder(resolveDataDir(allowDebugOverride: kDebugMode));
  }

  @override
  void dispose() {
    _db?.dispose();
    super.dispose();
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
          DataFolderReady() => _buildReady(result),
          DataFolderMissing() => _DataFolderProblemScreen(
            title: 'No se encuentra la carpeta de datos',
            message:
                'Se esperaba en:\n${result.expectedPath}\n\n'
                'Coloca la carpeta "datos" junto al ejecutable, o pide una al curador.',
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

  /// `loadDataFolder` solo valida `manifest.json` (forma + schema_version)
  /// -- nunca intenta abrir `data.sqlite` en sí. Una carpeta con el schema
  /// correcto pero un `data.sqlite` corrupto (p. ej. truncado a medias por
  /// una copia interrumpida) pasaría ese chequeo igualmente. `sqlite3.open`
  /// tampoco sirve de comprobación por sí sola: SQLite abre el archivo de
  /// forma perezosa y no lee su contenido hasta la primera sentencia real
  /// -- `open()` nunca lanza para un archivo corrupto, solo la primera
  /// query (comprobado en la práctica: hasta un `SELECT 1` sin tabla
  /// dispara `SqliteException(26)` "file is not a database"). Por eso se
  /// fuerza aquí esa primera lectura, dentro del try/catch, en vez de
  /// dejar que la carpeta dañada se descubra tarde y en cualquier sitio --
  /// dentro del build() de HubScreen o de la primera pantalla que haga una
  /// consulta real -- como una excepción sin capturar.
  Widget _buildReady(DataFolderReady result) {
    try {
      final db = _db ??= openDataDb(result.dbPath);
      db.select('SELECT 1');
      return HubScreen(db: db, dataDir: result.dataDir);
    } on SqliteException catch (e) {
      _db?.dispose();
      _db = null;
      return _DataFolderProblemScreen(
        title: 'Carpeta de datos dañada',
        message: 'No se pudo abrir data.sqlite: $e',
      );
    }
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
