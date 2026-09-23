// Navegación "por sistema" (R13/R15): lista de sistemas -> ficha del
// sistema + sus manuales de `05` + sus actividades agrupadas por ciclo. El
// técnico solo consulta -- ningún control de edición aquí (R18; la edición
// es U14/Fase C).

import 'package:flutter/material.dart';
// Database, no la clase Row de sqlite3 -- Row también es el widget de layout
// de Flutter, y ambas librerías la exportan.
import 'package:sqlite3/sqlite3.dart' hide Row;

import '../data/queries.dart';
import 'recientes.dart';

class PorSistemaScreen extends StatelessWidget {
  final Database db;
  final RecientesController recientes;
  const PorSistemaScreen({super.key, required this.db, required this.recientes});

  @override
  Widget build(BuildContext context) {
    final sistemas = listSistemas(db);
    return Scaffold(
      appBar: AppBar(title: const Text('Por sistema')),
      body: ListView.separated(
        itemCount: sistemas.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = sistemas[i];
          return ListTile(
            title: Text('${s.codigo}${s.nombre != null ? ' — ${s.nombre}' : ''}'),
            subtitle: Text('${s.numActividades} actividades'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              recientes.registrar(
                RecienteEntry(
                  tipo: 'sistema',
                  id: s.codigo,
                  titulo: '${s.codigo}${s.nombre != null ? ' — ${s.nombre}' : ''}',
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SistemaDetalleScreen(db: db, codigo: s.codigo),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SistemaDetalleScreen extends StatelessWidget {
  final Database db;
  final String codigo;
  const SistemaDetalleScreen({super.key, required this.db, required this.codigo});

  @override
  Widget build(BuildContext context) {
    final detalle = getSistemaDetalle(db, codigo);
    if (detalle == null) {
      return Scaffold(
        appBar: AppBar(title: Text(codigo)),
        body: const Center(child: Text('Sistema no encontrado.')),
      );
    }
    final s = detalle.sistema;
    final ciclosOrdenados = detalle.actividadesPorCiclo.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: Text('${s.codigo}${s.nombre != null ? ' — ${s.nombre}' : ''}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (detalle.ficha != null) ...[
            Row(
              children: [
                Icon(
                  detalle.ficha!.revisado ? Icons.check_circle : Icons.edit_note,
                  size: 18,
                  color: detalle.ficha!.revisado ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(detalle.ficha!.revisado ? 'Ficha revisada' : 'Ficha en borrador'),
              ],
            ),
            if (detalle.ficha!.cuerpo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detalle.ficha!.cuerpo),
            ],
            const SizedBox(height: 16),
          ],
          if (detalle.manuales.isNotEmpty) ...[
            Text('Manuales', style: Theme.of(context).textTheme.titleMedium),
            for (final m in detalle.manuales)
              ListTile(
                dense: true,
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(m.relPath),
                // U11 abrirá el PDF real embebido; por ahora solo se lista.
              ),
            const SizedBox(height: 16),
          ],
          Text('Actividades por ciclo', style: Theme.of(context).textTheme.titleMedium),
          if (ciclosOrdenados.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin actividades vinculadas a un ciclo.'),
            ),
          for (final ciclo in ciclosOrdenados)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Chip(label: Text(ciclo)),
                  ...detalle.actividadesPorCiclo[ciclo]!.map((c) => Text(c)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
