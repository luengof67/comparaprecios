import '../models/comparativa.dart';
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
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
