// Catálogo de herramientas y consumibles (R8/R13): listado navegable. Cada
// entrada abre el filtro bidireccional actividad<->material (R17/AE7):
// qué actividades usan esta herramienta o consumible, en cualquier ciclo.
// El curador (U14/R8) puede editar el código ERP in-place desde el detalle,
// y (U15/R22) fusionar dos entradas duplicadas, con opción a deshacer.

import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';

import '../app_session.dart';
import '../curacion/campo_editable.dart';
import '../curacion/fusion_catalogo.dart';
import '../data/overrides.dart';
import '../data/queries.dart';
import '../detalle/actividad_detalle.dart';
import 'recientes.dart';

class CatalogoScreen extends StatefulWidget {
  final AppSession session;
  const CatalogoScreen({super.key, required this.session});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  // Al volver del detalle (donde puede haberse fusionado o editado una
  // entrada) hace falta refrescar la lista -- CatalogoScreen ya no puede
  // ser un StatelessWidget puro porque un pop no lo reconstruye solo.
  Future<void> _abrirEntrada(BuildContext context, CatalogoEntrada e) async {
    widget.session.recientes.registrar(
      RecienteEntry(tipo: 'catalogo', id: e.id, titulo: e.descripcion ?? e.id),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogoEntradaDetalleScreen(session: widget.session, entrada: e),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entradas = listCatalogo(widget.session.db);
    final fusiones =
        widget.session.editMode ? listFusionesPendientes(widget.session.db) : const <FusionPendiente>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo')),
      body: Column(
        children: [
          if (fusiones.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Fusiones recientes', style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final f in fusiones)
              ListTile(
                dense: true,
                title: Text('"${f.perdedorDescripcion ?? '?'}" fusionada en '
                    '"${f.supervivienteDescripcion ?? f.supervivienteId}"'),
                trailing: TextButton(
                  onPressed: () {
                    deshacerFusion(widget.session.db, f.id);
                    setState(() {});
                  },
                  child: const Text('Deshacer'),
                ),
              ),
            const Divider(height: 1),
          ],
          Expanded(
            child: ListView.separated(
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
                  onTap: () => _abrirEntrada(context, e),
                );
              },
            ),
          ),
        ],
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
          if (session.editMode) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.call_merge),
              label: const Text('Fusionar con otra entrada'),
              onPressed: () => _fusionar(context),
            ),
          ],
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

  Future<void> _fusionar(BuildContext context) async {
    final elegido = await showDialog<CatalogoEntrada>(
      context: context,
      builder: (_) => _ElegirEntradaDialog(db: session.db, excluirId: entrada.id),
    );
    if (elegido == null) return;
    // La entrada actual siempre es la superviviente -- se fusiona la
    // elegida EN ella, nunca al revés, para que este mismo detalle siga
    // siendo válido después (su id no cambia ni desaparece).
    fusionarCatalogo(session.db, supervivienteId: entrada.id, perdedorId: elegido.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Fusionado "${elegido.descripcion ?? elegido.id}" en "${entrada.descripcion ?? entrada.id}".',
        ),
      ),
    );
    Navigator.of(context).pop();
  }
}

/// Diálogo para elegir la entrada "perdedora" de una fusión (R22): buscador
/// en memoria sobre el catálogo completo, sin la entrada actual.
class _ElegirEntradaDialog extends StatefulWidget {
  final Database db;
  final String excluirId;
  const _ElegirEntradaDialog({required this.db, required this.excluirId});

  @override
  State<_ElegirEntradaDialog> createState() => _ElegirEntradaDialogState();
}

class _ElegirEntradaDialogState extends State<_ElegirEntradaDialog> {
  late final List<CatalogoEntrada> _todas =
      listCatalogo(widget.db).where((e) => e.id != widget.excluirId).toList();
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final filtro = _filtro.trim().toLowerCase();
    final filtradas = filtro.isEmpty
        ? _todas
        : _todas.where((e) => (e.descripcion ?? e.id).toLowerCase().contains(filtro)).toList();
    return AlertDialog(
      title: const Text('Fusionar con...'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buscar entrada...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtradas.isEmpty
                  ? const Center(child: Text('Sin resultados.'))
                  : ListView.builder(
                      itemCount: filtradas.length,
                      itemBuilder: (context, i) {
                        final e = filtradas[i];
                        return ListTile(
                          title: Text(e.descripcion ?? e.id),
                          subtitle: e.codigoErp != null ? Text('ERP ${e.codigoErp}') : null,
                          onTap: () => Navigator.of(context).pop(e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
      ],
    );
  }
}
