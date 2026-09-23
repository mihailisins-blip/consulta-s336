// Catálogo de herramientas y consumibles (R8/R13): listado navegable. El
// filtro bidireccional actividad<->material es U12, todavía no construido
// -- esta pantalla hoy solo lista y muestra el código ERP cuando existe.

import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/queries.dart';
import 'recientes.dart';

class CatalogoScreen extends StatelessWidget {
  final Database db;
  final RecientesController recientes;
  const CatalogoScreen({super.key, required this.db, required this.recientes});

  @override
  Widget build(BuildContext context) {
    final entradas = listCatalogo(db);
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
            onTap: () => recientes.registrar(
              RecienteEntry(tipo: 'catalogo', id: e.id, titulo: e.descripcion ?? e.id),
            ),
          );
        },
      ),
    );
  }
}
