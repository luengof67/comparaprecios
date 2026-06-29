import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

class ComprasScreen extends StatelessWidget {
  final FirestoreService db;
  const ComprasScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NuevaCompraScreen(db: db)),
        ),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Nueva compra'),
      ),
      body: StreamBuilder<List<Compra>>(
        stream: db.compras(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: ${snap.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final compras = snap.data!;
          if (compras.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no has registrado compras.\nPulsa "Nueva compra".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: compras.length,
            itemBuilder: (_, i) {
              final c = compras[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(c.proveedorNombre,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${fecha(c.fecha)} · ${c.lineas.length} líneas'
                    '${c.evento != null && c.evento!.isNotEmpty ? " · ${c.evento}" : ""}',
                  ),
                  trailing: Text(euros(c.total),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  onLongPress: () => _confirmarBorrado(context, c),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmarBorrado(BuildContext context, Compra c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar compra'),
        content: Text('¿Borrar la compra de ${c.proveedorNombre} '
            'del ${fecha(c.fecha)}?\n\n(No borra los precios ya registrados.)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              db.borrarCompra(c.id);
              Navigator.pop(ctx);
            },
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
  }
}

/// --- Pantalla de alta de compra ---
class NuevaCompraScreen extends StatefulWidget {
  final FirestoreService db;
  const NuevaCompraScreen({super.key, required this.db});

  @override
  State<NuevaCompraScreen> createState() => _NuevaCompraScreenState();
}

class _NuevaCompraScreenState extends State<NuevaCompraScreen> {
  String? _proveedorId;
  String _proveedorNombre = '';
  DateTime _fecha = DateTime.now();
  final _eventoCtrl = TextEditingController();
  final List<LineaCompra> _lineas = [];
  bool _guardando = false;

  @override
  void dispose() {
    _eventoCtrl.dispose();
    super.dispose();
  }

  double get _total => _lineas.fold(0, (s, l) => s + l.total);

  Future<void> _guardar() async {
    if (_proveedorId == null) {
      _aviso('Elige un proveedor.');
      return;
    }
    if (_lineas.isEmpty) {
      _aviso('Añade al menos una línea.');
      return;
    }
    setState(() => _guardando = true);
    final compra = Compra(
      id: '',
      proveedorId: _proveedorId!,
      proveedorNombre: _proveedorNombre,
      fecha: _fecha,
      lineas: _lineas,
      evento: _eventoCtrl.text.trim().isEmpty ? null : _eventoCtrl.text.trim(),
    );
    await widget.db.registrarCompra(compra);
    if (mounted) Navigator.pop(context);
  }

  void _aviso(String t) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva compra')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text('Total: ${euros(_total)}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          // Proveedor
          StreamBuilder<List<Proveedor>>(
            stream: widget.db.proveedores(),
            builder: (context, snap) {
              final proveedores = snap.data ?? [];
              return DropdownButtonFormField<String>(
                initialValue: _proveedorId,
                decoration: const InputDecoration(
                    labelText: 'Proveedor', border: OutlineInputBorder()),
                items: proveedores
                    .map((p) =>
                        DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                    .toList(),
                onChanged: (v) {
                  final prov =
                      proveedores.where((p) => p.id == v).firstOrNull;
                  setState(() {
                    _proveedorId = v;
                    _proveedorNombre = prov?.nombre ?? '';
                  });
                },
              );
            },
          ),
          const SizedBox(height: 12),
          // Fecha y evento
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 18),
              const SizedBox(width: 8),
              Text(fecha(_fecha)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _fecha,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => _fecha = d);
                },
                child: const Text('Cambiar fecha'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _eventoCtrl,
            decoration: const InputDecoration(
              labelText: 'Evento (opcional)',
              hintText: 'Ej. Banquete sábado',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          Row(
            children: [
              Text('Líneas (${_lineas.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _agregarLinea,
                icon: const Icon(Icons.add),
                label: const Text('Añadir'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_lineas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sin líneas todavía.',
                  style: TextStyle(color: Colors.grey)),
            ),
          ..._lineas.asMap().entries.map((e) {
            final i = e.key;
            final l = e.value;
            return Card(
              child: ListTile(
                title: Text(l.productoNombre),
                subtitle: Text(
                    '${_num(l.cantidad)} ${l.unidad} × ${euros3(l.precioUnitario)}/${l.unidad}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(euros(l.total),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => _lineas.removeAt(i)),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  void _agregarLinea() {
    if (_proveedorId == null) {
      _aviso('Elige primero el proveedor.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LineaSheet(
        db: widget.db,
        proveedorId: _proveedorId!,
        onAdd: (linea) => setState(() => _lineas.add(linea)),
      ),
    );
  }
}

/// Hoja para añadir una linea: elegir producto, cantidad y precio pagado.
class _LineaSheet extends StatefulWidget {
  final FirestoreService db;
  final String proveedorId;
  final void Function(LineaCompra) onAdd;
  const _LineaSheet({
    required this.db,
    required this.proveedorId,
    required this.onAdd,
  });

  @override
  State<_LineaSheet> createState() => _LineaSheetState();
}

class _LineaSheetState extends State<_LineaSheet> {
  Producto? _producto;
  final _cantidadCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  String? _pista; // texto informativo del precio sugerido

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _precioCtrl.dispose();
    super.dispose();
  }

  /// Al elegir producto: rellena el precio con el ultimo de ESTE proveedor;
  /// si no hay, con el mas barato de cualquiera.
  Future<void> _sugerirPrecio(Producto p) async {
    final precios = await widget.db.preciosDeProductoUnaVez(p.id);
    if (!mounted) return;
    if (precios.isEmpty) {
      setState(() => _pista = 'Sin precios previos. Pon el precio.');
      return;
    }
    // Ultimo de este proveedor.
    final delProveedor =
        precios.where((x) => x.proveedorId == widget.proveedorId).toList()
          ..sort((a, b) => b.fecha.compareTo(a.fecha));
    if (delProveedor.isNotEmpty) {
      final pr = delProveedor.first;
      _precioCtrl.text = _num(pr.precioUnitario);
      setState(() => _pista =
          'Último precio de este proveedor (${fechaCorta(pr.fecha)}).');
      return;
    }
    // Si no hay de este proveedor, el mas barato de cualquiera.
    final masBarato =
        precios.reduce((a, b) => a.precioUnitario <= b.precioUnitario ? a : b);
    _precioCtrl.text = _num(masBarato.precioUnitario);
    setState(() => _pista = 'No hay de este proveedor. Sugerido: el más barato.');
  }

  void _guardar() {
    final cantidad =
        double.tryParse(_cantidadCtrl.text.trim().replaceAll(',', '.'));    final precio =
        double.tryParse(_precioCtrl.text.trim().replaceAll(',', '.'));
    if (_producto == null || cantidad == null || precio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige producto y rellena cantidad y precio.')),
      );
      return;
    }
    widget.onAdd(LineaCompra(
      productoId: _producto!.id,
      productoNombre: _producto!.nombre,
      unidad: _producto!.unidadBase.nombre,
      cantidad: cantidad,
      precioUnitario: precio,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unidad = _producto?.unidadBase.nombre ?? 'ud';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Añadir línea', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            StreamBuilder<List<Producto>>(
              stream: widget.db.productos(),
            builder: (context, snap) {
              final productos = snap.data ?? [];
              return DropdownButtonFormField<String>(
                initialValue: _producto?.id,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Producto', border: OutlineInputBorder()),
                items: productos
                    .map((p) =>
                        DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                    .toList(),
                onChanged: (v) {
                  final prod = productos.where((p) => p.id == v).firstOrNull;
                  setState(() => _producto = prod);
                  if (prod != null) _sugerirPrecio(prod);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cantidadCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Cantidad ($unidad)',
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _precioCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Precio €/$unidad',
                      border: const OutlineInputBorder()),
                ),
              ),
            ],
          ),
          if (_pista != null) ...[
            const SizedBox(height: 6),
            Text(_pista!,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: _guardar, child: const Text('Añadir línea')),
          ),
        ],
        ),
      ),
    );
  }

  String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
