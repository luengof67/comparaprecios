import 'package:cloud_firestore/cloud_firestore.dart';

/// Un proveedor al que le compras producto.
class Proveedor {
  final String id;
  final String nombre;
  final String? contacto; // telefono / whatsapp / email
  final String? notas;
  final int color; // color de identificacion en la UI (ARGB)

  Proveedor({
    required this.id,
    required this.nombre,
    this.contacto,
    this.notas,
    this.color = 0xFF1565C0,
  });

  factory Proveedor.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Proveedor(
      id: doc.id,
      nombre: d['nombre'] ?? '',
      contacto: d['contacto'],
      notas: d['notas'],
      color: d['color'] ?? 0xFF1565C0,
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'contacto': contacto,
        'notas': notas,
        'color': color,
        'actualizado': FieldValue.serverTimestamp(),
      };
}
