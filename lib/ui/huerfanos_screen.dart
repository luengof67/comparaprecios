import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import '../services/mantenimiento_service.dart';
import 'formato.dart';

/// Proveedores que se borraron pero cuyo historico sigue en la base de datos.
///
/// Los precios y las compras guardan el proveedorId, no una referencia: al
/// borrar la ficha, esos documentos quedan apuntando a un id que ya no existe.
/// Siguen contando en la comparativa, pero sin nombre.
class HuerfanosScreen extends StatefulWidget {
  final FirestoreService db;
  const HuerfanosScreen({super.key, required this.db});

  @override
  State<HuerfanosScreen> createState() => _HuerfanosScreenState();
}

class _HuerfanosScreenState extends State<HuerfanosScreen> {
  bool _cargando = true;
  String? _error;

  List<Proveedor> _proveedores = const [];
  List<Producto> _productos = const [];
  List<Precio> _precios = const [];
  List<Compra> _compras = const [];
  List<ProveedorHuerfano> _huerfanos = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Lectura de una sola vez, no en escucha: son tres colecciones enteras y no
  /// hace falta que se recalculen solas mientras se mira la pantalla.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final proveedores = await widget.db.proveedores().first;
      final productos = await widget.db.productos().first;
      final precios = await widget.db.precios().first;
      final compras = await widget.db.compras().first;
      if (!mounted) return;
      setState(() {
        _proveedores = proveedores;
        _productos = productos;
        _precios = precios;
        _compras = compras;
        _huerfanos = MantenimientoService.huerfanos(
          proveedores: proveedores,
          precios: precios,
          compras: compras,
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores sin ficha'),
        actions: [
          IconButton(
            tooltip: 'Volver a comprobar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No se ha podido leer la base de datos.\n\n$_error',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_huerfanos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
              SizedBox(height: 12),
              Text(
                'Todo en orden.\n'
                'Cada precio y cada compra tienen su proveedor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final conCompras =
        _huerfanos.where((h) => h.preciosDeCompra > 0).length;

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
                Text('${_huerfanos.length} proveedores sin ficha',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Su histórico sigue guardado y sigue compitiendo en la '
                  'comparativa, pero sin nombre. Si se borraron por estar '
                  'duplicados, fusiónalos con el que conservaste: así se '
                  'juntan los dos históricos en vez de perder la mitad.',
                  style: TextStyle(fontSize: 13),
                ),
                if (conCompras > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$conCompras tienen compras registradas: ahí hay gasto '
                    'real, no solo tarifas.',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final h in _huerfanos) _tarjeta(h),
      ],
    );
  }

  Widget _tarjeta(ProveedorHuerfano h) {
    final candidatos = MantenimientoService.candidatos(
      huerfano: h,
      proveedores: _proveedores,
      precios: _precios,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(h.etiqueta,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            if (!h.nombreRecuperable)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No se le registró ninguna compra, así que su nombre se '
                  'perdió al borrarlo. Solo quedan los números.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip('${h.nPrecios} precios'),
                if (h.nProductos > 0) _chip('${h.nProductos} productos'),
                if (h.nCompras > 0) _chip('${h.nCompras} compras'),
                if (h.gastoTotal > 0) _chip(euros(h.gastoTotal)),
                if (h.ultimo != null) _chip('último ${fecha(h.ultimo!)}'),
              ],
            ),
            if (h.preciosDeCompra > 0) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 15, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${h.preciosDeCompra} de sus precios salieron de compras: '
                      'son el gasto real de esos meses. Borrarlos cambiaría '
                      'los informes.',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            if (candidatos.isNotEmpty) ...[
              const Text('Podría ser el mismo que:',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              for (final c in candidatos.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                          radius: 6,
                          backgroundColor: Color(c.proveedor.color)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(c.proveedor.nombre,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (c.colisiones > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text('${c.colisiones} solapes',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange.shade800)),
                        ),
                      TextButton(
                        onPressed: () => _confirmarFusion(h, c.proveedor),
                        child: const Text('Fusionar'),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 18),
            ],
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: Text('Ver ${h.nProductos} productos'),
                  onPressed: () => _verProductos(h),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.merge, size: 18),
                  label: const Text('Elegir otro'),
                  onPressed: () => _elegirDestino(h),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Recuperar'),
                  onPressed: () => _recuperar(h),
                ),
                if (h.preciosDeTarifa > 0)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.red),
                    label: Text('Borrar ${h.preciosDeTarifa} tarifas',
                        style: const TextStyle(color: Colors.red)),
                    onPressed: () => _borrarTarifas(h),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Enseña que productos tiene este huerfano y a que precio. Es solo
  /// lectura: con los nombres delante suele reconocerse de quien era, que es
  /// lo unico que queda cuando el nombre se perdio al borrar la ficha.
  Future<void> _verProductos(ProveedorHuerfano h) async {
    final nombres = {for (final p in _productos) p.id: p};

    // El ultimo precio de cada producto, que es el que dice algo.
    final ultimos = <String, Precio>{};
    for (final p in _precios) {
      if (p.proveedorId != h.id) continue;
      final actual = ultimos[p.productoId];
      if (actual == null || p.fecha.isAfter(actual.fecha)) {
        ultimos[p.productoId] = p;
      }
    }

    final filas = ultimos.entries.toList()
      ..sort((a, b) {
        final na = nombres[a.key]?.nombre ?? '';
        final nb = nombres[b.key]?.nombre ?? '';
        return na.toLowerCase().compareTo(nb.toLowerCase());
      });

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(h.etiqueta),
        content: SizedBox(
          width: 420,
          child: filas.isEmpty
              ? const Text('No tiene precios.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in filas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombres[e.key]?.nombre ??
                                        'Producto borrado',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    '${fecha(e.value.fecha)}'
                                    '${e.value.fuente == FuentePrecio.compra ? " · de compra" : ""}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${e.value.precioUnitario.toStringAsFixed(2)} '
                              '${nombres[e.key]?.unidadBase.etiqueta ?? ""}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _chip(String t) => Chip(
        label: Text(t, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 2),
      );

  /// Lista completa de proveedores, para cuando la propuesta automatica no
  /// acierta o el huerfano perdio el nombre.
  Future<void> _elegirDestino(ProveedorHuerfano h) async {
    final elegido = await showDialog<Proveedor>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Fusionar "${h.etiqueta}" con…'),
        children: [
          for (final p in _proveedores)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Row(
                children: [
                  CircleAvatar(radius: 7, backgroundColor: Color(p.color)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.nombre)),
                ],
              ),
            ),
        ],
      ),
    );
    if (elegido != null && mounted) {
      await _confirmarFusion(h, elegido);
    }
  }

  Future<void> _confirmarFusion(
      ProveedorHuerfano h, Proveedor destino) async {
    final solapes =
        MantenimientoService.colisiones(h.id, destino.id, _precios);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fusionar histórico'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Todo el histórico de "${h.etiqueta}" pasará a '
                '"${destino.nombre}".'),
            const SizedBox(height: 10),
            Text('· ${h.nPrecios} precios'),
            if (h.nCompras > 0) Text('· ${h.nCompras} compras'),
            if (solapes > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$solapes precios caen el mismo día y el mismo producto que '
                'los de "${destino.nombre}". No se pierde nada, pero quedarán '
                'dos registros y la comparativa usará uno de los dos.',
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
            child: const Text('Fusionar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _ejecutar(() async {
      final r = await widget.db.reasignarProveedor(
        de: h.id,
        a: destino.id,
        nombreDestino: destino.nombre,
      );
      return 'Movidos ${r.precios} precios y ${r.compras} compras '
          'a "${destino.nombre}".';
    });
  }

