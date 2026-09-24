// Revisión de fichas de sistema (R20/U15): el curador edita el cuerpo y la
// marca como revisada. `ficha_sistema.cuerpo`/`.revisado` son las columnas
// que diff.js YA traspasa intactas entre re-extracciones (Fase A) -- a
// diferencia de duracion/zona/codigo_erp (U14), no pasan por la tabla
// `overrides`: el flujo de revisión es el mecanismo de persistencia en sí,
// no algo que competir con el extraído.
import 'package:flutter/material.dart';
// Database, no la clase Row de sqlite3 -- Row también es el widget de layout
// de Flutter, y ambas librerías la exportan.
import 'package:sqlite3/sqlite3.dart' hide Row;

import '../data/queries.dart';

/// Guarda el cuerpo y el estado de revisión de la ficha de [sistemaCodigo].
/// `INSERT OR REPLACE` porque el pipeline ya crea una fila en borrador para
/// cada sistema (U5) -- pero no asume que exista, por si un test o una
/// carpeta de datos más antigua no la trae.
void guardarFicha(
  Database db,
  String sistemaCodigo, {
  required String cuerpo,
  required bool revisado,
}) {
  db.execute(
    'INSERT OR REPLACE INTO ficha_sistema (sistema_codigo, cuerpo, revisado) VALUES (?,?,?)',
    [sistemaCodigo, cuerpo, revisado ? 1 : 0],
  );
}

/// Editor de ficha para el curador (R20/R16): el técnico siempre ve el
/// índice, la búsqueda y el PDF del sistema esté la ficha revisada o no
/// (eso lo sigue mostrando SistemaDetalleScreen aparte) -- este widget solo
/// se monta dentro de una sección gateada por `session.editMode`.
class FichaEditor extends StatefulWidget {
  final Database db;
  final String sistemaCodigo;
  final FichaSistema? fichaInicial;

  const FichaEditor({
    super.key,
    required this.db,
    required this.sistemaCodigo,
    required this.fichaInicial,
  });

  @override
  State<FichaEditor> createState() => _FichaEditorState();
}

class _FichaEditorState extends State<FichaEditor> {
  late bool _revisado = widget.fichaInicial?.revisado ?? false;
  late final _controller = TextEditingController(text: widget.fichaInicial?.cuerpo ?? '');
  bool _guardadoRecientemente = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _guardar() {
    guardarFicha(widget.db, widget.sistemaCodigo, cuerpo: _controller.text, revisado: _revisado);
    setState(() => _guardadoRecientemente = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _revisado ? Icons.check_circle : Icons.edit_note,
              size: 18,
              color: _revisado ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(_revisado ? 'Ficha revisada' : 'Ficha en borrador'),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                _revisado = !_revisado;
                _guardadoRecientemente = false;
              }),
              child: Text(_revisado ? 'Marcar como borrador' : 'Marcar como revisada'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Síntesis del sistema para el técnico...',
          ),
          onChanged: (_) => setState(() => _guardadoRecientemente = false),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar ficha'),
              onPressed: _guardar,
            ),
            if (_guardadoRecientemente) ...[
              const SizedBox(width: 12),
              const Text('Guardado.'),
            ],
          ],
        ),
      ],
    );
  }
}
