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

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.shopping_cart_checkout, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Comprando al más barato cada producto:\n'
                                '$totalProductos productos repartidos en ${porProveedor.length} proveedores.',
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
  const _BloqueProveedor({required this.proveedor, required this.items});

  @override
  Widget build(BuildContext context) {
    final color = proveedor != null ? Color(proveedor!.color) : Colors.grey;
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
                Text(
                  proveedor?.nombre ?? 'Proveedor borrado',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text('${items.length} ${items.length == 1 ? "producto" : "productos"}',
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          ...items.map((c) {
            final o = c.masBarato!;
            return ListTile(
              dense: true,
              leading: const Icon(Icons.check_box_outline_blank, size: 20),
              title: Text(c.producto.nombre),
              trailing: Text(
                '${euros3(o.precioUnitario)}/${c.producto.unidadBase.nombre}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            );
          }),
        ],
      ),
    );
  }
}
