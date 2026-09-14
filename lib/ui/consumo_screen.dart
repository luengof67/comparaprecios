import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import '../services/historial_compras_service.dart';
import '../services/informe_productos_service.dart';
import 'corregir_compra_dialog.dart';
import 'formato.dart';

/// Como se ve el histórico de los productos buscados.
enum _Vista {
  /// Un número por mes: cantidad, precio medio y gasto.
  resumen,

  /// Cada compra individual, con fecha exacta y la variación frente a la
  /// compra anterior de ese producto, sea quien sea quien lo sirviera. Es lo
  /// que hace falta para pillar una subida puntual dentro de un mismo mes.
  detalle,
}

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
  List<Proveedor> _proveedores = const [];
  Map<String, ResumenProducto> _resumenes = const {};

  _Vista _vista = _Vista.resumen;

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

  /// Meses elegidos para acotar el histórico. Vacío = se ven todos.
  /// No hace falta que sean consecutivos: julio y septiembre sin agosto
  /// es una selección tan válida como julio-agosto-septiembre seguidos.
  final Set<String> _mesesElegidos = {};

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
      final proveedores = await widget.db.proveedores().first;
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
        _proveedores = proveedores;
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
    // Se ordena por lo que se gasto en los meses elegidos, no por el total
    // historico: si se comparan julio y septiembre, manda ese gasto y no el
    // de todo el año.
    double gasto(ResumenProducto r) =>
        r.ordenadosEn(_mesesElegidos).fold<double>(0, (s, m) => s + m.gasto);
    final l = _resumenes.values.where(_pasaFiltros).toList()
      ..sort((a, b) => gasto(b).compareTo(gasto(a)));
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

  /// El histórico compra a compra de los productos que han pasado el
  /// filtro, mezclando todos los proveedores por fecha. Reutiliza los
  /// productos ya filtrados (_filtrados) para no duplicar la lógica de
  /// búsqueda por nombre y alias.
  List<HistoricoProducto> get _historicoDetallado {
    final claves = _filtrados.map((r) => r.clave).toSet();
    return HistorialComprasService.deProductos(
      claves: claves,
      compras: _compras,
      productos: _productos,
      proveedores: _proveedores,
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Productos comprados')),
      floatingActionButton: _cargando || _mes == null
          ? null
          : FloatingActionButton.extended(
              onPressed: !_hayFiltro
                  ? () => InformeProductosService.generarPdf(
                        mes: _mes!,
                        compras: _compras,
                        productos: _productos,
                      )
                  : _vista == _Vista.resumen
                      ? () => InformeProductosService.generarHistoricoPdf(
                            productos: _filtrados,
                            titulo: _tituloFiltro(),
                            mesesElegidos: _mesesElegidos,
                          )
                      : () => HistorialComprasService.generarPdf(
                            titulo: _tituloFiltro(),
                            historicos: _historicoDetallado,
                            mostrarProveedor: true,
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
        Expanded(
          child: !_hayFiltro
              ? _listaDelMes()
              : _vista == _Vista.resumen
                  ? _historico()
                  : _historicoDetalladoWidget(),
        ),
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
          if (_hayFiltro) ...[
            const SizedBox(height: 8),
            SegmentedButton<_Vista>(
              segments: const [
                ButtonSegment(
                    value: _Vista.resumen, label: Text('Resumen mensual')),
                ButtonSegment(
                    value: _Vista.detalle, label: Text('Cada compra')),
              ],
              selected: {_vista},
              onSelectionChanged: (s) => setState(() => _vista = s.first),
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

    // Los totales tambien respetan los meses elegidos: si se compara julio
    // con septiembre, el total es el de esos dos, no el de todo el historico.
    double totalDe(ResumenProducto r) =>
        r.ordenadosEn(_mesesElegidos).fold<double>(0, (s, m) => s + m.gasto);
    final total = hallados.fold<double>(0, (s, r) => s + totalDe(r));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      children: [
        _chipsMeses(),
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            '${hallados.length} producto${hallados.length == 1 ? "" : "s"} · '
            '${euros(total)} en total'
            '${_mesesElegidos.isEmpty ? "" : " · ${_mesesElegidos.length} mes${_mesesElegidos.length == 1 ? "" : "es"} elegidos"}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final r in hallados) _tarjetaProducto(r),
      ],
    );
  }

  /// Chips para elegir que meses entran en la comparacion. No hace falta que
  /// sean consecutivos: julio y septiembre sin agosto es una eleccion tan
  /// valida como tres meses seguidos. Vacio = se ven todos.
  Widget _chipsMeses() {
    if (_mesesDisponibles.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final m in _mesesDisponibles)
            FilterChip(
              label: Text(_mesCorto(m)),
              selected: _mesesElegidos.contains(ResumenProducto.claveMes(m)),
              onSelected: (v) => setState(() {
                final k = ResumenProducto.claveMes(m);
                if (v) {
                  _mesesElegidos.add(k);
                } else {
                  _mesesElegidos.remove(k);
                }
              }),
              visualDensity: VisualDensity.compact,
            ),
          if (_mesesElegidos.isNotEmpty)
            ActionChip(
              label: const Text('Ver todos'),
              onPressed: () => setState(_mesesElegidos.clear),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _tarjetaProducto(ResumenProducto r) {
    final meses = r.ordenadosEn(_mesesElegidos);
    if (meses.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            '${r.nombre} · sin compras en los meses elegidos',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      );
    }

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
              '${r.categoria} · '
              '${_num(meses.fold<double>(0, (s, m) => s + m.cantidad))} ${r.unidad} · '
              '${euros(meses.fold<double>(0, (s, m) => s + m.gasto))} '
              'en ${meses.length} mes${meses.length == 1 ? "" : "es"}',
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

  // -------------------------------------------- historico compra a compra

  /// Cada compra individual de los productos buscados, mezclando todos los
  /// proveedores por fecha. Es lo que hace falta para pillar una subida el
  /// 18 de agosto aunque el 10 de agosto ya hubiera otra compra ese mismo
  /// mes: el resumen mensual la fundiría en una media y la escondería.
  Widget _historicoDetalladoWidget() {
    final historicos = _historicoDetallado;

    if (historicos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Ningún producto comprado con esa búsqueda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final gastoTotal = historicos.fold<double>(0, (s, h) => s + h.gastoTotal);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            '${historicos.length} producto${historicos.length == 1 ? "" : "s"} · '
            '${euros(gastoTotal)} en total',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        for (final h in historicos) _tarjetaHistorico(h),
      ],
    );
  }

  Widget _tarjetaHistorico(HistoricoProducto h) {
    final u = h.producto.unidadBase.etiqueta;
    final vt = h.variacionTotal;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: h.tieneAlgunaSubida,
        title: Text(h.producto.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${h.compras.length} compra${h.compras.length == 1 ? "" : "s"} · '
          '${euros(h.gastoTotal)}'
          '${h.variosProveedores ? " · varios proveedores" : ""}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: vt == null
            ? null
            : Text(
                '${vt > 0 ? "+" : ""}${(vt * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: vt > 0.005
                      ? Colors.red.shade700
                      : vt < -0.005
                          ? Colors.green.shade700
                          : Colors.grey,
                ),
              ),
        children: [
          for (final c in h.compras)
            _filaCompraDetallada(c, u, h.producto.unidadBase.nombre),
        ],
      ),
    );
  }

  Widget _filaCompraDetallada(
      CompraDeProducto c, String u, String unidadCantidad) {
    Color? color;
    IconData? icono;
    if (c.sube) {
      color = Colors.red.shade700;
      icono = Icons.arrow_upward;
    } else if (c.baja) {
      color = Colors.green.shade700;
      icono = Icons.arrow_downward;
    }

    return ListTile(
      dense: true,
      onTap: () => CorregirCompraDialog.mostrar(
        context,
        widget.db,
        c,
        unidadCantidad,
        onListo: _cargar,
      ),
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Color(c.proveedorColor),
          shape: BoxShape.circle,
        ),
      ),
      title: Text(fecha(c.fecha), style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        c.numeroAlbaran != null
            ? '${c.proveedorNombre} · nº ${c.numeroAlbaran} · ${_num(c.cantidad)} $unidadCantidad'
            : '${c.proveedorNombre} · a mano · ${_num(c.cantidad)} $unidadCantidad',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 14, color: color),
            const SizedBox(width: 2),
            Text('${(c.variacion!.abs() * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 8),
          ],
          Text('${c.precioUnitario.toStringAsFixed(2)} $u',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
