import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/compra.dart';
import '../models/producto.dart';
import '../ui/formato.dart';
import 'estilo_pdf.dart';
import 'fuentes_pdf.dart';

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

    final doc = await FuentesPdf.documento();

    String pctDe(double v) =>
        total > 0 ? '${(v / total * 100).toStringAsFixed(1)}%' : '—';

    doc.addPage(
      EstiloPdf.paginas(
        build: (context) => [
          EstiloPdf.cabecera(
            'Cierre de compras · $nombreMes',
            derecha: fecha(DateTime.now()),
            subtitulo: '${delMes.length} compra${delMes.length == 1 ? "" : "s"} registrada'
                '${delMes.length == 1 ? "" : "s"}'
                ' · ${proveedoresOrd.length} proveedor'
                '${proveedoresOrd.length == 1 ? "" : "es"}',
          ),
          EstiloPdf.destacado('Gasto total del mes', euros(total)),
          if (delMes.isEmpty)
            EstiloPdf.vacio('No hay compras registradas en este mes.'),
          if (delMes.isNotEmpty) ...[
            EstiloPdf.seccion('Gasto por proveedor', arriba: 16),
            EstiloPdf.tabla(
              cabeceras: ['Proveedor', 'Gasto', '% del total'],
              anchos: [5, 2, 2],
              filas: proveedoresOrd
                  .map((e) => [e.key, euros(e.value), pctDe(e.value)])
                  .toList(),
            ),
            EstiloPdf.seccion('Gasto por categoría', arriba: 16),
            EstiloPdf.tabla(
              cabeceras: ['Categoría', 'Gasto', '% del total'],
              anchos: [5, 2, 2],
              filas: categoriasOrd
                  .map((e) => [e.key, euros(e.value), pctDe(e.value)])
                  .toList(),
            ),
            EstiloPdf.seccion('Top 10 productos por gasto', arriba: 16),
            EstiloPdf.tabla(
              cabeceras: ['Producto', 'Cantidad', 'Precio medio', 'Gasto'],
              anchos: [5, 2, 2, 2],
              filas: top10.map((e) {
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
              EstiloPdf.seccion('Mayores variaciones de precio en el mes',
                  arriba: 16),
              EstiloPdf.tabla(
                cabeceras: ['Producto', 'Inicio de mes', 'Fin de mes', 'Variación'],
                anchos: [5, 2, 2, 2],
                filas: topVar
                    .map((v) => [
                          v.nombre,
                          euros3(v.ini),
                          euros3(v.fin),
                          '${v.pct >= 0 ? "▲ +" : "▼ "}${v.pct.toStringAsFixed(1)}%',
                        ])
                    .toList(),
              ),
              EstiloPdf.nota(
                'Variación = primer precio pagado en el mes frente al último. '
                'Útil para detectar subidas y preparar la negociación.',
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
