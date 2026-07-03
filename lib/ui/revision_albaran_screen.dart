import 'package:flutter/material.dart';

import '../models/compra.dart';
import '../models/linea_albaran.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/casador_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Estado editable de una línea durante la revisión.
class _LineaEd {
  final LineaAlbaran origen;
  String? productoId;
  TipoCasado tipo;
  bool ignorar;
  final TextEditingController cantidad;
  final TextEditingController precio;

  _LineaEd(this.origen, this.tipo, this.productoId)
      : ignorar = false,
        cantidad = TextEditingController(
            text: origen.cantidad != null ? _n(origen.cantidad!) : ''),
        precio = TextEditingController(
            text: origen.unitarioCalculado != null
                ? origen.unitarioCalculado!.toStringAsFixed(3)
                : '');

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}

class RevisionAlbaranScreen extends StatefulWidget {
  final FirestoreService db;
  final ResultadoAlbaran resultado;
  const RevisionAlbaranScreen({
    super.key,
    required this.db,
    required this.resultado,
  });

  @override
  State<RevisionAlbaranScreen> createState() => _RevisionAlbaranScreenState();
}

class _RevisionAlbaranScreenState extends State<RevisionAlbaranScreen> {
  bool _cargando = true;
  bool _guardando = false;
  List<Producto> _productos = [];
  List<Proveedor> _proveedores = [];
  String? _proveedorId;
  DateTime _fecha = DateTime.now();
  final List<_LineaEd> _lineas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _productos = await widget.db.productos().first;
    _proveedores = await widget.db.proveedores().first;
    // Intenta preseleccionar proveedor por el nombre detectado.
    if (widget.resultado.proveedor != null) {
      final det = widget.resultado.proveedor!.toLowerCase();
      for (final p in _proveedores) {
        if (det.contains(p.nombre.toLowerCase()) ||
            p.nombre.toLowerCase().contains(det)) {
          _proveedorId = p.id;
          break;
        }
      }
    }
    _recalcular();
    if (mounted) setState(() => _cargando = false);
  }

  void _recalcular() {
    _lineas.clear();
    for (final l in widget.resultado.lineas) {
      final c = CasadorService.casar(l.descripcion, _proveedorId, _productos);
      _lineas.add(_LineaEd(l, c.tipo, c.producto?.id));
    }
  }

  Producto? _prod(String? id) {
    for (final p in _productos) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _guardar() async {
    if (_proveedorId == null) {
      _aviso('Elige el proveedor de la compra.');
      return;
    }
    final prov = _proveedores.firstWhere((p) => p.id == _proveedorId);
    final lineasCompra = <LineaCompra>[];
    final aprender = <MapEntry<String, AliasProducto>>[];

    for (final le in _lineas) {
      if (le.ignorar || le.productoId == null) continue;
      final producto = _prod(le.productoId);
      if (producto == null) continue;
      final cant = double.tryParse(le.cantidad.text.trim().replaceAll(',', '.'));
      final precio = double.tryParse(le.precio.text.trim().replaceAll(',', '.'));
      if (cant == null || precio == null) continue;

      lineasCompra.add(LineaCompra(
        productoId: producto.id,
        productoNombre: producto.nombre,
        unidad: producto.unidadBase.nombre,
        cantidad: cant,
        precioUnitario: precio,
      ));

      // Aprender alias si el texto del albarán no está ya como alias de este
      // producto para este proveedor.
      final ya = producto.alias.any((a) =>
          a.texto.toLowerCase().trim() ==
          le.origen.descripcion.toLowerCase().trim());
      if (!ya) {
        aprender.add(MapEntry(
          producto.id,
          AliasProducto(texto: le.origen.descripcion, proveedorId: _proveedorId),
        ));
      }
    }

    if (lineasCompra.isEmpty) {
      _aviso('No hay líneas casadas para guardar.');
      return;
    }

    setState(() => _guardando = true);
    try {
      // Aprender alias (uno por uno).
      for (final e in aprender) {
        await widget.db.agregarAlias(e.key, e.value);
      }
      // Registrar la compra (crea también los precios).
      await widget.db.registrarCompra(Compra(
        id: '',
        proveedorId: prov.id,
        proveedorNombre: prov.nombre,
        fecha: _fecha,
        lineas: lineasCompra,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compra guardada: ${lineasCompra.length} líneas.')),
        );
        Navigator.pop(context); // cierra revisión
        Navigator.pop(context); // cierra escáner
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        _aviso('Error al guardar: $e');
      }
    }
  }

  void _aviso(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Revisar albarán')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Guardar compra'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _proveedorId,
            decoration: const InputDecoration(
                labelText: 'Proveedor de la compra',
                border: OutlineInputBorder()),
            items: _proveedores
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                .toList(),
            onChanged: (v) => setState(() {
              _proveedorId = v;
              _recalcular();
            }),
          ),
          const SizedBox(height: 8),
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
          const Divider(),
          ..._lineas.map(_tarjetaLinea),
        ],
      ),
    );
  }

  Widget _tarjetaLinea(_LineaEd le) {
    final prod = _prod(le.productoId);
    final unidad = prod?.unidadBase.nombre ?? le.origen.unidad ?? 'ud';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Texto original del albarán.
            Text(le.origen.descripcion,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            // Estado del casado + producto.
            Row(
              children: [
                _chipEstado(le),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prod != null ? '→ ${prod.nombre}' : 'Sin producto',
                    style: TextStyle(
                        color: prod != null ? null : Colors.grey,
                        fontStyle: prod != null ? null : FontStyle.italic),
                  ),
                ),
                TextButton(
                  onPressed: () => _elegirProducto(le),
                  child: Text(prod != null ? 'Cambiar' : 'Elegir'),
                ),
              ],
            ),
            if (!le.ignorar) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: le.cantidad,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Cantidad ($unidad)',
                          isDense: true,
                          border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: le.precio,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Precio €/$unidad',
                          isDense: true,
                          border: const OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(le.ignorar ? Icons.undo : Icons.block, size: 16),
                label: Text(le.ignorar ? 'Incluir' : 'Ignorar línea'),
                onPressed: () => setState(() => le.ignorar = !le.ignorar),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipEstado(_LineaEd le) {
    if (le.ignorar) {
      return const Chip(
        label: Text('Ignorada'),
        visualDensity: VisualDensity.compact,
        backgroundColor: Color(0xFFEEEEEE),
      );
    }
    return switch (le.tipo) {
      TipoCasado.automatico => const Chip(
          label: Text('Auto'),
          visualDensity: VisualDensity.compact,
          avatar: Icon(Icons.check_circle, color: Colors.green, size: 16)),
      TipoCasado.propuesto => const Chip(
          label: Text('Sugerido'),
          visualDensity: VisualDensity.compact,
          avatar: Icon(Icons.help_outline, color: Colors.orange, size: 16)),
      TipoCasado.sinCoincidencia => const Chip(
          label: Text('Sin casar'),
          visualDensity: VisualDensity.compact,
          avatar: Icon(Icons.error_outline, color: Colors.red, size: 16)),
    };
  }

  Future<void> _elegirProducto(_LineaEd le) async {
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SelectorProducto(
        db: widget.db,
        productos: _productos,
        sugerencia: le.origen.descripcion,
      ),
    );
    if (res == null) return;
    if (res.startsWith('nuevo:')) {
      // Se creó un producto nuevo; recargar lista y seleccionarlo.
      final nuevoId = res.substring(6);
      _productos = await widget.db.productos().first;
      setState(() {
        le.productoId = nuevoId;
        le.tipo = TipoCasado.propuesto;
      });
    } else {
      setState(() {
        le.productoId = res;
        le.tipo = TipoCasado.propuesto;
      });
    }
  }
}

