// Desbloqueo del modo edición (U14/R18/R19): un fichero centinela dentro de
// la propia carpeta de datos del curador. Ausente en la copia que reciben
// los técnicos -- que es la misma carpeta de datos, sin ese fichero -- así
// que sin él la UI no ofrece ningún control de edición (R18).
//
// Nota de operación: una re-extracción reemplaza la carpeta de datos entera
// (R24), así que el centinela no sobrevive un reemplazo -- el curador debe
// volver a crearlo tras cada actualización de contenido (documentado en
// packaging/README.md, U16).
import 'dart:io';

import 'package:path/path.dart' as p;

const centinelaCurador = '.curador';

/// true si [dataDir] es la copia del curador (tiene el fichero centinela).
bool esModoEdicion(String dataDir) =>
    File(p.join(dataDir, centinelaCurador)).existsSync();
