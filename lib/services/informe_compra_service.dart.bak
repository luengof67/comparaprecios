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
  final String? formato; // "caja", "saco"... si se pide por formato
  final bool enFormato; // true = la cantidad son cajas (coste por confirmar)
  final bool sinPrecio; // true = producto sin precio (va con guion)

  /// Subtotal solo si se pide en unidad base y tiene precio.
  double get subtotal => (enFormato || sinPrecio) ? 0 : cantidad * precioUnitario;
  bool get tieneCoste => !enFormato && !sinPrecio;

  LineaOptima({
    required this.producto,
    required this.cantidad,
    required this.unidad,
    required this.precioUnitario,
    this.formato,
    this.enFormato = false,
    this.sinPrecio = false,
  });

  /// Texto de lo que hay que pedir: "2 cajas" o "12 kg".
  String get pedido {
    if (enFormato && formato != null) {
      return '${_n(cantidad)} $formato${cantidad == 1 ? "" : "s"}';
    }
    return '${_n(cantidad)} $unidad';
  }

  /// Texto del precio unitario: guion si no tiene precio.
  String get textoPrecio =>
      sinPrecio ? '—' : '${euros3(precioUnitario)}/$unidad';

  String get textoSubtotal =>
      sinPrecio ? '—' : (enFormato ? 's/albarán' : euros(subtotal));

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}

class InformeCompraService {
  /// Genera y muestra (imprimir/guardar/compartir) el PDF de la compra óptima.
  /// Recibe las comparativas ya filtradas (en lista y con cantidad).
  static Future<void> generarPdf(List<ComparativaProducto> comparativas) async {
    // Fuentes con soporte del símbolo del euro (€).
    final fuenteNormal = await PdfGoogleFonts.robotoRegular();
    final fuenteNegrita = await PdfGoogleFonts.robotoBold();

    // Nombres de proveedores (para los asignados a mano sin precio).
    final nombreProv = <String, String>{};
    for (final c in comparativas) {
      for (final o in c.ofertas) {
        nombreProv[o.proveedor.id] = o.proveedor.nombre;
      }
    }

    // Agrupa por proveedor. Clave especial 'SIN' = sin proveedor asignado.
    final porProveedor = <String, List<LineaOptima>>{};
    double totalOptimo = 0;
    double totalCaro = 0;

    for (final c in comparativas) {
      final cant = c.producto.cantidadEfectiva;
      if (cant <= 0) continue;

      if (c.tieneDatos) {
        // CON precio: al proveedor más barato.
        final barata = c.ofertaEfectiva!;
        final enFormato = c.producto.pedirEnFormato && barata.tieneFormato;
        final linea = LineaOptima(
          producto: c.producto.nombre,
          cantidad: cant,
          unidad: c.producto.unidadBase.nombre,
          precioUnitario: barata.precioUnitario,
          formato: barata.tieneFormato ? barata.formato : null,
          enFormato: enFormato,
        );
        porProveedor.putIfAbsent(barata.proveedor.nombre, () => []).add(linea);
        if (linea.tieneCoste) {
          totalOptimo += linea.subtotal;
          totalCaro += c.precioMax * cant;
        }
      } else {
        // SIN precio: al proveedor asignado, o al bloque 'Sin asignar'.
        final asignado = c.producto.proveedorAsignadoId;
        final clave = (asignado.isNotEmpty && nombreProv.containsKey(asignado))
            ? nombreProv[asignado]!
            : 'Sin proveedor asignado';
        final enFormato =
            c.producto.pedirEnFormato && c.producto.formatoSemana.isNotEmpty;
        final linea = LineaOptima(
          producto: c.producto.nombre,
          cantidad: cant,
          unidad: c.producto.unidadBase.nombre,
          precioUnitario: 0,
          formato: enFormato ? c.producto.formatoSemana : null,
          enFormato: enFormato,
          sinPrecio: true,
        );
        porProveedor.putIfAbsent(clave, () => []).add(linea);
      }
    }

    // Ordenar: proveedores con nombre primero, 'Sin proveedor asignado' al final.
    final claves = porProveedor.keys.toList()
      ..sort((a, b) {
        if (a == 'Sin proveedor asignado') return 1;
        if (b == 'Sin proveedor asignado') return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final ahorro = totalCaro - totalOptimo;

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fuenteNormal,
        bold: fuenteNegrita,
      ),
    );

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
          pw.SizedBox(height: 4),
          pw.Text(
            'Los importes de productos que se piden por caja/saco son estimados '
            '(el peso real se ajusta al recibir el albarán). El guion (—) indica '
            'un producto sin precio registrado todavía.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          // Una sección por proveedor.
          ...claves.map((clave) {
            final lineas = porProveedor[clave]!;
            final subtotal =
                lineas.fold<double>(0, (s, l) => s + l.subtotal);
            final hayCajas = lineas.any((l) => l.enFormato);
            final haySinPrecio = lineas.any((l) => l.sinPrecio);
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 10),
                pw.Text(clave,
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
                  headers: ['Producto', 'Pedir', 'Precio', 'Subtotal'],
                  data: lineas
                      .map((l) => [
                            l.producto,
                            l.pedido,
                            l.textoPrecio,
                            l.textoSubtotal,
                          ])
                      .toList(),
                ),
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                      'Subtotal $clave: ${euros(subtotal)}'
                      '${hayCajas ? " (+ lo que se pide por caja)" : ""}'
                      '${haySinPrecio ? " (+ productos sin precio)" : ""}',
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
