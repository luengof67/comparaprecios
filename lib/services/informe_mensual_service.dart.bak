import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../ui/formato.dart';

/// Informe de cierre de mes: cuánto se ha gastado, con quién, en qué,
/// y qué precios se han movido. Pensado para enseñar a gerencia o para
/// preparar la negociación con proveedores.
class InformeMensualService {
  /// Genera y muestra (imprimir/guardar/compartir) el PDF del mes indicado.
  static Future<void> generarPdf({
    required DateTime mes,
    required List<Compra> compras,
    required List<Producto> productos,
  }) async {
    final delMes = compras
        .where((c) => c.fecha.year == mes.year && c.fecha.month == mes.month)
        .toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));

    final catDe = <String, String>{
      for (final p in productos) p.id: p.categoria.isEmpty ? 'Sin categoría' : p.categoria
    };

    // --- Agregados ---
    double total = 0;
    final porProveedor = <String, double>{};
    final porCategoria = <String, double>{};
    // productoId -> (nombre, unidad, cantidad total, gasto total)
    final porProducto =
        <String, ({String nombre, String unidad, double cant, double gasto})>{};
    // productoId -> precios unitarios ordenados por fecha (para variaciones)
    final serie = <String, List<({DateTime f, double p})>>{};

    for (final c in delMes) {
      for (final l in c.lineas) {
        total += l.total;
        porProveedor.update(c.proveedorNombre, (v) => v + l.total,
            ifAbsent: () => l.total);
        final cat = catDe[l.productoId] ?? 'Sin categoría';
        porCategoria.update(cat, (v) => v + l.total, ifAbsent: () => l.total);
        final prev = porProducto[l.productoId];
        porProducto[l.productoId] = (
          nombre: l.productoNombre,
          unidad: l.unidad,
          cant: (prev?.cant ?? 0) + l.cantidad,
          gasto: (prev?.gasto ?? 0) + l.total,
        );
        serie
            .putIfAbsent(l.productoId, () => [])
            .add((f: c.fecha, p: l.precioUnitario));
      }
    }

    // Top 10 productos por gasto.
    final top = porProducto.entries.toList()
      ..sort((a, b) => b.value.gasto.compareTo(a.value.gasto));
    final top10 = top.take(10).toList();

    // Variaciones: primer vs último precio del mes por producto (>= 2 datos).
    final variaciones = <({String nombre, double ini, double fin, double pct})>[];
    serie.forEach((id, puntos) {
      if (puntos.length < 2) return;
      puntos.sort((a, b) => a.f.compareTo(b.f));
      final ini = puntos.first.p, fin = puntos.last.p;
      if (ini <= 0) return;
      final pct = (fin - ini) / ini * 100;
      if (pct.abs() < 1) return; // sin cambios relevantes
      variaciones.add((
        nombre: porProducto[id]?.nombre ?? id,
        ini: ini,
        fin: fin,
        pct: pct,
      ));
    });
    variaciones.sort((a, b) => b.pct.abs().compareTo(a.pct.abs()));
    final topVar = variaciones.take(10).toList();

    final proveedoresOrd = porProveedor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final categoriasOrd = porCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final nombreMes =
        DateFormat('MMMM yyyy', 'es_ES').format(mes).toUpperCase();

    final fuenteNormal = await PdfGoogleFonts.robotoRegular();
    final fuenteNegrita = await PdfGoogleFonts.robotoBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fuenteNormal, bold: fuenteNegrita),
    );

    String pctDe(double v) =>
        total > 0 ? '${(v / total * 100).toStringAsFixed(1)}%' : '—';

    pw.Widget titulo(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
          child: pw.Text(t,
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Cierre de compras · $nombreMes',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Generado el ${fecha(DateTime.now())} · '
              '${delMes.length} compras registradas'),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('GASTO TOTAL DEL MES',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(euros(total),
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          if (delMes.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 12),
              child: pw.Text('No hay compras registradas en este mes.'),
            ),
          if (delMes.isNotEmpty) ...[
            titulo('Gasto por proveedor'),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
              headers: ['Proveedor', 'Gasto', '% del total'],
              data: proveedoresOrd
                  .map((e) => [e.key, euros(e.value), pctDe(e.value)])
                  .toList(),
            ),
            titulo('Gasto por categoría'),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
              headers: ['Categoría', 'Gasto', '% del total'],
              data: categoriasOrd
                  .map((e) => [e.key, euros(e.value), pctDe(e.value)])
                  .toList(),
            ),
            titulo('Top 10 productos por gasto'),
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
              headers: ['Producto', 'Cantidad', 'Precio medio', 'Gasto'],
              data: top10.map((e) {
                final v = e.value;
                final medio = v.cant > 0 ? v.gasto / v.cant : 0;
                return [
                  v.nombre,
                  '${_n(v.cant)} ${v.unidad}',
                  '${euros3(medio)}/${v.unidad}',
                  euros(v.gasto),
                ];
              }).toList(),
            ),
            if (topVar.isNotEmpty) ...[
              titulo('Mayores variaciones de precio en el mes'),
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
                headers: ['Producto', 'Inicio de mes', 'Fin de mes', 'Variación'],
                data: topVar
                    .map((v) => [
                          v.nombre,
                          euros3(v.ini),
                          euros3(v.fin),
                          '${v.pct >= 0 ? "+" : ""}${v.pct.toStringAsFixed(1)}%',
                        ])
                    .toList(),
                cellStyle: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Variación = primer precio pagado en el mes vs último. '
                'Útil para detectar subidas y preparar la negociación.',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ],
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  static String _n(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