  /// Vuelve a crear el proveedor con SU id original, con lo que su historico
  /// vuelve a colgar de el sin mover ningun documento.
  Future<void> _recuperar(ProveedorHuerfano h) async {
    final ctrl = TextEditingController(text: h.nombre);
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar proveedor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se vuelve a crear la ficha con su mismo identificador, así que '
              'su histórico vuelve a colgar de él tal cual estaba.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Recuperar'),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;

    await _ejecutar(() async {
      await widget.db.crearProveedorConId(
        h.id,
        Proveedor(id: h.id, nombre: nombre),
      );
      return '"$nombre" recuperado con su histórico.';
    });
  }

  Future<void> _borrarTarifas(ProveedorHuerfano h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar precios de tarifa'),
        content: Text(
          'Se borrarán ${h.preciosDeTarifa} precios de tarifa de '
          '"${h.etiqueta}".\n\n'
          '${h.preciosDeCompra > 0 ? "Los ${h.preciosDeCompra} que vienen de compras NO se tocan: son el gasto real.\n\n" : ""}'
          'Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _ejecutar(() async {
      final n = await widget.db.borrarPreciosDeProveedor(h.id);
      return 'Borrados $n precios de tarifa.';
    });
  }

  /// Lanza una operacion enseñando un candado mientras dura, avisa del
  /// resultado y vuelve a recalcular la lista.
  Future<void> _ejecutar(Future<String> Function() accion) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Trabajando…')),
          ],
        ),
      ),
    );
    String mensaje;
    try {
      mensaje = await accion();
    } catch (e) {
      mensaje = 'Ha fallado: $e';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // cierra el candado
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    await _cargar();
  }
}
