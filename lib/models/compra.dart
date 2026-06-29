import 'package:cloud_firestore/cloud_firestore.dart';

/// Una linea dentro de una compra: un producto concreto, su cantidad
/// y el precio unitario PAGADO ese dia.
class LineaCompra {
  final String productoId;
  final String productoNombre; // guardado para mostrar el informe aunque cambie
  final String unidad;
  final double cantidad;
  final double precioUnitario; // lo pagado ese dia, por unidad base

  LineaCompra({
    required this.productoId,
    required this.productoNombre,
    required this.unidad,
    required this.cantidad,
    required this.precioUnitario,
  });

  double get total => cantidad * precioUnitario;

  factory LineaCompra.fromMap(Map<String, dynamic> d) => LineaCompra(
        productoId: d['productoId'] ?? '',
        productoNombre: d['productoNombre'] ?? '',
        unidad: d['unidad'] ?? 'ud',
        cantidad: (d['cantidad'] ?? 0).toDouble(),
        precioUnitario: (d['precioUnitario'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'productoId': productoId,
        'productoNombre': productoNombre,
        'unidad': unidad,
        'cantidad': cantidad,
        'precioUnitario': precioUnitario,
      };
}

/// Una compra registrada: a quien, que dia, con sus lineas.
/// Sirve para los informes temporales (ahorro por semana/mes/evento).
class Compra {
  final String id;
  final String proveedorId;
  final String proveedorNombre; // guardado para el informe
  final DateTime fecha;
  final List<LineaCompra> lineas;
  final String? evento; // opcional: "Banquete sabado", etc.

  Compra({
    required this.id,
    required this.proveedorId,
    required this.proveedorNombre,
    required this.fecha,
    required this.lineas,
    this.evento,
  });

  double get total => lineas.fold(0, (s, l) => s + l.total);

  factory Compra.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawLineas = (d['lineas'] as List?) ?? const [];
    return Compra(
      id: doc.id,
      proveedorId: d['proveedorId'] ?? '',
      proveedorNombre: d['proveedorNombre'] ?? '',
      fecha: (d['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lineas: rawLineas
          .map((e) => LineaCompra.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      evento: d['evento'],
    );
  }

  Map<String, dynamic> toMap() => {
        'proveedorId': proveedorId,
        'proveedorNombre': proveedorNombre,
        'fecha': Timestamp.fromDate(fecha),
        'lineas': lineas.map((l) => l.toMap()).toList(),
        'evento': evento,
        'total': total, // guardado para consultas/informes rapidos
        'creado': FieldValue.serverTimestamp(),
      };
}
