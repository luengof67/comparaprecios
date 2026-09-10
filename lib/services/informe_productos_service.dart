import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../ui/formato.dart';
import 'fuentes_pdf.dart';

/// Un producto en un mes: cantidad y gasto sumados.
class MesProducto {
  final DateTime mes;
  double cantidad = 0;
  double gasto = 0;
  int compras = 0;
  MesProducto(this.mes);

  double get precioMedio => cantidad > 0 ? gasto / cantidad : 0;
}

/// Un producto con su historico por meses.
class ResumenProducto {
  final String clave;
  final String nombre;
  final String unidad;
  final String categoria;
  final Map<String, MesProducto> meses = {};

  ResumenProducto({
    required this.clave,
    required this.nombre,
    required this.unidad,
    required this.categoria,
  });

  static String claveMes(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  MesProducto? del(DateTime mes) => meses[claveMes(mes)];

  /// Del mas reciente al mas antiguo.
  List<MesProducto> get ordenados {
    final l = meses.values.toList()..sort((a, b) => b.mes.compareTo(a.mes));
    return l;
  }

  /// Igual que [ordenados], pero solo con los meses cuya clave este en
  /// [claves]. Con [claves] vacio devuelve todos: es el estado "sin filtrar".
  /// No hace falta que sean consecutivos.
  List<MesProducto> ordenadosEn(Set<String> claves) {
    if (claves.isEmpty) return ordenados;
    final l = meses.entries
        .where((e) => claves.contains(e.key))
        .map((e) => e.value)
        .toList()
      ..sort((a, b) => b.mes.compareTo(a.mes));
    return l;
  }

  double get gastoTotal => meses.values.fold(0, (s, m) => s + m.gasto);
  double get cantidadTotal => meses.values.fold(0, (s, m) => s + m.cantidad);
}

/// Que se ha comprado, cuanto y por cuanto. Todo sale de las compras
/// registradas, no de los precios de tarifa: es lo que se pago de verdad.
class InformeProductosService {
  /// Agrupa todas las compras por producto y mes.
  static Map<String, ResumenProducto> agrupar(
      List<Compra> compras, List<Producto> productos) {
    final cat = {for (final p in productos) p.id: p.categoria};
    final uni = {for (final p in productos) p.id: p.unidadBase.nombre};

    final salida = <String, ResumenProducto>{};
    for (final c in compras) {
      final mes = DateTime(c.fecha.year, c.fecha.month);
      for (final l in c.lineas) {
        final clave = l.productoId.isNotEmpty ? l.productoId : l.productoNombre;
        final r = salida.putIfAbsent(
          clave,
          () => ResumenProducto(
            clave: clave,
            nombre: l.productoNombre,
            unidad: uni[l.productoId] ?? l.unidad,
            categoria: cat[l.productoId] ?? 'Sin categoría',
          ),
        );
        final m = r.meses.putIfAbsent(
            ResumenProducto.claveMes(mes), () => MesProducto(mes));
        m.cantidad += l.cantidad;
        m.gasto += l.total;
        m.compras++;
      }
    }
    return salida;
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _mesLargo(DateTime m) =>
      DateFormat('MMMM yyyy', 'es_ES').format(m);

  static String _mesCorto(DateTime m) =>
      DateFormat('MMM yyyy', 'es_ES').format(m);

  // ------------------------------------------------------------ PDF del mes

  /// Listado de un mes: por categoria y ordenado por gasto.
  static Future<void> generarPdf({
    required DateTime mes,
    required List<Compra> compras,
    required List<Producto> productos,
  }) async {
    final todos = agrupar(compras, productos);
    final delMes = todos.values
        .map((r) => (r, r.del(mes)))
        .where((e) => e.$2 != null)
        .toList();

    final porCategoria = <String, List<(ResumenProducto, MesProducto)>>{};
    for (final e in delMes) {
      porCategoria.putIfAbsent(e.$1.categoria, () => []).add((e.$1, e.$2!));
    }
    double suma(List<(ResumenProducto, MesProducto)> l) =>
        l.fold(0, (s, e) => s + e.$2.gasto);

    final categorias = porCategoria.entries.toList()
      ..sort((a, b) => suma(b.value).compareTo(suma(a.value)));
    for (final e in categorias) {
      e.value.sort((a, b) => b.$2.gasto.compareTo(a.$2.gasto));
    }

    final totalGasto = delMes.fold<double>(0, (s, e) => s + e.$2!.gasto);
    final nCompras = compras
        .where((c) => c.fecha.year == mes.year && c.fecha.month == mes.month)
        .length;

    final doc = await FuentesPdf.documento();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          final w = <pw.Widget>[
            _cabecera('Productos comprados · ${_mesLargo(mes)}',
                '${delMes.length} productos distintos en $nCompras compras · '
                    '${euros(totalGasto)} en total'),
          ];

          if (delMes.isEmpty) {
            w.add(pw.Text('No hay compras registradas en este mes.'));
            return w;
          }

          for (final e in categorias) {
            final sub = suma(e.value);
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
            w.add(_tabla(
              cabeceras: ['Producto', 'Cantidad', 'Gasto'],
              anchos: [5, 2, 2],
              filas: e.value
                  .map((x) => [
                        x.$1.nombre,
                        '${_num(x.$2.cantidad)} ${x.$1.unidad}',
                        euros(x.$2.gasto),
                      ])
                  .toList(),
            ));
          }

          w.add(_total(totalGasto));
          return w;
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'productos_${ResumenProducto.claveMes(mes)}.pdf',
      onLayout: (format) async => doc.save(),
    );
  }

