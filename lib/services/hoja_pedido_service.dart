import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/comparativa.dart';
import '../models/producto.dart';
import '../ui/formato.dart';
import 'estilo_pdf.dart';
import 'fuentes_pdf.dart';

/// Genera la HOJA DE PEDIDO imprimible: solo los productos con cantidad puesta
/// (el pedido real), agrupados por el proveedor más barato de cada uno, con la
/// cantidad tal cual (kg o cajas según lo pedido) y su precio de orientación.
/// Es una copia en papel del pedido que ya montaste en la app.
class HojaPedidoService {
  static Future<void> generar(List<ComparativaProducto> comparativas) async {

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

    final doc = await FuentesPdf.documento();

    doc.addPage(
      EstiloPdf.paginas(
        build: (ctx) {
          final widgets = <pw.Widget>[
            EstiloPdf.cabecera(
              'Hoja de pedido',
              derecha: fecha(DateTime.now()),
              subtitulo: '${pedido.length} producto${pedido.length == 1 ? "" : "s"}'
                  ' · ${provIds.length} proveedor${provIds.length == 1 ? "" : "es"}',
            ),
          ];

          if (pedido.isEmpty) {
            widgets.add(EstiloPdf.vacio(
              'No hay productos con cantidad en el pedido. Monta la lista '
              '(pon cantidades) y vuelve a generar la hoja.',
            ));
            return widgets;
          }

          for (final pid in provIds) {
            final nombre = pid == 'SIN'
                ? 'Sin proveedor asignado'
                : (nombreProv[pid] ?? 'Proveedor');
            final lineas = porProveedor[pid]!;
            widgets.add(EstiloPdf.seccion(
              nombre,
              derecha: '${lineas.length} producto${lineas.length == 1 ? "" : "s"}',
              colorDerecha: EstiloPdf.gris,
            ));
            widgets.add(_rotulos());
            for (final c in lineas) {
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
              widgets.add(_fila(p.nombre, pedirTxt, precio));
            }
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  static const double _anchoPedir = 80;
  static const double _anchoPrecio = 90;

  static pw.Widget _rotulos() {
    final estilo = pw.TextStyle(
      fontSize: 6.5,
      fontWeight: pw.FontWeight.bold,
      color: EstiloPdf.gris,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.SizedBox()),
          pw.SizedBox(
            width: _anchoPedir,
            child: pw.Text('PEDIR', style: estilo, textAlign: pw.TextAlign.right),
          ),
          pw.SizedBox(
            width: _anchoPrecio,
            child: pw.Text('ÚLT. PRECIO',
                style: estilo, textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }

  static pw.Widget _fila(String producto, String pedir, String precio) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            EstiloPdf.conPuntos(
              pw.Text(producto,
                  style: const pw.TextStyle(
                      fontSize: 10, color: EstiloPdf.tinta)),
            ),
            pw.SizedBox(
              width: _anchoPedir,
              child: pw.Text(
                pedir,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: EstiloPdf.tinta,
                ),
              ),
            ),
            pw.SizedBox(
              width: _anchoPrecio,
              child: pw.Text(
                precio,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 8.5, color: EstiloPdf.gris),
              ),
            ),
          ],
        ),
      );
}
