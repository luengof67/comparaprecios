import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../services/firestore_service.dart';

/// Monta la lista de la compra escribiendo: autocompletar desde el catálogo,
/// pide la cantidad al elegir, y al terminar la lista queda lista para ver
/// el reparto y el ahorro.
class MontarListaScreen extends StatefulWidget {
  final FirestoreService db;
  const MontarListaScreen({super.key, required this.db});

  @override
  State<MontarListaScreen> createState() => _MontarListaScreenState();
}

class _MontarListaScreenState extends State<MontarListaScreen> {
  final _campo = TextEditingController();
  List<Producto> _catalogo = [];
  bool _cargando = true;
  String _busqueda = '';
  // Añadidos en esta sesión: productoId -> cantidad.
  final Map<String, double> _anadidos = {};

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    _catalogo = await widget.db.productos().first;
    if (!mounted) return;
    // Confirmar que se vacía la lista actual para empezar de cero.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Montar lista nueva'),
        content: const Text(
            'Se vaciará la lista actual para que montes una nueva escribiendo. '
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vaciar y empezar')),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await widget.db.setEnListaTodos(false);
    if (mounted) setState(() => _cargando = false);
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  List<Producto> get _sugerencias {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _catalogo.where((p) {
      if (p.nombre.toLowerCase().contains(q)) return true;
      for (final a in p.alias) {
        if (a.texto.toLowerCase().contains(q)) return true;
      }
      return false;
    }).take(8).toList();
  }

  Future<void> _elegir(Producto p) async {
    final ctrl = TextEditingController(
        text: p.cantidadHabitual > 0 ? _n(p.cantidadHabitual) : '');
    final cantidad = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.nombre),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cantidad (${p.unidadBase.nombre})',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
            Navigator.pop(ctx, v);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              Navigator.pop(ctx, v);
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (cantidad == null || cantidad <= 0) return;

    await widget.db.setEnLista(p.id, true);
    await widget.db.setCantidadSemana(p.id, cantidad);
    setState(() {
      _anadidos[p.id] = cantidad;
      _campo.clear();
      _busqueda = '';
    });
  }

  Future<void> _quitar(String id) async {
    await widget.db.setEnLista(id, false);
    setState(() => _anadidos.remove(id));
  }

  Producto? _prod(String id) {
    for (final p in _catalogo) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sug = _sugerencias;
    final sinResultados = _busqueda.trim().isNotEmpty && sug.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Montar lista')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text('Hecho (${_anadidos.length} en la lista)'),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _campo,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Escribe un producto',
                hintText: 'Ej. tomate, aceite, pollo…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _campo.clear();
                          setState(() => _busqueda = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
          // Sugerencias o aviso.
          if (sug.isNotEmpty)
            SizedBox(
              height: 220,
              child: ListView(
                children: sug.map((p) {
                  final yaEsta = _anadidos.containsKey(p.id);
                  return ListTile(
                    title: Text(p.nombre),
                    subtitle: Text(p.categoria),
                    trailing: yaEsta
                        ? const Icon(Icons.check, color: Colors.green)
                        : const Icon(Icons.add),
                    onTap: yaEsta ? null : () => _elegir(p),
                  );
                }).toList(),
              ),
            ),
          if (sinResultados)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: Colors.orange.withValues(alpha: 0.12),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Ese producto no está en tu catálogo, así que no puedo '
                    'darte precio. Créalo antes en la pestaña Productos si '
                    'quieres incluirlo con precios.',
                  ),
                ),
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('En la lista (${_anadidos.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: _anadidos.isEmpty
                ? const Center(
                    child: Text('Ve escribiendo y eligiendo productos',
                        style: TextStyle(color: Colors.grey)))
                : ListView(
                    children: _anadidos.entries.map((e) {
                      final p = _prod(e.key);
                      return ListTile(
                        title: Text(p?.nombre ?? '—'),
                        subtitle: Text(
                            '${_n(e.value)} ${p?.unidadBase.nombre ?? ""}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _quitar(e.key),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  static String _n(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}
