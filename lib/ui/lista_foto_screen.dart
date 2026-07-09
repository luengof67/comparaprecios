import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/linea_albaran.dart';
import '../models/producto.dart';
import '../services/albaran_service.dart';
import '../services/casador_service.dart';
import '../services/firestore_service.dart';

/// Estado editable de una línea leída de la foto de la lista.
class _LineaLista {
  final LineaAlbaran origen;
  String? productoId;
  TipoCasado tipo;
  bool ignorar;
  bool manual;
  final TextEditingController cantidad;

  _LineaLista(this.origen, this.tipo, this.productoId)
      : ignorar = false,
        manual = false,
        cantidad = TextEditingController(
            text: origen.cantidad != null ? _n(origen.cantidad!) : '');

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}

class ListaFotoScreen extends StatefulWidget {
  final FirestoreService db;
  const ListaFotoScreen({super.key, required this.db});

  @override
  State<ListaFotoScreen> createState() => _ListaFotoScreenState();
}

class _ListaFotoScreenState extends State<ListaFotoScreen> {
  bool _cargando = false;
  bool _guardando = false;
  String? _error;
  List<Producto> _catalogo = [];
  final List<_LineaLista> _lineas = [];
  bool _leido = false;

  Future<void> _capturar(ImageSource source) async {
    setState(() => _error = null);
    try {
      final picker = ImagePicker();
      final XFile? foto = await picker.pickImage(
          source: source, imageQuality: 85, maxWidth: 2000);
      if (foto == null) return;

      setState(() => _cargando = true);
      _catalogo = await widget.db.productos().first;
      final bytes = await foto.readAsBytes();
      final resultado = await AlbaranService.leer(bytes);

      _lineas.clear();
      for (final l in resultado.lineas) {
        final c = CasadorService.casar(l.descripcion, null, _catalogo);
        _lineas.add(_LineaLista(l, c.tipo, c.producto?.id));
      }
      if (mounted) {
        setState(() {
          _leido = true;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _cargando = false;
        });
      }
    }
  }

  Producto? _prod(String? id) {
    for (final p in _catalogo) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _guardar() async {
    final aMarcar = <MapEntry<String, double>>[];
    final incompletas = <String>[];
    for (final le in _lineas) {
      if (le.ignorar) continue;
      final prod = _prod(le.productoId);
      final cant = double.tryParse(le.cantidad.text.trim().replaceAll(',', '.'));
      if (prod == null) {
        incompletas.add('${le.origen.descripcion} — sin producto');
        continue;
      }
      if (cant == null || cant <= 0) {
        incompletas.add('${le.origen.descripcion} — falta cantidad');
        continue;
      }
      aMarcar.add(MapEntry(prod.id, cant));
    }

    if (incompletas.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Líneas sin completar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${aMarcar.length} productos listos.\n'
                    'Estos ${incompletas.length} no se añadirán:'),
                const SizedBox(height: 8),
                ...incompletas.map((t) => Text('• $t',
                    style: const TextStyle(fontSize: 13, color: Colors.red))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Volver')),
            if (aMarcar.isNotEmpty)
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Añadir ${aMarcar.length}')),
          ],
        ),
      );
      if (seguir != true) return;
    }

    if (aMarcar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay productos para añadir.')));
      return;
    }

    setState(() => _guardando = true);
    try {
      // Empezar de cero: vaciar la lista actual.
      await widget.db.setEnListaTodos(false);
      for (final e in aMarcar) {
        await widget.db.setEnLista(e.key, true);
        await widget.db.setCantidadSemana(e.key, e.value);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lista montada: ${aMarcar.length} productos.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _elegirProducto(_LineaLista le) async {
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SelectorSimple(catalogo: _catalogo, sugerencia: le.origen.descripcion),
    );
    if (res == null) return;
    setState(() {
      le.productoId = res;
      le.tipo = TipoCasado.propuesto;
      le.manual = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lista por foto')),
      bottomNavigationBar: _leido
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.playlist_add_check),
                  label: const Text('Montar lista con esto'),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Haz una foto de tu lista de la compra (o elígela de la galería). '
            'La IA leerá los productos y podrás revisarlos antes de montarla.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _cargando ? null : () => _capturar(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed:
                      _cargando ? null : () => _capturar(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_cargando) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(
                child: Text('Leyendo la lista…',
                    style: TextStyle(color: Colors.grey))),
          ],
          if (_error != null)
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudo leer:\n$_error',
                    style: const TextStyle(color: Colors.red)),
              ),
            ),
          if (_leido && !_cargando) ...[
            Text('${_lineas.length} líneas leídas — revisa y casa:',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._lineas.map(_tarjeta),
          ],
        ],
      ),
    );
  }

  Widget _tarjeta(_LineaLista le) {
    final prod = _prod(le.productoId);
    final unidad = prod?.unidadBase.nombre ?? le.origen.unidad ?? 'ud';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(le.origen.descripcion,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                _chip(le),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(prod != null ? '→ ${prod.nombre}' : 'Sin producto',
                      style: TextStyle(
                          color: prod != null ? null : Colors.grey,
                          fontStyle:
                              prod != null ? null : FontStyle.italic)),
                ),
                TextButton(
                  onPressed: () => _elegirProducto(le),
                  child: Text(prod != null ? 'Cambiar' : 'Elegir'),
                ),
              ],
            ),
            if (!le.ignorar) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 160,
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
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(le.ignorar ? Icons.undo : Icons.block, size: 16),
                label: Text(le.ignorar ? 'Incluir' : 'Ignorar'),
                onPressed: () => setState(() => le.ignorar = !le.ignorar),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(_LineaLista le) {
    if (le.ignorar) {
      return const Chip(
          label: Text('Ignorada'),
          visualDensity: VisualDensity.compact,
          backgroundColor: Color(0xFFEEEEEE));
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
}

/// Selector simple de producto del catálogo (sin crear nuevos).
class _SelectorSimple extends StatefulWidget {
  final List<Producto> catalogo;
  final String sugerencia;
  const _SelectorSimple({required this.catalogo, required this.sugerencia});

  @override
  State<_SelectorSimple> createState() => _SelectorSimpleState();
}

class _SelectorSimpleState extends State<_SelectorSimple> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtro = _q.toLowerCase();
    final lista = widget.catalogo
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
          Text('Foto: "${widget.sugerencia}"',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Buscar producto',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
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
}
