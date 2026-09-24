// Campo de texto editable solo por el curador (U14/R18/R19): en modo
// lectura es un simple texto; solo cuando el llamador lo monta dentro de
// una sección gateada por `session.editMode` aparece el control de edición
// -- un técnico (sin el centinela de curacion/edit_mode.dart) nunca ve ni
// este widget ni el botón de lápiz.
import 'package:flutter/material.dart';

class CampoEditable extends StatefulWidget {
  final String etiqueta;
  final String? valorInicial;
  final ValueChanged<String> onGuardar;

  const CampoEditable({
    super.key,
    required this.etiqueta,
    required this.valorInicial,
    required this.onGuardar,
  });

  @override
  State<CampoEditable> createState() => _CampoEditableState();
}

class _CampoEditableState extends State<CampoEditable> {
  late String? _valor;
  bool _editando = false;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _valor = widget.valorInicial;
    _controller.text = _valor ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _guardar() {
    final nuevo = _controller.text.trim();
    widget.onGuardar(nuevo);
    setState(() {
      _valor = nuevo;
      _editando = false;
    });
  }

  void _cancelar() {
    setState(() {
      _controller.text = _valor ?? '';
      _editando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_editando) {
      final mostrado = (_valor?.isNotEmpty ?? false) ? _valor! : '(sin definir)';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${widget.etiqueta}: $mostrado'),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Editar ${widget.etiqueta}',
            onPressed: () => setState(() => _editando = true),
          ),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.etiqueta, isDense: true),
            onSubmitted: (_) => _guardar(),
          ),
        ),
        IconButton(icon: const Icon(Icons.check), tooltip: 'Guardar', onPressed: _guardar),
        IconButton(icon: const Icon(Icons.close), tooltip: 'Cancelar', onPressed: _cancelar),
      ],
    );
  }
}
