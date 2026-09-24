// Localiza la carpeta de datos (KTD3) y valida su compatibilidad de esquema
// antes de abrir nada (R25 / AE6). En producción vive junto al ejecutable
// (R24); en desarrollo se puede apuntar a otra con `allowDebugOverride` +
// `--dart-define=CONSULTA_S336_DATA_DIR=<ruta>` -- nunca en un build release
// (main.dart pasa `allowDebugOverride: kDebugMode`, no una constante fija).
//
// Deliberadamente sin dependencias de Flutter: se puede testear con
// `flutter test` sin montar ningún widget.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Versión de esquema que este binario sabe leer (KTD3 / R25).
/// Debe coincidir con `SCHEMA_VERSION` en `pipeline/src/build/manifest.js`.
/// v2 (2026-09-23) añadió la tabla `actividad_lote` (R11/R12/AE3).
/// v3 (2026-09-23) añadió `actividad.seguridad`, el texto de la sección 1
/// del VMI (R6/U11).
/// v4 (2026-09-24) añadió `fusion_catalogo` (R22/U15).
const int kExpectedSchemaVersion = 4;

/// Resultado de intentar cargar la carpeta de datos. Sellada a propósito:
/// el llamador (main.dart) debe manejar los cuatro casos explícitamente.
sealed class DataFolderResult {
  const DataFolderResult();
}

/// La carpeta de datos existe, su manifest es legible y el esquema coincide.
class DataFolderReady extends DataFolderResult {
  final String dataDir;
  final String dbPath;
  final DataManifest manifest;
  const DataFolderReady({
    required this.dataDir,
    required this.dbPath,
    required this.manifest,
  });
}

/// No hay carpeta de datos (ni manifest.json ni data.sqlite) en la ruta esperada.
class DataFolderMissing extends DataFolderResult {
  final String expectedPath;
  const DataFolderMissing(this.expectedPath);
}

/// El manifest se leyó bien, pero su `schema_version` no es el que este
/// binario espera (R25 / AE6: nunca cargar datos desajustados en silencio).
class DataFolderVersionMismatch extends DataFolderResult {
  final DataManifest manifest;
  const DataFolderVersionMismatch(this.manifest);
}

/// La carpeta existe pero `manifest.json` no se pudo leer o parsear, o le
/// faltan campos imprescindibles.
class DataFolderCorrupt extends DataFolderResult {
  final String reason;
  const DataFolderCorrupt(this.reason);
}

/// Espejo tipado de `manifest.json` (ver `pipeline/src/build/manifest.js`).
class DataManifest {
  final int schemaVersion;
  final int dataFolderVersion;
  final String buildDate;
  final Map<String, dynamic> sources;
  final Map<String, dynamic> counts;
  final List<dynamic> avisos;

  const DataManifest({
    required this.schemaVersion,
    required this.dataFolderVersion,
    required this.buildDate,
    required this.sources,
    required this.counts,
    required this.avisos,
  });

  factory DataManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'];
    final dataFolderVersion = json['data_folder_version'];
    if (schemaVersion is! int || dataFolderVersion is! int) {
      throw const FormatException(
        "manifest.json debe tener 'schema_version' y 'data_folder_version' numéricos",
      );
    }
    return DataManifest(
      schemaVersion: schemaVersion,
      dataFolderVersion: dataFolderVersion,
      buildDate: json['build_date'] as String? ?? '',
      sources: (json['sources'] as Map?)?.cast<String, dynamic>() ?? const {},
      counts: (json['counts'] as Map?)?.cast<String, dynamic>() ?? const {},
      avisos: (json['avisos'] as List?) ?? const [],
    );
  }
}

/// Nombre de la carpeta de datos, junto al ejecutable. NO se llama "data" a
/// propósito: el propio runner de Flutter Windows ya usa
/// `<exeDir>/data/` para sus archivos de runtime (`flutter_assets/`,
/// `icudtl.dat`, el kernel JIT en debug o `app.so` en release) -- lo
/// descubrió una verificación real de punta a punta (el .exe no arrancaba,
/// "could not resolve the kernel binary", tras copiar ahí la carpeta de
/// datos de la app tal cual). R24 solo pide "junto al ejecutable", no un
/// nombre concreto.
const String kDataDirName = 'datos';

/// Resuelve la carpeta de datos: junto al ejecutable en producción (R24).
///
/// `allowDebugOverride` (pásalo como `kDebugMode` desde main.dart, nunca a
/// mano) habilita `--dart-define=CONSULTA_S336_DATA_DIR=<ruta>` para poder
/// probar con `flutter run`/`flutter test` sin empaquetar el instalador
/// (U16, fuera de alcance aquí) -- en un build release esa variable se
/// ignora siempre, esté definida o no.
String resolveDataDir({bool allowDebugOverride = false}) {
  if (allowDebugOverride) {
    const override = String.fromEnvironment('CONSULTA_S336_DATA_DIR');
    if (override.isNotEmpty) return override;
  }
  final exeDir = p.dirname(Platform.resolvedExecutable);
  return p.join(exeDir, kDataDirName);
}

/// Carga y valida la carpeta de datos en `dataDir`. No lanza excepciones
/// para ningún problema esperable (ausente, corrupta, versión distinta) --
/// esos son resultados de negocio, no errores del programa.
Future<DataFolderResult> loadDataFolder(String dataDir) async {
  final manifestFile = File(p.join(dataDir, 'manifest.json'));
  final dbFile = File(p.join(dataDir, 'data.sqlite'));

  if (!await manifestFile.exists() || !await dbFile.exists()) {
    return DataFolderMissing(dataDir);
  }

  final String raw;
  try {
    raw = await manifestFile.readAsString();
  } on IOException catch (e) {
    return DataFolderCorrupt('no se pudo leer manifest.json: $e');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    return DataFolderCorrupt('manifest.json no es JSON válido: $e');
  }
  if (decoded is! Map<String, dynamic>) {
    return const DataFolderCorrupt('manifest.json no es un objeto JSON');
  }

  final DataManifest manifest;
  try {
    manifest = DataManifest.fromJson(decoded);
  } on FormatException catch (e) {
    return DataFolderCorrupt(e.message);
  }

  if (manifest.schemaVersion != kExpectedSchemaVersion) {
    return DataFolderVersionMismatch(manifest);
  }

  return DataFolderReady(
    dataDir: dataDir,
    dbPath: dbFile.path,
    manifest: manifest,
  );
}
