import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../ui/formato.dart';
import 'fuentes_pdf.dart';

/// Una compra concreta de un producto, con la variacion respecto a la compra
/// INMEDIATAMENTE ANTERIOR de ese mismo producto. No es una media mensual:
/// cada fecha es una fila, para que una subida el 18 de agosto se vea aunque
/// el 10 de agosto ya hubiera otra compra ese mismo mes.
///
/// En el historial de UN proveedor, la secuencia es solo la suya. En el
/// historial GENERAL de un producto, la secuencia mezcla todos los
/// proveedores por fecha: lo que importa es el precio real que se pago cada
/// vez, sea quien sea quien lo sirvio.
class CompraDeProducto {
  final DateTime fecha;
  final double cantidad;
  final double precioUnitario;
  final String? numeroAlbaran;

  /// Solo se usa en el historial general (varios proveedores mezclados). En
  /// el historial de un proveedor concreto es siempre el mismo y no hace
  /// falta mostrarlo.
  final String proveedorNombre;
  final int proveedorColor;

  /// null en la primera compra registrada: no hay con que comparar.
  final double? variacion;

  /// La compra de origen y la posicion de esta linea dentro de ella. Hace
  /// falta para poder editar o quitar la linea desde donde se esta mirando,
  /// en vez de obligar a ir a otra pantalla a corregir un dato que se acaba
  /// de detectar aqui mismo.
  final Compra compraOrigen;
  final int indiceEnCompra;
  final String productoId;

  const CompraDeProducto({
    required this.fecha,
    required this.cantidad,
    required this.precioUnitario,
    required this.numeroAlbaran,
    required this.proveedorNombre,
    required this.proveedorColor,
    required this.variacion,
    required this.compraOrigen,
    required this.indiceEnCompra,
    required this.productoId,
  });

  bool get sube => variacion != null && variacion! > 0.005;
  bool get baja => variacion != null && variacion! < -0.005;
}

/// Un producto con TODAS sus compras en orden de fecha.
class HistoricoProducto {
  final Producto producto;
  final List<CompraDeProducto> compras;

  const HistoricoProducto({required this.producto, required this.compras});

  /// La primera compra frente a la ultima: la deriva total, no solo el
  /// ultimo salto.
  double? get variacionTotal {
    if (compras.length < 2) return null;
    final primero = compras.first.precioUnitario;
    final ultimo = compras.last.precioUnitario;
    if (primero <= 0) return null;
    return (ultimo - primero) / primero;
  }

  /// Alguna compra individual se disparo frente a la anterior.
  bool get tieneAlgunaSubida => compras.any((c) => c.sube);

  /// Mas de un proveedor ha servido este producto en el periodo mostrado.
  bool get variosProveedores =>
      compras.map((c) => c.proveedorNombre).toSet().length > 1;

  double get gastoTotal =>
      compras.fold(0, (s, c) => s + c.cantidad * c.precioUnitario);
}

class HistorialComprasService {
  static String? _numeroAlbaran(Compra c) {
    final k = c.origenClave;
    if (k == null || k.isEmpty) return null;
    final t = k.split('|');
    if (t.length < 2) return null;
    final n = t[1].trim();
    return n.isEmpty ? null : n;
  }

  /// Arma la secuencia de compras de una lista de lineas ya filtradas
  /// (mismo producto), calculando la variacion de cada una frente a la
  /// anterior. Comun a los dos modos de abajo.
  static HistoricoProducto _secuencia(
    String productoClave,
    Producto producto,
    List<(Compra, int, String?, String, int)> lineas,
  ) {
    lineas.sort((a, b) => a.$1.fecha.compareTo(b.$1.fecha));
    final compras = <CompraDeProducto>[];
    double? anterior;
    for (final (compra, indice, numero, provNombre, provColor) in lineas) {
      final linea = compra.lineas[indice];
      final variacion = anterior == null || anterior <= 0
          ? null
          : (linea.precioUnitario - anterior) / anterior;
      compras.add(CompraDeProducto(
        fecha: compra.fecha,
        cantidad: linea.cantidad,
        precioUnitario: linea.precioUnitario,
        numeroAlbaran: numero,
        proveedorNombre: provNombre,
        proveedorColor: provColor,
        variacion: variacion,
        compraOrigen: compra,
        indiceEnCompra: indice,
        productoId: productoClave,
      ));
      anterior = linea.precioUnitario;
    }
    return HistoricoProducto(producto: producto, compras: compras);
  }

