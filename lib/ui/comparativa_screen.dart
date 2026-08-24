import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/comparativa_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Listado de TODOS los productos con el precio de cada proveedor, el mas
/// barato resaltado y el ahorro que supone. Misma tabla en pantalla y en PDF:
/// las dos salidas leen de ComparativaService, asi que no pueden desviarse.
class ComparativaScreen extends StatefulWidget {
  final FirestoreService db;
  const ComparativaScreen({super.key, required this.db});

  @override
  State<ComparativaScreen> createState() => _ComparativaScreenState();
}

class _ComparativaScreenState extends State<ComparativaScreen> {
  final _buscador = TextEditingController();
  String _busqueda = '';
  String _categoria = '';
  int _dias = ComparativaService.diasVigenciaPorDefecto;

  /// Cuando esta activo solo se ven los productos donde hay algo que ganar.
  bool _soloConAhorro = false;

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparativa de precios'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Antigüedad máxima',
            icon: const Icon(Icons.history),
            initialValue: _dias,
            onSelected: (v) => setState(() => _dias = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 30, child: Text('Últimos 30 días')),
              PopupMenuItem(value: 60, child: Text('Últimos 60 días')),
              PopupMenuItem(value: 90, child: Text('Últimos 90 días')),
              PopupMenuItem(value: 3650, child: Text('Sin límite')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Producto>>(
        stream: widget.db.productos(),
        builder: (context, snapProd) {
          return StreamBuilder<List<Proveedor>>(
            stream: widget.db.proveedores(),
            builder: (context, snapProv) {
              return StreamBuilder<List<Precio>>(
                stream: widget.db.precios(),
                builder: (context, snapPre) {
                  if (!snapProd.hasData ||
                      !snapProv.hasData ||
                      !snapPre.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final productos = snapProd.data!;
                  final proveedores = snapProv.data!;
                  final precios = snapPre.data!;

                  if (precios.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Todavía no hay precios registrados.\n'
                          'Importa albaranes o anota precios y aquí verás '
                          'qué proveedor sale mejor en cada producto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  final categorias = ComparativaService.categoriasConPrecio(
                      productos, precios);

                  final c = ComparativaService.construir(
                    productos: productos,
                    proveedores: proveedores,
                    precios: precios,
                    diasVigencia: _dias,
                    categoria: _categoria.isEmpty ? null : _categoria,
                    busqueda: _busqueda,
                  );

                  return Column(
                    children: [
                      _filtros(categorias),
                      _resumen(c),
                      Expanded(child: _lista(c)),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _exportarPdf(context),
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('PDF'),
      ),
    );
  }

  Widget _filtros(List<String> categorias) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          TextField(
            controller: _buscador,
            decoration: InputDecoration(
              hintText: 'Buscar producto…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscador.clear();
                        setState(() => _busqueda = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _busqueda = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Categoría',
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todas')),
                    for (final c in categorias)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _categoria = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Con ahorro'),
                selected: _soloConAhorro,
                onSelected: (v) => setState(() => _soloConAhorro = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resumen(Comparativa c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metrica('Comparados', '${c.productosComparados}'),
                  _metrica('Ahorro/semana', euros(c.ahorroSemanal),
                      color: Colors.green.shade800),
                  _metrica('Sin comparar', '${c.sinComparar.length}'),
                ],
              ),
              if (c.sinCantidad > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${c.sinCantidad} productos salen más baratos en un '
                        'proveedor pero no tienen cantidad habitual puesta: '
                        'su ahorro no está contado aquí.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metrica(String titulo, String valor, {Color? color}) {
    return Column(
      children: [
        Text(titulo, style: const TextStyle(fontSize: 12)),
        Text(valor,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _lista(Comparativa c) {
    final hijos = <Widget>[];

    for (final g in c.grupos) {
      final filas = _soloConAhorro
          ? g.filas.where((f) => f.diferencia > 0.001).toList()
          : g.filas;
      if (filas.isEmpty) continue;

      hijos.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(
          children: [
            Text(g.categoria,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            if (g.ahorroSemanal > 0.005)
              Text('ahorro ${euros(g.ahorroSemanal)}/sem',
                  style: TextStyle(
                      fontSize: 12, color: Colors.green.shade800)),
          ],
        ),
      ));
      for (final f in filas) {
        hijos.add(_FilaProducto(fila: f));
      }
    }

    if (hijos.isEmpty) {
      hijos.add(const Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Ningún producto tiene dos proveedores con precio reciente.\n'
          'Amplía la antigüedad desde el icono del reloj.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ));
    }

    if (c.sinComparar.isNotEmpty) {
      hijos.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 6),
        child: Text('Un solo proveedor (${c.sinComparar.length})',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.grey.shade700)),
      ));
      for (final f in c.sinComparar) {
        hijos.add(_FilaProducto(fila: f));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
      children: hijos,
    );
  }

  Future<void> _exportarPdf(BuildContext context) async {
    final productos = await widget.db.productos().first;
    final proveedores = await widget.db.proveedores().first;
    final precios = await widget.db.precios().first;

    final c = ComparativaService.construir(
      productos: productos,
      proveedores: proveedores,
      precios: precios,
      diasVigencia: _dias,
      categoria: _categoria.isEmpty ? null : _categoria,
      busqueda: _busqueda,
    );

    if (c.productosComparados == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No hay productos que comparar con estos filtros.')));
      }
      return;
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          final w = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text('Comparativa de precios por producto',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text('Generado el ${fecha(c.generado)} · '
                'precios de los últimos ${c.diasVigencia} días'
                '${_categoria.isEmpty ? "" : " · $_categoria"}'),
            pw.SizedBox(height: 4),
            pw.Text(
              '${c.productosComparados} productos con dos o más proveedores. '
              'Ahorro estimado comprando siempre al más barato: '
              '${euros(c.ahorroSemanal)} por semana.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
          ];

          for (final g in c.grupos) {
            final filas = _soloConAhorro
                ? g.filas.where((f) => f.diferencia > 0.001).toList()
                : g.filas;
            if (filas.isEmpty) continue;

            w.add(pw.SizedBox(height: 10));
            w.add(pw.Text(g.categoria,
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)));
            w.add(pw.SizedBox(height: 4));
            w.add(pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2.4),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(2.4),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FlexColumnWidth(1.5),
              },
              headers: [
                'Producto',
                'Más barato',
                'Precio',
                'Siguiente',
                'Dif.',
                'Ahorro/sem'
              ],
              data: filas.map((f) {
                final b = f.masBarato;
                final s = f.segundo;
                final u = f.producto.unidadBase.etiqueta;
                return [
                  f.producto.nombre,
                  b?.proveedorNombre ?? '-',
                  b == null ? '-' : '${b.precioUnitario.toStringAsFixed(2)} $u',
                  s?.proveedorNombre ?? '-',
                  f.diferenciaPorcentaje <= 0
                      ? '-'
                      : '-${f.diferenciaPorcentaje.toStringAsFixed(0)}%',
                  f.ahorroSemanal <= 0.005 ? '-' : euros(f.ahorroSemanal),
                ];
              }).toList(),
            ));
          }

          if (c.sinComparar.isNotEmpty) {
            w.add(pw.SizedBox(height: 16));
            w.add(pw.Text('Con un solo proveedor',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)));
            w.add(pw.SizedBox(height: 4));
            w.add(pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              headers: ['Producto', 'Proveedor', 'Precio', 'Días'],
              data: c.sinComparar.map((f) {
                final b = f.celdas.isEmpty ? null : f.celdas.first;
                final u = f.producto.unidadBase.etiqueta;
                return [
                  f.producto.nombre,
                  b?.proveedorNombre ?? '-',
                  b == null ? '-' : '${b.precioUnitario.toStringAsFixed(2)} $u',
                  b == null ? '-' : '${b.dias}',
                ];
              }).toList(),
            ));
          }

          return w;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }
}

/// Un producto con todos sus proveedores desplegados debajo.
class _FilaProducto extends StatelessWidget {
  final FilaComparativa fila;
  const _FilaProducto({required this.fila});

  @override
  Widget build(BuildContext context) {
    final base = fila.producto.unidadBase;
    final barato = fila.masBarato;
    final hayAhorro = fila.diferencia > 0.001;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(fila.producto.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          barato == null
              ? 'sin precio vigente'
              : '${barato.proveedorNombre} · '
                  '${fila.celdas.length} proveedor'
                  '${fila.celdas.length == 1 ? "" : "es"}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              barato == null
                  ? '—'
                  : '${barato.precioUnitario.toStringAsFixed(2)} ${base.etiqueta}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if (hayAhorro)
              Text(
                fila.ahorroSemanal > 0.005
                    ? '-${fila.diferenciaPorcentaje.toStringAsFixed(0)}% · '
                        '${euros(fila.ahorroSemanal)}/sem'
                    : '-${fila.diferenciaPorcentaje.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: Colors.green.shade800),
              ),
          ],
        ),
        children: [
          for (final c in fila.celdas) _celda(context, c, base, c == barato),
        ],
      ),
    );
  }

  Widget _celda(BuildContext context, CeldaComparativa c, UnidadBase base,
      bool esMejor) {
    final detalle = c.descripcionFormato(base);
    return ListTile(
      dense: true,
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Color(c.proveedorColor),
          shape: BoxShape.circle,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              c.proveedorNombre,
              style: TextStyle(
                fontSize: 13,
                fontWeight: esMejor ? FontWeight.bold : FontWeight.normal,
                color: c.obsoleto ? Colors.grey : null,
              ),
            ),
          ),
          if (esMejor)
            Icon(Icons.star, size: 14, color: Colors.green.shade700),
        ],
      ),
      subtitle: Text(
        [
          '${fecha(c.fecha)} · hace ${c.dias} días',
          if (c.obsoleto) 'fuera de plazo, no compite',
          if (detalle.isNotEmpty) detalle,
        ].join(' · '),
        style: TextStyle(
            fontSize: 11, color: c.obsoleto ? Colors.grey : Colors.black54),
      ),
      trailing: Text(
        '${c.precioUnitario.toStringAsFixed(2)} ${base.etiqueta}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: esMejor ? FontWeight.bold : FontWeight.normal,
          color: c.obsoleto
              ? Colors.grey
              : (esMejor ? Colors.green.shade800 : null),
        ),
      ),
    );
  }
}
