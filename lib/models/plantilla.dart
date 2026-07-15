import 'package:cloud_firestore/cloud_firestore.dart';

/// Una línea de plantilla: producto + cantidad + formato con el que se pide.
class LineaPlantilla {
  final String productoId;
  final double cantidad;
  final String formato; // '' = unidad base

  LineaPlantilla({
    required this.productoId,
    required this.cantidad,
    this.formato = '',
  });

  factory LineaPlantilla.fromMap(Map<String, dynamic> d) => LineaPlantilla(
        productoId: d['productoId'] ?? '',
        cantidad: (d['cantidad'] ?? 0).toDouble(),
        formato: (d['formato'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'productoId': productoId,
        'cantidad': cantidad,
        'formato': formato,
      };
}

/// Una lista guardada para reutilizar: "Pedido del martes",
/// "Pescado del viernes", "Básicos de semana"...
class PlantillaLista {
  final String id;
  final String nombre;
  final List<LineaPlantilla> lineas;

  PlantillaLista({
    required this.id,
    required this.nombre,
    required this.lineas,
  });

  factory PlantillaLista.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final raw = (d['lineas'] as List?) ?? const [];
    return PlantillaLista(
      id: doc.id,
      nombre: d['nombre'] ?? '',
      lineas: raw
          .map((e) => LineaPlantilla.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'lineas': lineas.map((l) => l.toMap()).toList(),
        'creado': FieldValue.serverTimestamp(),
      };
}
