import 'package:flutter/material.dart';

import '../models/proveedor.dart';
import '../services/firestore_service.dart';

const _coloresProveedor = [
  0xFF1565C0, // azul
  0xFFD84315, // naranja oscuro
  0xFF2E7D32, // verde
  0xFF6A1B9A, // morado
  0xFFC62828, // rojo
  0xFF00838F, // teal
  0xFFF9A825, // ambar
  0xFF4527A0, // indigo
];

class ProveedoresScreen extends StatelessWidget {
  final FirestoreService db;
  const ProveedoresScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Proveedor'),
      ),
      body: StreamBuilder<List<Proveedor>>(
        stream: db.proveedores(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final proveedores = snap.data!;
          if (proveedores.isEmpty) {
            return const Center(
              child: Text('Añade tus proveedores con el botón +',
                  style: TextStyle(color: Colors.grey)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: proveedores.length,
            itemBuilder: (_, i) {
              final p = proveedores[i];
              return ListTile(
                leading: CircleAvatar(backgroundColor: Color(p.color)),
                title: Text(p.nombre),
                subtitle: p.contacto != null ? Text(p.contacto!) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editar(context, p),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _editar(BuildContext context, Proveedor? existente) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProveedorForm(db: db, existente: existente),
    );
  }
}

class _ProveedorForm extends StatefulWidget {
  final FirestoreService db;
  final Proveedor? existente;
  const _ProveedorForm({required this.db, this.existente});

  @override
  State<_ProveedorForm> createState() => _ProveedorFormState();
}

class _ProveedorFormState extends State<_ProveedorForm> {
  late final TextEditingController _nombre;
  late final TextEditingController _contacto;
  late int _color;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.existente?.nombre ?? '');
    _contacto = TextEditingController(text: widget.existente?.contacto ?? '');
    _color = widget.existente?.color ?? _coloresProveedor.first;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _contacto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) return;
    await widget.db.guardarProveedor(Proveedor(
      id: widget.existente?.id ?? '',
      nombre: _nombre.text.trim(),
      contacto: _contacto.text.trim().isEmpty ? null : _contacto.text.trim(),
      color: _color,
    ));
    if (mounted) Navigator.pop(context);
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
          Text(widget.existente == null ? 'Nuevo proveedor' : 'Editar proveedor',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nombre,
            decoration: const InputDecoration(
                labelText: 'Nombre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contacto,
            decoration: const InputDecoration(
                labelText: 'Contacto (teléfono / WhatsApp)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Color de identificación'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: _coloresProveedor.map((c) {
              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c ? Colors.black : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.existente != null)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Borrar', style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    await widget.db.borrarProveedor(widget.existente!.id);
                    if (mounted) Navigator.pop(context);
                  },
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
