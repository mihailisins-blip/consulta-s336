// Panel-hub (R13): buscador global permanente + accesos a por sistema, por
// ciclo, catálogo, y últimas consultadas.

import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';

import '../detalle/actividad_detalle.dart';
import '../search/search_service.dart';
import 'catalogo_screen.dart';
import 'por_ciclo_screen.dart';
import 'por_sistema_screen.dart';
import 'recientes.dart';

class HubScreen extends StatefulWidget {
  final Database db;
  final String dataDir;
  const HubScreen({super.key, required this.db, required this.dataDir});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  late final SearchService _search;
  final _recientes = RecientesController();
  final _searchController = TextEditingController();
  List<SearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _search = SearchService(widget.db);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _recientes.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _results = _search.search(value));
  }

  void _abrirResultado(SearchResult r) {
    switch (r.tipo) {
      case SearchResultType.sistema:
        _recientes.registrar(RecienteEntry(tipo: 'sistema', id: r.id, titulo: r.titulo));
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SistemaDetalleScreen(
              db: widget.db,
              dataDir: widget.dataDir,
              codigo: r.id,
              recientes: _recientes,
            ),
          ),
        );
      case SearchResultType.catalogo:
        _recientes.registrar(RecienteEntry(tipo: 'catalogo', id: r.id, titulo: r.titulo));
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CatalogoScreen(db: widget.db, recientes: _recientes)),
        );
      case SearchResultType.actividad:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ActividadDetalleScreen(
              db: widget.db,
              dataDir: widget.dataDir,
              codigo: r.id,
              recientes: _recientes,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consulta S336')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar actividad, sistema, herramienta o consumible…',
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(_iconFor(r.tipo)),
                        title: Text(r.titulo),
                        subtitle: r.chips.isNotEmpty ? Text(r.chips.join(' · ')) : null,
                        onTap: () => _abrirResultado(r),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _HubEntryCard(
                  icon: Icons.category_outlined,
                  label: 'Por sistema',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PorSistemaScreen(
                        db: widget.db,
                        dataDir: widget.dataDir,
                        recientes: _recientes,
                      ),
                    ),
                  ),
                ),
                _HubEntryCard(
                  icon: Icons.timeline_outlined,
                  label: 'Por ciclo',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PorCicloScreen(
                        db: widget.db,
                        dataDir: widget.dataDir,
                        recientes: _recientes,
                      ),
                    ),
                  ),
                ),
                _HubEntryCard(
                  icon: Icons.inventory_2_outlined,
                  label: 'Catálogo',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CatalogoScreen(db: widget.db, recientes: _recientes),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Últimas consultadas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListenableBuilder(
                listenable: _recientes,
                builder: (context, _) {
                  final entradas = _recientes.entradas;
                  if (entradas.isEmpty) {
                    return const Text('Todavía no has consultado nada en esta sesión.');
                  }
                  return ListView(
                    children: [
                      for (final e in entradas)
                        ListTile(
                          dense: true,
                          leading: Icon(_iconForTipo(e.tipo)),
                          title: Text(e.titulo),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(SearchResultType tipo) => switch (tipo) {
    SearchResultType.actividad => Icons.build_outlined,
    SearchResultType.sistema => Icons.category_outlined,
    SearchResultType.catalogo => Icons.inventory_2_outlined,
  };

  IconData _iconForTipo(String tipo) => switch (tipo) {
    'sistema' => Icons.category_outlined,
    'ciclo' => Icons.timeline_outlined,
    'catalogo' => Icons.inventory_2_outlined,
    'actividad' => Icons.build_outlined,
    _ => Icons.history,
  };
}

class _HubEntryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HubEntryCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 100,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32),
              const SizedBox(height: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
