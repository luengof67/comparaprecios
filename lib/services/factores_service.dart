import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';

/// Busca precios de un ENVASE que se guardaron como si fueran una unidad.
///
/// El caso real: "32,09 € / 1 garrafa = 1 ud". La garrafa se anoto con
/// cantidad 1, asi que el precio por unidad sale 32,09 y compite contra el
/// bote suelto de otro proveedor a 6,95. La comparativa marca un -78% que no
/// existe: no son la misma cosa.
///
/// Falta el factor: cuantas unidades base trae ese envase. Es lo mismo que
/// ahora se pregunta al importar, pero aplicado al historico de antes.
///
/// OJO: cantidad 1 con formato NO siempre es un error. Una "botella 1 L" en
/// un producto que va por litros esta bien puesta. Por eso esto propone
/// candidatos ordenados por lo raros que son, y decide la persona.

/// Un grupo de precios del mismo producto, proveedor y formato.
class GrupoSinFactor {
  final Producto producto;
  final String proveedorId;
  final String proveedorNombre;
  final int proveedorColor;
  final String formato;

  /// Los precios afectados, del mas reciente al mas antiguo.
  final List<Precio> precios;

  /// Precio por unidad base tal como esta guardado ahora.
  final double unitarioActual;

  /// Lo que cobran los demas proveedores por ese producto (mediana).
  /// 0 si no hay con quien comparar.
  final double referencia;

  const GrupoSinFactor({
    required this.producto,
    required this.proveedorId,
    required this.proveedorNombre,
    required this.proveedorColor,
    required this.formato,
    required this.precios,
    required this.unitarioActual,
    required this.referencia,
  });

  /// Cuantas veces mas caro sale que la referencia. 4.6 significa que este
  /// envase cuesta como 4,6 unidades de los demas: casi seguro que ese es el
  /// factor que falta.
  double get desviacion =>
      referencia > 0 ? unitarioActual / referencia : 0;

  /// El formato es en realidad la unidad base ("unidad", "kilos", "L").
  /// Entonces cantidad 1 esta bien puesta y no hay nada que convertir.
  bool get formatoEsUnidadBase =>
      FactoresService.esUnidadBase(formato);

  /// Merece la pena revisarlo.
  ///
  /// Hace falta que sea un envase de verdad Y que se salga MUCHO. Un x2 no
  /// prueba nada: que un proveedor cobre el doble que otro por el mismo
  /// genero es de lo mas normal. A partir de x3 ya no se explica solo por
  /// precio.
  bool get sospechoso => !formatoEsUnidadBase && desviacion >= 3.0;

  /// El factor que cuadraria este precio con lo que cobran los demas.
  /// Es una pista para rellenar la casilla, no una verdad.
  double get factorSugerido => desviacion > 0 ? desviacion : 0;

  DateTime get ultimaFecha => precios.first.fecha;

  /// Como quedaria el precio por unidad base con el factor que se teclee.
  double unitarioCon(double factor) =>
      factor > 0 ? precios.first.precioPaquete / factor : 0;
}

class FactoresService {
  /// Formatos que no son un envase, sino la propia unidad de medida.
  static const _unidadesBase = {
    'ud', 'uds', 'u', 'unidad', 'unidades', 'pza', 'pzas', 'pieza', 'piezas',
    'kg', 'kgs', 'k', 'kilo', 'kilos', 'kilogramo', 'kilogramos',
    'l', 'lt', 'ltr', 'litro', 'litros',
  };

  /// ¿Este "formato" es en realidad la unidad de medida?
  static bool esUnidadBase(String formato) =>
      _unidadesBase.contains(formato.toLowerCase().trim());

  /// Encuentra los grupos con formato y cantidad 1.
  ///
  /// [soloSospechosos] deja fuera los que no se salen de lo que cobran los
  /// demas: si el precio ya cuadra, probablemente el envase SI era una unidad
  /// y no hay nada que tocar.
  static List<GrupoSinFactor> detectar({
    required List<Producto> productos,
    required List<Proveedor> proveedores,
    required List<Precio> precios,
    bool soloSospechosos = true,
  }) {
    final prodPorId = {for (final p in productos) p.id: p};
    final provPorId = {for (final p in proveedores) p.id: p};

    // Ultimo precio de cada pareja producto-proveedor, para la referencia.
    final ultimos = <String, Precio>{};
    for (final p in precios) {
      if (p.precioUnitario <= 0) continue;
      final k = '${p.productoId}|${p.proveedorId}';
      final a = ultimos[k];
      if (a == null || p.fecha.isAfter(a.fecha)) ultimos[k] = p;
    }

    // Agrupar los candidatos por producto + proveedor + formato.
    final grupos = <String, List<Precio>>{};
    for (final p in precios) {
      final f = (p.formato ?? '').trim();
      if (f.isEmpty) continue;
      // cantidad 1 = "un envase entero cuenta como una unidad base"
      if ((p.cantidad - 1).abs() > 0.0001) continue;
      if (p.precioUnitario <= 0) continue;
      grupos
          .putIfAbsent('${p.productoId}|${p.proveedorId}|${f.toLowerCase()}',
              () => [])
          .add(p);
    }

    final salida = <GrupoSinFactor>[];
    for (final e in grupos.entries) {
      final lista = e.value..sort((a, b) => b.fecha.compareTo(a.fecha));
      final primero = lista.first;

      final producto = prodPorId[primero.productoId];
      if (producto == null) continue; // producto borrado: no hay unidad base

      // Referencia: lo que cobran los OTROS proveedores por este producto.
      final otros = <double>[];
      for (final u in ultimos.entries) {
        if (!u.key.startsWith('${primero.productoId}|')) continue;
        if (u.value.proveedorId == primero.proveedorId) continue;
        otros.add(u.value.precioUnitario);
      }
      otros.sort();
      final referencia = otros.isEmpty
          ? 0.0
          : otros.length.isOdd
              ? otros[otros.length ~/ 2]
              : (otros[otros.length ~/ 2 - 1] + otros[otros.length ~/ 2]) / 2;

      final prov = provPorId[primero.proveedorId];
      final g = GrupoSinFactor(
        producto: producto,
        proveedorId: primero.proveedorId,
        proveedorNombre: prov?.nombre ?? 'Sin proveedor',
        proveedorColor: prov?.color ?? 0xFF1565C0,
        formato: (primero.formato ?? '').trim(),
        precios: lista,
        unitarioActual: primero.precioUnitario,
        referencia: referencia,
      );

      if (soloSospechosos && !g.sospechoso) continue;
      salida.add(g);
    }

    // Primero los que mas distorsionan la comparativa.
    salida.sort((a, b) => b.desviacion.compareTo(a.desviacion));
    return salida;
  }

  /// Cuantos candidatos hay en total, se salgan o no de lo normal.
  static int contarTodos({
    required List<Producto> productos,
    required List<Proveedor> proveedores,
    required List<Precio> precios,
  }) =>
      detectar(
        productos: productos,
        proveedores: proveedores,
        precios: precios,
        soloSospechosos: false,
      ).length;
}
