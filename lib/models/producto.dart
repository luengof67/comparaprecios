import 'package:cloud_firestore/cloud_firestore.dart';

/// Unidad base sobre la que se compara el precio (precio por kg, por litro, por ud).
enum UnidadBase { kg, litro, unidad }

extension UnidadBaseX on UnidadBase {
  String get etiqueta => switch (this) {
        UnidadBase.kg => '€/kg',
        UnidadBase.litro => '€/L',
        UnidadBase.unidad => '€/ud',
      };

  String get nombre => switch (this) {
        UnidadBase.kg => 'kg',
        UnidadBase.litro => 'L',
        UnidadBase.unidad => 'ud',
      };

  static UnidadBase fromString(String? s) => switch (s) {
        'litro' => UnidadBase.litro,
        'unidad' => UnidadBase.unidad,
        _ => UnidadBase.kg,
      };
}

/// Un producto que compras (ej. "Tomate pera", "Aceite de oliva virgen extra").
/// Tu lo creas una vez y le vas asociando precios de distintos proveedores.
class Producto {
  final String id;
  final String nombre;
  final String categoria; // ej. Verdura, Carne, Aceites...
  final UnidadBase unidadBase;
  final String? notas;

  Producto({
    required this.id,
    required this.nombre,
    this.categoria = 'General',
    this.unidadBase = UnidadBase.kg,
    this.notas,
  });

  factory Producto.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Producto(
      id: doc.id,
      nombre: d['nombre'] ?? '',
      categoria: d['categoria'] ?? 'General',
      unidadBase: UnidadBaseX.fromString(d['unidadBase']),
      notas: d['notas'],
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'nombreLower': nombre.toLowerCase(), // para buscar/ordenar
        'categoria': categoria,
        'unidadBase': unidadBase.name,
        'notas': notas,
        'actualizado': FieldValue.serverTimestamp(),
      };
}
