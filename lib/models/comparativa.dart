import 'precio.dart';
import 'producto.dart';
import 'proveedor.dart';

/// Precio actual (el mas reciente) de un proveedor concreto para un producto.
class OfertaProveedor {
  final Proveedor proveedor;
  final double precioUnitario;
  final DateTime fecha;

  /// Variacion respecto a la ultima compra a ese proveedor (fraccion).
  /// +0.10 = ha subido un 10%. null = sin referencia para comparar.
  final double? variacion;

  /// Formato de compra de este proveedor ("caja", "saco"...) y cuantas
  /// unidades base lleva (ej. caja = 6 kg). null = se pide en unidad base.
  final String? formato;
  final double formatoCantidad;

  OfertaProveedor({
    required this.proveedor,
    required this.precioUnitario,
    required this.fecha,
    this.variacion,
    this.formato,
    this.formatoCantidad = 0,
  });

  bool get tieneFormato =>
      formato != null && formato!.trim().isNotEmpty && formatoCantidad > 0;

  /// Cuantas unidades de formato (cajas) hacen falta para X unidades base,
  /// redondeando siempre a cajas enteras hacia arriba.
  int cajasPara(double cantidadBase) {
    if (!tieneFormato || cantidadBase <= 0) return 0;
    return (cantidadBase / formatoCantidad).ceil();
  }

  /// Unidades base reales que suponen N cajas.
  double baseDeCajas(int cajas) =>
      tieneFormato ? cajas * formatoCantidad : 0;
}

/// Resultado de comparar todos los proveedores para UN producto.
class ComparativaProducto {
  final Producto producto;
  final List<OfertaProveedor> ofertas; // ordenadas de mas barato a mas caro
  final List<Precio> historico; // todos los precios, para el grafico

  ComparativaProducto({
    required this.producto,
    required this.ofertas,
    required this.historico,
  });

  bool get tieneDatos => ofertas.isNotEmpty;

  OfertaProveedor? get masBarato => ofertas.isEmpty ? null : ofertas.first;
  OfertaProveedor? get masCaro => ofertas.isEmpty ? null : ofertas.last;

  double get precioMin => masBarato?.precioUnitario ?? 0;
  double get precioMax => masCaro?.precioUnitario ?? 0;

  /// Ahorro por unidad si compras al mas barato en vez de al mas caro.
  double get ahorroPorUnidad => precioMax - precioMin;

  /// Porcentaje de ahorro respecto al mas caro.
  double get ahorroPorcentaje =>
      precioMax > 0 ? (ahorroPorUnidad / precioMax) * 100 : 0;
}

/// Resumen global para el dashboard.
class ResumenDashboard {
  final int totalProductos;
  final int totalProveedores;
  final int productosConDatos;

  /// Suma del ahorro potencial por unidad de todos los productos
  /// (comprando cada uno a su proveedor mas barato).
  final double ahorroPotencialTotal;

  /// Proveedor que gana en mas productos (es el mas barato mas veces).
  final Proveedor? proveedorGanador;
  final int vecesGanador;

  ResumenDashboard({
    required this.totalProductos,
    required this.totalProveedores,
    required this.productosConDatos,
    required this.ahorroPotencialTotal,
    required this.proveedorGanador,
    required this.vecesGanador,
  });
}
