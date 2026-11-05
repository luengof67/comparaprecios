import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/comparativa.dart';
import '../models/producto.dart';
import '../ui/formato.dart';
import 'estilo_pdf.dart';
import 'fuentes_pdf.dart';

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

    final doc = await FuentesPdf.documento();

    doc.addPage(
      EstiloPdf.paginas(
        build: (context) => [
          EstiloPdf.cabecera(
            'Lista de compra óptima',
            derecha: fecha(DateTime.now()),
            subtitulo: '${claves.length} proveedor${claves.length == 1 ? "" : "es"}'
                ' · ${euros(totalOptimo)} estimados',
          ),
          EstiloPdf.nota(
            'Los importes de productos que se piden por caja/saco son estimados '
            '(el peso real se ajusta al recibir el albarán). El guion (—) indica '
            'un producto sin precio registrado todavía.',
            arriba: 0,
          ),
          if (claves.isEmpty)
            EstiloPdf.vacio('No hay productos con cantidad en la lista.'),
          // Una sección por proveedor.
          for (final clave in claves) ...() {
            final lineas = porProveedor[clave]!;
            final subtotal = lineas.fold<double>(0, (s, l) => s + l.subtotal);
            final hayCajas = lineas.any((l) => l.enFormato);
            final haySinPrecio = lineas.any((l) => l.sinPrecio);
            return <pw.Widget>[
              EstiloPdf.seccion(clave, derecha: euros(subtotal)),
              EstiloPdf.tabla(
                cabeceras: ['Producto', 'Pedir', 'Precio', 'Subtotal'],
                anchos: [5, 2, 2, 2],
                filas: lineas
                    .map((l) => [
                          l.producto,
                          l.pedido,
                          l.textoPrecio,
                          l.textoSubtotal,
                        ])
                    .toList(),
              ),
              if (hayCajas || haySinPrecio)
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: EstiloPdf.nota(
                    '${hayCajas ? "+ lo que se pide por caja" : ""}'
                    '${hayCajas && haySinPrecio ? " · " : ""}'
                    '${haySinPrecio ? "+ productos sin precio" : ""}',
                  ),
                ),
            ];
          }(),
          EstiloPdf.total(
            'Total compra',
            euros(totalOptimo),
            nota: 'Ahorro frente al más caro: ${euros(ahorro)}',
            colorNota: EstiloPdf.verde,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static String _n(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
}
