import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/comparativa.dart';
import '../models/producto.dart';
import '../ui/formato.dart';

/// Genera la HOJA DE PEDIDO imprimible: solo los productos con cantidad puesta
/// (el pedido real), agrupados por el proveedor más barato de cada uno, con la
/// cantidad tal cual (kg o cajas según lo pedido) y su precio de orientación.
/// Es una copia en papel del pedido que ya montaste en la app.
class HojaPedidoService {
  static Future<void> generar(List<ComparativaProducto> comparativas) async {
    final fuente = await PdfGoogleFonts.robotoRegular();
    final fuenteBold = await PdfGoogleFonts.robotoBold();

    // Productos en lista Y con cantidad puesta (tengan o no precio).
    final pedido = comparativas.where((c) {
      final p = c.producto;
      return p.enLista && p.cantidadEfectiva > 0;
    }).toList();

    // Necesitamos los nombres de proveedores para los asignados a mano.
    final Map<String, String> nombreProv = {};
    for (final c in comparativas) {
      for (final o in c.ofertas) {
        nombreProv[o.proveedor.id] = o.proveedor.nombre;
      }
    }

    // Agrupar: con precio -> proveedor mas barato; sin precio -> asignado.
    // Clave especial 'SIN' para los que no tienen ni precio ni asignado.
    final Map<String, List<ComparativaProducto>> porProveedor = {};
    for (final c in pedido) {
      String pid;
      if (c.tieneDatos) {
        pid = c.masBarato!.proveedor.id;
        nombreProv[pid] = c.masBarato!.proveedor.nombre;
      } else if (c.producto.proveedorAsignadoId.isNotEmpty) {
        pid = c.producto.proveedorAsignadoId;
      } else {
        pid = 'SIN';
      }
      porProveedor.putIfAbsent(pid, () => []).add(c);
    }
    // Ordenar proveedores por nombre y productos dentro por nombre.
    final provIds = porProveedor.keys.toList()
      ..sort((a, b) {
        if (a == 'SIN') return 1;
        if (b == 'SIN') return -1;
        return (nombreProv[a] ?? '')
            .toLowerCase()
            .compareTo((nombreProv[b] ?? '').toLowerCase());
      });
    for (final id in provIds) {
      porProveedor[id]!.sort((a, b) => a.producto.nombre
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
              '${pedido.length} productos',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          );
          widgets.add(pw.SizedBox(height: 12));

          if (pedido.isEmpty) {
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Text(
                  'No hay productos con cantidad en el pedido. Monta la lista '
                  '(pon cantidades) y vuelve a generar la hoja.',
                  style: const pw.TextStyle(color: PdfColors.grey700),
                ),
              ),
            );
            return widgets;
          }

          for (final pid in provIds) {
            final nombre = pid == 'SIN'
                ? 'Sin proveedor asignado'
                : (nombreProv[pid] ?? 'Proveedor');
            // Cabecera del proveedor.
            widgets.add(
              pw.Container(
                width: double.infinity,
                margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                color: PdfColors.grey200,
                child: pw.Text(nombre.toUpperCase(),
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
              ),
            );
            // Tabla de productos de este proveedor.
            widgets.add(
              pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(6), // producto
                  1: const pw.FlexColumnWidth(3), // cantidad a pedir
                  2: const pw.FlexColumnWidth(3), // precio orient.
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      _cel('Producto', bold: true),
                      _cel('Pedir', bold: true),
                      _cel('Últ. precio', bold: true),
                    ],
                  ),
                  ...porProveedor[pid]!.map((c) {
                    final p = c.producto;
                    final cant = p.cantidadEfectiva;
                    // Texto de cantidad: cajas o unidad base.
                    final String pedirTxt;
                    if (p.pedirEnFormato && p.formatoSemana.isNotEmpty) {
                      final f = p.formatoSemana;
                      pedirTxt = '${_n(cant)} $f${cant == 1 ? "" : "s"}';
                    } else {
                      pedirTxt = '${_n(cant)} ${p.unidadBase.nombre}';
                    }
                    // Precio de orientacion, o guion si aun no tiene.
                    final precio = c.tieneDatos
                        ? '${euros3(c.masBarato!.precioUnitario)}/${p.unidadBase.nombre}'
                        : '—';
                    return pw.TableRow(
                      children: [
                        _cel(p.nombre),
                        _cel(pedirTxt),
                        _cel(precio),
                      ],
                    );
                  }),
                ],
              ),
            );
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  static pw.Widget _cel(String texto, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 5),
        child: pw.Text(texto,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
}
