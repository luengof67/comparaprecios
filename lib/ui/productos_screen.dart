import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../services/firestore_service.dart';
import 'producto_detalle_screen.dart';

class ProductosScreen extends StatelessWidget {
  final FirestoreService db;
  const ProductosScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Producto'),
      ),
      body: StreamBuilder<List<Producto>>(
        stream: db.productos(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final productos = snap.data!;
          if (productos.isEmpty) {
            return const Center(
              child: Text('Crea tu primer producto con el botón +',
                  style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: productos.length,
            itemBuilder: (_, i) {
              final p = productos[i];
              return ListTile(
                leading: CircleAvatar(child: Text(p.unidadBase.nombre)),
                title: Text(p.nombre),
                subtitle: Text(p.categoria),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editar(context, p),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductoDetalleScreen(db: db, producto: p),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _editar(BuildContext context, Producto? existente) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductoForm(db: db, existente: existente),
    );
  }
}

class _ProductoForm extends StatefulWidget {
  final FirestoreService db;
  final Producto? existente;
  const _ProductoForm({required this.db, this.existente});

  @override
  State<_ProductoForm> createState() => _ProductoFormState();
}

class _ProductoFormState extends State<_ProductoForm> {
  late final TextEditingController _nombre;
  late final TextEditingController _categoria;
  late final TextEditingController _cantidad;
  late UnidadBase _unidad;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.existente?.nombre ?? '');
    _categoria = TextEditingController(text: widget.existente?.categoria ?? 'General');
    final ch = widget.existente?.cantidadHabitual ?? 0;
    _cantidad = TextEditingController(text: ch > 0 ? _num(ch) : '');
    _unidad = widget.existente?.unidadBase ?? UnidadBase.kg;
  }

  String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _nombre.dispose();
    _categoria.dispose();
    _cantidad.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) return;
    final cantidad =
        double.tryParse(_cantidad.text.trim().replaceAll(',', '.')) ?? 0;
    await widget.db.guardarProducto(Producto(
      id: widget.existente?.id ?? '',
      nombre: _nombre.text.trim(),
      categoria: _categoria.text.trim().isEmpty ? 'General' : _categoria.text.trim(),
      unidadBase: _unidad,
      cantidadHabitual: cantidad,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmarBorrado() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar producto'),
        content: Text('¿Seguro que quieres borrar "${widget.existente!.nombre}"?\n\n'
            'Esta acción no se puede deshacer.'),
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
    if (ok == true) {
      await widget.db.borrarProducto(widget.existente!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text(widget.existente == null ? 'Nuevo producto' : 'Editar producto',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nombre,
            decoration: const InputDecoration(
                labelText: 'Nombre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoria,
            decoration: const InputDecoration(
                labelText: 'Categoría', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          const Text('Comparar precio por:'),
          const SizedBox(height: 4),
          SegmentedButton<UnidadBase>(
            segments: const [
              ButtonSegment(value: UnidadBase.kg, label: Text('€/kg')),
              ButtonSegment(value: UnidadBase.litro, label: Text('€/L')),
              ButtonSegment(value: UnidadBase.unidad, label: Text('€/ud')),
            ],
            selected: {_unidad},
            onSelectionChanged: (s) => setState(() => _unidad = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cantidad,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cantidad que sueles comprar (${_unidad.nombre})',
              helperText: 'Opcional. Sirve para calcular el coste y ahorro reales.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.existente != null)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Borrar', style: TextStyle(color: Colors.red)),
                  onPressed: _confirmarBorrado,
                ),
              const Spacer(),
              FilledButton(onPressed: _guardar, child: const Text('Guardar')),
            ],
          ),
        ],
      ),
    );
  }
}
