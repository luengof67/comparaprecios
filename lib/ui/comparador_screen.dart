import 'package:flutter/material.dart';

import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/analitica_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Compara varios proveedores entre si: precio unitario producto a producto
/// (solo los productos que TODOS los proveedores elegidos tienen) y el total
/// de la compra con cada uno, con el ahorro de elegir el mejor.
class ComparadorScreen extends StatefulWidget {
  final FirestoreService db;
  const ComparadorScreen({super.key, required this.db});

  @override
  State<ComparadorScreen> createState() => _ComparadorScreenState();
}

class _ComparadorScreenState extends State<ComparadorScreen> {
  final Set<String> _seleccionados = {};
  bool _iniciado = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar proveedores')),
      body: StreamBuilder<List<Proveedor>>(
        stream: widget.db.proveedores(),
        builder: (context, snapProv) {
          return StreamBuilder<List<Producto>>(
            stream: widget.db.productos(),
            builder: (context, snapProd) {
              return StreamBuilder<List<Precio>>(
                stream: widget.db.precios(),
                builder: (context, snapPre) {
                  if (!snapProv.hasData ||
                      !snapProd.hasData ||
                      !snapPre.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final proveedores = snapProv.data!;
                  final productos = snapProd.data!;
                  final precios = snapPre.data!;

                  if (proveedores.length < 2) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Necesitas al menos dos proveedores para comparar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  // Por defecto, todos seleccionados la primera vez.
                  if (!_iniciado) {
                    _seleccionados.addAll(proveedores.map((p) => p.id));
                    _iniciado = true;
                  }

                  final comparativas = AnaliticaService.compararTodo(
                      productos, precios, proveedores);

                  // Precio actual por (producto, proveedor).
                  final mapaProv = {for (final p in proveedores) p.id: p};
                  final elegidos = proveedores
                      .where((p) => _seleccionados.contains(p.id))
                      .toList();

                  // Productos que TODOS los elegidos tienen.
                  final filas = <_FilaComp>[];
                  final totales = <String, double>{
                    for (final p in elegidos) p.id: 0
                  };
                  for (final c in comparativas) {
                    final precioPorProv = <String, double>{
                      for (final o in c.ofertas) o.proveedor.id: o.precioUnitario
                    };
                    final todos = elegidos
                        .every((p) => precioPorProv.containsKey(p.id));
                    if (!todos || elegidos.length < 2) continue;
                    filas.add(_FilaComp(
                      producto: c.producto,
                      precios: precioPorProv,
                    ));
                    for (final p in elegidos) {
                      totales[p.id] =
                          totales[p.id]! + precioPorProv[p.id]! * c.producto.cantidadEfectiva;
                    }
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                    children: [
                      const Text('Elige proveedores a comparar:',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: proveedores.map((p) {
                          final sel = _seleccionados.contains(p.id);
                          return FilterChip(
                            label: Text(p.nombre),
                            selected: sel,
                            avatar: CircleAvatar(
                                backgroundColor: Color(p.color), radius: 8),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _seleccionados.add(p.id);
                              } else {
                                _seleccionados.remove(p.id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      if (elegidos.length < 2)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Selecciona al menos dos proveedores.',
                              style: TextStyle(color: Colors.grey)),
                        )
                      else if (filas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No hay productos que tengan precio en TODOS los '
                            'proveedores elegidos. Prueba con menos proveedores.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        _Tabla(
                          filas: filas,
                          elegidos: elegidos,
                          totales: totales,
                        ),
                      const SizedBox(height: 16),
                      if (elegidos.length >= 2 && filas.isNotEmpty)
                        _Resumen(elegidos: elegidos, totales: totales, mapaProv: mapaProv),
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
}

class _FilaComp {
  final Producto producto;
  final Map<String, double> precios; // provId -> precio unitario
  _FilaComp({required this.producto, required this.precios});
}

class _Tabla extends StatelessWidget {
  final List<_FilaComp> filas;
  final List<Proveedor> elegidos;
  final Map<String, double> totales;
  const _Tabla({
    required this.filas,
    required this.elegidos,
    required this.totales,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 22,
        headingRowColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHighest),
        columns: [
          const DataColumn(label: Text('Producto')),
          ...elegidos.map((p) => DataColumn(
                label: Text(p.nombre,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                numeric: true,
              )),
        ],
        rows: [
          ...filas.map((f) {
            final valores = elegidos.map((p) => f.precios[p.id]!).toList();
            final minV = valores.reduce((a, b) => a < b ? a : b);
            final maxV = valores.reduce((a, b) => a > b ? a : b);
            final unidad = f.producto.unidadBase.nombre;
            return DataRow(cells: [
              DataCell(Text(f.producto.nombre)),
              ...elegidos.map((p) {
                final v = f.precios[p.id]!;
                final esMin = v == minV && minV != maxV;
                final esMax = v == maxV && minV != maxV;
                return DataCell(Text(
                  '${euros3(v)}/$unidad',
                  style: TextStyle(
                    fontWeight: esMin ? FontWeight.bold : FontWeight.normal,
                    color: esMin
                        ? Colors.green.shade700
                        : esMax
                            ? Colors.red.shade700
                            : null,
                  ),
                ));
              }),
            ]);
          }),
          // Fila de totales.
          DataRow(
            color: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)),
            cells: [
              const DataCell(Text('TOTAL compra',
                  style: TextStyle(fontWeight: FontWeight.bold))),
              ...() {
                final vals = elegidos.map((p) => totales[p.id]!).toList();
                final minT = vals.reduce((a, b) => a < b ? a : b);
                final maxT = vals.reduce((a, b) => a > b ? a : b);
                return elegidos.map((p) {
                  final t = totales[p.id]!;
                  final esMin = t == minT && minT != maxT;
                  final esMax = t == maxT && minT != maxT;
                  return DataCell(Text(
                    euros(t),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: esMin
                          ? Colors.green.shade700
                          : esMax
                              ? Colors.red.shade700
                              : null,
                    ),
                  ));
                });
              }(),
            ],
          ),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  final List<Proveedor> elegidos;
  final Map<String, double> totales;
  final Map<String, Proveedor> mapaProv;
  const _Resumen({
    required this.elegidos,
    required this.totales,
    required this.mapaProv,
  });

  @override
  Widget build(BuildContext context) {
    // Mejor (mas barato) y peor (mas caro) en total.
    String? mejorId;
    String? peorId;
    for (final p in elegidos) {
      final t = totales[p.id]!;
      if (mejorId == null || t < totales[mejorId]!) mejorId = p.id;
      if (peorId == null || t > totales[peorId]!) peorId = p.id;
    }
    if (mejorId == null || peorId == null) return const SizedBox.shrink();

    final ahorro = totales[peorId]! - totales[mejorId]!;
    final mejor = mapaProv[mejorId]!;
    final peor = mapaProv[peorId]!;

    return Card(
      color: Colors.green.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Más barato en conjunto: ${mejor.nombre} '
                    '(${euros(totales[mejorId]!)})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (ahorro > 0.005) ...[
              const SizedBox(height: 8),
              Text(
                'Comprando a ${mejor.nombre} en vez de a ${peor.nombre} '
                'ahorras ${euros(ahorro)} en esta compra.',
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
