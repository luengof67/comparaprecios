import '../models/linea_albaran.dart';
import '../models/producto.dart';

/// Resultado de intentar casar una línea de albarán con un producto.
enum TipoCasado { automatico, propuesto, sinCoincidencia }

class Casado {
  final TipoCasado tipo;
  final Producto? producto; // el producto casado o propuesto (null si ninguno)

  Casado(this.tipo, this.producto);
}

/// Lógica para relacionar el texto leído de un albarán con tus productos.
class CasadorService {
  /// Intenta casar una descripción de línea (de un proveedor concreto) con un
  /// producto:
  ///  1) alias exacto de ese proveedor  -> automático
  ///  2) alias exacto de cualquiera     -> automático
  ///  3) parecido por palabras          -> propuesto
  ///  4) nada                           -> sin coincidencia
  static Casado casar(
    String descripcion,
    String? proveedorId,
    List<Producto> productos,
  ) {
    final desc = _norm(descripcion);
    if (desc.isEmpty) return Casado(TipoCasado.sinCoincidencia, null);

    // 1 y 2: alias exacto.
    Producto? aliasGeneral;
    for (final p in productos) {
      for (final a in p.alias) {
        if (_norm(a.texto) == desc) {
          if (a.proveedorId == proveedorId) {
            return Casado(TipoCasado.automatico, p); // coincide proveedor
          }
          aliasGeneral ??= p; // alias de otro proveedor: lo guardamos por si acaso
        }
      }
    }
    if (aliasGeneral != null) {
      return Casado(TipoCasado.automatico, aliasGeneral);
    }

    // 3: parecido por solapamiento de palabras con nombre o alias.
    Producto? mejor;
    double mejorPunt = 0;
    final palabrasDesc = desc.split(' ').where((w) => w.length > 2).toSet();
    for (final p in productos) {
      final candidatos = <String>[_norm(p.nombre), ...p.alias.map((a) => _norm(a.texto))];
      for (final cand in candidatos) {
        final palabras = cand.split(' ').where((w) => w.length > 2).toSet();
        if (palabras.isEmpty) continue;
        final comunes = palabras.intersection(palabrasDesc).length;
        if (comunes == 0) continue;
        // puntuación: proporción de palabras que coinciden.
        final punt = comunes / palabras.length;
        if (punt > mejorPunt) {
          mejorPunt = punt;
          mejor = p;
        }
      }
    }
    if (mejor != null && mejorPunt >= 0.5) {
      return Casado(TipoCasado.propuesto, mejor);
    }

    return Casado(TipoCasado.sinCoincidencia, null);
  }

  /// Normaliza texto para comparar: minúsculas, sin acentos, sin signos.
  static String _norm(String s) {
    var t = s.toLowerCase().trim();
    const acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u'};
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }
}
