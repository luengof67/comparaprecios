import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../services/firestore_service.dart';
import '../services/informe_productos_service.dart';
import 'formato.dart';

/// Que se ha comprado, cuanto y por cuanto.
///
/// Sin filtros: el listado del mes elegido, ordenado por gasto.
/// Con filtros: los productos que casan, cada uno con una fila por mes.
///
/// Los filtros son fichas de busqueda (varias, se suman: "platanos" +
/// "kiwis" + "nectarinas" en el mismo informe) y una seccion. El PDF imprime
/// lo que se este viendo.
class ConsumoScreen extends StatefulWidget {
  final FirestoreService db;
  const ConsumoScreen({super.key, required this.db});

  @override
  State<ConsumoScreen> createState() => _ConsumoScreenState();
}

class _ConsumoScreenState extends State<ConsumoScreen> {
  bool _cargando = true;
  String? _error;

  List<Compra> _compras = const [];
  List<Producto> _productos = const [];
  Map<String, ResumenProducto> _resumenes = const {};

  List<DateTime> _mesesDisponibles = const [];
  DateTime? _mes;

  final _buscador = TextEditingController();

  /// Terminos de busqueda confirmados. Un producto entra si casa con
  /// cualquiera de ellos.
  final List<String> _terminos = [];

  /// Lo que se esta escribiendo, todavia sin confirmar con Enter. Tambien
  /// filtra, para que la lista responda mientras se teclea.
  String _escribiendo = '';

  String _categoria = '';

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
        meses[ResumenProducto.claveMes(m)] = m;
      }
      final lista = meses.values.toList()..sort((a, b) => b.compareTo(a));

      setState(() {
        _compras = compras;
        _productos = productos;
        _mesesDisponibles = lista;
        _mes ??= lista.isEmpty ? null : lista.first;
        _resumenes = InformeProductosService.agrupar(compras, productos);
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

  // ----------------------------------------------------------------- filtros

  bool get _hayFiltro =>
      _terminos.isNotEmpty || _escribiendo.isNotEmpty || _categoria.isNotEmpty;

  /// Los alias aprendidos tambien cuentan: "colitas de bacalao 150gr" tiene
  /// que encontrar "bacalao".
  bool _casaTermino(ResumenProducto r, String q) {
    if (r.nombre.toLowerCase().contains(q)) return true;
    for (final p in _productos) {
      if (p.id != r.clave) continue;
      return p.alias.any((a) => a.texto.toLowerCase().contains(q));
    }
    return false;
  }

  bool _pasaFiltros(ResumenProducto r) {
    if (_categoria.isNotEmpty && r.categoria != _categoria) return false;
    final terminos = [
      ..._terminos,
      if (_escribiendo.isNotEmpty) _escribiendo,
    ];
    if (terminos.isEmpty) return true;
    return terminos.any((t) => _casaTermino(r, t));
  }

  List<ResumenProducto> get _filtrados {
    final l = _resumenes.values.where(_pasaFiltros).toList()
      ..sort((a, b) => b.gastoTotal.compareTo(a.gastoTotal));
    return l;
  }

  void _confirmarTermino() {
    final t = _buscador.text.toLowerCase().trim();
    _buscador.clear();
    setState(() {
      _escribiendo = '';
      if (t.isNotEmpty && !_terminos.contains(t)) _terminos.add(t);
    });
  }

  List<String> get _categorias {
    final s = _resumenes.values.map((r) => r.categoria).toSet().toList()
      ..sort();
    return s;
  }

  String _tituloFiltro() {
    final partes = <String>[
      if (_categoria.isNotEmpty) _categoria,
      ..._terminos,
      if (_escribiendo.isNotEmpty) _escribiendo,
    ];
    return partes.join(', ');
  }

  String _mesCorto(DateTime m) => DateFormat('MMM yyyy', 'es_ES').format(m);

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Productos comprados')),
      floatingActionButton: _cargando || _mes == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _hayFiltro
                  ? () => InformeProductosService.generarHistoricoPdf(
                        productos: _filtrados,
                        titulo: _tituloFiltro(),
                      )
                  : () => InformeProductosService.generarPdf(
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
        _filtros(),
        Expanded(child: _hayFiltro ? _historico() : _listaDelMes()),
      ],
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _buscador,
                  decoration: InputDecoration(
                    hintText: _terminos.isEmpty
                        ? 'Buscar producto… (Enter para añadir otro)'
                        : 'Añadir otro producto…',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _escribiendo.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Añadir a la búsqueda',
                            icon: const Icon(Icons.add),
                            onPressed: _confirmarTermino,
                          ),
                  ),
                  onChanged: (v) =>
                      setState(() => _escribiendo = v.toLowerCase().trim()),
                  onSubmitted: (_) => _confirmarTermino(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Sección',
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todas')),
                    for (final c in _categorias)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _categoria = v ?? ''),
                ),
              ),
            ],
          ),
          if (_terminos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _terminos)
                    InputChip(
                      label: Text(t),
                      onDeleted: () => setState(() => _terminos.remove(t)),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (_terminos.length > 1)
                    ActionChip(
                      label: const Text('Limpiar'),
                      onPressed: () => setState(_terminos.clear),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: ResumenProducto.claveMes(mes),
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Mes',
                ),
                items: [
                  for (final m in _mesesDisponibles)
                    DropdownMenuItem(
                        value: ResumenProducto.claveMes(m),
                        child: Text(_mesCorto(m))),
                ],
                onChanged: (v) => setState(() => _mes = _mesesDisponibles
                    .firstWhere((m) => ResumenProducto.claveMes(m) == v)),
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
                    onTap: () => setState(() {
                      final t = r.nombre.toLowerCase();
                      if (!_terminos.contains(t)) _terminos.add(t);
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------- historico por producto

  Widget _historico() {
    final hallados = _filtrados;

    if (hallados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Ningún producto comprado con esa búsqueda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final total = hallados.fold<double>(0, (s, r) => s + r.gastoTotal);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            '${hallados.length} producto${hallados.length == 1 ? "" : "s"} · '
            '${euros(total)} en total',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final r in hallados) _tarjetaProducto(r),
      ],
    );
  }

  Widget _tarjetaProducto(ResumenProducto r) {
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

  Widget _filaMes(MesProducto m, MesProducto? anterior, ResumenProducto r) {
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
            child: Text(_mesCorto(m.mes), style: const TextStyle(fontSize: 13)),
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
