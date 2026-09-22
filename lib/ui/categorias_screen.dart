import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import 'categorias.dart';
import 'reorganizar_categorias_screen.dart';

/// Gestion de las categorias de producto: la lista vive en Firestore, asi que
/// se puede ampliar sin tocar el codigo. La primera vez que se abre, si la
/// coleccion esta vacia, se siembra con las categorias iniciales.
class CategoriasScreen extends StatefulWidget {
  final FirestoreService db;
  const CategoriasScreen({super.key, required this.db});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  @override
  void initState() {
    super.initState();
    // Idempotente: solo escribe si la coleccion esta vacia de verdad.
    widget.db.sembrarCategoriasSiVacio(categoriasIniciales);
  }

  Future<void> _agregar() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Nombre', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;
    await widget.db.agregarCategoria(nombre);
  }

  Future<void> _borrar(String nombre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar categoría'),
        content: Text(
          '¿Borrar "$nombre"?\n\n'
          'Si algún producto la tiene asignada, no se podrá borrar hasta que '
          'se le cambie la categoría.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final pudo = await widget.db.borrarCategoria(nombre);
    if (!mounted) return;
    if (!pudo) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'No se puede borrar: hay productos con la categoría "$nombre".'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        actions: [
          IconButton(
            tooltip: 'Reorganizar productos entre categorías',
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ReorganizarCategoriasScreen(db: widget.db)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregar,
        icon: const Icon(Icons.add),
        label: const Text('Categoría'),
      ),
      body: StreamBuilder<List<String>>(
        stream: widget.db.categorias(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lista = snap.data!;
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Preparando las categorías…',
                    style: TextStyle(color: Colors.grey)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: lista.length,
            itemBuilder: (_, i) {
              final c = lista[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorCategoria(c).withValues(alpha: 0.15),
                  child: Icon(iconoCategoria(c), color: colorCategoria(c)),
                ),
                title: Text(c),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _borrar(c),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
