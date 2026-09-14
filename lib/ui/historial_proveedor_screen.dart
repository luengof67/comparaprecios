import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import '../services/historial_compras_service.dart';
import 'corregir_compra_dialog.dart';
import 'formato.dart';

/// Todo lo comprado a un proveedor, producto a producto y compra a compra,
/// con la subida o bajada de cada una frente a la anterior.
///
/// Pensado para llevarlo impreso a hablar con el proveedor: "el 10 de agosto
/// el lomo estaba a 15 € y el 18 a 19 €" es justo lo que esta pantalla saca a
/// la luz, aunque las dos compras caigan en el mismo mes.
class HistorialProveedorScreen extends StatefulWidget {
  final FirestoreService db;
  const HistorialProveedorScreen({super.key, required this.db});

  @override
  State<HistorialProveedorScreen> createState() =>
      _HistorialProveedorScreenState();
}

class _HistorialProveedorScreenState extends State<HistorialProveedorScreen> {
  bool _cargando = true;
  String? _error;

  List<Proveedor> _proveedores = const [];
  List<Compra> _compras = const [];
  List<Producto> _productos = const [];

  Proveedor? _proveedor;
  bool _soloConSubidas = true;

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
      final compras = await widget.db.compras().first;
      final productos = await widget.db.productos().first;
      if (!mounted) return;
      setState(() {
        _proveedores = proveedores;
        _compras = compras;
        _productos = productos;
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

  List<HistoricoProducto> get _historicos {
    final p = _proveedor;
    if (p == null) return const [];
    return HistorialComprasService.porProveedor(
      proveedor: p,
      compras: _compras,
      productos: _productos,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _proveedor;
    return Scaffold(
      appBar: AppBar(title: const Text('Historial por proveedor')),
      floatingActionButton: (p == null || _cargando)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => HistorialComprasService.generarPdf(
                titulo: p.nombre,
                historicos: _historicos,
                soloConSubidas: _soloConSubidas,
              ),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _proveedor?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _proveedores
                      .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.nombre, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _proveedor =
                      _proveedores.where((p) => p.id == v).firstOrNull),
                ),
              ),
            ],
          ),
        ),
        if (_proveedor != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Switch(
                  value: _soloConSubidas,
                  onChanged: (v) => setState(() => _soloConSubidas = v),
                ),
                const Expanded(
                  child: Text('Solo productos con alguna subida',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        Expanded(child: _lista()),
      ],
    );
  }

  Widget _lista() {
    final p = _proveedor;
    if (p == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Elige un proveedor para ver su historial.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final todos = _historicos;
    final lista =
        _soloConSubidas ? todos.where((h) => h.tieneAlgunaSubida).toList() : todos;

    if (lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            todos.isEmpty
                ? 'No hay compras registradas a ${p.nombre}.'
                : 'Ningún producto de ${p.nombre} ha subido de precio.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final gastoTotal = lista.fold<double>(0, (s, h) => s + h.gastoTotal);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            '${lista.length} producto${lista.length == 1 ? "" : "s"} · '
            '${euros(gastoTotal)} en total',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final h in lista) _tarjeta(h),
      ],
    );
  }

  Widget _tarjeta(HistoricoProducto h) {
    final u = h.producto.unidadBase.etiqueta;
    final vt = h.variacionTotal;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: h.tieneAlgunaSubida,
        title: Text(h.producto.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${h.compras.length} compra${h.compras.length == 1 ? "" : "s"} · '
          '${euros(h.gastoTotal)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: vt == null
            ? null
            : Text(
                '${vt > 0 ? "+" : ""}${(vt * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: vt > 0.005
                      ? Colors.red.shade700
                      : vt < -0.005
                          ? Colors.green.shade700
                          : Colors.grey,
                ),
              ),
        children: [
          for (final c in h.compras) _filaCompra(c, u, h.producto.unidadBase.nombre),
        ],
      ),
    );
  }

  Widget _filaCompra(CompraDeProducto c, String u, String unidadCantidad) {
    Color? color;
    IconData? icono;
    if (c.sube) {
      color = Colors.red.shade700;
      icono = Icons.arrow_upward;
    } else if (c.baja) {
      color = Colors.green.shade700;
      icono = Icons.arrow_downward;
    }

    return ListTile(
      dense: true,
      onTap: () => CorregirCompraDialog.mostrar(
        context,
        widget.db,
        c,
        unidadCantidad,
        onListo: _cargar,
      ),
      leading: Icon(
        c.numeroAlbaran != null ? Icons.receipt_long : Icons.edit_note,
        size: 18,
        color: Colors.grey.shade500,
      ),
      title: Text(fecha(c.fecha), style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        c.numeroAlbaran != null
            ? 'nº ${c.numeroAlbaran} · ${_num(c.cantidad)} $unidadCantidad'
            : 'a mano · ${_num(c.cantidad)} $unidadCantidad',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 14, color: color),
            const SizedBox(width: 2),
            Text('${(c.variacion!.abs() * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 8),
          ],
          Text('${c.precioUnitario.toStringAsFixed(2)} $u',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
