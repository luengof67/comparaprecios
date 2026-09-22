import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../services/firestore_service.dart';
import 'categorias.dart';

/// Mueve muchos productos de una categoria a otra de golpe.
///
/// Pensado para cuando la lista de categorias cambia (por ejemplo, la vieja
/// "Congelados" se reparte ahora entre "Carne congelada" y "Verdura
/// congelada") y hay que reclasificar lo que ya existia: se elige la
/// categoria de origen, se marcan los productos con casillas y se mandan
/// todos a la categoria de destino en una sola operacion.
class ReorganizarCategoriasScreen extends StatefulWidget {
  final FirestoreService db;
  const ReorganizarCategoriasScreen({super.key, required this.db});

  @override
  State<ReorganizarCategoriasScreen> createState() =>
      _ReorganizarCategoriasScreenState();
}

class _ReorganizarCategoriasScreenState
    extends State<ReorganizarCategoriasScreen> {
  bool _cargando = true;
  bool _moviendo = false;
  String? _error;

  List<Producto> _productos = const [];
  List<String> _categoriasOficiales = const [];

  String? _origen;
  String? _destino;
  final Set<String> _marcados = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final productos = await widget.db.productos().first;
      final categorias = await widget.db.categorias().first;
      if (!mounted) return;
      setState(() {
        _productos = productos;
        _categoriasOficiales = categorias;
        _marcados.clear();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  /// De donde se puede partir: cualquier categoria que tenga de verdad algun
  /// producto puesto, sea o no una de las oficiales. Las categorias viejas
  /// que ya no estan en la lista maestra (p. ej. "Congelados") tienen que
  /// poder elegirse igual, porque son justo las que hay que repartir.
  List<String> get _origenesDisponibles {
    final s = _productos.map((p) => p.categoria).toSet().toList()..sort();
    return s;
  }

  List<Producto> get _productosDelOrigen {
    final o = _origen;
    if (o == null) return const [];
    final l = _productos.where((p) => p.categoria == o).toList()
      ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reorganizar categorías')),
      bottomNavigationBar: (_marcados.isEmpty || _destino == null)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _moviendo ? null : _mover,
                  icon: _moviendo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.drive_file_move_outline),
                  label: Text('Mover ${_marcados.length} a $_destino'),
                ),
              ),
            ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No se ha podido leer:\n\n$_error',
              textAlign: TextAlign.center),
        ),
      );
    }

    final origenes = _origenesDisponibles;
    final productos = _productosDelOrigen;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _origen,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Desde qué categoría',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: origenes
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(iconoCategoria(c),
                                  size: 18, color: colorCategoria(c)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(c,
                                      overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _origen = v;
                  _marcados.clear();
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _destino,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Hacia qué categoría',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _categoriasOficiales
                    .where((c) => c != _origen)
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(iconoCategoria(c),
                                  size: 18, color: colorCategoria(c)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(c,
                                      overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _destino = v),
              ),
            ],
          ),
        ),
        if (_origen == null)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Elige de qué categoría salen los productos que quieres '
                  'repartir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else if (productos.isEmpty)
          const Expanded(
            child: Center(
              child: Text('No hay productos en esa categoría.',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Text('${_marcados.length} de ${productos.length} marcados',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    if (_marcados.length == productos.length) {
                      _marcados.clear();
                    } else {
                      _marcados
                        ..clear()
                        ..addAll(productos.map((p) => p.id));
                    }
                  }),
                  child: Text(_marcados.length == productos.length
                      ? 'Ninguno'
                      : 'Todos'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 90),
              itemCount: productos.length,
              itemBuilder: (_, i) {
                final p = productos[i];
                return CheckboxListTile(
                  dense: true,
                  value: _marcados.contains(p.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _marcados.add(p.id);
                    } else {
                      _marcados.remove(p.id);
                    }
                  }),
                  title: Text(p.nombre),
                  subtitle: Text(p.unidadBase.etiqueta,
                      style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _mover() async {
    final destino = _destino;
    if (destino == null || _marcados.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mover productos'),
        content: Text(
          'Se mueven ${_marcados.length} productos de "$_origen" a '
          '"$destino".\n\n'
          'El histórico de precios y compras no cambia: solo la categoría '
          'del producto.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mover'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _moviendo = true);
    String mensaje;
    try {
      final n = await widget.db
          .moverProductosACategoria(_marcados.toList(), destino);
      mensaje = 'Movidos $n productos a "$destino".';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }
    if (!mounted) return;
    setState(() => _moviendo = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    await _cargar();
  }
}
