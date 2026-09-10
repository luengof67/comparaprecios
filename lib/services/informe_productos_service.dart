import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../ui/formato.dart';
import 'fuentes_pdf.dart';

/// Lo que se compro de un producto en el mes: cantidad total y gasto total.
class _Linea {
  final String productoId;
  final String nombre;
  final String unidad;
  final String categoria;
  double cantidad = 0;
  double gasto = 0;
  int veces = 0;

  _Linea({
    required this.productoId,
    required this.nombre,
    required this.unidad,
    required this.categoria,
  });
}

/// Informe de productos comprados en un mes.
///
/// Solo lo que se compro de verdad: sale de las compras, no de los precios de
/// tarifa. Cada producto una vez, con su cantidad y su gasto sumados, por
/// categoria y ordenado por donde se va el dinero.
class InformeProductosService {
  static Future<void> generarPdf({
    required DateTime mes,
    required List<Compra> compras,
    required List<Producto> productos,
  }) async {
    final delMes = compras
        .where((c) => c.fecha.year == mes.year && c.fecha.month == mes.month)
        .toList();

    final catPorId = {for (final p in productos) p.id: p.categoria};
    final unidadPorId = {
      for (final p in productos) p.id: p.unidadBase.nombre,
    };

    // Sumar por producto.
    final porProducto = <String, _Linea>{};
    for (final c in delMes) {
      for (final l in c.lineas) {
        final key = l.productoId.isNotEmpty ? l.productoId : l.productoNombre;
        final linea = porProducto.putIfAbsent(
          key,
          () => _Linea(
            productoId: l.productoId,
            nombre: l.productoNombre,
            unidad: unidadPorId[l.productoId] ?? l.unidad,
            categoria: catPorId[l.productoId] ?? 'Sin categoría',
          ),
        );
        linea.cantidad += l.cantidad;
        linea.gasto += l.total;
        linea.veces++;
      }
    }

    // Agrupar por categoria y ordenar por gasto, en los dos niveles.
    final porCategoria = <String, List<_Linea>>{};
    for (final l in porProducto.values) {
      porCategoria.putIfAbsent(l.categoria, () => []).add(l);
    }
    final categorias = porCategoria.entries.toList()
      ..sort((a, b) => _suma(b.value).compareTo(_suma(a.value)));
    for (final e in categorias) {
      e.value.sort((a, b) => b.gasto.compareTo(a.gasto));
    }

    final totalGasto = porProducto.values.fold<double>(0, (s, l) => s + l.gasto);
    final nombreMes = DateFormat('MMMM yyyy', 'es_ES').format(mes);

    final doc = await FuentesPdf.documento();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          final w = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text('Productos comprados · $nombreMes',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text('Generado el ${fecha(DateTime.now())}'),
            pw.SizedBox(height: 4),
            pw.Text(
              '${porProducto.length} productos distintos en '
              '${delMes.length} compras · ${euros(totalGasto)} en total',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
          ];

          if (porProducto.isEmpty) {
            w.add(pw.Text('No hay compras registradas en este mes.'));
            return w;
          }

          for (final e in categorias) {
            final sub = _suma(e.value);
            final pct = totalGasto > 0 ? sub / totalGasto * 100 : 0;

            w.add(pw.SizedBox(height: 10));
            w.add(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(e.key,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text('${euros(sub)} · ${pct.toStringAsFixed(0)}%',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ));
            w.add(pw.SizedBox(height: 4));
            w.add(pw.TableHelper.fromTextArray(
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(5),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
              },
              headers: ['Producto', 'Cantidad', 'Gasto'],
              data: e.value
                  .map((l) => [
                        l.nombre,
                        '${_num(l.cantidad)} ${l.unidad}',
                        euros(l.gasto),
                      ])
                  .toList(),
            ));
          }

          w.add(pw.SizedBox(height: 16));
          w.add(pw.Divider());
          w.add(pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('TOTAL ${euros(totalGasto)}',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ],
          ));

          return w;
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'productos_${mes.year}-${mes.month.toString().padLeft(2, '0')}.pdf',
      onLayout: (format) async => doc.save(),
    );
  }

  static double _suma(List<_Linea> l) => l.fold(0, (s, x) => s + x.gasto);

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