/// Hoja para elegir un producto existente o crear uno nuevo.
class _SelectorProducto extends StatefulWidget {
  final FirestoreService db;
  final List<Producto> productos;
  final String sugerencia;
  const _SelectorProducto({
    required this.db,
    required this.productos,
    required this.sugerencia,
  });

  @override
  State<_SelectorProducto> createState() => _SelectorProductoState();
}

class _SelectorProductoState extends State<_SelectorProducto> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final filtro = _busqueda.toLowerCase();
    final lista = widget.productos
        .where((p) => p.nombre.toLowerCase().contains(filtro))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Elegir producto',
              style: Theme.of(context).textTheme.titleLarge),
          Text('Albarán: "${widget.sugerencia}"',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Buscar producto',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _busqueda = v),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: const Text('Crear producto nuevo con este nombre'),
            onPressed: _crearNuevo,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 280,
            child: ListView(
              children: lista
                  .map((p) => ListTile(
                        title: Text(p.nombre),
                        subtitle: Text(p.categoria),
                        onTap: () => Navigator.pop(context, p.id),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _crearNuevo() async {
    // Crea un producto rápido con el nombre del albarán (editable luego).
    final id = await widget.db.guardarProducto(Producto(
      id: '',
      nombre: widget.sugerencia,
      categoria: 'General',
      unidadBase: UnidadBase.kg,
    ));
    if (mounted) Navigator.pop(context, 'nuevo:$id');
  }
}
