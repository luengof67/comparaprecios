import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// En que albaranes aparece este producto, y correccion de esas lineas.
///
/// Sirve para dos cosas: ir al papel (el numero de albaran esta ahi) y
/// arreglar lo que entro mal.
///
/// Al corregir se tocan DOS sitios, y los dos hacen falta:
///   - la linea dentro de la compra, que alimenta los informes de gasto
///   - el precio que esa linea dejo en el historico, que alimenta la
///     comparativa
///
/// Tocar solo uno deja el informe y la comparativa diciendo cosas distintas
/// del mismo dia.
///
/// ComparaPrecios no guarda el escaneo del albaran, solo el dato. El papel
/// esta en TRAZA, y asi se queda: las dos apps van por libre a proposito.
class AlbaranesDelProducto extends StatefulWidget {
  final FirestoreService db;
  final Producto producto;

  /// Cuantos se enseñan como mucho. Los mas recientes.
  final int maximo;

  const AlbaranesDelProducto({
    super.key,
    required this.db,
    required this.producto,
    this.maximo = 20,
  });

  /// El numero de albaran vive dentro de origenClave, que TRAZA compone como
  /// "proveedor|albaran|fecha". Las compras metidas a mano no lo tienen.
  static String? numeroDeAlbaran(Compra c) {
    final k = c.origenClave;
    if (k == null || k.isEmpty) return null;
    final trozos = k.split('|');
    if (trozos.length < 2) return null;
    final n = trozos[1].trim();
    return n.isEmpty ? null : n;
  }

  @override
  State<AlbaranesDelProducto> createState() => _AlbaranesDelProductoState();
}

class _AlbaranesDelProductoState extends State<AlbaranesDelProducto> {
  @override
  Widget build(BuildContext context) {
    final unidad = widget.producto.unidadBase.nombre;

    return StreamBuilder<List<Compra>>(
      stream: widget.db.compras(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        // Firestore no puede filtrar dentro de un array de mapas, asi que las
        // lineas se recorren aqui. Se guarda el indice porque hace falta para
        // poder sustituir o quitar esa linea concreta.
        final conEste = <(Compra, LineaCompra, int)>[];
        for (final c in snap.data!) {
          for (var i = 0; i < c.lineas.length; i++) {
            if (c.lineas[i].productoId == widget.producto.id) {
              conEste.add((c, c.lineas[i], i));
            }
          }
        }
        if (conEste.isEmpty) return const SizedBox.shrink();

        conEste.sort((a, b) => b.$1.fecha.compareTo(a.$1.fecha));

        final gastado = conEste.fold<double>(0, (s, e) => s + e.$2.total);
        final cantidad = conEste.fold<double>(0, (s, e) => s + e.$2.cantidad);
        final visibles = conEste.take(widget.maximo).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text('En qué albaranes aparece',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${conEste.length} compra${conEste.length == 1 ? "" : "s"} · '
              '${_num(cantidad)} $unidad · ${euros(gastado)} en total · '
              'toca para corregir',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final (c, l, i) in visibles) _fila(c, l, i, unidad),
                ],
              ),
            ),
            if (conEste.length > visibles.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'y ${conEste.length - visibles.length} más antiguas',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _fila(Compra c, LineaCompra l, int indice, String unidad) {
    final numero = AlbaranesDelProducto.numeroDeAlbaran(c);

    return ListTile(
      dense: true,
      onTap: () => _corregir(c, l, indice, unidad),
      leading: Icon(
        numero == null ? Icons.edit_note : Icons.receipt_long,
        size: 20,
        color: Colors.grey.shade600,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              c.proveedorNombre.isEmpty ? 'Sin proveedor' : c.proveedorNombre,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (numero != null)
            Text(
              'nº $numero',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800),
            )
          else
            Text('a mano',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
      subtitle: Text(
        '${fecha(c.fecha)} · ${_num(l.cantidad)} $unidad '
        'a ${euros3(l.precioUnitario)}/$unidad',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(euros(l.total),
          style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  /// Abre el cuadro de correccion. Devuelve 'guardar', 'borrar' o nada.
  Future<void> _corregir(
      Compra c, LineaCompra l, int indice, String unidad) async {
    final cantCtrl = TextEditingController(text: _num(l.cantidad));
    final precioCtrl =
        TextEditingController(text: l.precioUnitario.toStringAsFixed(3));

    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final cant =
              double.tryParse(cantCtrl.text.replaceAll(',', '.')) ?? 0;
          final precio =
              double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
          final nuevo = cant * precio;

          return AlertDialog(
            title: Text(widget.producto.nombre),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c.proveedorNombre} · ${fecha(c.fecha)}',
                      style: const TextStyle(fontSize: 12)),
                  if (AlbaranesDelProducto.numeroDeAlbaran(c) != null)
                    SelectableText(
                      'albarán nº ${AlbaranesDelProducto.numeroDeAlbaran(c)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cantCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Cantidad ($unidad)',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setDlg(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: precioCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: '€/$unidad',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setDlg(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Antes: ${euros(l.total)}',
                      style: const TextStyle(fontSize: 12)),
                  Text('Ahora: ${euros(nuevo)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text(
                    'Se corrige el total de la compra y también el precio que '
                    'esta línea dejó en el histórico.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'borrar'),
                child: const Text('Quitar línea',
                    style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed:
                    nuevo > 0 ? () => Navigator.pop(ctx, 'guardar') : null,
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    final cant = double.tryParse(cantCtrl.text.replaceAll(',', '.')) ?? 0;
    final precio = double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
    cantCtrl.dispose();
    precioCtrl.dispose();

    if (accion == 'guardar') {
      if (cant <= 0 || precio <= 0) return;
      await _guardar(c, l, indice, cant, precio);
    } else if (accion == 'borrar') {
      await _borrar(c, indice);
    }
  }

  Future<void> _guardar(
      Compra c, LineaCompra l, int indice, double cant, double precio) async {
    String mensaje;
    try {
      final nuevas = [...c.lineas];
      nuevas[indice] = LineaCompra(
        productoId: l.productoId,
        productoNombre: l.productoNombre,
        unidad: l.unidad,
        cantidad: cant,
        precioUnitario: precio,
      );
      await widget.db.actualizarCompraLineas(c.id, nuevas);
      await widget.db.actualizarPrecioDeCompra(
        productoId: l.productoId,
        proveedorId: c.proveedorId,
        fecha: c.fecha,
        nuevoUnitario: precio,
      );
      mensaje = 'Corregido: ${euros(cant * precio)}';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _borrar(Compra c, int indice) async {
    final soloUna = c.lineas.length == 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar la línea'),
        content: Text(
          soloUna
              ? 'Es la única línea de este albarán, así que se borrará la '
                  'compra entera.\n\nTambién se quita el precio que dejó en el '
                  'histórico.\n\nEsto no se puede deshacer.'
              : 'Se quita esta línea del albarán y el precio que dejó en el '
                  'histórico. El total de la compra se recalcula.\n\n'
                  'Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    String mensaje;
    try {
      final compraBorrada =
          await widget.db.borrarLineaDeCompra(compra: c, indice: indice);
      mensaje = compraBorrada
          ? 'Línea quitada y albarán borrado por quedarse vacío.'
          : 'Línea quitada de ${c.proveedorNombre}.';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
