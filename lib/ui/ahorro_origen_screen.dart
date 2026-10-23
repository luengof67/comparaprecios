import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/compra.dart';
import '../services/analitica_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Solo LEE. Explica de dónde sale el "Ahorrado" de Informes.
///
/// El informe calcula, para cada línea comprada:
///     ahorro = (precio MÁS CARO que hay hoy para ese producto, entre todos los
///               proveedores) x cantidad  -  lo que se pagó
/// Si UN solo precio está mal (un envase guardado como si fuera una unidad, un
/// precio de otro formato...), ese precio hace de "más caro" y el ahorro se
/// dispara. Esta pantalla enseña qué productos aportan más y cuáles son
/// sospechosos (el más caro es 3 veces o más lo que se pagó).
class AhorroOrigenScreen extends StatefulWidget {
  final FirestoreService db;
  const AhorroOrigenScreen({super.key, required this.db});

  @override
  State<AhorroOrigenScreen> createState() => _AhorroOrigenScreenState();
}

class _Fila {
  final String nombre;
  final String unidad;
  double ahorro = 0;
  double gastado = 0;
  double cantidad = 0;
  double max = 0;
  String provMax = '';
  DateTime? fechaMax;
  _Fila(this.nombre, this.unidad);

  double get pagado => cantidad != 0 ? gastado / cantidad : 0;
  double get ratio => pagado > 0 ? max / pagado : 0;
  bool get sospechosa => ratio >= 3;
}

class _AhorroOrigenScreenState extends State<AhorroOrigenScreen> {
  bool _cargando = true;
  String? _error;
  List<Compra> _compras = const [];
  Map<String, _InfoMax> _maxPor = {};
  Map<String, ({String nombre, String unidad})> _prods = {};

  String _mes = 'todos'; // 'todos' o 'AAAA-MM'

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final productos = await widget.db.productos().first;
      final precios = await widget.db.precios().first;
      final proveedores = await widget.db.proveedores().first;
      final compras = await widget.db.compras().first;

      final comps = AnaliticaService.compararTodo(productos, precios, proveedores);
      final m = <String, _InfoMax>{};
      for (final c in comps) {
        if (!c.tieneDatos) continue;
        final o = c.masCaro!;
        m[c.producto.id] = _InfoMax(o.precioUnitario, o.proveedor.nombre, o.fecha);
      }
      if (!mounted) return;
      setState(() {
        _compras = compras;
        _maxPor = m;
        _prods = {
          for (final p in productos)
            p.id: (nombre: p.nombre, unidad: p.unidadBase.nombre)
        };
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  String _claveMes(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  List<String> get _meses {
    final s = _compras.map((c) => _claveMes(c.fecha)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return s;
  }

  List<_Fila> _calcular() {
    final filas = <String, _Fila>{};
    for (final c in _compras) {
      if (_mes != 'todos' && _claveMes(c.fecha) != _mes) continue;
      for (final l in c.lineas) {
        final info = _maxPor[l.productoId];
        final p = _prods[l.productoId];
        final f = filas.putIfAbsent(
            l.productoId,
            () => _Fila(p?.nombre ?? l.productoNombre, p?.unidad ?? l.unidad));
        f.gastado += l.total;
        f.cantidad += l.cantidad;
        final max = info?.precio;
        final ref = (max != null && max > l.precioUnitario) ? max : l.precioUnitario;
        f.ahorro += (ref - l.precioUnitario) * l.cantidad;
        if (info != null) {
          f.max = info.precio;
          f.provMax = info.proveedor;
          f.fechaMax = info.fecha;
        }
      }
    }
    final lista = filas.values.where((f) => f.ahorro.abs() > 0.005).toList()
      ..sort((a, b) => b.ahorro.compareTo(a.ahorro));
    return lista;
  }

  String _texto(List<_Fila> filas) {
    final b = StringBuffer('DE DONDE SALE EL AHORRO ($_mes)\n\n');
    for (final f in filas.take(40)) {
      b.writeln('- ${f.nombre}: ahorro ${euros(f.ahorro)} | pagado '
          '${euros3(f.pagado)}/${f.unidad} | mas caro ${euros3(f.max)}/${f.unidad} '
          '(${f.provMax}) | x${f.ratio.toStringAsFixed(1)}'
          '${f.sospechosa ? ' SOSPECHOSO' : ''}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final filas = _cargando || _error != null ? <_Fila>[] : _calcular();
    final total = filas.fold<double>(0, (s, f) => s + f.ahorro);
    final sosp = filas.where((f) => f.sospechosa).toList();
    final totalSosp = sosp.fold<double>(0, (s, f) => s + f.ahorro);

    return Scaffold(
      appBar: AppBar(
        title: const Text('De dónde sale el ahorro'),
        actions: [
          if (!_cargando && _error == null)
            IconButton(
              tooltip: 'Copiar la lista',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _texto(filas)));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lista copiada.')));
              },
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Solo consulta: no cambia nada. El ahorro del informe es '
                      '(precio más caro que hay hoy para cada producto - lo que '
                      'pagaste) x cantidad. Un solo precio mal puesto lo dispara.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _mes,
                      decoration: const InputDecoration(
                          labelText: 'Periodo', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(
                            value: 'todos', child: Text('Todos los meses')),
                        ..._meses.map(
                            (m) => DropdownMenuItem(value: m, child: Text(m))),
                      ],
                      onChanged: (v) => setState(() => _mes = v ?? 'todos'),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ahorro total: ${euros(total)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                                'De ellos, ${euros(totalSosp)} vienen de '
                                '${sosp.length} productos sospechosos (el precio '
                                'más caro es 3 veces o más lo que pagaste).',
                                style: const TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...filas.take(40).map((f) => Card(
                          child: ListTile(
                            leading: Icon(
                                f.sospechosa
                                    ? Icons.warning_amber_outlined
                                    : Icons.savings_outlined,
                                color: f.sospechosa ? Colors.red : Colors.green),
                            title: Text('${f.nombre}  ·  ${euros(f.ahorro)}'),
                            subtitle: Text(
                                'Pagaste ${euros3(f.pagado)}/${f.unidad} '
                                '(${f.cantidad.toStringAsFixed(f.cantidad == f.cantidad.roundToDouble() ? 0 : 1)} ${f.unidad}). '
                                'El más caro: ${euros3(f.max)}/${f.unidad} de '
                                '${f.provMax}'
                                '${f.fechaMax != null ? ' (${fechaCorta(f.fechaMax!)})' : ''}'
                                ' · x${f.ratio.toStringAsFixed(1)}'),
                          ),
                        )),
                  ],
                ),
    );
  }
}

class _InfoMax {
  final double precio;
  final String proveedor;
  final DateTime fecha;
  _InfoMax(this.precio, this.proveedor, this.fecha);
}
