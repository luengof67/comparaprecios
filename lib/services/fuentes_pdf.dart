import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Fuentes para los PDFs.
///
/// El paquete `pdf` usa Helvetica por defecto, que solo lleva el alfabeto
/// latino basico: el simbolo del euro, el punto medio y el aspa salen como
/// cuadraditos. DejaVu Sans si los tiene, y va empaquetada con la app, asi
/// que funciona sin conexion.
///
/// Se carga una sola vez y se guarda en memoria: leer 1,4 MB de disco en cada
/// informe seria absurdo.
class FuentesPdf {
  static pw.ThemeData? _tema;

  /// Tema para pasar a `pw.Document(theme: ...)`. Con esto, todos los textos
  /// del documento salen en DejaVu sin tener que tocarlos uno a uno.
  static Future<pw.ThemeData> tema() async {
    if (_tema != null) return _tema!;

    final normal = pw.Font.ttf(
        await rootBundle.load('assets/fuentes/DejaVuSans.ttf'));
    final negrita = pw.Font.ttf(
        await rootBundle.load('assets/fuentes/DejaVuSans-Bold.ttf'));

    _tema = pw.ThemeData.withFont(
      base: normal,
      bold: negrita,
      italic: normal, // DejaVu Oblique no se empaqueta: no merece 700 KB mas
      boldItalic: negrita,
    );
    return _tema!;
  }

  /// Crea el documento ya con la fuente puesta. Sustituye a `pw.Document()`.
  static Future<pw.Document> documento() async =>
      pw.Document(theme: await tema());
}
