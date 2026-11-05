import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ui/formato.dart';

/// Estilo comun de todos los PDF de la app.
///
/// Mismo lenguaje que el resto de herramientas de cocina: titulo en versales
/// con una raya oscura debajo, secciones en verde azulado subrayadas, filas
/// limpias sin rejilla y lineas de puntos que llevan la vista del nombre al
/// dato. Si un dia hay que cambiar un color o un tamaño, se cambia aqui y
/// cambian todos los informes a la vez.
class EstiloPdf {
  // ---------------------------------------------------------------- colores

  static const PdfColor acento = PdfColor.fromInt(0xFF1F7A7A);
  static const PdfColor tinta = PdfColor.fromInt(0xFF222222);
  static const PdfColor gris = PdfColor.fromInt(0xFF8A8A8A);
  static const PdfColor linea = PdfColor.fromInt(0xFFDDE3E3);
  static const PdfColor caja = PdfColor.fromInt(0xFFF2F7F7);
  static const PdfColor rojo = PdfColor.fromInt(0xFFB3261E);
  static const PdfColor verde = PdfColor.fromInt(0xFF2E7D32);

  // ----------------------------------------------------------------- pagina

  static const pw.EdgeInsets margen = pw.EdgeInsets.fromLTRB(34, 30, 34, 22);

  /// Documento de varias paginas con el pie comun (app, fecha y paginas).
  static pw.MultiPage paginas({required pw.BuildListCallback build}) =>
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margen,
        footer: pie,
        build: build,
      );

  static pw.Widget pie(pw.Context ctx) {
    final estilo = pw.TextStyle(fontSize: 7, color: gris);
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('ComparaPrecios · ${fecha(DateTime.now())}', style: estilo),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: estilo),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- cabecera

  /// Titulo del informe en versales, con un dato pequeño a la derecha
  /// (fecha, hoja...) y una linea de resumen debajo de la raya.
  static pw.Widget cabecera(
    String titulo, {
    String? derecha,
    String? subtitulo,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Text(
                  titulo.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: tinta,
                  ),
                ),
              ),
              if (derecha != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 10, bottom: 1),
                  child: pw.Text(derecha,
                      style: pw.TextStyle(fontSize: 8.5, color: gris)),
                ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Container(height: 1.2, color: tinta),
          if (subtitulo != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(subtitulo, style: pw.TextStyle(fontSize: 8.5, color: gris)),
          ],
          pw.SizedBox(height: 4),
        ],
      );

  // ---------------------------------------------------------------- seccion

  /// Rotulo de seccion: versales en verde azulado, subrayado. Opcionalmente
  /// un dato a la derecha (subtotal, porcentaje...).
  static pw.Widget seccion(
    String texto, {
    String? derecha,
    PdfColor? colorDerecha,
    double arriba = 12,
  }) =>
      pw.Container(
        margin: pw.EdgeInsets.only(top: arriba, bottom: 3),
        padding: const pw.EdgeInsets.only(bottom: 2),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: acento, width: 0.6)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                texto.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: acento,
                ),
              ),
            ),
            if (derecha != null)
              pw.Text(
                derecha,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: colorDerecha ?? tinta,
                ),
              ),
          ],
        ),
      );

  // ------------------------------------------------------------------ tabla

  /// Tabla sin rejilla: rotulos pequeños en verde azulado y una raya fina
  /// entre filas. Las columnas en [izquierda] van alineadas a la izquierda,
  /// el resto (cifras) a la derecha.
  static pw.Widget tabla({
    required List<String> cabeceras,
    required List<List<String>> filas,
    List<double>? anchos,
    Set<int> izquierda = const {0},
    double tamano = 8.5,
  }) {
    final alineacion = {
      for (var i = 0; i < cabeceras.length; i++)
        i: izquierda.contains(i)
            ? pw.Alignment.centerLeft
            : pw.Alignment.centerRight,
    };
    return pw.TableHelper.fromTextArray(
      border: null,
      headers: cabeceras.map((c) => c.toUpperCase()).toList(),
      data: filas,
      headerStyle: pw.TextStyle(
        fontSize: 7,
        fontWeight: pw.FontWeight.bold,
        color: acento,
      ),
      cellStyle: pw.TextStyle(fontSize: tamano, color: tinta),
      headerDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: acento, width: 0.6)),
      ),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: linea, width: 0.5)),
      ),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      cellAlignments: alineacion,
      headerAlignments: alineacion,
      columnWidths: anchos == null
          ? null
          : {
              for (var i = 0; i < anchos.length; i++)
                i: pw.FlexColumnWidth(anchos[i]),
            },
    );
  }

  // ------------------------------------------------------------ fila puntos

  /// El texto seguido de una linea de puntos que ocupa todo el hueco libre
  /// hasta lo que venga detras en la fila. Va dentro de un `pw.Row`.
  static pw.Widget conPuntos(pw.Widget texto, {double sangria = 0}) =>
      pw.Expanded(
        child: pw.Padding(
          padding: pw.EdgeInsets.only(left: sangria, right: 4),
          child: pw.Stack(
            alignment: pw.Alignment.bottomLeft,
            children: [
              pw.Positioned(
                left: 0,
                right: 0,
                bottom: 2.2,
                child: pw.Container(
                  height: 1,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: gris,
                        width: 0.7,
                        style: pw.BorderStyle.dotted,
                      ),
                    ),
                  ),
                ),
              ),
              // El fondo blanco tapa los puntos por detras del nombre.
              pw.Container(
                color: PdfColors.white,
                padding: const pw.EdgeInsets.only(right: 3),
                child: texto,
              ),
            ],
          ),
        ),
      );

  /// Casilla clara para escribir a mano (cantidades, precios...).
  static pw.Widget casilla({double ancho = 32, double alto = 11}) =>
      pw.Container(
        width: ancho,
        height: alto,
        decoration: pw.BoxDecoration(
          color: caja,
          border: pw.Border.all(color: gris, width: 0.4),
        ),
      );

  // ------------------------------------------------------- totales y notas

  /// Recuadro destacado para la cifra principal del informe.
  static pw.Widget destacado(String etiqueta, String valor) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const pw.BoxDecoration(
          color: caja,
          border: pw.Border(left: pw.BorderSide(color: acento, width: 3)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              etiqueta.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: acento,
              ),
            ),
            pw.Text(
              valor,
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: tinta,
              ),
            ),
          ],
        ),
      );

  /// Cierre del informe: raya oscura y el total a la derecha. [nota] sale a
  /// la izquierda (por ejemplo, el ahorro).
  static pw.Widget total(
    String etiqueta,
    String valor, {
    String? nota,
    PdfColor? colorNota,
  }) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 16),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: tinta, width: 1.2)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            nota == null
                ? pw.SizedBox()
                : pw.Text(
                    nota,
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: colorNota ?? tinta,
                    ),
                  ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  etiqueta.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: gris,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  valor,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: tinta,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  /// Texto pequeño en gris para aclaraciones.
  static pw.Widget nota(String texto, {double arriba = 4}) => pw.Padding(
        padding: pw.EdgeInsets.only(top: arriba),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 7.5, color: gris)),
      );

  /// Mensaje cuando no hay nada que listar.
  static pw.Widget vacio(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 10, color: gris)),
      );
}
