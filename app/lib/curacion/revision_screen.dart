// Pantalla de revisión del curador tras una re-extracción (R21/KTD7):
// cambios de origen (`cambio_pendiente`) para marcar como revisados, e
// incidencias de extracción (`incidencia_extraccion`) para consulta. Solo
// se llega aquí desde el hub con `session.editMode` (R18) -- un técnico
// nunca la ve.

import 'package:flutter/material.dart';

import '../app_session.dart';
import '../detalle/actividad_detalle.dart';
import 'revision_cambios.dart';

class RevisionScreen extends StatefulWidget {
  final AppSession session;
  const RevisionScreen({super.key, required this.session});

  @override
  State<RevisionScreen> createState() => _RevisionScreenState();
}

class _RevisionScreenState extends State<RevisionScreen> {
  bool _mostrarRevisados = false;

  void _abrirActividad(String codigo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActividadDetalleScreen(session: widget.session, codigo: codigo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.session.db;
    final cambios = listCambiosPendientes(db, incluirRevisados: _mostrarRevisados);
    final sinRevisar = contarCambiosSinRevisar(db);
    final incidencias = listIncidencias(db);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Revisión de la extracción'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Cambios de origen ($sinRevisar)'),
              Tab(text: 'Incidencias (${incidencias.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCambios(context, cambios, sinRevisar),
            _buildIncidencias(context, incidencias),
          ],
        ),
      ),
    );
  }

  Widget _buildCambios(BuildContext context, List<CambioPendiente> cambios, int sinRevisar) {
    final db = widget.session.db;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          // Wrap, no Row: en una ventana estrecha el botón baja de línea
          // en vez de desbordar.
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _mostrarRevisados,
                    onChanged: (v) => setState(() => _mostrarRevisados = v),
                  ),
                  const SizedBox(width: 8),
                  const Text('Mostrar también los revisados'),
                ],
              ),
              if (sinRevisar > 0)
                TextButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: const Text('Marcar todos como revisados'),
                  onPressed: () {
                    marcarTodosRevisados(db);
                    setState(() {});
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: cambios.isEmpty
              ? const Center(
                  child: Text('No hay cambios de origen pendientes de revisar.'),
                )
              : ListView.separated(
                  itemCount: cambios.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = cambios[i];
                    final actividad = c.actividadCodigo;
                    final abrible = actividad != null && existeActividad(db, actividad);
                    return CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      value: c.revisado,
                      onChanged: (v) {
                        marcarCambioRevisado(db, c.rowid, revisado: v ?? false);
                        setState(() {});
                      },
                      title: Text('${c.entidad} · ${c.id} · ${c.campo}'),
                      subtitle: Text(
                        'Antes: ${c.valorAntes ?? '(vacío)'}\n'
                        'Ahora: ${c.valorDespues ?? '(vacío)'}',
                      ),
                      isThreeLine: true,
                      secondary: abrible
                          ? IconButton(
                              tooltip: 'Abrir actividad',
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () => _abrirActividad(actividad),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildIncidencias(BuildContext context, List<Incidencia> incidencias) {
    if (incidencias.isEmpty) {
      return const Center(child: Text('Esta extracción no dejó incidencias.'));
    }
    final db = widget.session.db;
    return ListView.separated(
      itemCount: incidencias.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final inc = incidencias[i];
        final abrible = existeActividad(db, inc.ref);
        return ListTile(
          leading: const Icon(Icons.report_problem_outlined),
          title: Text(inc.ref),
          subtitle: Text([
            inc.tipo,
            if (inc.detalle != null && inc.detalle!.isNotEmpty) inc.detalle!,
          ].join(' · ')),
          trailing: abrible ? const Icon(Icons.chevron_right) : null,
          onTap: abrible ? () => _abrirActividad(inc.ref) : null,
        );
      },
    );
  }
}
