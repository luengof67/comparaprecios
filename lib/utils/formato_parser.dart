import '../models/producto.dart';

/// Lo que se ha podido deducir del texto de una linea de albaran.
class FormatoDetectado {
  /// Nombre del envase: "caja", "saco", "garrafa"... Vacio si no se nombra.
  final String formato;

  /// Unidades base que trae ese envase (6 kg, 12 ud, 4.5 L...).
  final double factor;

  const FormatoDetectado(this.formato, this.factor);

  @override
  String toString() => 'FormatoDetectado($formato, $factor)';
}

/// Deduce el formato y el factor de conversion leyendo el texto del albaran.
///
/// "TOMATE PERA CAJA 6X1KG"  con producto en kg     -> caja, factor 6
/// "PATATA SACO 25 KG"       con producto en kg     -> saco, factor 25
/// "AGUA MINERAL 12X33CL"    con producto en litros -> factor 3.96
/// "HUEVOS L DOCENA"         con producto en ud     -> docena, factor 12
///
/// Devuelve null cuando no encuentra nada fiable, o cuando lo que encuentra
/// no cuadra con la unidad base del producto (un "6X1L" en un producto que se
/// compara por kg es un error de casado, no una conversion). En ese caso hay
/// que preguntarle el factor al usuario y guardarlo en el alias.
class FormatoParser {
  // Envases ordenados de continente a contenido: en "PACK 3 LATAS" queremos
  // quedarnos con "pack", no con "lata".
  static const List<List<String>> _formatos = [
    ['CAJA', 'caja'],
    ['PACK', 'pack'],
    ['PALET', 'palet'],
    ['SACO', 'saco'],
    ['MALLA', 'malla'],
    ['CUBETA', 'cubeta'],
    ['CUBO', 'cubo'],
    ['BIDON', 'bidon'],
    ['GARRAFA', 'garrafa'],
    ['BOLSA', 'bolsa'],
    ['ESTUCHE', 'estuche'],
    ['BANDEJA', 'bandeja'],
    ['BAND', 'bandeja'],
    ['BARQUETA', 'barqueta'],
    ['BLISTER', 'blister'],
    ['TARRINA', 'tarrina'],
    ['DOCENA', 'docena'],
    ['TETRABRIK', 'brik'],
    ['BRIK', 'brik'],
    ['BOTELLA', 'botella'],
    ['LATA', 'lata'],
    ['BOTE', 'bote'],
    ['TARRO', 'tarro'],
    ['PAQUETE', 'paquete'],
  ];

  static const Map<String, double> _kg = {
    'KG': 1, 'KGS': 1, 'K': 1,
    'G': 0.001, 'GR': 0.001, 'GRS': 0.001, 'GRAMOS': 0.001,
  };

  static const Map<String, double> _litro = {
    'L': 1, 'LT': 1, 'LTR': 1, 'LITRO': 1, 'LITROS': 1,
    'DL': 0.1, 'CL': 0.01, 'ML': 0.001,
  };

  static const Map<String, double> _unidad = {
    'UD': 1, 'UDS': 1, 'U': 1, 'UNID': 1, 'UNIDAD': 1, 'UNIDADES': 1,
    'PZ': 1, 'PZS': 1,
  };

  // Todas las unidades conocidas, las largas primero para que "KGS" no se
  // parta en "KG" y sobre una "S".
  static final String _unidades = () {
    final todas = <String>{..._kg.keys, ..._litro.keys, ..._unidad.keys}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return todas.join('|');
  }();

  static const String _envases =
      'BOTELLAS?|BRIKS?|LATAS?|BOTES?|TARROS?|UDS?|PIEZAS?|BOLSAS?|'
      'PAQUETES?|ESTUCHES?|BANDEJAS?|TARRINAS?';

  static Map<String, double> _tabla(UnidadBase base) => switch (base) {
        UnidadBase.kg => _kg,
        UnidadBase.litro => _litro,
        UnidadBase.unidad => _unidad,
      };

  static const String _con = 'ÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇáàäâãéèëêíìïîóòöôõúùüûñç';
  static const String _sin = 'AAAAAEEEEIIIIOOOOOUUUUNCaaaaaeeeeiiiiooooouuuunc';

