// Catálogo de herramientas y consumibles (R8/R13): listado navegable. Cada
// entrada abre el filtro bidireccional actividad<->material (R17/AE7):
// qué actividades usan esta herramienta o consumible, en cualquier ciclo.
// El curador (U14/R8) puede editar el código ERP in-place desde el detalle.

import 'package:flutter/material.dart';

import '../app_session.dart';
import '../curacion/campo_editable.dart';
import '../data/overrides.dart';
import '../data/queries.dart';
import '../detalle/actividad_detalle.dart';
import 'recientes.dart';

class CatalogoScreen extends StatelessWidget {
  final AppSession session;
  const CatalogoScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final entradas = listCatalogo(session.db);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo')),
      body: ListView.separated(
        itemCount: entradas.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final e = entradas[i];
          return ListTile(
            title: Text(e.descripcion ?? e.id),
            subtitle: Text([
              if (e.fabricante != null) e.fabricante!,
              if (e.unidad != null) e.unidad!,
            ].join(' · ')),
            trailing: e.codigoErp != null
                ? Chip(label: Text(e.codigoErp!))
                : const Text('sin código ERP', style: TextStyle(fontStyle: FontStyle.italic)),
            onTap: () {
              session.recientes.registrar(
                RecienteEntry(tipo: 'catalogo', id: e.id, titulo: e.descripcion ?? e.id),
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CatalogoEntradaDetalleScreen(session: session, entrada: e),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Filtro bidireccional actividad<->material (R17): desde una entrada del
/// catálogo, todas las actividades que la usan, en cualquier ciclo (AE7).
class CatalogoEntradaDetalleScreen extends StatelessWidget {
  final AppSession session;
  final CatalogoEntrada entrada;
  const CatalogoEntradaDetalleScreen({super.key, required this.session, required this.entrada});

  @override
  Widget build(BuildContext context) {
    final usos = actividadesQueUsan(session.db, entrada.id);
    return Scaffold(
      appBar: AppBar(title: Text(entrada.descripcion ?? entrada.id)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (entrada.fabricante != null) Chip(label: Text(entrada.fabricante!)),
              if (entrada.unidad != null) Chip(label: Text(entrada.unidad!)),
              // Con centinela de curador (U14/R8): editable in-place -- el
              // curador "lo valida y completa" (KD7) directamente aquí, sin
              // salir del detalle. Sin él, el técnico solo ve el chip.
              if (session.editMode)
                CampoEditable(
                  etiqueta: 'Código ERP',
                  valorInicial: entrada.codigoErp,
                  onGuardar: (v) => guardarOverride(session.db, 'catalogo', entrada.id, 'codigo_erp', v),
                )
              else if (entrada.codigoErp != null)
                Chip(label: Text('ERP ${entrada.codigoErp}')),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${usos.length} actividad${usos.length == 1 ? '' : 'es'} la usa${usos.length == 1 ? '' : 'n'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (usos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Ninguna actividad vinculada todavía.'),
            ),
          for (final u in usos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(u.actividadCodigo),
              subtitle: u.descripcionActividad != null ? Text(u.descripcionActividad!) : null,
              trailing: Text(
                [
                  if (u.cant != null) [u.cant, u.ud].whereType<String>().join(' '),
                  if (u.uso != null) u.uso!,
                ].join(' · '),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActividadDetalleScreen(session: session, codigo: u.actividadCodigo),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
