import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/compra.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/analitica_service.dart';
import '../services/firestore_service.dart';
import 'comparador_screen.dart';
import 'formato.dart';

class InformesScreen extends StatefulWidget {
  final FirestoreService db;
  const InformesScreen({super.key, required this.db});

  @override
  State<InformesScreen> createState() => _InformesScreenState();
}

class _InformesScreenState extends State<InformesScreen> {
  AgrupacionInforme _agrupacion = AgrupacionInforme.mes;

  String _etiquetaAgrupacion() => switch (_agrupacion) {
        AgrupacionInforme.mes => 'Por mes',
        AgrupacionInforme.semana => 'Por semana',
        AgrupacionInforme.evento => 'Por evento',
        AgrupacionInforme.proveedor => 'Por proveedor',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes'),
        actions: [
          IconButton(
            tooltip: 'Comparar proveedores',
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ComparadorScreen(db: widget.db)),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Compra>>(
        stream: widget.db.compras(),
        builder: (context, snapC) {
          return StreamBuilder<List<Producto>>(
            stream: widget.db.productos(),
            builder: (context, snapProd) {
              return StreamBuilder<List<Proveedor>>(
                stream: widget.db.proveedores(),
                builder: (context, snapProv) {
                  return StreamBuilder<List<Precio>>(
                    stream: widget.db.precios(),
                    builder: (context, snapPre) {
                      if (!snapC.hasData ||
                          !snapProd.hasData ||
                          !snapProv.hasData ||
                          !snapPre.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final compras = snapC.data!;
                      if (compras.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No hay compras registradas.\n'
                              'Registra compras y aquí verás el gasto y el ahorro.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }

                      final precioMax = AnaliticaService.precioMaxPorProducto(
                          snapProd.data!, snapPre.data!, snapProv.data!);
                      final grupos = AnaliticaService.informe(
                          compras, precioMax, _agrupacion);

                      final totalGastado =
                          grupos.fold<double>(0, (s, g) => s + g.gastado);
                      final totalAhorro =
                          grupos.fold<double>(0, (s, g) => s + g.ahorro);

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SegmentedButton<AgrupacionInforme>(
                              segments: const [
                                ButtonSegment(
                                    value: AgrupacionInforme.mes,
                                    label: Text('Mes')),
                                ButtonSegment(
                                    value: AgrupacionInforme.semana,
                                    label: Text('Semana')),
                                ButtonSegment(
                                    value: AgrupacionInforme.evento,
                                    label: Text('Evento')),
                                ButtonSegment(
                                    value: AgrupacionInforme.proveedor,
                                    label: Text('Prov.')),
                              ],
                              selected: {_agrupacion},
                              onSelectionChanged: (s) =>
                                  setState(() => _agrupacion = s.first),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _Metrica('Gastado', euros(totalGastado)),
                                    _Metrica('Ahorrado', euros(totalAhorro),
                                        color: Colors.green.shade800),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 8, 12, 90),
                              children: grupos
                                  .map((g) => _FilaGrupo(grupo: g))
                                  .toList(),
                            ),
                          ),
                        ],
                      );
                    },
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

  Future<void> _exportarPdf(BuildContext context) async {
    // Recoge los datos actuales una vez.
    final compras = await widget.db.compras().first;
    if (compras.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay compras para exportar.')),
        );
      }
      return;
    }
    final productos = await widget.db.productos().first;
    final proveedores = await widget.db.proveedores().first;
    final precios = await widget.db.precios().first;

    final precioMax = AnaliticaService.precioMaxPorProducto(
        productos, precios, proveedores);
    final grupos = AnaliticaService.informe(compras, precioMax, _agrupacion);
    final totalGastado = grupos.fold<double>(0, (s, g) => s + g.gastado);
    final totalAhorro = grupos.fold<double>(0, (s, g) => s + g.ahorro);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('Informe de compras · ${_etiquetaAgrupacion()}',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Generado el ${fecha(DateTime.now())}'),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            headers: ['Grupo', 'Compras', 'Gastado', 'Ahorrado'],
            data: grupos
                .map((g) => [
                      g.etiqueta,
                      g.nCompras.toString(),
                      euros(g.gastado),
                      euros(g.ahorro),
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL gastado: ${euros(totalGastado)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('TOTAL ahorrado: ${euros(totalAhorro)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }
}

class _Metrica extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color? color;
  const _Metrica(this.titulo, this.valor, {this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(titulo, style: const TextStyle(fontSize: 13)),
        Text(valor,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _FilaGrupo extends StatelessWidget {
  final GrupoInforme grupo;
  const _FilaGrupo({required this.grupo});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(grupo.etiqueta,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${grupo.nCompras} compras · ${grupo.nLineas} líneas · gastado ${euros(grupo.gastado)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(euros(grupo.ahorro),
                style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Text('${grupo.ahorroPorcentaje.toStringAsFixed(0)}% ahorro',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
