import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../services/firestore_service.dart';
import '../services/informe_productos_service.dart';
import 'formato.dart';

/// Que se ha comprado, cuanto y por cuanto.
///
/// Sin buscar: el listado del mes elegido, ordenado por gasto.
/// Buscando: los productos que casan, cada uno con una fila por mes. Ahi se
/// ve si el consumo sube, y si el precio sube con el.
///
/// Todo sale de las compras registradas, no de los precios de tarifa: es lo
/// que se pago de verdad.
class ConsumoScreen extends StatefulWidget {
  final FirestoreService db;
  const ConsumoScreen({super.key, required this.db});

  @override
  State<ConsumoScreen> createState() => _ConsumoScreenState();
}

/// Un producto en un mes: cantidad y gasto sumados.
class _Mes {
  final DateTime mes;
  double cantidad = 0;
  double gasto = 0;
  int compras = 0;
  _Mes(this.mes);

  double get precioMedio => cantidad > 0 ? gasto / cantidad : 0;
}

/// Un producto con su historico por meses.
class _Resumen {
  final String clave;
  final String nombre;
  final String unidad;
  final String categoria;
  final Map<String, _Mes> meses = {};

  _Resumen({
    required this.clave,
    required this.nombre,
    required this.unidad,
    required this.categoria,
  });

  static String claveMes(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  _Mes? del(DateTime mes) => meses[claveMes(mes)];

  List<_Mes> get ordenados {
    final l = meses.values.toList()..sort((a, b) => b.mes.compareTo(a.mes));
    return l;
  }

  double get gastoTotal => meses.values.fold(0, (s, m) => s + m.gasto);
  double get cantidadTotal => meses.values.fold(0, (s, m) => s + m.cantidad);
}

class _ConsumoScreenState extends State<ConsumoScreen> {
  bool _cargando = true;
  String? _error;

  List<Compra> _compras = const [];
  List<Producto> _productos = const [];

  /// Meses con compras, del mas reciente al mas antiguo.
  List<DateTime> _mesesDisponibles = const [];
  DateTime? _mes;

  final _buscador = TextEditingController();
  String _busqueda = '';

