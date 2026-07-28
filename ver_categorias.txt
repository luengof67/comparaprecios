import 'package:flutter/material.dart';

/// Lista fija de categorias de producto.
const List<String> categorias = [
  'Verduras',
  'Carnes',
  'Pescados/Mariscos',
  'Congelados',
  'Almacén',
  'General',
];

/// Icono para una categoria (tolerante a variaciones de texto).
IconData iconoCategoria(String cat) {
  final c = cat.toLowerCase();
  if (c.contains('verdura') || c.contains('hortaliza')) return Icons.eco;
  if (c.contains('carne')) return Icons.kebab_dining;
  if (c.contains('pescado') || c.contains('marisco')) return Icons.set_meal;
  if (c.contains('congelad')) return Icons.ac_unit;
  if (c.contains('almac')) return Icons.warehouse;
  return Icons.category;
}

/// Color para una categoria.
Color colorCategoria(String cat) {
  final c = cat.toLowerCase();
  if (c.contains('verdura') || c.contains('hortaliza')) return const Color(0xFF2E7D32);
  if (c.contains('carne')) return const Color(0xFFC62828);
  if (c.contains('pescado') || c.contains('marisco')) return const Color(0xFF1565C0);
  if (c.contains('congelad')) return const Color(0xFF00838F);
  if (c.contains('almac')) return const Color(0xFF8D6E63);
  return const Color(0xFF757575);
}

/// Devuelve una categoria valida de la lista fija; si no coincide, 'General'.
String categoriaValida(String? cat) {
  if (cat == null) return 'General';
  return categorias.contains(cat) ? cat : 'General';
}
