import '../models/comparativa.dart';
import '../models/compra.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';

/// Aqui vive la "inteligencia" de la app: a partir de los registros de precios
/// calcula quien es el mas barato, cuanto ahorras y la evolucion en el tiempo.
class AnaliticaService {
  /// Compara todos los proveedores para un producto.
  /// "Precio actual" de cada proveedor = su registro MAS RECIENTE.
  static ComparativaProducto comparar(
    Producto producto,
    List<Precio> preciosDelProducto,
    List<Proveedor> proveedores,
  ) {
    final mapaProveedores = {for (final p in proveedores) p.id: p};

    // Ultimo precio por proveedor.
    final Map<String, Precio> ultimoPorProveedor = {};
    for (final precio in preciosDelProducto) {
      final actual = ultimoPorProveedor[precio.proveedorId];
      if (actual == null || precio.fecha.isAfter(actual.fecha)) {
        ultimoPorProveedor[precio.proveedorId] = precio;
      }
    }

    final ofertas = <OfertaProveedor>[];
    ultimoPorProveedor.forEach((provId, precio) {
      final prov = mapaProveedores[provId];
      if (prov != null) {
        ofertas.add(OfertaProveedor(
          proveedor: prov,
          precioUnitario: precio.precioUnitario,
          fecha: precio.fecha,
          variacion: _variacionVsUltimaCompra(
              preciosDelProducto, provId, precio),
          formato: precio.formato,
          formatoCantidad: precio.cantidad,
        ));
      }
    });

    ofertas.sort((a, b) => a.precioUnitario.compareTo(b.precioUnitario));

    return ComparativaProducto(
      producto: producto,
      ofertas: ofertas,
      historico: preciosDelProducto,
    );
  }

  /// Variacion del precio [actual] respecto a la ultima COMPRA registrada a ese
  /// proveedor (anterior al precio actual). Si no hay compra previa, usa el
  /// registro inmediatamente anterior de ese proveedor. null si no hay con que
  /// comparar.
  static double? _variacionVsUltimaCompra(
    List<Precio> todos,
    String provId,
    Precio actual,
  ) {
    // Registros de ese proveedor, anteriores al actual, mas nuevos primero.
    final previos = todos
        .where((p) =>
            p.proveedorId == provId && p.fecha.isBefore(actual.fecha))
        .toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
    if (previos.isEmpty) return null;

    // Preferimos la ultima COMPRA; si no hay, el registro anterior cualquiera.
    final ref = previos.firstWhere(
      (p) => p.fuente == FuentePrecio.compra,
      orElse: () => previos.first,
    );
    if (ref.precioUnitario <= 0) return null;
    return (actual.precioUnitario - ref.precioUnitario) / ref.precioUnitario;
  }

  /// Calcula la comparativa de todos los productos de golpe.
  static List<ComparativaProducto> compararTodo(
    List<Producto> productos,
    List<Precio> todosLosPrecios,
    List<Proveedor> proveedores,
  ) {
    // Agrupar precios por producto.
    final Map<String, List<Precio>> porProducto = {};
    for (final p in todosLosPrecios) {
      porProducto.putIfAbsent(p.productoId, () => []).add(p);
    }

    return productos
        .map((prod) => comparar(prod, porProducto[prod.id] ?? const [], proveedores))
        .toList();
  }

  /// Resumen para el dashboard a partir de todas las comparativas.
  static ResumenDashboard resumen(
    List<ComparativaProducto> comparativas,
    List<Proveedor> proveedores,
  ) {
    double ahorroTotal = 0;
    int conDatos = 0;
    final Map<String, int> victorias = {}; // proveedorId -> nº de productos donde es el mas barato

    for (final c in comparativas) {
      if (!c.tieneDatos) continue;
      conDatos++;
      ahorroTotal += c.ahorroPorUnidad;
      final ganador = c.masBarato!.proveedor.id;
      victorias[ganador] = (victorias[ganador] ?? 0) + 1;
    }

    Proveedor? proveedorGanador;
    int vecesGanador = 0;
    if (victorias.isNotEmpty) {
      final mejor = victorias.entries.reduce((a, b) => a.value >= b.value ? a : b);
      proveedorGanador = proveedores.where((p) => p.id == mejor.key).firstOrNull;
      vecesGanador = mejor.value;
    }

    return ResumenDashboard(
      totalProductos: comparativas.length,
      totalProveedores: proveedores.length,
      productosConDatos: conDatos,
      ahorroPotencialTotal: ahorroTotal,
      proveedorGanador: proveedorGanador,
      vecesGanador: vecesGanador,
    );
  }

