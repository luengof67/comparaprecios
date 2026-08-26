import 'package:flutter/material.dart';

import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/comparativa_service.dart';
import '../services/firestore_service.dart';
import 'producto_detalle_screen.dart';

/// Productos cuya comparativa no se cree nadie.
///
/// Solo salen los que tienen DOS O MAS proveedores compitiendo: un producto
/// con un solo precio podra estar mal, pero no le miente a nadie. Lo que
/// ensucia las decisiones es cuando dos precios del mismo producto se
/// separan tanto que uno de los dos tiene que estar mal metido.
///
/// De cada uno se ven todos sus precios con su fecha y su formato, que suele
/// bastar para ver cual es el raro. Y desde ahi se abre el producto, donde ya
/// se puede corregir tanto el precio como la linea de compra.
class DudosasScreen extends StatefulWidget {
  final FirestoreService db;
  const DudosasScreen({super.key, required this.db});

  @override
  State<DudosasScreen> createState() => _DudosasScreenState();
}

class _DudosasScreenState extends State<DudosasScreen> {
  bool _cargando = true;
  String? _error;

  List<Producto> _productos = const [];
  List<Proveedor> _proveedores = const [];
  List<Precio> _precios = const [];

  /// A partir de que separacion entre el mas barato y el siguiente se
  /// considera que algo no cuadra.
  double _umbral = 50;

  /// Cuantos dias atras se miran los precios. Por defecto 120: el objetivo es
  /// justamente repasar los meses antiguos, no los recientes.
  int _dias = 120;

  final Set<String> _revisados = {};

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
      final productos = await widget.db.productos().first;
      final proveedores = await widget.db.proveedores().first;
      final precios = await widget.db.precios().first;
      if (!mounted) return;
      setState(() {
        _productos = productos;
        _proveedores = proveedores;
        _precios = precios;
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

  List<FilaComparativa> get _filas {
    final c = ComparativaService.construir(
      productos: _productos,
      proveedores: _proveedores,
      precios: _precios,
      diasVigencia: _dias,
    );
    final todas = c.grupos.expand((g) => g.filas).toList();
    final dudosas = todas
        .where((f) =>
            f.diferenciaPorcentaje >= _umbral &&
            !_revisados.contains(f.producto.id))
        .toList();
    dudosas.sort(
        (a, b) => b.diferenciaPorcentaje.compareTo(a.diferenciaPorcentaje));
    return dudosas;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparativas dudosas'),
        actions: [
          PopupMenuButton<double>(
            tooltip: 'A partir de qué diferencia',
            icon: const Icon(Icons.tune),
            initialValue: _umbral,
            onSelected: (v) => setState(() => _umbral = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 80, child: Text('Más del 80%')),
              PopupMenuItem(value: 60, child: Text('Más del 60%')),
              PopupMenuItem(value: 50, child: Text('Más del 50%')),
              PopupMenuItem(value: 35, child: Text('Más del 35%')),
            ],
          ),
          PopupMenuButton<int>(
            tooltip: 'Qué antigüedad se mira',
            icon: const Icon(Icons.history),
            initialValue: _dias,
            onSelected: (v) => setState(() => _dias = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 60, child: Text('Últimos 60 días')),
              PopupMenuItem(value: 120, child: Text('Últimos 120 días')),
              PopupMenuItem(value: 3650, child: Text('Todo')),
            ],
          ),
        ],
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

    final filas = _filas;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Productos donde dos proveedores dan precios tan distintos '
                  'que uno de los dos tiene que estar mal metido. Son los que '
                  'de verdad ensucian las decisiones: los productos con un '
                  'solo precio podrán estar mal, pero no compiten con nadie.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '${filas.length} por revisar · diferencia mayor del '
                  '${_umbral.toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (filas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 48, color: Colors.green),
                SizedBox(height: 12),
                Text('Nada que revisar con estos filtros.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          )
        else
          for (final f in filas) _tarjeta(f),
      ],
    );
  }

  Widget _tarjeta(FilaComparativa f) {
    final base = f.producto.unidadBase;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(f.producto.nombre,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text('${f.diferenciaPorcentaje.toStringAsFixed(0)}% de hueco',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800)),
              ],
            ),
            const SizedBox(height: 8),
            for (final c in f.celdas) _celda(c, base),
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      setState(() => _revisados.add(f.producto.id)),
                  child: const Text('Está bien'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductoDetalleScreen(
                            db: widget.db, producto: f.producto),
                      ),
                    );
                    // Al volver, los precios pueden haber cambiado.
                    await _cargar();
                  },
                  child: const Text('Abrir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _celda(CeldaComparativa c, UnidadBase base) {
    final detalle = c.descripcionFormato(base);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Color(c.proveedorColor),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.proveedorNombre,
                    style: TextStyle(
                        fontSize: 13,
                        color: c.obsoleto ? Colors.grey : null)),
                if (detalle.isNotEmpty)
                  Text(detalle,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${c.precioUnitario.toStringAsFixed(2)} ${base.etiqueta}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.obsoleto ? Colors.grey : null),
              ),
              Text('hace ${c.dias} días',
                  style: const TextStyle(
                      fontSize: 10, color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }
}
