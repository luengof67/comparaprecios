import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Mover albaranes y precios sueltos de un proveedor a otro, uno a uno.
///
/// Hace falta cuando dos proveedores se mezclaron pero los dos existen: no se
/// puede fusionar (eso los uniria) ni dejarlo (los datos estan en el sitio
/// equivocado). Hay que ir eligiendo que es de quien.
///
/// El programa no puede saberlo: los nombres de producto no dicen quien lo
/// sirvio. Por eso aqui solo se enseña lo que hay, con su fecha y su numero
/// de albaran, y elige la persona.
class MoverDatosScreen extends StatefulWidget {
  final FirestoreService db;
  const MoverDatosScreen({super.key, required this.db});

  @override
  State<MoverDatosScreen> createState() => _MoverDatosScreenState();
}

class _MoverDatosScreenState extends State<MoverDatosScreen> {
  bool _cargando = true;
  bool _trabajando = false;
  String? _error;

  List<Proveedor> _proveedores = const [];
  List<Producto> _productos = const [];
  List<Compra> _compras = const [];
  List<Precio> _precios = const [];

  Proveedor? _origen;
  Proveedor? _destino;

  final Set<String> _compasMarcadas = {};
  final Set<String> _preciosMarcados = {};

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
      final proveedores = await widget.db.proveedores().first;
      final productos = await widget.db.productos().first;
      final compras = await widget.db.compras().first;
      final precios = await widget.db.precios().first;
      if (!mounted) return;
      setState(() {
        _proveedores = proveedores;
        _productos = productos;
        _compras = compras;
        _precios = precios;
        // Si el origen ya no existe o cambio, se limpian las marcas.
        _compasMarcadas.clear();
        _preciosMarcados.clear();
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

  List<Compra> get _comprasOrigen {
    final o = _origen;
    if (o == null) return const [];
    final l = _compras.where((c) => c.proveedorId == o.id).toList();
    l.sort((a, b) => b.fecha.compareTo(a.fecha));
    return l;
  }

  /// Precios de tarifa (no salidos de una compra) del proveedor origen.
  List<Precio> get _preciosOrigen {
    final o = _origen;
    if (o == null) return const [];
    final l = _precios
        .where((p) =>
            p.proveedorId == o.id && p.fuente != FuentePrecio.compra)
        .toList();
    l.sort((a, b) => b.fecha.compareTo(a.fecha));
    return l;
  }

  String _nombreProducto(String id) =>
      _productos.where((p) => p.id == id).map((p) => p.nombre).firstOrNull ??
      'Producto borrado';

  String? _numero(Compra c) {
    final k = c.origenClave;
    if (k == null || k.isEmpty) return null;
    final t = k.split('|');
    if (t.length < 2) return null;
    final n = t[1].trim();
    return n.isEmpty ? null : n;
  }

  int get _marcados => _compasMarcadas.length + _preciosMarcados.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mover a otro proveedor')),
      bottomNavigationBar: (_origen == null ||
              _destino == null ||
              _marcados == 0)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _trabajando ? null : _mover,
                  icon: _trabajando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.swap_horiz),
                  label: Text('Mover $_marcados a ${_destino!.nombre}'),
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

    final compras = _comprasOrigen;
    final precios = _preciosOrigen;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _origen?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Están ahora en',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _proveedores
                      .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.nombre, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _origen = _proveedores.where((p) => p.id == v).firstOrNull;
                    _compasMarcadas.clear();
                    _preciosMarcados.clear();
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _destino?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Pasan a',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _proveedores
                      .where((p) => p.id != _origen?.id)
                      .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.nombre, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() =>
                      _destino = _proveedores.where((p) => p.id == v).firstOrNull),
                ),
              ],
            ),
          ),
        ),
        if (_origen == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Elige de qué proveedor salen los datos que están mal '
              'colocados.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          )
        else ...[
          if (compras.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Albaranes (${compras.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    if (_compasMarcadas.length == compras.length) {
                      _compasMarcadas.clear();
                    } else {
                      _compasMarcadas
                        ..clear()
                        ..addAll(compras.map((c) => c.id));
                    }
                  }),
                  child: Text(_compasMarcadas.length == compras.length
                      ? 'Ninguno'
                      : 'Todos'),
                ),
              ],
            ),
            for (final c in compras) _tarjetaCompra(c),
          ],
          if (precios.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Precios de tarifa (${precios.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
              'Precios anotados a mano, sin compra detrás.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Card(
              child: Column(
                children: [
                  for (final p in precios)
                    CheckboxListTile(
                      dense: true,
                      value: _preciosMarcados.contains(p.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _preciosMarcados.add(p.id);
                        } else {
                          _preciosMarcados.remove(p.id);
                        }
                      }),
                      title: Text(_nombreProducto(p.productoId),
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${fecha(p.fecha)} · '
                        '${p.precioUnitario.toStringAsFixed(2)} €',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (compras.isEmpty && precios.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Este proveedor no tiene nada que mover.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            ),
        ],
      ],
    );
  }

  Widget _tarjetaCompra(Compra c) {
    final numero = _numero(c);
    final marcada = _compasMarcadas.contains(c.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Checkbox(
          value: marcada,
          onChanged: (v) => setState(() {
            if (v == true) {
              _compasMarcadas.add(c.id);
            } else {
              _compasMarcadas.remove(c.id);
            }
          }),
        ),
        title: Text(
          numero != null ? 'Albarán nº $numero' : 'Compra a mano',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          '${fecha(c.fecha)} · ${c.lineas.length} líneas · ${euros(c.total)}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          for (final l in c.lineas)
            ListTile(
              dense: true,
              title: Text(l.productoNombre,
                  style: const TextStyle(fontSize: 12)),
              trailing: Text(euros(l.total),
                  style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Future<void> _mover() async {
    final origen = _origen, destino = _destino;
    if (origen == null || destino == null) return;

    final nCom = _compasMarcadas.length;
    final nPre = _preciosMarcados.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mover a otro proveedor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('De: "${origen.nombre}"'),
            Text('A: "${destino.nombre}"',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (nCom > 0)
              Text('· $nCom albarán${nCom == 1 ? "" : "es"}, con los precios '
                  'que dejaron en el histórico'),
            if (nPre > 0) Text('· $nPre precio${nPre == 1 ? "" : "s"} de tarifa'),
            const SizedBox(height: 12),
            const Text('Esto no se puede deshacer.',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mover')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _trabajando = true);
    String mensaje;
    try {
      var precios = 0;
      for (final c in _comprasOrigen) {
        if (!_compasMarcadas.contains(c.id)) continue;
        precios += await widget.db.moverCompraDeProveedor(
          compra: c,
          nuevoProveedorId: destino.id,
          nuevoProveedorNombre: destino.nombre,
        );
      }
      for (final id in _preciosMarcados) {
        await widget.db.moverPrecio(id, destino.id);
      }
      mensaje = 'Movidos $nCom albaranes ($precios precios) '
          'y $nPre tarifas a "${destino.nombre}".';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }

    if (!mounted) return;
    setState(() => _trabajando = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    await _cargar();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
