// Agrupa las dependencias que casi toda pantalla necesita para consultar y
// navegar (la conexión a data.sqlite, la carpeta de datos para resolver
// rutas de PDF, el registro compartido de "últimas consultadas", y si esta
// carpeta de datos es la copia del curador -- U14/R18) en un único objeto
// -- antes db/dataDir/recientes se repetían como tres parámetros sueltos en
// cada constructor de pantalla.
import 'package:sqlite3/sqlite3.dart';

import 'curacion/edit_mode.dart';
import 'hub/recientes.dart';

class AppSession {
  final Database db;
  final String dataDir;
  final RecientesController recientes;

  /// true si `dataDir` es la copia del curador (R18/R19) -- ver
  /// curacion/edit_mode.dart. Solo entonces la UI ofrece controles de
  /// edición; un técnico nunca los ve.
  final bool editMode;

  AppSession({
    required this.db,
    required this.dataDir,
    required this.recientes,
    bool? editMode,
  }) : editMode = editMode ?? esModoEdicion(dataDir);
}
