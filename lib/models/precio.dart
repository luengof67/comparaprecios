import 'package:cloud_firestore/cloud_firestore.dart';

/// De donde viene el precio. Permite alimentar la misma coleccion
/// manualmente o, en el futuro, desde la importacion de albaranes.
enum FuentePrecio { manual, albaran }

/// Un registro de precio: "este producto, de este proveedor, costo X en esta fecha".
///
/// IMPORTANTE: no se sobrescribe. Cada vez que un precio cambia se crea un
/// registro nuevo. Asi:
///   - el "precio actual" de un proveedor = su registro mas reciente
///   - la evolucion del precio = todos los registros ordenados por fecha
class Precio {
  final String id;
  final String productoId;
  final String proveedorId;

  /// Lo que cuesta el formato comprado (ej. una caja de 5 kg = 12.50 €).
  final double precioPaquete;

  /// Cantidad del formato (ej. 5) en la unidad base del producto.
  final double cantidad;

  /// Precio normalizado por unidad base (€/kg, €/L, €/ud) = precioPaquete / cantidad.
  /// Es el numero con el que se comparan los proveedores entre si.
  final double precioUnitario;

  final DateTime fecha;
  final FuentePrecio fuente;
  final String? nota;

  Precio({
    required this.id,
    required this.productoId,
    required this.proveedorId,
    required this.precioPaquete,
    required this.cantidad,
    required this.precioUnitario,
    required this.fecha,
    this.fuente = FuentePrecio.manual,
    this.nota,
  });

  factory Precio.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Precio(
      id: doc.id,
      productoId: d['productoId'] ?? '',
      proveedorId: d['proveedorId'] ?? '',
      precioPaquete: (d['precioPaquete'] ?? 0).toDouble(),
      cantidad: (d['cantidad'] ?? 1).toDouble(),
      precioUnitario: (d['precioUnitario'] ?? 0).toDouble(),
      fecha: (d['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fuente: d['fuente'] == 'albaran' ? FuentePrecio.albaran : FuentePrecio.manual,
      nota: d['nota'],
    );
  }

  Map<String, dynamic> toMap() => {
        'productoId': productoId,
        'proveedorId': proveedorId,
        'precioPaquete': precioPaquete,
        'cantidad': cantidad,
        'precioUnitario': precioUnitario,
        'fecha': Timestamp.fromDate(fecha),
        'fuente': fuente.name,
        'nota': nota,
      };

  /// Helper para crear un registro calculando el precio unitario.
  static Precio nuevo({
    required String productoId,
    required String proveedorId,
    required double precioPaquete,
    required double cantidad,
    DateTime? fecha,
    FuentePrecio fuente = FuentePrecio.manual,
    String? nota,
  }) {
    final c = cantidad <= 0 ? 1.0 : cantidad;
    return Precio(
      id: '',
      productoId: productoId,
      proveedorId: proveedorId,
      precioPaquete: precioPaquete,
      cantidad: c,
      precioUnitario: precioPaquete / c,
      fecha: fecha ?? DateTime.now(),
      fuente: fuente,
      nota: nota,
    );
  }
}