  /// Todo lo comprado a [proveedor], organizado por producto. La secuencia de
  /// cada producto es solo la de ese proveedor.
  static List<HistoricoProducto> porProveedor({
    required Proveedor proveedor,
    required List<Compra> compras,
    required List<Producto> productos,
  }) {
    final prodPorId = {for (final p in productos) p.id: p};

    final porProducto = <String, List<(Compra, int, String?, String, int)>>{};
    for (final c in compras) {
      if (c.proveedorId != proveedor.id) continue;
      final numero = _numeroAlbaran(c);
      for (var i = 0; i < c.lineas.length; i++) {
        final l = c.lineas[i];
        if (l.precioUnitario <= 0) continue;
        final clave = l.productoId.isNotEmpty ? l.productoId : l.productoNombre;
        porProducto
            .putIfAbsent(clave, () => [])
            .add((c, i, numero, proveedor.nombre, proveedor.color));
      }
    }

    final salida = <HistoricoProducto>[];
    for (final entry in porProducto.entries) {
      final primeraLinea = entry.value.first.$1.lineas[entry.value.first.$2];
      final producto = prodPorId[entry.key] ??
          Producto(id: entry.key, nombre: primeraLinea.productoNombre);
      salida.add(_secuencia(entry.key, producto, entry.value));
    }
    return _ordenar(salida);
  }

  /// El historial GENERAL de los productos cuya clave (id, o nombre si el
  /// producto no tiene id) este en [claves]. Mezcla TODOS los proveedores por
  /// fecha: la variacion de cada compra es frente a la anterior de ese
  /// producto sea quien sea quien lo sirviera, porque lo que se quiere ver es
  /// la evolucion real del precio pagado, no la de un proveedor suelto.
  static List<HistoricoProducto> deProductos({
    required Set<String> claves,
    required List<Compra> compras,
    required List<Producto> productos,
    required List<Proveedor> proveedores,
  }) {
    final prodPorId = {for (final p in productos) p.id: p};
    final provPorId = {for (final p in proveedores) p.id: p};

    final porProducto = <String, List<(Compra, int, String?, String, int)>>{};
    for (final c in compras) {
      final numero = _numeroAlbaran(c);
      final prov = provPorId[c.proveedorId];
      final provNombre = prov?.nombre ??
          (c.proveedorNombre.isEmpty ? 'Sin proveedor' : c.proveedorNombre);
      final provColor = prov?.color ?? 0xFF9E9E9E;
      for (var i = 0; i < c.lineas.length; i++) {
        final l = c.lineas[i];
        if (l.precioUnitario <= 0) continue;
        final clave = l.productoId.isNotEmpty ? l.productoId : l.productoNombre;
        if (!claves.contains(clave)) continue;
        porProducto
            .putIfAbsent(clave, () => [])
            .add((c, i, numero, provNombre, provColor));
      }
    }

    final salida = <HistoricoProducto>[];
    for (final entry in porProducto.entries) {
      final primeraLinea = entry.value.first.$1.lineas[entry.value.first.$2];
      final producto = prodPorId[entry.key] ??
          Producto(id: entry.key, nombre: primeraLinea.productoNombre);
      salida.add(_secuencia(entry.key, producto, entry.value));
    }
    return _ordenar(salida);
  }

