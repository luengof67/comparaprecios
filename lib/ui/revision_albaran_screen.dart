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
  bool manual; // el usuario eligió producto a mano (no re-casar)
  final TextEditingController cantidad;
  final TextEditingController precio;

  _LineaEd(this.origen, this.tipo, this.productoId)
      : ignorar = false,
        manual = false,
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
    // Crea las líneas UNA vez (conserva controllers y elecciones).
    _lineas.clear();
    for (final l in widget.resultado.lineas) {
      _lineas.add(_LineaEd(l, TipoCasado.sinCoincidencia, null));
    }
    _aplicarCasado();
    if (mounted) setState(() => _cargando = false);
  }

  /// Aplica el casado a las líneas que el usuario no ha tocado a mano.
  void _aplicarCasado() {
    for (final le in _lineas) {
      if (le.manual) continue;
      final c = CasadorService.casar(le.origen.descripcion, _proveedorId, _productos);
      le.tipo = c.tipo;
      le.productoId = c.producto?.id;
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
    final incompletas = <String>[]; // descripciones de las que no se pueden guardar

    for (final le in _lineas) {
      if (le.ignorar) continue;
      final producto = _prod(le.productoId);
      final cant = double.tryParse(le.cantidad.text.trim().replaceAll(',', '.'));
      final precio = double.tryParse(le.precio.text.trim().replaceAll(',', '.'));

      // Motivo por el que una línea no es guardable.
      if (producto == null) {
        incompletas.add('${le.origen.descripcion} — sin producto asignado');
        continue;
      }
      if (cant == null || cant <= 0) {
        incompletas.add('${le.origen.descripcion} — falta la cantidad');
        continue;
      }
      if (precio == null || precio <= 0) {
        incompletas.add('${le.origen.descripcion} — falta el precio');
        continue;
      }

      lineasCompra.add(LineaCompra(
        productoId: producto.id,
        productoNombre: producto.nombre,
        unidad: producto.unidadBase.nombre,
        cantidad: cant,
        precioUnitario: precio,
      ));

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

    // Si hay líneas que no se pueden guardar, avisar y dejar decidir.
    if (incompletas.isNotEmpty) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Líneas sin completar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${lineasCompra.length} líneas listas para guardar.\n'
                    'Estas ${incompletas.length} no se guardarán:'),
                const SizedBox(height: 8),
                ...incompletas.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $t',
                          style: const TextStyle(fontSize: 13, color: Colors.red)),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Volver a revisar')),
            if (lineasCompra.isNotEmpty)
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Guardar ${lineasCompra.length}')),
          ],
        ),
      );
      if (continuar != true) return;
    }

    if (lineasCompra.isEmpty) {
      _aviso('No hay líneas completas para guardar.');
      return;
    }

    setState(() => _guardando = true);
    try {
      for (final e in aprender) {
        await widget.db.agregarAlias(e.key, e.value);
      }
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
              _aplicarCasado();
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
        le.manual = true;
      });
    } else {
      setState(() {
        le.productoId = res;
        le.tipo = TipoCasado.propuesto;
        le.manual = true;
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
