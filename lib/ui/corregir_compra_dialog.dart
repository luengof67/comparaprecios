import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../services/firestore_service.dart';
import '../services/historial_compras_service.dart';
import 'formato.dart';

/// Abre el mismo cuadro de corrección que hay en "En qué albaranes aparece"
/// del detalle de producto, pero aplicado a una fila del historial (por
/// proveedor o por producto). Sirve para arreglar un dato torcido justo donde
/// se ha visto, sin cambiar de pantalla.
///
/// Al guardar se tocan las DOS cosas que hacen falta: la línea dentro de la
/// compra (para los informes de gasto) y el precio que esa línea dejó en el
/// histórico (para la comparativa). Tocar solo una deja las dos partes de la
/// app diciendo cosas distintas del mismo día.
class CorregirCompraDialog {
  static Future<void> mostrar(
    BuildContext context,
    FirestoreService db,
    CompraDeProducto c,
    String unidad, {
    VoidCallback? onListo,
  }) async {
    final cantCtrl = TextEditingController(text: _num(c.cantidad));
    final precioCtrl =
        TextEditingController(text: c.precioUnitario.toStringAsFixed(3));

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
            title: Text(c.compraOrigen.lineas[c.indiceEnCompra].productoNombre),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c.proveedorNombre} · ${fecha(c.fecha)}',
                      style: const TextStyle(fontSize: 12)),
                  if (c.numeroAlbaran != null)
                    SelectableText('albarán nº ${c.numeroAlbaran}',
                        style: const TextStyle(fontSize: 12)),
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
                  Text('Antes: ${euros(c.cantidad * c.precioUnitario)}',
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

    if (!context.mounted) return;

    if (accion == 'guardar' && cant > 0 && precio > 0) {
      await _guardar(context, db, c, cant, precio, onListo);
    } else if (accion == 'borrar') {
      await _confirmarBorrar(context, db, c, onListo);
    }
  }

  static Future<void> _guardar(
    BuildContext context,
    FirestoreService db,
    CompraDeProducto c,
    double cant,
    double precio,
    VoidCallback? onListo,
  ) async {
    String mensaje;
    try {
      final compra = c.compraOrigen;
      final vieja = compra.lineas[c.indiceEnCompra];
      final nuevas = [...compra.lineas];
      nuevas[c.indiceEnCompra] = LineaCompra(
        productoId: vieja.productoId,
        productoNombre: vieja.productoNombre,
        unidad: vieja.unidad,
        cantidad: cant,
        precioUnitario: precio,
      );
      await db.actualizarCompraLineas(compra.id, nuevas);
      await db.actualizarPrecioDeCompra(
        productoId: vieja.productoId,
        proveedorId: compra.proveedorId,
        fecha: compra.fecha,
        nuevoUnitario: precio,
      );
      mensaje = 'Corregido: ${euros(cant * precio)}';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    onListo?.call();
  }

  static Future<void> _confirmarBorrar(
    BuildContext context,
    FirestoreService db,
    CompraDeProducto c,
    VoidCallback? onListo,
  ) async {
    final soloUna = c.compraOrigen.lineas.length == 1;

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
      final compraBorrada = await db.borrarLineaDeCompra(
        compra: c.compraOrigen,
        indice: c.indiceEnCompra,
      );
      mensaje = compraBorrada
          ? 'Línea quitada y albarán borrado por quedarse vacío.'
          : 'Línea quitada de ${c.proveedorNombre}.';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    onListo?.call();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
