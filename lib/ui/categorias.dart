import 'package:flutter/material.dart';

/// Categorias que se siembran en Firestore la primera vez que se abre la
/// pantalla de categorias, si la coleccion esta vacia. A partir de ahi la
/// lista de verdad vive en Firestore (coleccion "categorias"): esto es solo
/// la semilla inicial, para no arrancar de cero.
///
/// "General" se queda siempre al final como cajon de sastre: es el valor por
/// defecto de Producto cuando no se especifica categoria.
const List<String> categoriasIniciales = [
  'Almacén',
  'Carne fresca',
  'Carne congelada',
  'Pescado fresco',
  'Frutas y verduras frescas',
  'Verdura congelada',
  'Postres',
  'Buffet',
  'General',
];

/// Icono para una categoria (tolerante a variaciones de texto).
IconData iconoCategoria(String cat) {
  final c = cat.toLowerCase();
  if (c.contains('verdura') || c.contains('hortaliza') || c.contains('fruta')) {
    return c.contains('congelad') ? Icons.ac_unit : Icons.eco;
  }
  if (c.contains('carne')) {
    return c.contains('congelad') ? Icons.ac_unit : Icons.kebab_dining;
  }
  if (c.contains('pescado') || c.contains('marisco')) return Icons.set_meal;
  if (c.contains('congelad')) return Icons.ac_unit;
  if (c.contains('almac')) return Icons.warehouse;
  if (c.contains('postre')) return Icons.cake_outlined;
  if (c.contains('buffet')) return Icons.restaurant;
  return Icons.category;
}

/// Color para una categoria.
Color colorCategoria(String cat) {
  final c = cat.toLowerCase();
  if (c.contains('verdura') || c.contains('hortaliza') || c.contains('fruta')) {
    return c.contains('congelad')
        ? const Color(0xFF00838F)
        : const Color(0xFF2E7D32);
  }
  if (c.contains('carne')) {
    return c.contains('congelad')
        ? const Color(0xFF5E35B1)
        : const Color(0xFFC62828);
  }
  if (c.contains('pescado') || c.contains('marisco')) return const Color(0xFF1565C0);
  if (c.contains('congelad')) return const Color(0xFF00838F);
  if (c.contains('almac')) return const Color(0xFF8D6E63);
  if (c.contains('postre')) return const Color(0xFFEC407A);
  if (c.contains('buffet')) return const Color(0xFFF9A825);
  return const Color(0xFF757575);
}

/// Una categoria valida para mostrar: nunca vacia ni nula.
///
/// Ya no colapsa contra una lista fija -- las categorias viven en Firestore y
/// se pueden ampliar libremente en cualquier momento -- solo evita el hueco
/// de un valor ausente cuando un producto no tiene categoria puesta.
String categoriaValida(String? cat) {
  final t = cat?.trim() ?? '';
  return t.isEmpty ? 'General' : t;
}
