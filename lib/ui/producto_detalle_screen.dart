import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/comparativa.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/analitica_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

class ProductoDetalleScreen extends StatelessWidget {
  final FirestoreService db;
  final Producto producto;
  const ProductoDetalleScreen({super.key, required this.db, required this.producto});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(producto.nombre),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Chip(label: Text(producto.unidadBase.etiqueta))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirAltaPrecio(context),
        icon: const Icon(Icons.add),
        label: const Text('Añadir precio'),
      ),
      body: StreamBuilder<List<Proveedor>>(
        stream: db.proveedores(),
        builder: (context, snapProv) {
          return StreamBuilder<List<Precio>>(
            stream: db.preciosDeProducto(producto.id),
            builder: (context, snapPre) {
              if (snapProv.hasError || snapPre.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error al cargar:\n${snapProv.error ?? snapPre.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }
              if (!snapProv.hasData || !snapPre.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final proveedores = snapProv.data!;
              final precios = snapPre.data!;
              final c = AnaliticaService.comparar(producto, precios, proveedores);

              if (!c.tieneDatos) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Todavía no hay precios para este producto.\nPulsa "Añadir precio".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  _Comparativa(comparativa: c),
                  const SizedBox(height: 24),
                  Text('Evolución del precio',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _GraficoEvolucion(comparativa: c, proveedores: proveedores),
                  const SizedBox(height: 24),
                  Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._historicoOrdenado(precios).map(
                    (p) => _FilaHistorico(
                      precio: p,
                      proveedor: proveedores.where((pr) => pr.id == p.proveedorId).firstOrNull,
                      unidad: producto.unidadBase.nombre,
                      onBorrar: () => db.borrarPrecio(p.id),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Precio> _historicoOrdenado(List<Precio> precios) =>
      [...precios]..sort((a, b) => b.fecha.compareTo(a.fecha));

  void _abrirAltaPrecio(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AltaPrecioSheet(db: db, producto: producto),
    );
  }
}

/// Tabla de proveedores ordenada por precio. Verde = mas barato, rojo = mas caro.
class _Comparativa extends StatelessWidget {
  final ComparativaProducto comparativa;
  const _Comparativa({required this.comparativa});

  @override
  Widget build(BuildContext context) {
    final c = comparativa;
    final unidad = c.producto.unidadBase.nombre;
    return Card(
      child: Column(
        children: [
          if (c.ahorroPorUnidad > 0.0001)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Text(
                'Ahorras ${euros3(c.ahorroPorUnidad)}/$unidad '
                '(${c.ahorroPorcentaje.toStringAsFixed(0)}%) comprando a ${c.masBarato!.proveedor.nombre}',
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold),
              ),
            ),
          ...c.ofertas.asMap().entries.map((e) {
            final i = e.key;
            final o = e.value;
            final esMejor = i == 0;
            final esPeor = i == c.ofertas.length - 1 && c.ofertas.length > 1;
            return ListTile(
              leading: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(o.proveedor.color),
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(o.proveedor.nombre,
                  style: TextStyle(
                      fontWeight: esMejor ? FontWeight.bold : FontWeight.normal)),
              subtitle: Row(
                children: [
                  Text('actualizado ${fechaCorta(o.fecha)}'),
                  if (o.variacion != null && o.variacion!.abs() > 0.005) ...[
                    const SizedBox(width: 8),
                    Icon(
                      o.variacion! > 0
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 13,
                      color: o.variacion! > 0 ? Colors.red : Colors.green,
                    ),
                    Text(
                      '${(o.variacion!.abs() * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: o.variacion! > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${euros3(o.precioUnitario)}/$unidad',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: esMejor
                          ? Colors.green
                          : esPeor
                              ? Colors.red
                              : null,
                    ),
                  ),
                  if (esMejor)
                    const Text('MÁS BARATO',
                        style: TextStyle(fontSize: 10, color: Colors.green)),
                  if (esPeor)
                    const Text('más caro',
                        style: TextStyle(fontSize: 10, color: Colors.red)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Grafico de lineas: una linea por proveedor a lo largo del tiempo.
class _GraficoEvolucion extends StatelessWidget {
  final ComparativaProducto comparativa;
  final List<Proveedor> proveedores;
  const _GraficoEvolucion({required this.comparativa, required this.proveedores});

  @override
  Widget build(BuildContext context) {
    final precios = comparativa.historico;
    if (precios.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Necesitas al menos dos registros para ver la evolución.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final mapaProv = {for (final p in proveedores) p.id: p};

    // Agrupar por proveedor.
    final Map<String, List<Precio>> porProv = {};
    for (final p in precios) {
      porProv.putIfAbsent(p.proveedorId, () => []).add(p);
    }

    final fechas = precios.map((p) => p.fecha).toList()..sort();
    final minX = fechas.first.millisecondsSinceEpoch.toDouble();
    final maxX = fechas.last.millisecondsSinceEpoch.toDouble();
    final minY = precios.map((p) => p.precioUnitario).reduce((a, b) => a < b ? a : b);
    final maxY = precios.map((p) => p.precioUnitario).reduce((a, b) => a > b ? a : b);
    final margen = (maxY - minY) * 0.15 + 0.01;

    final lineas = <LineChartBarData>[];
    porProv.forEach((provId, lista) {
      final prov = mapaProv[provId];
      if (prov == null) return;
      final puntos = ([...lista]..sort((a, b) => a.fecha.compareTo(b.fecha)))
          .map((p) => FlSpot(
                p.fecha.millisecondsSinceEpoch.toDouble(),
                p.precioUnitario,
              ))
          .toList();
      lineas.add(LineChartBarData(
        spots: puntos,
        isCurved: false,
        color: Color(prov.color),
        barWidth: 3,
        dotData: const FlDotData(show: true),
      ));
    });

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
              child: LineChart(
                LineChartData(
                  minX: minX,
                  maxX: maxX,
                  minY: minY - margen,
                  maxY: maxY + margen,
                  lineBarsData: lineas,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(2),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (maxX - minX) <= 0 ? null : (maxX - minX),
                        getTitlesWidget: (v, _) {
                          final d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(fechaCorta(d),
                                style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: porProv.keys.map((id) {
            final prov = mapaProv[id];
            if (prov == null) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: Color(prov.color), shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(prov.nombre, style: const TextStyle(fontSize: 12)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _FilaHistorico extends StatelessWidget {
  final Precio precio;
  final Proveedor? proveedor;
  final String unidad;
  final VoidCallback onBorrar;
  const _FilaHistorico({
    required this.precio,
    required this.proveedor,
    required this.unidad,
    required this.onBorrar,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        precio.fuente == FuentePrecio.albaran ? Icons.receipt_long : Icons.edit_note,
        color: proveedor != null ? Color(proveedor!.color) : Colors.grey,
      ),
      title: Text(proveedor?.nombre ?? 'Proveedor borrado'),
      subtitle: Text(
          '${fecha(precio.fecha)} · ${euros(precio.precioPaquete)} / ${precio.cantidad.toStringAsFixed(precio.cantidad % 1 == 0 ? 0 : 2)} $unidad'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${euros3(precio.precioUnitario)}/$unidad',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onBorrar,
          ),
        ],
      ),
    );
  }
}

/// Hoja para registrar un nuevo precio de un proveedor.
class _AltaPrecioSheet extends StatefulWidget {
  final FirestoreService db;
  final Producto producto;
  const _AltaPrecioSheet({required this.db, required this.producto});

  @override
  State<_AltaPrecioSheet> createState() => _AltaPrecioSheetState();
}

class _AltaPrecioSheetState extends State<_AltaPrecioSheet> {
  String? _proveedorId;
  final _precioCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '1');
  final _notaCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  @override
  void dispose() {
    _precioCtrl.dispose();
    _cantidadCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  double get _precioUnitario {
    final p = double.tryParse(_precioCtrl.text.replaceAll(',', '.')) ?? 0;
    final c = double.tryParse(_cantidadCtrl.text.replaceAll(',', '.')) ?? 1;
    return c > 0 ? p / c : 0;
  }

  Future<void> _guardar() async {
    final precio = double.tryParse(_precioCtrl.text.replaceAll(',', '.'));
    final cantidad = double.tryParse(_cantidadCtrl.text.replaceAll(',', '.'));
    if (_proveedorId == null || precio == null || cantidad == null || cantidad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige proveedor y rellena precio y cantidad.')),
      );
      return;
    }
    setState(() => _guardando = true);
    await widget.db.registrarPrecio(Precio.nuevo(
      productoId: widget.producto.id,
      proveedorId: _proveedorId!,
      precioPaquete: precio,
      cantidad: cantidad,
      fecha: _fecha,
      nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unidad = widget.producto.unidadBase.nombre;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: StreamBuilder<List<Proveedor>>(
        stream: widget.db.proveedores(),
        builder: (context, snap) {
          final proveedores = snap.data ?? [];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nuevo precio · ${widget.producto.nombre}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _proveedorId,
                decoration: const InputDecoration(
                    labelText: 'Proveedor', border: OutlineInputBorder()),
                items: proveedores
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                    .toList(),
                onChanged: (v) => setState(() => _proveedorId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _precioCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Precio (€)', border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cantidadCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Cantidad ($unidad)',
                          border: const OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('= ${euros3(_precioUnitario)}/$unidad',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar precio'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
