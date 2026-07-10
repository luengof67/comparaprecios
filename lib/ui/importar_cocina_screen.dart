import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import '../services/importar_cocina_service.dart';
import 'formato.dart';

enum _Filtro { todas, prodNuevos, provNuevos, duplicados }

class ImportarCocinaScreen extends StatefulWidget {
  final FirestoreService db;
  const ImportarCocinaScreen({super.key, required this.db});

  @override
  State<ImportarCocinaScreen> createState() => _ImportarCocinaScreenState();
}

class _ImportarCocinaScreenState extends State<ImportarCocinaScreen> {
  bool _cargando = false;
  bool _guardando = false;
  String? _error;
  List<LineaImport> _lineas = [];
  List<Producto> _productos = [];
  List<Proveedor> _proveedores = [];
  _Filtro _filtro = _Filtro.todas;

  Future<void> _elegirArchivo() async {
    setState(() => _error = null);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.first.bytes;
      if (bytes == null) {
        setState(() => _error = 'No se pudo leer el archivo.');
        return;
      }
      setState(() => _cargando = true);
      final contenido = utf8.decode(bytes);
      _productos = await widget.db.productos().first;
      _proveedores = await widget.db.proveedores().first;
      final precios = await widget.db.precios().first;
      final lineas = ImportarCocinaService.parsear(
          contenido, _productos, _proveedores, precios);
      setState(() {
        _lineas = lineas;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al leer el JSON: $e';
        _cargando = false;
      });
    }
  }

  List<LineaImport> get _filtradas {
    switch (_filtro) {
      case _Filtro.todas:
        return _lineas;
      case _Filtro.prodNuevos:
        return _lineas.where((l) => l.productoId == null).toList();
      case _Filtro.provNuevos:
        return _lineas.where((l) => l.proveedorId == null).toList();
      case _Filtro.duplicados:
        return _lineas.where((l) => l.duplicado).toList();
    }
  }

  int get _marcadas => _lineas.where((l) => l.importar).length;

  Future<void> _importar() async {
    if (_marcadas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay líneas marcadas para importar.')));
      return;
    }
    setState(() => _guardando = true);
    try {
      final resumen = await ImportarCocinaService.importar(
          widget.db, _lineas, _productos, _proveedores);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Importación completada'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• Precios añadidos: ${resumen.preciosAnadidos}'),
              Text('• Productos nuevos: ${resumen.productosNuevos}'),
              Text('• Proveedores nuevos: ${resumen.proveedoresNuevos}'),
              Text('• Omitidos: ${resumen.omitidos}'),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Vale')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al importar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar de Compras Cocina')),
      bottomNavigationBar: _lineas.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _importar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text('Importar $_marcadas precios'),
                ),
              ),
            ),
      body: _lineas.isEmpty ? _vistaInicio() : _vistaRevision(),
    );
  }

  Widget _vistaInicio() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Importa los precios que ya tienes en la app "Compras Cocina". '
          'Exporta allí el JSON, elígelo aquí, revisa y confirma.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _cargando ? null : _elegirArchivo,
          icon: const Icon(Icons.folder_open),
          label: const Text('Elegir archivo JSON'),
        ),
        const SizedBox(height: 20),
        if (_cargando) const Center(child: CircularProgressIndicator()),
        if (_error != null)
          Card(
            color: Colors.red.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ),
      ],
    );
  }

  Widget _vistaRevision() {
    final lista = _filtradas;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                    '${_lineas.length} líneas · $_marcadas marcadas',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final l in _lineas) {
                    l.importar = true;
                  }
                }),
                child: const Text('Marcar todas'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  for (final l in _lineas) {
                    l.importar = false;
                  }
                }),
                child: const Text('Ninguna'),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _chipFiltro('Todas', _Filtro.todas),
              _chipFiltro('Prod. nuevos', _Filtro.prodNuevos),
              _chipFiltro('Prov. nuevos', _Filtro.provNuevos),
              _chipFiltro('Duplicados', _Filtro.duplicados),
            ],
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: lista.length,
            itemBuilder: (_, i) => _fila(lista[i]),
          ),
        ),
      ],
    );
  }

  Widget _chipFiltro(String label, _Filtro f) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _filtro == f,
        onSelected: (_) => setState(() => _filtro = f),
      ),
    );
  }

  Widget _fila(LineaImport l) {
    final prodNuevo = l.productoId == null;
    final provNuevo = l.proveedorId == null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: CheckboxListTile(
        value: l.importar,
        onChanged: (v) => setState(() => l.importar = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            Expanded(child: Text(l.producto)),
            if (l.duplicado)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Chip(
                  label: Text('dup', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Color(0xFFFFE0B2),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l.proveedorNombre} · ${euros3(l.precio)}/${l.unidad.nombre} · '
                '${fecha(l.fecha)}'),
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              children: [
                _mini(prodNuevo ? 'producto nuevo' : 'producto existe',
                    prodNuevo ? Colors.blue : Colors.green),
                _mini(provNuevo ? 'proveedor nuevo' : 'proveedor existe',
                    provNuevo ? Colors.blue : Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(t, style: TextStyle(fontSize: 11, color: c)),
      );
}