  /// Deja el texto en mayusculas, sin acentos y sin simbolos raros.
  static String normalizar(String s) {
    final b = StringBuffer();
    for (final c in s.split('')) {
      final i = _con.indexOf(c);
      b.write(i >= 0 ? _sin[i] : c);
    }
    var t = b.toString().toUpperCase();
    t = t.replaceAll(RegExp(r'[^A-Z0-9.,/*\s-]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static double _num(String s) => double.parse(s.replaceAll(',', '.'));

  static String _buscarFormato(String t) {
    for (final f in _formatos) {
      if (RegExp('\\b${f[0]}').hasMatch(t)) return f[1];
    }
    if (RegExp(r'\bC\s*/\s*\d').hasMatch(t)) return 'caja';
    return '';
  }

  /// Analiza [textoAlbaran] sabiendo en que unidad se compara el producto.
  static FormatoDetectado? detectar(String textoAlbaran, UnidadBase base) {
    final t = normalizar(textoAlbaran);
    final tabla = _tabla(base);
    final formato = _buscarFormato(t);

    // 1) "6 BOTELLAS DE 75 CL"  ->  6 * 0.75
    var m = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:' +
          _envases +
          r')\s*(?:DE\s*)?(\d+(?:[.,]\d+)?)\s*(' +
          _unidades +
          r')\b',
    ).firstMatch(t);
    if (m != null) {
      final f = tabla[m.group(3)];
      if (f == null) return null; // unidad de otra familia: no convertir
      return FormatoDetectado(formato, _num(m.group(1)!) * _num(m.group(2)!) * f);
    }

    // 2) "6X1KG", "12X33CL"  ->  6 * 1  /  12 * 0.33
    m = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*[X*]\s*(\d+(?:[.,]\d+)?)\s*(' + _unidades + r')\b',
    ).firstMatch(t);
    if (m != null) {
      final f = tabla[m.group(3)];
      if (f == null) return null;
      return FormatoDetectado(formato, _num(m.group(1)!) * _num(m.group(2)!) * f);
    }

    // 3) "DOCENA" a secas (solo tiene sentido contando piezas)
    if (base == UnidadBase.unidad && RegExp(r'\bDOCENA').hasMatch(t)) {
      return FormatoDetectado(formato.isEmpty ? 'docena' : formato, 12);
    }

    // 4) "25 KG", "500 G", "5 L"
    m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(' + _unidades + r')\b').firstMatch(t);
    if (m != null) {
      final f = tabla[m.group(2)];
      if (f == null) return null;
      return FormatoDetectado(formato, _num(m.group(1)!) * f);
    }

    // 5) "C/12", "CAJA 12"  (sin unidad: solo vale contando piezas)
    if (base == UnidadBase.unidad) {
      m = RegExp(r'\bC\s*/\s*(\d+)\b').firstMatch(t) ??
          RegExp(r'\bCAJA\s+(\d+)\b').firstMatch(t);
      if (m != null) {
        return FormatoDetectado(formato.isEmpty ? 'caja' : formato, _num(m.group(1)!));
      }
    }

    return null;
  }

  /// Comprueba si el precio de una linea viene por ENVASE o ya por unidad base.
  ///
  /// En los albaranes de genero de peso variable (carne, pescado) la cantidad
  /// ya viene en kilos y el precio ya es el precio por kilo: aplicarles el
  /// factor los dividiria dos veces y hundiria la comparativa.
  ///
  /// La pista es la propia aritmetica del albaran: si cantidad * precio da el
  /// importe de la linea, entonces `precio` esta en las unidades en que esta
  /// `cantidad`, sea caja o kilo. Si no cuadra, mejor no tocar nada.
  static bool cuadraLinea(double cantidad, double precio, double importe) {
    if (cantidad <= 0 || precio <= 0 || importe <= 0) return false;
    final esperado = cantidad * precio;
    final margen = importe.abs() * 0.02 + 0.02; // 2% + 2 centimos de redondeo
    return (esperado - importe).abs() <= margen;
  }
}
