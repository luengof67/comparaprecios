import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/comparativa.dart';
import '../models/producto.dart';
import '../ui/formato.dart';

/// Una línea de la compra óptima: un producto asignado a su proveedor más barato.
class LineaOptima {
  final String producto;
  final double cantidad;
  final String unidad;
  final double precioUnitario;
  double get subtotal => cantidad * precioUnitario;

  LineaOptima({
    required this.producto,
    required this.cantidad,
    required this.unidad,
    required this.precioUnitario,
  });
}

class InformeCompraService {
  /// Genera y muestra (imprimir/guardar/compartir) el PDF de la compra óptima.
  /// Recibe las comparativas ya filtradas (en lista y con cantidad).
  static Future<void> generarPdf(List<ComparativaProducto> comparativas) async {
    // Agrupa por proveedor más barato.
    final porProveedor = <String, List<LineaOptima>>{};
    double totalOptimo = 0;
    double totalCaro = 0;

    for (final c in comparativas) {
      final cant = c.producto.cantidadEfectiva;
      if (cant <= 0 || !c.tieneDatos) continue;
      // Oferta más barata.
      final barata = c.ofertas.reduce(
          (a, b) => a.precioUnitario <= b.precioUnitario ? a : b);
      final linea = LineaOptima(
        producto: c.producto.nombre,
        cantidad: cant,
        unidad: c.producto.unidadBase.nombre,
        precioUnitario: barata.precioUnitario,
      );
      porProveedor.putIfAbsent(barata.proveedor.nombre, () => []).add(linea);
      totalOptimo += linea.subtotal;
      totalCaro += c.precioMax * cant;
    }

    final ahorro = totalCaro - totalOptimo;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Lista de compra óptima',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Generada el ${fecha(DateTime.now())}'),
          pw.SizedBox(height: 12),
          // Una sección por proveedor.
          ...porProveedor.entries.map((e) {
            final lineas = e.value;
            final subtotal =
                lineas.fold<double>(0, (s, l) => s + l.subtotal);
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 10),
                pw.Text(e.key,
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
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
                  headers: ['Producto', 'Cantidad', 'Precio', 'Subtotal'],
                  data: lineas
                      .map((l) => [
                            l.producto,
                            '${_n(l.cantidad)} ${l.unidad}',
                            '${euros3(l.precioUnitario)}/${l.unidad}',
                            euros(l.subtotal),
                          ])
                      .toList(),
                ),
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('Subtotal ${e.key}: ${euros(subtotal)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
              ],
            );
          }),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL compra: ${euros(totalOptimo)}',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text('Ahorro vs más caro: ${euros(ahorro)}',
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green800)),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static String _n(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}
