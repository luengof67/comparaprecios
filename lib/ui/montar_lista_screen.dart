import 'package:flutter/material.dart';

import '../models/plantilla.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Monta la lista de la compra escribiendo, sin pensar en precios:
/// autocompletar desde el catálogo, cantidad + formato (caja, docena,
/// estuche...) y un aviso informativo del último precio más barato.
/// El precio real se confirma después, con el albarán.
class MontarListaScreen extends StatefulWidget {
  final FirestoreService db;
  const MontarListaScreen({super.key, required this.db});

  @override
  State<MontarListaScreen> createState() => _MontarListaScreenState();
}

/// Formatos genéricos que se ofrecen siempre, además de los que ya
/// tenga registrados el proveedor en el histórico de precios.
const _formatosGenericos = ['caja', 'docena', 'estuche', 'saco', 'garrafa', 'lata'];
class _MontarListaScreenState extends State<MontarListaScreen> {
  final _campo = TextEditingController();
  List<Producto> _catalogo = [];
  Map<String, Proveedor> _proveedores = {};
  bool _cargando = true;
  String _busqueda = '';
  // Añadidos en esta sesión: productoId -> (cantidad, formato).
  final Map<String, ({double cantidad, String formato})> _anadidos = {};

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    _catalogo = await widget.db.productos().first;
    final provs = await widget.db.proveedores().first;
    _proveedores = {for (final p in provs) p.id: p};
    if (!mounted) return;
    // Confirmar que se vacía la lista actual para empezar de cero.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Montar lista nueva'),
        content: const Text(
            'Se vaciará la lista actual para que montes una nueva escribiendo. '
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vaciar y empezar')),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await widget.db.setEnListaTodos(false);
    if (mounted) setState(() => _cargando = false);
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  List<Producto> get _sugerencias {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _catalogo.where((p) {
      if (p.nombre.toLowerCase().contains(q)) return true;
      for (final a in p.alias) {
        if (a.texto.toLowerCase().contains(q)) return true;
      }
      return false;
    }).take(8).toList();
  }

  /// Último precio de cada proveedor para este producto; devuelve el más
  /// barato (para el aviso) y los formatos conocidos del histórico.
  ({Precio? mejor, List<String> formatos}) _analizar(List<Precio> historico) {
    final Map<String, Precio> ultimoPorProv = {};
    for (final pr in historico) {
      final actual = ultimoPorProv[pr.proveedorId];
      if (actual == null || pr.fecha.isAfter(actual.fecha)) {
        ultimoPorProv[pr.proveedorId] = pr;
      }
    }
    Precio? mejor;
    final formatos = <String>[];
    for (final pr in ultimoPorProv.values) {
      if (mejor == null || pr.precioUnitario < mejor.precioUnitario) {
        mejor = pr;
      }
      final f = (pr.formato ?? '').trim().toLowerCase();
      if (f.isNotEmpty && !formatos.contains(f)) formatos.add(f);
    }
    return (mejor: mejor, formatos: formatos);
  }

  Future<void> _elegir(Producto p) async {
    // Histórico del producto: para el aviso de mejor precio y sus formatos.
    final historico = await widget.db.preciosDeProductoUnaVez(p.id);
    if (!mounted) return;
    final analisis = _analizar(historico);
    final mejor = analisis.mejor;
    final nombreMejor = mejor == null
        ? null
        : (_proveedores[mejor.proveedorId]?.nombre ?? 'proveedor');

    // Chips de formato: unidad base + históricos + genéricos, sin repetir.
    final opciones = <String>[
      p.unidadBase.nombre,
      ...analisis.formatos,
      for (final f in _formatosGenericos)
        if (!analisis.formatos.contains(f)) f,
    ];

    final ctrl = TextEditingController(
        text: p.cantidadHabitual > 0 ? _n(p.cantidadHabitual) : '');
    String formatoElegido = p.unidadBase.nombre;

    final resultado =
        await showDialog<({double cantidad, String formato})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogo) {
          void confirmar() {
            final v =
                double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
            if (v == null || v <= 0) return;
            Navigator.pop(ctx, (cantidad: v, formato: formatoElegido));
          }

          return AlertDialog(
            title: Text(p.nombre),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Cantidad ($formatoElegido)',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => confirmar(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: -4,
                  children: opciones.map((f) {
                    return ChoiceChip(
                      label: Text(f),
                      selected: formatoElegido == f,
                      onSelected: (_) =>
                          setDialogo(() => formatoElegido = f),
                    );
                  }).toList(),
                ),
                if (mejor != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Último mejor precio: $nombreMejor · '
                      '${euros(mejor.precioUnitario)}/${p.unidadBase.nombre} '
                      '(${fechaCorta(mejor.fecha)})',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.green),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: confirmar,
                child: const Text('Añadir'),
              ),
            ],
          );
        },
      ),
    );
    if (resultado == null) return;

    // Si el formato elegido no es la unidad base, la cantidad va "en formato"
    // (cajas, docenas...) y el coste se confirmará con el albarán.
    final enFormato = resultado.formato != p.unidadBase.nombre;
    await widget.db.setEnLista(p.id, true);
    await widget.db.setCantidadSemana(p.id, resultado.cantidad,
        enFormato: enFormato, formato: enFormato ? resultado.formato : '');
    setState(() {
      _anadidos[p.id] =
          (cantidad: resultado.cantidad, formato: resultado.formato);
      _campo.clear();
      _busqueda = '';
    });
  }

  Future<void> _quitar(String id) async {
    await widget.db.setEnLista(id, false);
    setState(() => _anadidos.remove(id));
  }

  Producto? _prod(String id) {
    for (final p in _catalogo) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sug = _sugerencias;
    final sinResultados = _busqueda.trim().isNotEmpty && sug.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Montar lista'),
        actions: [
          IconButton(
            tooltip: 'Cargar plantilla',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: _cargarPlantilla,
          ),
          IconButton(
            tooltip: 'Guardar como plantilla',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _anadidos.isEmpty ? null : _guardarPlantilla,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text('Hecho (${_anadidos.length} en la lista)'),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _campo,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Escribe un producto',
                hintText: 'Ej. tomate, aceite, pollo…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _campo.clear();
                          setState(() => _busqueda = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
          // Sugerencias o aviso.
          if (sug.isNotEmpty)
            SizedBox(
              height: 220,
              child: ListView(
                children: sug.map((p) {
                  final yaEsta = _anadidos.containsKey(p.id);
                  return ListTile(
                    title: Text(p.nombre),
                    subtitle: Text(p.categoria),
                    trailing: yaEsta
                        ? const Icon(Icons.check, color: Colors.green)
                        : const Icon(Icons.add),
                    onTap: yaEsta ? null : () => _elegir(p),
                  );
                }).toList(),
              ),
            ),
          if (sinResultados)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: Colors.orange.withValues(alpha: 0.12),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Ese producto no está en tu catálogo, así que no puedo '
                    'darte precio. Créalo antes en la pestaña Productos si '
                    'quieres incluirlo con precios.',
                  ),
                ),
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('En la lista (${_anadidos.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: _anadidos.isEmpty
                ? const Center(
                    child: Text('Ve escribiendo y eligiendo productos',
                        style: TextStyle(color: Colors.grey)))
                : ListView(
                    children: _anadidos.entries.map((e) {
                      final p = _prod(e.key);
                      final v = e.value;
                      return ListTile(
                        title: Text(p?.nombre ?? '—'),
                        subtitle: Text('${_n(v.cantidad)} ${v.formato}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _quitar(e.key),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }


  /// Guarda la lista actual como plantilla reutilizable.
  Future<void> _guardarPlantilla() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar como plantilla'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Ej. Pedido del martes',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;
    final lineas = _anadidos.entries.map((e) {
      final p = _prod(e.key);
      final esBase = p != null && e.value.formato == p.unidadBase.nombre;
      return LineaPlantilla(
        productoId: e.key,
        cantidad: e.value.cantidad,
        formato: esBase ? '' : e.value.formato,
      );
    }).toList();
    await widget.db.guardarPlantilla(nombre, lineas);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Plantilla "$nombre" guardada (${lineas.length} productos).')));
    }
  }

  /// Muestra las plantillas guardadas y carga la elegida sobre la lista.
  Future<void> _cargarPlantilla() async {
    final plantillas = await widget.db.plantillasUnaVez();
    if (!mounted) return;
    if (plantillas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay plantillas. Monta una lista y guárdala '
              'con el icono de marcador.')));
      return;
    }
    final elegida = await showModalBottomSheet<PlantillaLista>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Cargar plantilla',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...plantillas.map((pl) => ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(pl.nombre),
                  subtitle: Text('${pl.lineas.length} productos'),
                  onTap: () => Navigator.pop(ctx, pl),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (c2) => AlertDialog(
                          title: Text('¿Borrar "${pl.nombre}"?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c2, false),
                                child: const Text('Cancelar')),
                            FilledButton(
                                onPressed: () => Navigator.pop(c2, true),
                                child: const Text('Borrar')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await widget.db.borrarPlantilla(pl.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                  ),
                )),
          ],
        ),
      ),
    );
    if (elegida == null) return;
    // Aplica cada línea; los productos borrados del catálogo se omiten.
    var omitidos = 0;
    for (final l in elegida.lineas) {
      final p = _prod(l.productoId);
      if (p == null) {
        omitidos++;
        continue;
      }
      final formato = l.formato.isEmpty ? p.unidadBase.nombre : l.formato;
      final enFormato = formato != p.unidadBase.nombre;
      await widget.db.setEnLista(p.id, true);
      await widget.db.setCantidadSemana(p.id, l.cantidad,
          enFormato: enFormato, formato: enFormato ? formato : '');
      _anadidos[p.id] = (cantidad: l.cantidad, formato: formato);
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Plantilla "${elegida.nombre}" cargada'
              '${omitidos > 0 ? " ($omitidos productos ya no existen)" : ""}.')));
    }
  }

  static String _n(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}
