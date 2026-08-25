import '../models/compra.dart';
import '../models/producto.dart';

/// Busca lineas de compra con pinta de estar mal metidas.
///
/// El caso tipico: 75 mini pizzas a 19,86 cada una = 1.489,50 €. Ese precio
/// es el de la CAJA, no el de la pizza, asi que el informe de gasto sale
/// disparado y no hay forma de verlo hasta que se mira el total del mes.
///
/// Dos criterios, porque detectan cosas distintas:
///   - precio: el €/unidad se sale de lo que se paga normalmente por ese
///     producto. Delata un precio de envase tomado como precio de unidad.
///   - importe: la linea se lleva mucho mas dinero que las demas del mismo
///     producto. Delata una cantidad mal tecleada.
///
/// Los dos necesitan con que comparar. Con menos de tres compras de ese
/// producto no hay referencia y no se puede decir nada: para esos esta el
/// modo "las mas caras", que solo ordena por importe y no adivina.
class LineaSospechosa {
  final Compra compra;
  final LineaCompra linea;

  /// Posicion dentro de compra.lineas. Hace falta para poder sustituirla.
  final int indice;

  final String productoNombre;
  final String unidad;

  /// Cuantas veces se sale del precio normal de ese producto. 0 = no aplica.
  final double ratioPrecio;

  /// Cuantas veces se sale del importe normal. 0 = no aplica.
  final double ratioImporte;

  const LineaSospechosa({
    required this.compra,
    required this.linea,
    required this.indice,
    required this.productoNombre,
    required this.unidad,
    this.ratioPrecio = 0,
    this.ratioImporte = 0,
  });

  double get importe => linea.total;

  bool get porPrecio => ratioPrecio >= 3;
  bool get porImporte => ratioImporte >= 3;
  bool get sospechosa => porPrecio || porImporte;

  /// El mayor de los dos, para ordenar.
  double get gravedad =>
      ratioPrecio > ratioImporte ? ratioPrecio : ratioImporte;

  String get motivo {
    final m = <String>[];
    if (porPrecio) m.add('precio ×${ratioPrecio.toStringAsFixed(1)}');
    if (porImporte) m.add('importe ×${ratioImporte.toStringAsFixed(1)}');
    return m.join(' · ');
  }

  /// El numero de albaran, si vino de TRAZA.
  String? get numeroAlbaran {
    final k = compra.origenClave;
    if (k == null || k.isEmpty) return null;
    final t = k.split('|');
    if (t.length < 2) return null;
    final n = t[1].trim();
    return n.isEmpty ? null : n;
  }
}

class LineasService {
  static double _mediana(List<double> v) {
    if (v.isEmpty) return 0;
    final l = [...v]..sort();
    final n = l.length;
    return n.isOdd ? l[n ~/ 2] : (l[n ~/ 2 - 1] + l[n ~/ 2]) / 2;
  }

  /// Todas las lineas de todas las compras, con su ratio calculado.
  static List<LineaSospechosa> analizar({
    required List<Compra> compras,
    required List<Producto> productos,
  }) {
    final unidades = {
      for (final p in productos) p.id: p.unidadBase.nombre,
    };

    // Agrupar precios e importes por producto, para tener referencia.
    final unitarios = <String, List<double>>{};
    final importes = <String, List<double>>{};
    for (final c in compras) {
      for (final l in c.lineas) {
        if (l.precioUnitario > 0) {
          unitarios.putIfAbsent(l.productoId, () => []).add(l.precioUnitario);
        }
        if (l.total > 0) {
          importes.putIfAbsent(l.productoId, () => []).add(l.total);
        }
      }
    }

    final salida = <LineaSospechosa>[];
    for (final c in compras) {
      for (var i = 0; i < c.lineas.length; i++) {
        final l = c.lineas[i];

        // Hace falta un minimo de historia para poder comparar. Con dos
        // lineas, si una esta mal, la mediana ya sale contaminada.
        final listaU = unitarios[l.productoId] ?? const <double>[];
        final listaI = importes[l.productoId] ?? const <double>[];
        final hayReferencia = listaU.length >= 3;

        var rp = 0.0, ri = 0.0;
        if (hayReferencia) {
          final medU = _mediana(listaU);
          final medI = _mediana(listaI);
          if (medU > 0 && l.precioUnitario > 0) rp = l.precioUnitario / medU;
          if (medI > 0 && l.total > 0) ri = l.total / medI;
        }

        salida.add(LineaSospechosa(
          compra: c,
          linea: l,
          indice: i,
          productoNombre: l.productoNombre,
          unidad: unidades[l.productoId] ?? l.unidad,
          ratioPrecio: rp,
          ratioImporte: ri,
        ));
      }
    }
    return salida;
  }

  /// Las que se salen de lo normal, de mas grave a menos.
  static List<LineaSospechosa> sospechosas({
    required List<Compra> compras,
    required List<Producto> productos,
  }) {
    final todas = analizar(compras: compras, productos: productos)
        .where((l) => l.sospechosa)
        .toList();
    todas.sort((a, b) => b.gravedad.compareTo(a.gravedad));
    return todas;
  }

  /// Las de mas importe, sin juzgar nada.
  ///
  /// Es el complemento necesario: un producto comprado una sola vez no tiene
  /// referencia, asi que ningun criterio lo detecta. Pero si una linea suelta
  /// se lleva 1.489 €, merece un vistazo aunque el programa no sepa decir
  /// por que.
  static List<LineaSospechosa> masCaras({
    required List<Compra> compras,
    required List<Producto> productos,
    int cuantas = 40,
  }) {
    final todas = analizar(compras: compras, productos: productos)
      ..sort((a, b) => b.importe.compareTo(a.importe));
    return todas.take(cuantas).toList();
  }
}
