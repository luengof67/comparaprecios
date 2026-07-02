import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import 'categorias.dart';
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
                leading: CircleAvatar(
                  backgroundColor: colorCategoria(p.categoria).withValues(alpha: 0.15),
                  child: Icon(iconoCategoria(p.categoria),
                      color: colorCategoria(p.categoria)),
                ),
                title: Text(p.nombre),
                subtitle: Text('${p.categoria} · ${p.unidadBase.etiqueta}'),
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
  late String _categoria;
  late final TextEditingController _cantidad;
  late UnidadBase _unidad;
  late List<AliasProducto> _alias;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.existente?.nombre ?? '');
    _categoria = categoriaValida(widget.existente?.categoria);
    final ch = widget.existente?.cantidadHabitual ?? 0;
    _cantidad = TextEditingController(text: ch > 0 ? _num(ch) : '');
    _unidad = widget.existente?.unidadBase ?? UnidadBase.kg;
    _alias = List<AliasProducto>.from(widget.existente?.alias ?? const []);
  }

  String _num(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) return;
    final cantidad =
        double.tryParse(_cantidad.text.trim().replaceAll(',', '.')) ?? 0;
    final base = widget.existente;
    await widget.db.guardarProducto(Producto(
      id: base?.id ?? '',
      nombre: _nombre.text.trim(),
      categoria: _categoria,
      unidadBase: _unidad,
      cantidadHabitual: cantidad,
      // Conservamos lo que no edita este formulario:
      cantidadSemana: base?.cantidadSemana ?? 0,
      enLista: base?.enLista ?? true,
      alias: _alias,
      notas: base?.notas,
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
          DropdownButtonFormField<String>(
            initialValue: _categoria,
            decoration: const InputDecoration(
                labelText: 'Categoría', border: OutlineInputBorder()),
            items: categorias
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Icon(iconoCategoria(c),
                              size: 20, color: colorCategoria(c)),
                          const SizedBox(width: 10),
                          Text(c),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _categoria = v ?? 'General'),
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
          const Divider(),
          Row(
            children: [
              const Icon(Icons.sell_outlined, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Nombres alternativos (alias)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Añadir'),
                onPressed: _agregarAlias,
              ),
            ],
          ),
          const Text(
            'Cómo llaman los proveedores a este producto. Se usan para reconocer '
            'las líneas al escanear albaranes.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (_alias.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Sin alias todavía.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            StreamBuilder<List<Proveedor>>(
              stream: widget.db.proveedores(),
              builder: (context, snap) {
                final provs = {for (final p in (snap.data ?? [])) p.id: p.nombre};
                return Column(
                  children: _alias.asMap().entries.map((e) {
                    final i = e.key;
                    final a = e.value;
                    final prov = a.proveedorId != null
                        ? (provs[a.proveedorId] ?? 'proveedor')
                        : 'todos';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.texto),
                      subtitle: Text(prov,
                          style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _alias.removeAt(i)),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          const SizedBox(height: 8),
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

  void _agregarAlias() {
    final textoCtrl = TextEditingController();
    String? provId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nuevo alias'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textoCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre tal como aparece',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<Proveedor>>(
                stream: widget.db.proveedores(),
                builder: (context, snap) {
                  final provs = snap.data ?? [];
                  return DropdownButtonFormField<String>(
                    initialValue: provId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Cualquiera')),
                      ...provs.map((p) => DropdownMenuItem(
                          value: p.id, child: Text(p.nombre))),
                    ],
                    onChanged: (v) => setLocal(() => provId = v),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final t = textoCtrl.text.trim();
                if (t.isEmpty) return;
                setState(() => _alias.add(
                    AliasProducto(texto: t, proveedorId: provId)));
                Navigator.pop(ctx);
              },
              child: const Text('Añadir'),
            ),
          ],
        ),
      ),
    );
  }
}
