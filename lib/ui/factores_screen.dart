import 'package:flutter/material.dart';

import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/factores_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Precios de envase que se guardaron como si el envase fuera una unidad.
///
/// "32,09 € / 1 garrafa = 1 ud" compite contra un bote de 6,95 €/ud y saca un
/// -78% que no existe. Falta decir cuantas unidades trae la garrafa.
class FactoresScreen extends StatefulWidget {
  final FirestoreService db;
  const FactoresScreen({super.key, required this.db});

  @override
  State<FactoresScreen> createState() => _FactoresScreenState();
}

class _FactoresScreenState extends State<FactoresScreen> {
  bool _cargando = true;
  String? _error;

  List<Producto> _productos = const [];
  List<Proveedor> _proveedores = const [];
  List<Precio> _precios = const [];
  List<GrupoSinFactor> _grupos = const [];
  int _totalCandidatos = 0;

  /// true = solo los que se salen de lo que cobran los demas.
  bool _soloSospechosos = true;

  /// Grupos marcados como correctos durante esta visita.
  final Set<String> _descartados = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _clave(GrupoSinFactor g) =>
      '${g.producto.id}|${g.proveedorId}|${g.formato.toLowerCase()}';

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
      _productos = productos;
      _proveedores = proveedores;
      _precios = precios;
      _recalcular();
      setState(() => _cargando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  void _recalcular() {
    _grupos = FactoresService.detectar(
      productos: _productos,
      proveedores: _proveedores,
      precios: _precios,
      soloSospechosos: _soloSospechosos,
    );
    _totalCandidatos = FactoresService.contarTodos(
      productos: _productos,
      proveedores: _proveedores,
      precios: _precios,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles =
        _grupos.where((g) => !_descartados.contains(_clave(g))).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Envases sin equivalencia'),
        actions: [
          IconButton(
            tooltip: 'Volver a comprobar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cuerpo(visibles),
    );
  }

  Widget _cuerpo(List<GrupoSinFactor> visibles) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No se ha podido leer la base de datos.\n\n$_error',
              textAlign: TextAlign.center),
        ),
      );
    }

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
                  'Precios de un envase entero anotados como si el envase '
                  'fuese una unidad. Compiten contra el formato pequeño de '
                  'otro proveedor y sacan diferencias enormes que no existen.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_totalCandidatos precios con formato y cantidad 1 en total. '
                  '${_grupos.length} se salen de lo que cobran los demás.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Switch(
                      value: _soloSospechosos,
                      onChanged: (v) => setState(() {
                        _soloSospechosos = v;
                        _recalcular();
                      }),
                    ),
                    const Expanded(
                      child: Text('Solo los que se salen de lo normal',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (visibles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 48, color: Colors.green),
                SizedBox(height: 12),
                Text(
                  'Nada que revisar aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        else
          for (final g in visibles) _Tarjeta(
            key: ValueKey(_clave(g)),
            grupo: g,
            onDescartar: () => setState(() => _descartados.add(_clave(g))),
            onAplicar: (factor) => _aplicar(g, factor),
          ),
      ],
    );
  }

  Future<void> _aplicar(GrupoSinFactor g, double factor) async {
    final nuevo = g.precios.first.precioPaquete / factor;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poner la equivalencia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${g.producto.nombre} · ${g.proveedorNombre}'),
            const SizedBox(height: 10),
            Text('Un ${g.formato} pasa a contar como '
                '${_num(factor)} ${g.producto.unidadBase.nombre}.'),
            const SizedBox(height: 10),
            Text('Antes: ${g.unitarioActual.toStringAsFixed(2)} '
                '${g.producto.unidadBase.etiqueta}'),
            Text('Ahora: ${nuevo.toStringAsFixed(2)} '
                '${g.producto.unidadBase.etiqueta}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (g.referencia > 0) ...[
              const SizedBox(height: 6),
              Text('Los demás cobran ${g.referencia.toStringAsFixed(2)} '
                  '${g.producto.unidadBase.etiqueta}',
                  style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 10),
            Text('Se corrigen ${g.precios.length} registro'
                '${g.precios.length == 1 ? "" : "s"} de precio.',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Corregir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    String mensaje;
    try {
      final n = await widget.db.corregirFactorPrecios(g.precios, factor);
      mensaje = 'Corregidos $n precios de ${g.producto.nombre}.';
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

/// Una tarjeta con su propia casilla de factor.
class _Tarjeta extends StatefulWidget {
  final GrupoSinFactor grupo;
  final VoidCallback onDescartar;
  final void Function(double factor) onAplicar;

  const _Tarjeta({
    super.key,
    required this.grupo,
    required this.onDescartar,
    required this.onAplicar,
  });

  @override
  State<_Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends State<_Tarjeta> {
  late final TextEditingController _ctrl;
  double _factor = 0;

  @override
  void initState() {
    super.initState();
    // Se propone el factor que cuadraria con lo que cobran los demas, pero
    // redondeado: los envases vienen en numeros redondos (5 L, 6 kg, 12 ud),
    // no en 4,62.
    final sug = widget.grupo.factorSugerido;
    final redondo = sug >= 1 ? sug.roundToDouble() : 0.0;
    _factor = redondo;
    _ctrl = TextEditingController(
        text: redondo > 0 ? redondo.toStringAsFixed(0) : '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.grupo;
    final base = g.producto.unidadBase;
    final resultado = g.unitarioCon(_factor);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    radius: 7, backgroundColor: Color(g.proveedorColor)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(g.producto.nombre,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (g.desviacion > 0)
                  Text('×${g.desviacion.toStringAsFixed(1)}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.orange.shade800)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${g.proveedorNombre} · ${g.precios.first.precioPaquete.toStringAsFixed(2)} € '
              'el ${g.formato} · ${fecha(g.ultimaFecha)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ahora ${g.unitarioActual.toStringAsFixed(2)} '
                          '${base.etiqueta}',
                          style: const TextStyle(fontSize: 12)),
                      if (g.referencia > 0)
                        Text('los demás ${g.referencia.toStringAsFixed(2)} '
                            '${base.etiqueta}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      labelText: base.nombre,
                      helperText: 'por ${g.formato}',
                      helperStyle: const TextStyle(fontSize: 10),
                    ),
                    onChanged: (v) => setState(() =>
                        _factor = double.tryParse(v.replaceAll(',', '.')) ?? 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_factor > 0)
              Text(
                'quedaría en ${resultado.toStringAsFixed(2)} ${base.etiqueta}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade800),
              )
            else
              const Text(
                'escribe cuánto trae el envase',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (g.precios.length > 1)
                  Text('${g.precios.length} registros',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                const Spacer(),
                TextButton(
                  onPressed: widget.onDescartar,
                  child: const Text('Está bien así'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed:
                      _factor > 0 ? () => widget.onAplicar(_factor) : null,
                  child: const Text('Corregir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
