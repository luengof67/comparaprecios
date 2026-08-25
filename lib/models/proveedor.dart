import 'package:cloud_firestore/cloud_firestore.dart';

/// Un proveedor al que le compras producto.
class Proveedor {
  final String id;
  final String nombre;
  final String? contacto; // telefono / whatsapp / email
  final String? notas;
  final int color; // color de identificacion en la UI (ARGB)

  /// Nombres con los que este proveedor aparece escrito en los albaranes.
  ///
  /// El OCR de TRAZA lee el membrete distinto cada vez: el mismo Customar
  /// llega como "CUSTODIO MARTIN LOPEZ, S.L. (Customar Food Solutions)",
  /// "Customar (Custodio Martin Lopez S.L.)" o "Custodio Martin Lopez S.L.
  /// (Customar)". Sin esto, cada forma crea una ficha nueva.
  ///
  /// Se aprenden al elegir el proveedor durante una importacion.
  final List<String> alias;

  Proveedor({
    required this.id,
    required this.nombre,
    this.contacto,
    this.notas,
    this.color = 0xFF1565C0,
    this.alias = const [],
  });

  /// Normaliza para comparar: minusculas, sin acentos ni signos.
  static String norm(String s) {
    var t = s.toLowerCase().trim();
    const acentos = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
      'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
      'ñ': 'n', 'ü': 'u', 'ç': 'c',
    };
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// ¿Este texto de albarán corresponde a este proveedor?
  /// Vale tanto su nombre como cualquiera de los alias aprendidos.
  bool casaCon(String textoAlbaran) {
    final t = norm(textoAlbaran);
    if (t.isEmpty) return false;
    if (norm(nombre) == t) return true;
    return alias.any((a) => norm(a) == t);
  }

  /// ¿Ya está aprendido este nombre? Evita guardarlo dos veces.
  bool tieneAlias(String textoAlbaran) {
    final t = norm(textoAlbaran);
    if (norm(nombre) == t) return true; // el nombre propio no es un alias
    return alias.any((a) => norm(a) == t);
  }

  factory Proveedor.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Proveedor(
      id: doc.id,
      nombre: d['nombre'] ?? '',
      contacto: d['contacto'],
      notas: d['notas'],
      color: d['color'] ?? 0xFF1565C0,
      alias: ((d['alias'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// OJO: `alias` NO va aqui a proposito.
  ///
  /// Este mapa lo usa `guardarProveedor`, y el formulario de edicion construye
  /// el Proveedor solo con nombre, contacto y color. Si los alias viajaran en
  /// el mapa, cada vez que alguien tocara el nombre o el color desde la ficha
  /// se borrarian todos los alias aprendidos, sin avisar.
  ///
  /// Los alias se escriben solo con `agregarAliasProveedor`, que toca ese
  /// campo y nada mas.
  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'contacto': contacto,
        'notas': notas,
        'color': color,
        'actualizado': FieldValue.serverTimestamp(),
      };
}
