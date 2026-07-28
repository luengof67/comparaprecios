import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/comparativa.dart';
import '../models/producto.dart';
import '../ui/formato.dart';

/// Genera una hoja PDF imprimible con los productos marcados (enLista),
/// agrupados por categoría y en orden alfabético, con su formato y su último
/// mejor precio de orientación, y una casilla vacía para escribir la cantidad
/// a mano. Pensada para imprimir, rellenar en la cocina y (más adelante)
/// fotografiar.
class HojaPedidoService {
  static Future<void> generar(List<ComparativaProducto> comparativas) async {
    final fuente = await PdfGoogleFonts.robotoRegular();
    final fuenteBold = await PdfGoogleFonts.robotoBold();

    // Solo los productos marcados en la lista.
    final enLista = comparativas.where((c) => c.producto.enLista).toList();

    // Agrupar por categoría.
    final Map<String, List<ComparativaProducto>> porCategoria = {};
    for (final c in enLista) {
      porCategoria.putIfAbsent(c.producto.categoria, () => []).add(c);
    }
    // Ordenar categorías alfabéticamente y productos dentro de cada una.
    final categorias = porCategoria.keys.toList()..sort();
    for (final cat in categorias) {
      porCategoria[cat]!.sort((a, b) => a.producto.nombre
          .toLowerCase()
          .compareTo(b.producto.nombre.toLowerCase()));
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fuente, bold: fuenteBold),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) {
          final widgets = <pw.Widget>[];
          widgets.add(
            pw.Text('Hoja de pedido',
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          );
          widgets.add(pw.SizedBox(height: 2));
          widgets.add(
            pw.Text(
              'Generada el ${fecha(DateTime.now())} · '
              '${enLista.length} productos · precios de orientación',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          );
          widgets.add(pw.SizedBox(height: 12));

          for (final cat in categorias) {
            // Título de categoría.
            widgets.add(
              pw.Container(
                width: double.infinity,
                margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                color: PdfColors.grey200,
                child: pw.Text(cat.toUpperCase(),
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
            );
            // Tabla de productos de esta categoría.
            widgets.add(
              pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(5), // producto
                  1: const pw.FlexColumnWidth(2), // formato
                  2: const pw.FlexColumnWidth(2.4), // precio orient.
                  3: const pw.FlexColumnWidth(2.6), // cantidad (vacío)
                },
                children: [
                  // Cabecera de la tabla.
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _cel('Producto', bold: true),
                      _cel('Formato', bold: true),
                      _cel('Últ. precio', bold: true),
                      _cel('Cantidad', bold: true),
                    ],
                  ),
                  ...porCategoria[cat]!.map((c) {
                    final p = c.producto;
                    final barato = c.masBarato;
                    // Formato del mas barato; si no tiene, su unidad base.
                    final formato = (barato != null && barato.tieneFormato)
                        ? barato.formato!
                        : p.unidadBase.nombre;
                    final precio = barato != null
                        ? '${euros3(barato.precioUnitario)}/${p.unidadBase.nombre}'
                        : '—';
                    return pw.TableRow(
                      children: [
                        _cel(p.nombre),
                        _cel(formato),
                        _cel(precio),
                        _cel(''), // casilla vacía para la cantidad
                      ],
                    );
                  }),
                ],
              ),
            );
          }

          if (enLista.isEmpty) {
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Text(
                  'No hay productos marcados en la lista. Marca productos '
                  '(en la pestaña Lista) y vuelve a generar la hoja.',
                  style: const pw.TextStyle(color: PdfColors.grey700),
                ),
              ),
            );
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static pw.Widget _cel(String texto, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 5),
        child: pw.Text(texto,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
}
