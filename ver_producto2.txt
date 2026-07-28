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

/// Un nombre alternativo con el que un proveedor concreto denomina el producto.
/// Ej: proveedor "Makro" lo llama "TOMATE PERA CAJA 6KG 1ª".
class AliasProducto {
  final String texto; // el nombre tal como aparece en el albarán
  final String? proveedorId; // de qué proveedor viene (null = general)

  AliasProducto({required this.texto, this.proveedorId});

  factory AliasProducto.fromMap(Map<String, dynamic> d) => AliasProducto(
        texto: (d['texto'] ?? '').toString(),
        proveedorId: d['proveedorId']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'texto': texto,
        'textoLower': texto.toLowerCase().trim(),
        'proveedorId': proveedorId,
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

  /// Si true, `cantidadSemana` está expresada en el FORMATO del proveedor
  /// (ej. 2 = 2 cajas), no en la unidad base. En ese caso no se puede calcular
  /// el coste hasta recibir el albarán.
  final bool pedirEnFormato;

  /// Nombre del formato elegido esta semana ("caja", "docena", "estuche"...).
  /// Solo tiene sentido si pedirEnFormato es true. Vacío = sin formato.
  final String formatoSemana;

  /// Cantidad que manda en la lista: la de semana si está puesta, si no la habitual.
  double get cantidadEfectiva =>
      cantidadSemana > 0 ? cantidadSemana : cantidadHabitual;

  /// ¿Entra este producto en la compra actual? Por defecto sí.
  /// Si se desmarca, en la lista aparece tachado y no cuenta en los totales.
  final bool enLista;

  /// Nombres alternativos con que los proveedores denominan este producto.
  /// Se usan para reconocer líneas de albarán automáticamente.
  final List<AliasProducto> alias;

  final String? notas;

  Producto({
    required this.id,
    required this.nombre,
    this.categoria = 'General',
    this.unidadBase = UnidadBase.kg,
    this.cantidadHabitual = 0,
    this.cantidadSemana = 0,
    this.pedirEnFormato = false,
    this.formatoSemana = '',
    this.enLista = true,
    this.alias = const [],
    this.notas,
  });

  factory Producto.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawAlias = (d['alias'] as List?) ?? const [];
    return Producto(
      id: doc.id,
      nombre: d['nombre'] ?? '',
      categoria: d['categoria'] ?? 'General',
      unidadBase: UnidadBaseX.fromString(d['unidadBase']),
      cantidadHabitual: (d['cantidadHabitual'] ?? 0).toDouble(),
      cantidadSemana: (d['cantidadSemana'] ?? 0).toDouble(),
      pedirEnFormato: d['pedirEnFormato'] ?? false,
      formatoSemana: (d['formatoSemana'] ?? '').toString(),
      enLista: d['enLista'] ?? true,
      alias: rawAlias
          .map((e) => AliasProducto.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
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
        'pedirEnFormato': pedirEnFormato,
        'formatoSemana': formatoSemana,
        'enLista': enLista,
        'alias': alias.map((a) => a.toMap()).toList(),
        'notas': notas,
        'actualizado': FieldValue.serverTimestamp(),
      };
}
