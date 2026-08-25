import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../services/firestore_service.dart';
import '../services/lineas_service.dart';
import 'formato.dart';

enum _Modo { sospechosas, caras }

/// Repasar y corregir lineas de compra mal metidas.
///
/// Es el unico sitio donde se puede tocar una linea ya registrada. Al
/// guardar hace DOS cosas, y las dos hacen falta:
///   - recalcula el total de la compra (informes de gasto)
///   - corrige el precio que esa linea genero en el historico (comparativa)
///
/// Tocar solo una de las dos deja los informes y la comparativa diciendo
/// cosas distintas del mismo dia.
class RevisarLineasScreen extends StatefulWidget {
  final FirestoreService db;
  const RevisarLineasScreen({super.key, required this.db});

  @override
  State<RevisarLineasScreen> createState() => _RevisarLineasScreenState();
}

class _RevisarLineasScreenState extends State<RevisarLineasScreen> {
  bool _cargando = true;
  String? _error;
  _Modo _modo = _Modo.sospechosas;

  List<Compra> _compras = const [];
  List<Producto> _productos = const [];

  /// Lineas dadas por buenas durante esta visita.
  final Set<String> _revisadas = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _clave(LineaSospechosa l) => '${l.compra.id}|${l.indice}';

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final compras = await widget.db.compras().first;
      final productos = await widget.db.productos().first;
      if (!mounted) return;
      setState(() {
        _compras = compras;
        _productos = productos;
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

  List<LineaSospechosa> get _lista {
    final l = _modo == _Modo.sospechosas
        ? LineasService.sospechosas(compras: _compras, productos: _productos)
        : LineasService.masCaras(compras: _compras, productos: _productos);
    return l.where((x) => !_revisadas.contains(_clave(x))).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar compras'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
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

    final lista = _lista;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_Modo>(
                  segments: const [
                    ButtonSegment(
                        value: _Modo.sospechosas, label: Text('Sospechosas')),
                    ButtonSegment(
                        value: _Modo.caras, label: Text('Las más caras')),
                  ],
                  selected: {_modo},
                  onSelectionChanged: (s) => setState(() => _modo = s.first),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Text(
            _modo == _Modo.sospechosas
                ? 'Líneas cuyo precio o importe se sale mucho de lo normal '
                    'para ese producto. Hacen falta al menos tres compras del '
                    'producto para poder compararlo.'
                : 'Las líneas de más importe, sin juzgar nada. Aquí salen los '
                    'productos comprados una sola vez, que ningún criterio '
                    'puede detectar.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nada que revisar aquí.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _tarjeta(lista[i]),
                ),
        ),
      ],
    );
  }

  Widget _tarjeta(LineaSospechosa s) {
    final l = s.linea;
    final numero = s.numeroAlbaran;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.productoNombre,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text(euros(s.importe),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${s.compra.proveedorNombre} · ${fecha(s.compra.fecha)}'
              '${numero != null ? " · nº $numero" : " · a mano"}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              '${_num(l.cantidad)} ${s.unidad} × '
              '${euros3(l.precioUnitario)}/${s.unidad}',
              style: const TextStyle(fontSize: 13),
            ),
            if (s.motivo.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(s.motivo,
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.shade900)),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      setState(() => _revisadas.add(_clave(s))),
                  child: const Text('Está bien'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => _editar(s),
                  child: const Text('Corregir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editar(LineaSospechosa s) async {
    final cantCtrl =
        TextEditingController(text: _num(s.linea.cantidad));
    final precioCtrl = TextEditingController(
        text: s.linea.precioUnitario.toStringAsFixed(3));

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final cant =
              double.tryParse(cantCtrl.text.replaceAll(',', '.')) ?? 0;
          final precio =
              double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
          final nuevoTotal = cant * precio;

          return AlertDialog(
            title: Text(s.productoNombre),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.compra.proveedorNombre} · ${fecha(s.compra.fecha)}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cantCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Cantidad (${s.unidad})',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setDlg(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: precioCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: '€/${s.unidad}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setDlg(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Antes: ${euros(s.importe)}',
                    style: const TextStyle(fontSize: 12)),
                Text('Ahora: ${euros(nuevoTotal)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                  'Se corrige el total de la compra y también el precio que '
                  'esta línea dejó en el histórico.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: nuevoTotal > 0
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    final cant = double.tryParse(cantCtrl.text.replaceAll(',', '.')) ?? 0;
    final precio = double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
    cantCtrl.dispose();
    precioCtrl.dispose();

    if (guardar != true || cant <= 0 || precio <= 0) return;

    String mensaje;
    try {
      // 1) La linea, dentro de su compra.
      final nuevas = [...s.compra.lineas];
      nuevas[s.indice] = LineaCompra(
        productoId: s.linea.productoId,
        productoNombre: s.linea.productoNombre,
        unidad: s.linea.unidad,
        cantidad: cant,
        precioUnitario: precio,
      );
      await widget.db.actualizarCompraLineas(s.compra.id, nuevas);

      // 2) El precio que esa linea dejo en el historico. Sin esto, la
      //    comparativa seguiria enseñando el precio viejo.
      await widget.db.actualizarPrecioDeCompra(
        productoId: s.linea.productoId,
        proveedorId: s.compra.proveedorId,
        fecha: s.compra.fecha,
        nuevoUnitario: precio,
      );

      mensaje = '${s.productoNombre}: ${euros(cant * precio)}';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    await _cargar();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
