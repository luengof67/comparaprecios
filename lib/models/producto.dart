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

  /// Cantidad que sueles comprar de este producto (en la unidad base).
  /// Se usa para calcular el coste total y el ahorro real en la lista de compra.
  /// 0 = sin definir (retrocompatible con productos antiguos).
  final double cantidadHabitual;

  /// Cantidad ajustada solo para la compra de esta semana.
  /// 0 = no ajustada; en ese caso manda la habitual.
  final double cantidadSemana;

  /// Cantidad que manda en la lista: la de semana si está puesta, si no la habitual.
  double get cantidadEfectiva =>
      cantidadSemana > 0 ? cantidadSemana : cantidadHabitual;

  /// ¿Entra este producto en la compra actual? Por defecto sí.
  /// Si se desmarca, en la lista aparece tachado y no cuenta en los totales.
  final bool enLista;

  final String? notas;

  Producto({
    required this.id,
    required this.nombre,
    this.categoria = 'General',
    this.unidadBase = UnidadBase.kg,
    this.cantidadHabitual = 0,
    this.cantidadSemana = 0,
    this.enLista = true,
    this.notas,
  });

  factory Producto.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Producto(
      id: doc.id,
      nombre: d['nombre'] ?? '',
      categoria: d['categoria'] ?? 'General',
      unidadBase: UnidadBaseX.fromString(d['unidadBase']),
      cantidadHabitual: (d['cantidadHabitual'] ?? 0).toDouble(),
      cantidadSemana: (d['cantidadSemana'] ?? 0).toDouble(),
      enLista: d['enLista'] ?? true,
      notas: d['notas'],
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'nombreLower': nombre.toLowerCase(), // para buscar/ordenar
        'categoria': categoria,
        'unidadBase': unidadBase.name,
        'cantidadHabitual': cantidadHabitual,
        'cantidadSemana': cantidadSemana,
        'enLista': enLista,
        'notas': notas,
        'actualizado': FieldValue.serverTimestamp(),
      };
}
