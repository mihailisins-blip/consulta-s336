// Navegación "por ciclo" (R9/R12/AE2/AE3): elegir programa (km / horas /
// NS) y nivel -> conjunto ACUMULADO de actividades (un nivel incluye las de
// todos los niveles anteriores del mismo programa -- R9), agrupadas por
// sistema, con un desglose por lote cuando el nivel está partido.

import 'package:flutter/material.dart';
// Database, no la clase Row de sqlite3 -- Row también es el widget de layout
// de Flutter, y ambas librerías la exportan.
import 'package:sqlite3/sqlite3.dart' hide Row;

import '../data/queries.dart';
import 'recientes.dart';

const _programas = [
  ('km', 'Por kilómetros'),
  ('horas', 'Por horas de motor (RDH)'),
  ('ns', 'Según condición (NS)'),
];

class PorCicloScreen extends StatefulWidget {
  final Database db;
  final RecientesController recientes;
  const PorCicloScreen({super.key, required this.db, required this.recientes});

  @override
  State<PorCicloScreen> createState() => _PorCicloScreenState();
}

class _PorCicloScreenState extends State<PorCicloScreen> {
  String _programa = 'km';
  String? _nivelCodigo;
  bool _verPorLote = false;

  @override
  Widget build(BuildContext context) {
    final niveles = listNiveles(widget.db, _programa);
    // 'ns' solo tiene el nivel NS en sí -- se selecciona solo.
    final nivelActivo = _nivelCodigo ?? (niveles.length == 1 ? niveles.first.codigo : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Por ciclo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: [
                for (final (value, label) in _programas)
                  ButtonSegment(value: value, label: Text(label)),
              ],
              selected: {_programa},
              onSelectionChanged: (s) => setState(() {
                _programa = s.first;
                _nivelCodigo = null;
                _verPorLote = false;
              }),
            ),
          ),
          if (_programa != 'ns')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final n in niveles)
                    ChoiceChip(
                      label: Text(n.codigo),
                      selected: nivelActivo == n.codigo,
                      onSelected: (_) => setState(() {
                        _nivelCodigo = n.codigo;
                        _verPorLote = false;
                      }),
                    ),
                ],
              ),
            ),
          const Divider(height: 24),
          Expanded(
            child: nivelActivo == null
                ? const Center(child: Text('Elige un nivel.'))
                : _NivelContent(
                    db: widget.db,
                    recientes: widget.recientes,
                    nivelCodigo: nivelActivo,
                    verPorLote: _verPorLote,
                    onVerPorLoteChanged: (v) => setState(() => _verPorLote = v),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NivelContent extends StatelessWidget {
  final Database db;
  final RecientesController recientes;
  final String nivelCodigo;
  final bool verPorLote;
  final ValueChanged<bool> onVerPorLoteChanged;

  const _NivelContent({
    required this.db,
    required this.recientes,
    required this.nivelCodigo,
    required this.verPorLote,
    required this.onVerPorLoteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final resultado = actividadesDeNivel(db, nivelCodigo);
    recientes.registrar(
      RecienteEntry(tipo: 'ciclo', id: nivelCodigo, titulo: nivelCodigo),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${resultado.codigos.length} actividades acumuladas en $nivelCodigo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              // R12: el desglose por lote solo se ofrece cuando el nivel
              // está partido -- AE3.
              if (resultado.lotes.isNotEmpty)
                FilterChip(
                  label: const Text('Ver por lote'),
                  selected: verPorLote,
                  onSelected: onVerPorLoteChanged,
                ),
            ],
          ),
        ),
        Expanded(
          child: verPorLote && resultado.lotes.isNotEmpty
              ? _PorLoteView(db: db, lotes: resultado.lotes)
              : _AgrupadoPorSistemaView(db: db, codigos: resultado.codigos),
        ),
      ],
    );
  }
}

class _AgrupadoPorSistemaView extends StatelessWidget {
  final Database db;
  final List<String> codigos;
  const _AgrupadoPorSistemaView({required this.db, required this.codigos});

  @override
  Widget build(BuildContext context) {
    if (codigos.isEmpty) {
      return const Center(child: Text('Ninguna actividad en este nivel.'));
    }
    final sistemaDe = sistemasDe(db, codigos);
    final porSistema = <String, List<String>>{};
    for (final c in codigos) {
      porSistema.putIfAbsent(sistemaDe[c] ?? '(sin sistema)', () => []).add(c);
    }
    final sistemasOrdenados = porSistema.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final sis in sistemasOrdenados)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Chip(label: Text(sis)),
                ...porSistema[sis]!.map((c) => Text(c)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PorLoteView extends StatelessWidget {
  final Database db;
  final List<String> lotes;
  const _PorLoteView({required this.db, required this.lotes});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final lote in lotes)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lote, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    final acts = actividadesDeLote(db, lote);
                    if (acts.isEmpty) {
                      return const Text('(sin actividades vinculadas a este lote todavía)');
                    }
                    return Wrap(spacing: 8, children: [for (final c in acts) Text(c)]);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