  // ---- INFORMES SOBRE COMPRAS REALES ----

  /// Precio actual mas caro por producto (referencia para el ahorro).
  static Map<String, double> precioMaxPorProducto(
    List<Producto> productos,
    List<Precio> precios,
    List<Proveedor> proveedores,
  ) {
    final comps = compararTodo(productos, precios, proveedores);
    final m = <String, double>{};
    for (final c in comps) {
      if (c.tieneDatos) m[c.producto.id] = c.precioMax;
    }
    return m;
  }

  /// Genera los grupos del informe segun la agrupacion elegida.
  /// Ahorro = (coste al proveedor mas caro de cada producto) - (lo gastado).
  static List<GrupoInforme> informe(
    List<Compra> compras,
    Map<String, double> precioMaxPorProd,
    AgrupacionInforme agrupacion,
  ) {
    final Map<String, GrupoInforme> mapa = {};

    for (final c in compras) {
      final (clave, etiqueta, orden) = _claveGrupo(c, agrupacion);
      final g = mapa.putIfAbsent(clave, () => GrupoInforme(etiqueta, orden));
      g.nCompras++;
      for (final l in c.lineas) {
        g.nLineas++;
        g.gastado += l.total;
        final max = precioMaxPorProd[l.productoId];
        final refUnit = (max != null && max > l.precioUnitario)
            ? max
            : l.precioUnitario;
        g.referencia += refUnit * l.cantidad;
      }
    }

    final lista = mapa.values.toList();
    if (agrupacion == AgrupacionInforme.mes ||
        agrupacion == AgrupacionInforme.semana) {
      lista.sort((a, b) =>
          (b.orden ?? DateTime(0)).compareTo(a.orden ?? DateTime(0)));
    } else {
      lista.sort((a, b) => b.gastado.compareTo(a.gastado));
    }
    return lista;
  }

  static (String, String, DateTime?) _claveGrupo(
      Compra c, AgrupacionInforme a) {
    switch (a) {
      case AgrupacionInforme.mes:
        final clave = '${c.fecha.year}-${c.fecha.month.toString().padLeft(2, '0')}';
        return (clave, clave, DateTime(c.fecha.year, c.fecha.month));
      case AgrupacionInforme.semana:
        final lunes = c.fecha.subtract(Duration(days: c.fecha.weekday - 1));
        final d = DateTime(lunes.year, lunes.month, lunes.day);
        final clave = '${d.year}-${d.month}-${d.day}';
        return (clave, 'Semana del ${d.day}/${d.month}', d);
      case AgrupacionInforme.evento:
        final ev = (c.evento == null || c.evento!.isEmpty)
            ? '(sin evento)'
            : c.evento!;
        return (ev, ev, null);
      case AgrupacionInforme.proveedor:
        return (c.proveedorId, c.proveedorNombre, null);
    }
  }
}

/// Como se agrupa el informe.
enum AgrupacionInforme { mes, semana, evento, proveedor }

/// Un grupo del informe (un mes, una semana, un evento o un proveedor).
class GrupoInforme {
  final String etiqueta;
  final DateTime? orden;
  double gastado = 0;
  double referencia = 0; // coste al mas caro
  int nLineas = 0;
  int nCompras = 0;

  GrupoInforme(this.etiqueta, this.orden);

  double get ahorro => referencia - gastado;
  double get ahorroPorcentaje =>
      referencia > 0 ? (ahorro / referencia) * 100 : 0;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
