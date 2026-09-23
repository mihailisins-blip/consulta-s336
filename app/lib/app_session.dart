// Agrupa las tres dependencias que casi toda pantalla de solo-lectura
// necesita para consultar y navegar (la conexión a data.sqlite, la carpeta
// de datos para resolver rutas de PDF, y el registro compartido de
// "últimas consultadas") en un único objeto -- antes se repetían como tres
// parámetros sueltos en cada constructor de pantalla.
import 'package:sqlite3/sqlite3.dart';

import 'hub/recientes.dart';

class AppSession {
  final Database db;
  final String dataDir;
  final RecientesController recientes;

  const AppSession({
    required this.db,
    required this.dataDir,
    required this.recientes,
  });
}
