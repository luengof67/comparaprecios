/// Una línea tal como la lee la IA del albarán (antes del casado).
class LineaAlbaran {
  final String descripcion;
  final double? cantidad;
  final String? unidad;
  final double? precioUnitario;
  final double? precioTotal;

  LineaAlbaran({
    required this.descripcion,
    this.cantidad,
    this.unidad,
    this.precioUnitario,
    this.precioTotal,
  });

  factory LineaAlbaran.fromMap(Map<String, dynamic> d) => LineaAlbaran(
        descripcion: (d['descripcion'] ?? '').toString(),
        cantidad: _num(d['cantidad']),
        unidad: d['unidad']?.toString(),
        precioUnitario: _num(d['precioUnitario']),
        precioTotal: _num(d['precioTotal']),
      );

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  /// Precio por unidad calculado: el unitario si viene, si no total/cantidad.
  double? get unitarioCalculado {
    if (precioUnitario != null && precioUnitario! > 0) return precioUnitario;
    if (precioTotal != null && cantidad != null && cantidad! > 0) {
      return precioTotal! / cantidad!;
    }
    return null;
  }
}

/// Resultado completo de leer un albarán.
class ResultadoAlbaran {
  final String? proveedor;
  final List<LineaAlbaran> lineas;

  ResultadoAlbaran({this.proveedor, required this.lineas});

  factory ResultadoAlbaran.fromMap(Map<String, dynamic> d) {
    final raw = (d['lineas'] as List?) ?? const [];
    return ResultadoAlbaran(
      proveedor: d['proveedor']?.toString(),
      lineas: raw
          .map((e) => LineaAlbaran.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
