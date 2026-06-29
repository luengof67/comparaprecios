import 'package:flutter/material.dart';

import '../models/comparativa.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/analitica_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Lista de la compra optima (Fase 1):
/// para cada producto con precios, coge el proveedor mas barato
/// y agrupa los productos POR proveedor, para saber que pedir a cada uno.
class ListaCompraScreen extends StatelessWidget {
  final FirestoreService db;
  const ListaCompraScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Producto>>(
      stream: db.productos(),
      builder: (context, snapProd) {
        return StreamBuilder<List<Proveedor>>(
          stream: db.proveedores(),
          builder: (context, snapProv) {
            return StreamBuilder<List<Precio>>(
              stream: db.precios(),
              builder: (context, snapPre) {
                if (snapProd.hasError || snapProv.hasError || snapPre.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error al cargar:\n${snapProd.error ?? snapProv.error ?? snapPre.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                if (!snapProd.hasData || !snapProv.hasData || !snapPre.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final productos = snapProd.data!;
                final proveedores = snapProv.data!;
                final precios = snapPre.data!;

                final comparativas =
                    AnaliticaService.compararTodo(productos, precios, proveedores);

                // Agrupamos por proveedor mas barato.
                final Map<String, List<ComparativaProducto>> porProveedor = {};
                for (final c in comparativas) {
                  if (!c.tieneDatos) continue;
                  final provId = c.masBarato!.proveedor.id;
                  porProveedor.putIfAbsent(provId, () => []).add(c);
                }

                if (porProveedor.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Añade precios a tus productos y aquí verás\nqué comprar a cada proveedor.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                final mapaProv = {for (final p in proveedores) p.id: p};

                // Ordenamos proveedores por nº de productos que ganan (desc).
                final provIdsOrdenados = porProveedor.keys.toList()
                  ..sort((a, b) =>
                      porProveedor[b]!.length.compareTo(porProveedor[a]!.length));

                final totalProductos =
                    porProveedor.values.fold<int>(0, (s, l) => s + l.length);

                // --- Calculos en euros (solo productos en lista y con cantidad > 0) ---
                double costeOptimo = 0; // comprando cada uno al mas barato
                double ahorroReal = 0;  // frente a comprarlo todo al mas caro
                int conCantidad = 0;
                for (final c in comparativas) {
                  if (!c.tieneDatos) continue;
                  if (!c.producto.enLista) continue;
                  final cant = c.producto.cantidadHabitual;
                  if (cant <= 0) continue;
                  conCantidad++;
                  costeOptimo += c.precioMin * cant;
                  ahorroReal += (c.precioMax - c.precioMin) * cant;
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.done_all, size: 18),
                            label: const Text('Marcar todo'),
                            onPressed: () => db.setEnListaTodos(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.remove_done, size: 18),
                            label: const Text('Quitar todo'),
                            onPressed: () => db.setEnListaTodos(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shopping_cart_checkout, size: 32),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '$totalProductos productos repartidos en '
                                    '${porProveedor.length} proveedores.',
                                  ),
                                ),
                              ],
                            ),
                            if (conCantidad > 0) ...[
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Coste de la compra'),
                                  Text(euros(costeOptimo),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Ahorro vs comprar al más caro'),
                                  Text('-${euros(ahorroReal)}',
                                      style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18)),
                                ],
                              ),
                            ] else
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Pon la "cantidad que sueles comprar" en tus '
                                  'productos para ver el coste y el ahorro en euros.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...provIdsOrdenados.map((provId) {
                      final prov = mapaProv[provId];
                      final items = porProveedor[provId]!
                        ..sort((a, b) =>
                            a.producto.nombre.compareTo(b.producto.nombre));
                      return _BloqueProveedor(
                        proveedor: prov,
                        items: items,
                        db: db,
                      );
                    }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _BloqueProveedor extends StatelessWidget {
  final Proveedor? proveedor;
  final List<ComparativaProducto> items;
  final FirestoreService db;
  const _BloqueProveedor({
    required this.proveedor,
    required this.items,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    final color = proveedor != null ? Color(proveedor!.color) : Colors.grey;
    // Subtotal del proveedor (solo lo que esta en lista y tiene cantidad).
    double subtotal = 0;
    for (final c in items) {
      final cant = c.producto.cantidadHabitual;
      if (c.producto.enLista && cant > 0) {
        subtotal += c.masBarato!.precioUnitario * cant;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: color, radius: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    proveedor?.nombre ?? 'Proveedor borrado',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (subtotal > 0)
                  Text(euros(subtotal),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16))
                else
                  Text('${items.length} ${items.length == 1 ? "producto" : "productos"}',
                      style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          ...items.map((c) {
            final o = c.masBarato!;
            final cant = c.producto.cantidadHabitual;
            final unidad = c.producto.unidadBase.nombre;
            final activo = c.producto.enLista;
            final estiloTitulo = TextStyle(
              decoration: activo ? null : TextDecoration.lineThrough,
              color: activo ? null : Colors.grey,
            );
            return ListTile(
              dense: true,
              leading: Checkbox(
                value: activo,
                onChanged: (v) => db.setEnLista(c.producto.id, v ?? true),
              ),
              title: Text(c.producto.nombre, style: estiloTitulo),
              subtitle: cant > 0
                  ? Text(
                      '${_num(cant)} $unidad × ${euros3(o.precioUnitario)}/$unidad',
                      style: TextStyle(color: activo ? null : Colors.grey))
                  : Text('Toca para poner cantidad · ${euros3(o.precioUnitario)}/$unidad',
                      style: TextStyle(color: activo ? null : Colors.grey)),
              trailing: (activo && cant > 0)
                  ? Text(
                      euros(o.precioUnitario * cant),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    )
                  : null,
              onTap: () => _editarCantidad(context, c.producto, unidad),
            );
          }),
        ],
      ),
    );
  }

  String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  void _editarCantidad(BuildContext context, Producto producto, String unidad) {
    final ctrl = TextEditingController(
      text: producto.cantidadHabitual > 0 ? _num(producto.cantidadHabitual) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(producto.nombre),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cantidad a comprar ($unidad)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0;
              db.setCantidad(producto.id, v);
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
