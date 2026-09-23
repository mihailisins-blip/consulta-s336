// "Últimas consultadas" (R13): lista local por dispositivo, sin
// persistencia compartida. Deliberadamente en memoria por ahora (se
// reinicia al cerrar la app) -- nada en el plan exige que sobreviva a un
// reinicio, solo que no se sincronice entre equipos; si se quiere que
// persista entre sesiones, cambiar el almacén interno por algo como
// shared_preferences sin tocar la API pública de esta clase.

import 'package:flutter/foundation.dart';

class RecienteEntry {
  final String tipo; // 'sistema' | 'ciclo' | 'catalogo'
  final String id;
  final String titulo;
  const RecienteEntry({required this.tipo, required this.id, required this.titulo});
}

class RecientesController extends ChangeNotifier {
  static const int _maxEntradas = 10;
  final List<RecienteEntry> _entradas = [];

  List<RecienteEntry> get entradas => List.unmodifiable(_entradas);

  void registrar(RecienteEntry entrada) {
    _entradas.removeWhere((e) => e.tipo == entrada.tipo && e.id == entrada.id);
    _entradas.insert(0, entrada);
    if (_entradas.length > _maxEntradas) {
      _entradas.removeRange(_maxEntradas, _entradas.length);
    }
    notifyListeners();
  }
}