  Map<String, _Resumen> _resumenes = const {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final compras = await widget.db.compras().first;
      final productos = await widget.db.productos().first;
      if (!mounted) return;

      final meses = <String, DateTime>{};
      for (final c in compras) {
        final m = DateTime(c.fecha.year, c.fecha.month);
        meses[_Resumen.claveMes(m)] = m;
      }
      final lista = meses.values.toList()..sort((a, b) => b.compareTo(a));

      setState(() {
        _compras = compras;
        _productos = productos;
        _mesesDisponibles = lista;
        _mes ??= lista.isEmpty ? null : lista.first;
        _resumenes = _agrupar(compras, productos);
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

  Map<String, _Resumen> _agrupar(
      List<Compra> compras, List<Producto> productos) {
    final cat = {for (final p in productos) p.id: p.categoria};
    final uni = {for (final p in productos) p.id: p.unidadBase.nombre};

    final salida = <String, _Resumen>{};
    for (final c in compras) {
      final mes = DateTime(c.fecha.year, c.fecha.month);
      for (final l in c.lineas) {
        final clave = l.productoId.isNotEmpty ? l.productoId : l.productoNombre;
        final r = salida.putIfAbsent(
          clave,
          () => _Resumen(
            clave: clave,
            nombre: l.productoNombre,
            unidad: uni[l.productoId] ?? l.unidad,
            categoria: cat[l.productoId] ?? 'Sin categoría',
          ),
        );
        final m = r.meses.putIfAbsent(_Resumen.claveMes(mes), () => _Mes(mes));
        m.cantidad += l.cantidad;
        m.gasto += l.total;
        m.compras++;
      }
    }
    return salida;
  }

  /// Los alias aprendidos tambien cuentan: "colitas de bacalao 150gr" tiene
  /// que encontrar "bacalao".
  bool _casa(_Resumen r, String q) {
    if (r.nombre.toLowerCase().contains(q)) return true;
    final p = _productos.where((x) => x.id == r.clave).firstOrNull;
    if (p == null) return false;
    return p.alias.any((a) => a.texto.toLowerCase().contains(q));
  }

  String _etiquetaMes(DateTime m) =>
      DateFormat('MMM yyyy', 'es_ES').format(m);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Productos comprados')),
      floatingActionButton: (_mes == null || _busqueda.isNotEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => InformeProductosService.generarPdf(
                mes: _mes!,
                compras: _compras,
                productos: _productos,
              ),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
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
    if (_mesesDisponibles.isEmpty) {
      return const Center(
        child: Text('No hay compras registradas.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _buscador,
            decoration: InputDecoration(
              hintText: 'Buscar producto…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscador.clear();
                        setState(() => _busqueda = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _busqueda = v.toLowerCase().trim()),
          ),
        ),
        Expanded(
          child: _busqueda.isEmpty ? _listaDelMes() : _historico(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- listado del mes

  Widget _listaDelMes() {
    final mes = _mes!;
    final filas = _resumenes.values
        .map((r) => (r, r.del(mes)))
        .where((e) => e.$2 != null)
        .toList()
      ..sort((a, b) => b.$2!.gasto.compareTo(a.$2!.gasto));

    final total = filas.fold<double>(0, (s, e) => s + e.$2!.gasto);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _Resumen.claveMes(mes),
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Mes',
                ),
                items: [
                  for (final m in _mesesDisponibles)
                    DropdownMenuItem(
                        value: _Resumen.claveMes(m),
                        child: Text(_etiquetaMes(m))),
                ],
                onChanged: (v) => setState(() => _mes = _mesesDisponibles
                    .firstWhere((m) => _Resumen.claveMes(m) == v)),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(euros(total),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${filas.length} productos',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Sin compras este mes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (r, m) in filas)
                  ListTile(
                    dense: true,
                    title: Text(r.nombre, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${r.categoria} · ${_num(m!.cantidad)} ${r.unidad} · '
                      '${euros3(m.precioMedio)}/${r.unidad}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(euros(m.gasto),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () {
                      _buscador.text = r.nombre;
                      setState(() => _busqueda = r.nombre.toLowerCase());
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------- historico por producto

  Widget _historico() {
    final hallados = _resumenes.values
        .where((r) => _casa(r, _busqueda))
        .toList()
      ..sort((a, b) => b.gastoTotal.compareTo(a.gastoTotal));

    if (hallados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Ningún producto comprado con ese nombre.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      children: [for (final r in hallados) _tarjetaProducto(r)],
    );
  }

  Widget _tarjetaProducto(_Resumen r) {
    final meses = r.ordenados;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.nombre,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            Text(
              '${r.categoria} · ${_num(r.cantidadTotal)} ${r.unidad} · '
              '${euros(r.gastoTotal)} en ${meses.length} mes${meses.length == 1 ? "" : "es"}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            // Cabecera de la tabla
            Row(
              children: [
                const SizedBox(width: 80, child: Text('Mes', style: _cab)),
                Expanded(
                    child: Text('Cantidad',
                        textAlign: TextAlign.right, style: _cab)),
                Expanded(
                    child: Text('€/${r.unidad}',
                        textAlign: TextAlign.right, style: _cab)),
                Expanded(
                    child:
                        Text('Gasto', textAlign: TextAlign.right, style: _cab)),
              ],
            ),
            const Divider(height: 8),
            for (var i = 0; i < meses.length; i++)
              _filaMes(meses[i], i + 1 < meses.length ? meses[i + 1] : null, r),
          ],
        ),
      ),
    );
  }

  static const _cab = TextStyle(fontSize: 11, color: Colors.grey);

  /// Una fila de mes. Si hay mes anterior, marca si el precio medio subio o
  /// bajo respecto a el.
  Widget _filaMes(_Mes m, _Mes? anterior, _Resumen r) {
    Color? color;
    IconData? icono;
    if (anterior != null && anterior.precioMedio > 0 && m.precioMedio > 0) {
      final dif = (m.precioMedio - anterior.precioMedio) / anterior.precioMedio;
      if (dif > 0.03) {
        color = Colors.red.shade700;
        icono = Icons.arrow_upward;
      } else if (dif < -0.03) {
        color = Colors.green.shade700;
        icono = Icons.arrow_downward;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(_etiquetaMes(m.mes),
                style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Text('${_num(m.cantidad)} ${r.unidad}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (icono != null) Icon(icono, size: 12, color: color),
                Text(euros3(m.precioMedio),
                    style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
          Expanded(
            child: Text(euros(m.gasto),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