  // ------------------------------------------------------ PDF del historico

  /// Historico por meses de unos productos concretos: los que salieron en la
  /// busqueda. Una tabla por producto, con cantidad, precio medio y gasto de
  /// cada mes.
  static Future<void> generarHistoricoPdf({
    required List<ResumenProducto> productos,
    required String titulo,
    Set<String> mesesElegidos = const {},
  }) async {
    // Los totales salen de los meses elegidos, no del historico completo:
    // si se esta comparando julio y septiembre, el total tiene que ser el de
    // esos dos, no el de los tres meses que hubiera de por medio.
    double totalDe(ResumenProducto r) => r
        .ordenadosEn(mesesElegidos)
        .fold<double>(0, (s, m) => s + m.gasto);
    double cantidadDe(ResumenProducto r) => r
        .ordenadosEn(mesesElegidos)
        .fold<double>(0, (s, m) => s + m.cantidad);

    final totalGasto = productos.fold<double>(0, (s, r) => s + totalDe(r));
    final rango = mesesElegidos.isEmpty
        ? ''
        : ' · ${mesesElegidos.length} mes${mesesElegidos.length == 1 ? "" : "es"} elegidos';

    final doc = await FuentesPdf.documento();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          final w = <pw.Widget>[
            _cabecera('Histórico de compras · $titulo',
                '${productos.length} producto${productos.length == 1 ? "" : "s"} · '
                    '${euros(totalGasto)} en total$rango'),
          ];

          for (final r in productos) {
            final meses = r.ordenadosEn(mesesElegidos);
            if (meses.isEmpty) continue;
            w.add(pw.SizedBox(height: 12));
            w.add(pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(r.nombre,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    '${_num(cantidadDe(r))} ${r.unidad} · ${euros(totalDe(r))}',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ));
            w.add(pw.Text(r.categoria,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700)));
            w.add(pw.SizedBox(height: 4));
            w.add(_tabla(
              cabeceras: ['Mes', 'Cantidad', '€/${r.unidad}', 'Gasto'],
              anchos: [3, 2, 2, 2],
              filas: [
                for (var i = 0; i < meses.length; i++)
                  [
                    _mesCorto(meses[i].mes),
                    '${_num(meses[i].cantidad)} ${r.unidad}',
                    _conFlecha(meses[i],
                        i + 1 < meses.length ? meses[i + 1] : null),
                    euros(meses[i].gasto),
                  ],
              ],
            ));
          }

          w.add(_total(totalGasto));
          return w;
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'historico_productos.pdf',
      onLayout: (format) async => doc.save(),
    );
  }

  /// El precio medio con una marca si subio o bajo respecto al mes anterior.
  static String _conFlecha(MesProducto m, MesProducto? anterior) {
    final p = euros3(m.precioMedio);
    if (anterior == null || anterior.precioMedio <= 0 || m.precioMedio <= 0) {
      return p;
    }
    final dif = (m.precioMedio - anterior.precioMedio) / anterior.precioMedio;
    if (dif > 0.03) return '▲ $p';
    if (dif < -0.03) return '▼ $p';
    return p;
  }

  // ------------------------------------------------------------ piezas PDF

  static pw.Widget _cabecera(String titulo, String resumen) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Header(
            level: 0,
            child: pw.Text(titulo,
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Generado el ${fecha(DateTime.now())}'),
          pw.SizedBox(height: 4),
          pw.Text(resumen, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
        ],
      );

  static pw.Widget _tabla({
    required List<String> cabeceras,
    required List<double> anchos,
    required List<List<String>> filas,
  }) =>
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignments: {
          for (var i = 0; i < cabeceras.length; i++)
            i: i == 0 ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
        },
        columnWidths: {
          for (var i = 0; i < anchos.length; i++)
            i: pw.FlexColumnWidth(anchos[i]),
        },
        headers: cabeceras,
        data: filas,
      );

  static pw.Widget _total(double total) => pw.Column(children: [
        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('TOTAL ${euros(total)}',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ]);
}
