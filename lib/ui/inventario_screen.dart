import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../services/firestore_service.dart';
import '../services/inventario_pdf_service.dart';

/// Genera la hoja de inventario en papel: todos los productos agrupados por
/// categoría, a dos columnas, con casillas vacías de existencia, previsión y
/// compra final para rellenar a mano recorriendo el almacén.
class InventarioScreen extends StatefulWidget {
  final FirestoreService db;

  const InventarioScreen({super.key, required this.db});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  /// Categorías desmarcadas por el usuario. Lo guardamos "al revés" (las
  /// excluidas) para que las categorías nuevas entren marcadas por defecto.
  final Set<String> _excluidas = {};

  bool _mostrarUnidad = true;
  bool _generando = false;

  static const String _sinCategoria = 'SIN CLASIFICAR';

  String _categoriaDe(Producto p) =>
      p.categoria.trim().isEmpty ? _sinCategoria : p.categoria.trim();

  Map<String, List<Producto>> _agrupar(List<Producto> productos) {
    final mapa = <String, List<Producto>>{};
    for (final p in productos) {
      if (p.nombre.trim().isEmpty) continue;
      mapa.putIfAbsent(_categoriaDe(p), () => []).add(p);
    }
    return mapa;
  }

  Map<String, List<ItemInventario>> _paraPdf(Map<String, List<Producto>> grupos) {
    final salida = <String, List<ItemInventario>>{};
    grupos.forEach((categoria, productos) {
      if (_excluidas.contains(categoria)) return;
      salida[categoria] = productos
          .map((p) => ItemInventario(
                nombre: p.nombre,
                detalle: _mostrarUnidad ? p.unidadBase.nombre : null,
              ))
          .toList();
    });
    return salida;
  }

  /// Estimación de hojas A4: cabecera de categoría + una fila por producto,
  /// repartidas en columnas de [InventarioPdfService.filasPorColumna], dos por hoja.
  int _hojas(Map<String, List<ItemInventario>> porFamilia) {
    var filas = 0;
    porFamilia.forEach((_, items) => filas += items.length + 1);
    if (filas == 0) return 0;
    final columnas = (filas / InventarioPdfService.filasPorColumna).ceil();
    return (columnas / 2).ceil();
  }

  Future<void> _lanzar(
    Map<String, List<ItemInventario>> porFamilia, {
    required bool compartir,
  }) async {
    if (porFamilia.isEmpty || _generando) return;
    setState(() => _generando = true);
    try {
      if (compartir) {
        await InventarioPdfService.compartir(porFamilia: porFamilia);
      } else {
        await InventarioPdfService.imprimir(porFamilia: porFamilia);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hoja de inventario')),
      body: StreamBuilder<List<Producto>>(
        stream: widget.db.productos(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error al cargar productos: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final grupos = _agrupar(snap.data!);
          if (grupos.isEmpty) {
            return const Center(child: Text('Todavía no hay productos guardados'));
          }

          final categorias = grupos.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final porFamilia = _paraPdf(grupos);
          final total = porFamilia.values.fold<int>(0, (s, l) => s + l.length);
          final hojas = _hojas(porFamilia);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Marca las secciones que quieres imprimir. Cada producto sale '
                  'con tres casillas vacías: existencia, previsión y compra final.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Todas'),
                      onPressed: () => setState(_excluidas.clear),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.remove_done, size: 18),
                      label: const Text('Ninguna'),
                      onPressed: () =>
                          setState(() => _excluidas.addAll(categorias)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final c in categorias)
                      CheckboxListTile(
                        dense: true,
                        title: Text(c),
                        subtitle: Text(
                          '${grupos[c]!.length} producto'
                          '${grupos[c]!.length == 1 ? '' : 's'}',
                        ),
                        value: !_excluidas.contains(c),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _excluidas.remove(c);
                          } else {
                            _excluidas.add(c);
                          }
                        }),
                      ),
                    const Divider(),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Mostrar unidad junto al nombre'),
                      subtitle: const Text('kg · L · ud'),
                      value: _mostrarUnidad,
                      onChanged: (v) => setState(() => _mostrarUnidad = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        total == 0
                            ? 'Ninguna sección seleccionada'
                            : '$total productos · aprox. $hojas hoja'
                                '${hojas == 1 ? '' : 's'} A4',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Compartir'),
                              onPressed: total == 0 || _generando
                                  ? null
                                  : () => _lanzar(porFamilia, compartir: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              icon: _generando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.print_outlined),
                              label: const Text('Imprimir'),
                              onPressed: total == 0 || _generando
                                  ? null
                                  : () => _lanzar(porFamilia, compartir: false),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
