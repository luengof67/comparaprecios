import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/precio.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import '../services/mantenimiento_service.dart';

/// Parejas de proveedores VIVOS que parecen el mismo.
///
/// Distinto de la pantalla de huerfanos: alli el origen era un id sin ficha.
/// Aqui las dos fichas existen, asi que ademas de mover el historico hay que
/// borrar la que sobra.
///
/// El parecido lo calcula MantenimientoService, y se equivoca: agrupa por
/// palabras, y dos casas distintas pueden compartir apellido. La lista es una
/// propuesta para revisar, nunca algo que aplicar en bloque.
class DuplicadosScreen extends StatefulWidget {
  final FirestoreService db;
  const DuplicadosScreen({super.key, required this.db});

  @override
  State<DuplicadosScreen> createState() => _DuplicadosScreenState();
}

/// Dos proveedores que se parecen, con lo que arrastra cada uno.
class _Pareja {
  final Proveedor a;
  final Proveedor b;
  final double parecido;
  final int preciosA;
  final int preciosB;
  final int comprasA;
  final int comprasB;
  final int colisiones;

  const _Pareja({
    required this.a,
    required this.b,
    required this.parecido,
    required this.preciosA,
    required this.preciosB,
    required this.comprasA,
    required this.comprasB,
    required this.colisiones,
  });

  int get total => preciosA + preciosB + comprasA + comprasB;
}

class _DuplicadosScreenState extends State<DuplicadosScreen> {
  bool _cargando = true;
  String? _error;

  List<Proveedor> _proveedores = const [];
  List<Precio> _precios = const [];
  List<Compra> _compras = const [];
  List<_Pareja> _parejas = const [];

  /// Parejas que el usuario ha marcado como "no son el mismo". Solo dura lo
  /// que dure la pantalla, pero evita seguir viendo la misma propuesta
  /// descartada mientras se revisan las demas.
  final Set<String> _descartadas = {};

  double _minimo = 0.5;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _clave(Proveedor a, Proveedor b) {
    final ids = [a.id, b.id]..sort();
    return ids.join('|');
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final proveedores = await widget.db.proveedores().first;
      final precios = await widget.db.precios().first;
      final compras = await widget.db.compras().first;
      if (!mounted) return;
      _proveedores = proveedores;
      _precios = precios;
      _compras = compras;
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
    final nPrecios = <String, int>{};
    for (final p in _precios) {
      nPrecios.update(p.proveedorId, (v) => v + 1, ifAbsent: () => 1);
    }
    final nCompras = <String, int>{};
    for (final c in _compras) {
      nCompras.update(c.proveedorId, (v) => v + 1, ifAbsent: () => 1);
    }

    final salida = <_Pareja>[];
    // Cada pareja una sola vez: j empieza en i+1.
    for (var i = 0; i < _proveedores.length; i++) {
      for (var j = i + 1; j < _proveedores.length; j++) {
        final a = _proveedores[i], b = _proveedores[j];
        final s = MantenimientoService.parecido(a.nombre, b.nombre);
        if (s < _minimo) continue;
        salida.add(_Pareja(
          a: a,
          b: b,
          parecido: s,
          preciosA: nPrecios[a.id] ?? 0,
          preciosB: nPrecios[b.id] ?? 0,
          comprasA: nCompras[a.id] ?? 0,
          comprasB: nCompras[b.id] ?? 0,
          colisiones: MantenimientoService.colisiones(a.id, b.id, _precios),
        ));
      }
    }

    salida.sort((x, y) {
      final porParecido = y.parecido.compareTo(x.parecido);
      if (porParecido != 0) return porParecido;
      return y.total.compareTo(x.total);
    });
    _parejas = salida;
  }

  @override
  Widget build(BuildContext context) {
    final visibles =
        _parejas.where((p) => !_descartadas.contains(_clave(p.a, p.b))).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores repetidos'),
        actions: [
          PopupMenuButton<double>(
            tooltip: 'Cuánto se tienen que parecer',
            icon: const Icon(Icons.tune),
            initialValue: _minimo,
            onSelected: (v) => setState(() {
              _minimo = v;
              _recalcular();
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0.9, child: Text('Solo casi idénticos')),
              PopupMenuItem(value: 0.7, child: Text('Muy parecidos')),
              PopupMenuItem(value: 0.5, child: Text('Parecidos (normal)')),
              PopupMenuItem(value: 0.3, child: Text('Buscar de más')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cuerpo(visibles),
    );
  }

  Widget _cuerpo(List<_Pareja> visibles) {
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
    if (visibles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 48, color: Colors.green),
              const SizedBox(height: 12),
              Text(
                _descartadas.isEmpty
                    ? 'No hay proveedores que se parezcan entre sí.'
                    : 'No queda ninguna pareja por revisar.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Puedes buscar con menos exigencia desde el icono de ajustes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        Card(
          color: Colors.amber.shade50,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Esto es una propuesta, no un diagnóstico. Se agrupa por las '
              'palabras del nombre, así que dos casas distintas que compartan '
              'apellido saldrán aquí igualmente. Revisa cada una antes de '
              'fusionar: no se puede deshacer.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final p in visibles) _tarjeta(p),
      ],
    );
  }

  Widget _tarjeta(_Pareja p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${(p.parecido * 100).toStringAsFixed(0)}% parecidos',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700)),
                const Spacer(),
                if (p.colisiones > 0)
                  Text('${p.colisiones} solapes',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade800)),
              ],
            ),
            const SizedBox(height: 8),
            _lado(p, p.a, p.b, p.preciosA, p.comprasA),
            const Divider(height: 20),
            _lado(p, p.b, p.a, p.preciosB, p.comprasB),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    setState(() => _descartadas.add(_clave(p.a, p.b))),
                child: const Text('No son el mismo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Una de las dos fichas, con el boton para quedarse con ESTA.
  Widget _lado(_Pareja p, Proveedor esta, Proveedor otra, int precios,
      int compras) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(radius: 8, backgroundColor: Color(esta.color)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(esta.nombre,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                [
                  '$precios precios',
                  if (compras > 0) '$compras compras',
                  if (esta.contacto != null && esta.contacto!.isNotEmpty)
                    esta.contacto!,
                ].join(' · '),
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () => _confirmar(quedarse: esta, borrar: otra),
          child: const Text('Quedarme con este'),
        ),
      ],
    );
  }

  Future<void> _confirmar(
      {required Proveedor quedarse, required Proveedor borrar}) async {
    final solapes =
        MantenimientoService.colisiones(borrar.id, quedarse.id, _precios);
    final nPre = _precios.where((x) => x.proveedorId == borrar.id).length;
    final nCom = _compras.where((x) => x.proveedorId == borrar.id).length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unir los dos en uno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se queda: "${quedarse.nombre}"',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Desaparece: "${borrar.nombre}"'),
            const SizedBox(height: 12),
            Text('Se mueven $nPre precios'
                '${nCom > 0 ? " y $nCom compras" : ""}, y después se borra '
                'la ficha que sobra.'),
            if (solapes > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$solapes precios caen el mismo día y el mismo producto en '
                'los dos. No se pierde nada, pero quedarán duplicados.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Esto no se puede deshacer.',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Uniendo…')),
          ],
        ),
      ),
    );

    String mensaje;
    try {
      final r = await widget.db.fusionarProveedores(
        de: borrar.id,
        a: quedarse.id,
        nombreDestino: quedarse.nombre,
      );
      mensaje = 'Movidos ${r.precios} precios y ${r.compras} compras '
          'a "${quedarse.nombre}".';
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    await _cargar();
  }
}