  /// Los que tienen alguna subida primero, y dentro por lo que mas ha subido
  /// en total: son los que interesa mirar primero.
  static List<HistoricoProducto> _ordenar(List<HistoricoProducto> l) {
    l.sort((a, b) {
      final porSubida =
          (b.tieneAlgunaSubida ? 1 : 0) - (a.tieneAlgunaSubida ? 1 : 0);
      if (porSubida != 0) return porSubida;
      final va = a.variacionTotal ?? 0, vb = b.variacionTotal ?? 0;
      return vb.compareTo(va);
    });
    return l;
  }

  // ------------------------------------------------------------------ PDF

  /// [mostrarProveedor] añade una columna con quien sirvio cada compra: hace
  /// falta en el historial general (varios proveedores mezclados) y sobra en
  /// el de un proveedor concreto, donde ya se sabe de quien es todo.
  static Future<void> generarPdf({
    required String titulo,
    required List<HistoricoProducto> historicos,
    bool soloConSubidas = false,
    bool mostrarProveedor = false,
  }) async {
    final lista = soloConSubidas
        ? historicos.where((h) => h.tieneAlgunaSubida).toList()
        : historicos;

    final gastoTotal = lista.fold<double>(0, (s, h) => s + h.gastoTotal);

    final doc = await FuentesPdf.documento();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          final w = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text('Historial de precios · $titulo',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text('Generado el ${fecha(DateTime.now())}'),
            pw.SizedBox(height: 4),
            pw.Text(
              '${lista.length} producto${lista.length == 1 ? "" : "s"} · '
              '${euros(gastoTotal)} en total'
              '${soloConSubidas ? " · solo con subidas" : ""}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 10),
          ];

          if (lista.isEmpty) {
            w.add(pw.Text('No hay compras registradas.'));
            return w;
          }

          for (final h in lista) {
            final unidadPrecio = h.producto.unidadBase.etiqueta;
            final unidadCantidad = h.producto.unidadBase.nombre;

            final headers = [
              'Fecha',
              if (mostrarProveedor) 'Proveedor',
              'Albarán',
              'Cantidad',
              unidadPrecio,
              'Variación',
            ];
            final anchos = [
              2.0,
              if (mostrarProveedor) 2.2,
              1.6,
              1.8,
              1.6,
              1.8,
            ];

            w.add(pw.SizedBox(height: 12));
            w.add(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(h.producto.nombre,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                if (h.variacionTotal != null)
                  pw.Text(
                    '${h.variacionTotal! > 0 ? "+" : ""}'
                    '${(h.variacionTotal! * 100).toStringAsFixed(0)}% '
                    'desde la primera compra',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: h.variacionTotal! > 0.005
                          ? PdfColors.red700
                          : h.variacionTotal! < -0.005
                              ? PdfColors.green700
                              : PdfColors.grey700,
                    ),
                  ),
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
                for (var i = 0; i < headers.length; i++)
                  i: i == 0 || (mostrarProveedor && i == 1)
                      ? pw.Alignment.centerLeft
                      : pw.Alignment.centerRight,
              },
              columnWidths: {
                for (var i = 0; i < anchos.length; i++)
                  i: pw.FlexColumnWidth(anchos[i]),
              },
              headers: headers,
              data: h.compras.map((c) {
                final fila = <String>[fecha(c.fecha)];
                if (mostrarProveedor) fila.add(c.proveedorNombre);
                fila.addAll([
                  c.numeroAlbaran ?? '—',
                  '${_num(c.cantidad)} $unidadCantidad',
                  c.precioUnitario.toStringAsFixed(2),
                  c.variacion == null
                      ? '—'
                      : '${c.variacion! > 0 ? "▲" : c.variacion! < 0 ? "▼" : ""} '
                          '${(c.variacion! * 100).toStringAsFixed(0)}%',
                ]);
                return fila;
              }).toList(),
            ));
          }

          w.add(pw.SizedBox(height: 16));
          w.add(pw.Divider());
          w.add(pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('TOTAL ${euros(gastoTotal)}',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ],
          ));

          return w;
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'historial_${titulo.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "_")}.pdf',
      onLayout: (format) async => doc.save(),
    );
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
