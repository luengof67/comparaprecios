import 'package:flutter/material.dart';

import '../models/comparativa.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/analitica_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';
import 'producto_detalle_screen.dart';

class DashboardScreen extends StatelessWidget {
  final FirestoreService db;
  const DashboardScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    // Combinamos los tres streams: productos, proveedores y precios.
    return StreamBuilder<List<Producto>>(
      stream: db.productos(),
      builder: (context, snapProd) {
        return StreamBuilder<List<Proveedor>>(
          stream: db.proveedores(),
          builder: (context, snapProv) {
            return StreamBuilder<List<Precio>>(
              stream: db.precios(),
              builder: (context, snapPre) {
                if (!snapProd.hasData || !snapProv.hasData || !snapPre.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final productos = snapProd.data!;
                final proveedores = snapProv.data!;
                final precios = snapPre.data!;

                if (productos.isEmpty) {
                  return _Vacio(
                    icono: Icons.compare_arrows,
                    titulo: 'Aún no hay comparativa',
                    texto:
                        'Crea tus proveedores y productos, añade algún precio y aquí verás dónde ahorras.',
                  );
                }

                final comparativas =
                    AnaliticaService.compararTodo(productos, precios, proveedores);
                final resumen = AnaliticaService.resumen(comparativas, proveedores);

                // Ordenamos productos por ahorro potencial (donde mas pintas tiene actuar).
                final ordenadas = [...comparativas]
                  ..sort((a, b) => b.ahorroPorUnidad.compareTo(a.ahorroPorUnidad));

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    _Metricas(resumen: resumen),
                    const SizedBox(height: 24),
                    _SubidasRecientes(
                      comparativas: comparativas,
                      onTap: (prod) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProductoDetalleScreen(db: db, producto: prod),
                        ),
                      ),
                    ),
                    Text('Dónde ahorras más',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...ordenadas.where((c) => c.tieneDatos).map(
                          (c) => _FilaProducto(
                            comparativa: c,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductoDetalleScreen(
                                  db: db,
                                  producto: c.producto,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ...ordenadas.where((c) => !c.tieneDatos).map(
                          (c) => ListTile(
                            leading: const Icon(Icons.help_outline, color: Colors.grey),
                            title: Text(c.producto.nombre),
                            subtitle: const Text('Sin precios todavía'),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductoDetalleScreen(
                                  db: db,
                                  producto: c.producto,
                                ),
                              ),
                            ),
                          ),
                        ),
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

/// Las tres tarjetas de cabecera.
class _Metricas extends StatelessWidget {
  final ResumenDashboard resumen;
  const _Metricas({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Card(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.savings, size: 40, color: cs.onPrimaryContainer),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ahorro potencial total',
                          style: TextStyle(color: cs.onPrimaryContainer)),
                      Text(
                        euros(resumen.ahorroPotencialTotal),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'comprando cada producto al más barato (por unidad)',
                        style: TextStyle(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniCard(
                icono: Icons.emoji_events,
                titulo: 'Mejor proveedor',
                valor: resumen.proveedorGanador?.nombre ?? '—',
                detalle: resumen.proveedorGanador != null
                    ? 'gana en ${resumen.vecesGanador} productos'
                    : 'sin datos',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniCard(
                icono: Icons.inventory_2,
                titulo: 'Catálogo',
                valor: '${resumen.productosConDatos}/${resumen.totalProductos}',
                detalle: '${resumen.totalProveedores} proveedores',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;
  final String detalle;
  const _MiniCard({
    required this.icono,
    required this.titulo,
    required this.valor,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(detalle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Una fila de producto en el dashboard: nombre, mas barato y cuanto ahorras.
class _FilaProducto extends StatelessWidget {
  final ComparativaProducto comparativa;
  final VoidCallback onTap;
  const _FilaProducto({required this.comparativa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = comparativa;
    final mejor = c.masBarato!;
    final hayAhorro = c.ahorroPorUnidad > 0.0001;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(c.producto.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Color(mejor.proveedor.color),
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Text(
                '${mejor.proveedor.nombre} · ${euros3(mejor.precioUnitario)}/${c.producto.unidadBase.nombre}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: hayAhorro
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('-${euros3(c.ahorroPorUnidad)}',
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Text('${c.ahorroPorcentaje.toStringAsFixed(0)}% vs caro',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              )
            : const Icon(Icons.check_circle_outline, color: Colors.grey),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  const _Vacio({required this.icono, required this.titulo, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(titulo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Seccion del dashboard con las subidas de precio recientes (vs ultima compra).
class _SubidasRecientes extends StatelessWidget {
  final List<ComparativaProducto> comparativas;
  final void Function(Producto) onTap;
  const _SubidasRecientes({required this.comparativas, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Recolecta subidas (variacion > 0.5%).
    final subidas = <({Producto producto, OfertaProveedor oferta})>[];
    for (final c in comparativas) {
      for (final o in c.ofertas) {
        if (o.variacion != null && o.variacion! > 0.005) {
          subidas.add((producto: c.producto, oferta: o));
        }
      }
    }
    if (subidas.isEmpty) return const SizedBox.shrink();

    subidas.sort((a, b) => b.oferta.variacion!.compareTo(a.oferta.variacion!));
    final top = subidas.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.trending_up, color: Colors.red, size: 20),
            const SizedBox(width: 6),
            Text('Subidas recientes',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        ...top.map((s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.arrow_upward, color: Colors.red),
                title: Text(s.producto.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${s.oferta.proveedor.nombre} · ahora ${euros3(s.oferta.precioUnitario)}/${s.producto.unidadBase.nombre}'),
                trailing: Text(
                  '+${(s.oferta.variacion! * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                onTap: () => onTap(s.producto),
              ),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}
