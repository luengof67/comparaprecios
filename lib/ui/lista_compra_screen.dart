import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/comparativa.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/analitica_service.dart';
import '../services/firestore_service.dart';
import '../services/informe_compra_service.dart';
import 'formato.dart';
import 'lista_foto_screen.dart';
import 'montar_lista_screen.dart';

/// Lista de la compra optima (Fase 1):
/// para cada producto con precios, coge el proveedor mas barato
/// y agrupa los productos POR proveedor, para saber que pedir a cada uno.
class ListaCompraScreen extends StatelessWidget {
  final FirestoreService db;
  const ListaCompraScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'listafoto',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ListaFotoScreen(db: db)),
            ),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Lista por foto'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'montarlista',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MontarListaScreen(db: db)),
            ),
            icon: const Icon(Icons.edit_note),
            label: const Text('Montar lista'),
          ),
        ],
      ),
      body: StreamBuilder<List<Producto>>(
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

                // ¿Hay algún producto con precio en el catálogo?
                final hayPrecios = comparativas.any((c) => c.tieneDatos);

                // Agrupamos por proveedor mas barato, SOLO los productos que se
                // van a pedir (en lista y con cantidad > 0).
                final Map<String, List<ComparativaProducto>> porProveedor = {};
                for (final c in comparativas) {
                  if (!c.tieneDatos) continue;
                  if (!c.producto.enLista) continue;
                  if (c.producto.cantidadEfectiva <= 0) continue;
                  final provId = c.masBarato!.proveedor.id;
                  porProveedor.putIfAbsent(provId, () => []).add(c);
                }

                if (porProveedor.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        hayPrecios
                            ? 'Tu lista está vacía.\n\nMonta tu pedido de la semana '
                                'con los botones de abajo: escríbelo, hazle una foto '
                                'o toca "Montar lista".'
                            : 'Añade precios a tus productos y aquí verás\n'
                                'qué comprar a cada proveedor.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
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
                // Para el "todo en un solo proveedor":
                final Map<String, double> totalPorProv = {};
                final Map<String, int> coberturaPorProv = {};
                for (final c in comparativas) {
                  if (!c.tieneDatos) continue;
                  if (!c.producto.enLista) continue;
                  final cant = c.producto.cantidadEfectiva;
                  if (cant <= 0) continue;
                  conCantidad++;
                  costeOptimo += c.precioMin * cant;
                  ahorroReal += (c.precioMax - c.precioMin) * cant;
                  for (final o in c.ofertas) {
                    totalPorProv[o.proveedor.id] =
                        (totalPorProv[o.proveedor.id] ?? 0) +
                            o.precioUnitario * cant;
                    coberturaPorProv[o.proveedor.id] =
                        (coberturaPorProv[o.proveedor.id] ?? 0) + 1;
                  }
                }
                // Mejor proveedor único que tenga TODOS los productos de la lista.
                String? mejorUnicoId;
                double mejorUnicoTotal = 0;
                totalPorProv.forEach((id, total) {
                  if (coberturaPorProv[id] == conCantidad) {
                    if (mejorUnicoId == null || total < mejorUnicoTotal) {
                      mejorUnicoId = id;
                      mejorUnicoTotal = total;
                    }
                  }
                });
                final mapaNombres = {for (final p in proveedores) p.id: p.nombre};
                final ahorroVsUnico =
                    mejorUnicoId != null ? mejorUnicoTotal - costeOptimo : null;

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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reiniciar semana (usar cantidades habituales)'),
                        onPressed: () => _confirmarReinicio(context, db),
                      ),
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
                              if (ahorroVsUnico != null) ...[
                                const Divider(height: 20),
                                Text(
                                  'Si compraras todo en un solo proveedor, el más '
                                  'barato sería ${mapaNombres[mejorUnicoId]} '
                                  '(${euros(mejorUnicoTotal)}).',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Ahorro repartiendo la compra'),
                                    Text(
                                      ahorroVsUnico > 0.005
                                          ? '-${euros(ahorroVsUnico)}'
                                          : '—',
                                      style: TextStyle(
                                          color: ahorroVsUnico > 0.005
                                              ? Colors.green
                                              : Colors.grey,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                const Divider(height: 20),
                                const Text(
                                  'Ningún proveedor tiene todos los productos de '
                                  'la lista, así que repartir la compra es '
                                  'obligado.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                              ],
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
                    const SizedBox(height: 12),
                    if (conCantidad > 0)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Exportar PDF de la compra'),
                          onPressed: () {
                            final incluidas = comparativas
                                .where((c) =>
                                    c.tieneDatos &&
                                    c.producto.enLista &&
                                    c.producto.cantidadEfectiva > 0)
                                .toList();
                            InformeCompraService.generarPdf(incluidas);
                          },
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
      ),
    );
  }

  Future<void> _confirmarReinicio(BuildContext context, FirestoreService db) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reiniciar semana'),
        content: const Text(
            'Se copiará la cantidad habitual de cada producto a la cantidad de '
            'esta semana. Perderás los ajustes semanales que hayas hecho.\n\n'
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reiniciar')),
        ],
      ),
    );
    if (ok == true) await db.reiniciarSemana();
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
      final cant = c.producto.cantidadEfectiva;
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
                IconButton(
                  tooltip: 'Enviar pedido por WhatsApp',
                  icon: const Icon(Icons.send, color: Color(0xFF25D366)),
                  onPressed: () => _enviarWhatsApp(context),
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
            final cant = c.producto.cantidadEfectiva;
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

  /// Construye el texto del pedido (solo productos marcados) y abre WhatsApp.
  Future<void> _enviarWhatsApp(BuildContext context) async {
    final nombre = proveedor?.nombre ?? 'Proveedor';
    final marcados = items.where((c) => c.producto.enLista).toList()
      ..sort((a, b) => a.producto.nombre.compareTo(b.producto.nombre));

    if (marcados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos marcados para este proveedor.')),
      );
      return;
    }

    final buffer = StringBuffer('*Pedido - $nombre*\n');
    for (final c in marcados) {
      final cant = c.producto.cantidadEfectiva;
      final unidad = c.producto.unidadBase.nombre;
      if (cant > 0) {
        buffer.writeln('- ${c.producto.nombre}: ${_num(cant)} $unidad');
      } else {
        buffer.writeln('- ${c.producto.nombre}');
      }
    }

    final texto = Uri.encodeComponent(buffer.toString());

    // Si el proveedor tiene telefono, abrimos su chat directo; si no, elige contacto.
    final tel = _telefono(proveedor?.contacto);
    final url = tel != null
        ? 'https://wa.me/$tel?text=$texto'
        : 'https://wa.me/?text=$texto';

    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
      );
    }
  }

  /// Normaliza el contacto a numero internacional (heuristica para España).
  String? _telefono(String? contacto) {
    if (contacto == null) return null;
    final digitos = contacto.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length < 9) return null;
    // Si son 9 digitos (movil/fijo español), anteponemos 34.
    if (digitos.length == 9) return '34$digitos';
    return digitos; // ya trae prefijo de pais
  }

  void _editarCantidad(BuildContext context, Producto producto, String unidad) {
    final ctrl = TextEditingController(
      text: producto.cantidadEfectiva > 0 ? _num(producto.cantidadEfectiva) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(producto.nombre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad esta semana ($unidad)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Habitual: ${_num(producto.cantidadHabitual)} $unidad',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0;
              db.setCantidadSemana(producto.id, v);
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
