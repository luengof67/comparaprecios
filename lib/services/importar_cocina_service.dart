import 'dart:convert';

import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';
import 'firestore_service.dart';

/// Una línea de precio leída del JSON de "Compras Cocina", ya con el casado
/// hecho contra el catálogo de ComparaPrecios.
class LineaImport {
  final String producto; // nombre en el JSON
  final String categoria; // 'tipo' del JSON
  final String proveedorNombre;
  final double precio;
  final UnidadBase unidad;
  final DateTime fecha;

  // Casado (se puede editar en la revisión):
  String? productoId; // null = producto nuevo
  String? proveedorId; // null = proveedor nuevo
  bool importar; // marcado para importar
  bool duplicado; // ya existe ese producto+proveedor+fecha

  LineaImport({
    required this.producto,
    required this.categoria,
    required this.proveedorNombre,
    required this.precio,
    required this.unidad,
    required this.fecha,
    this.productoId,
    this.proveedorId,
    this.importar = true,
    this.duplicado = false,
  });
}

class ImportarCocinaService {
  /// Mapea la unidad de Compras Cocina a la unidad base de ComparaPrecios.
  static UnidadBase _unidad(String u) {
    switch (u.toLowerCase().trim()) {
      case 'kg':
        return UnidadBase.kg;
      case 'litro':
      case 'l':
        return UnidadBase.litro;
      default: // docena, pieza, caja, lata, unidad...
        return UnidadBase.unidad;
    }
  }

  static String _norm(String s) {
    var t = s.toLowerCase().trim();
    const ac = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u'};
    ac.forEach((k, v) => t = t.replaceAll(k, v));
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Lee el JSON y construye las líneas con el casado inicial.
  static List<LineaImport> parsear(
    String contenido,
    List<Producto> productos,
    List<Proveedor> proveedores,
    List<Precio> preciosExistentes,
  ) {
    final data = jsonDecode(contenido) as Map<String, dynamic>;
    final precios = (data['precios'] as List?) ?? const [];

    // Índices para casar por nombre.
    final prodPorNombre = {for (final p in productos) _norm(p.nombre): p};
    final provPorNombre = {for (final p in proveedores) _norm(p.nombre): p};

    // Firmas de precios existentes para detectar duplicados: prodId|provId|yyyy-mm-dd
    final firmas = <String>{};
    for (final pr in preciosExistentes) {
      firmas.add('${pr.productoId}|${pr.proveedorId}|${_fechaClave(pr.fecha)}');
    }

    final lineas = <LineaImport>[];
    for (final e in precios) {
      final m = Map<String, dynamic>.from(e);
      final nombreProd = (m['producto'] ?? '').toString();
      if (nombreProd.trim().isEmpty) continue;
      final nombreProv = (m['proveedor'] ?? '').toString();
      final precio = (m['precio'] as num?)?.toDouble() ?? 0;
      if (precio <= 0) continue;
      final fecha = _parseFecha(m['fecha']?.toString());

      final prod = prodPorNombre[_norm(nombreProd)];
      final prov = provPorNombre[_norm(nombreProv)];

      // ¿duplicado? Solo comprobable si ya existen producto y proveedor.
      bool dup = false;
      if (prod != null && prov != null) {
        dup = firmas
            .contains('${prod.id}|${prov.id}|${_fechaClave(fecha)}');
      }

      lineas.add(LineaImport(
        producto: nombreProd,
        categoria: (m['tipo'] ?? 'General').toString(),
        proveedorNombre: nombreProv,
        precio: precio,
        unidad: _unidad((m['unidad'] ?? 'kg').toString()),
        fecha: fecha,
        productoId: prod?.id,
        proveedorId: prov?.id,
        importar: !dup, // los duplicados se desmarcan por defecto
        duplicado: dup,
      ));
    }
    return lineas;
  }

  static String _fechaClave(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _parseFecha(String? s) {
    if (s == null || s.isEmpty) return DateTime.now();
    return DateTime.tryParse(s) ?? DateTime.now();
  }

  /// Ejecuta la importación de las líneas marcadas. Crea productos y proveedores
  /// que falten (por nombre) y añade los precios. Devuelve un resumen.
  static Future<ResumenImport> importar(
    FirestoreService db,
    List<LineaImport> lineas,
    List<Producto> productos,
    List<Proveedor> proveedores,
  ) async {
    // Caches de lo que vamos creando, por nombre normalizado.
    final prodId = {for (final p in productos) _norm(p.nombre): p.id};
    final prodUnidad = {for (final p in productos) _norm(p.nombre): p.unidadBase};
    final provId = {for (final p in proveedores) _norm(p.nombre): p.id};

    int nuevosProd = 0, nuevosProv = 0, preciosAdd = 0, omitidos = 0;

    for (final l in lineas) {
      if (!l.importar) {
        omitidos++;
        continue;
      }
      // Proveedor: usar el casado, o buscar por nombre, o crear.
      var pid = l.proveedorId;
      final provKey = _norm(l.proveedorNombre);
      if (pid == null) {
        pid = provId[provKey];
        if (pid == null && l.proveedorNombre.trim().isNotEmpty) {
          pid = await db.crearProveedorNombre(l.proveedorNombre);
          provId[provKey] = pid;
          nuevosProv++;
        }
      }
      if (pid == null) {
        omitidos++;
        continue;
      }

      // Producto: usar el casado, o buscar por nombre, o crear.
      var prid = l.productoId;
      final prodKey = _norm(l.producto);
      if (prid == null) {
        prid = prodId[prodKey];
        if (prid == null) {
          prid = await db.guardarProducto(Producto(
            id: '',
            nombre: l.producto,
            categoria: l.categoria,
            unidadBase: l.unidad,
          ));
          prodId[prodKey] = prid;
          prodUnidad[prodKey] = l.unidad;
          nuevosProd++;
        }
      }

      // Precio (el JSON da precio por unidad → cantidad 1).
      await db.registrarPrecio(Precio.nuevo(
        productoId: prid,
        proveedorId: pid,
        precioPaquete: l.precio,
        cantidad: 1,
        fecha: l.fecha,
        fuente: FuentePrecio.manual,
      ));
      preciosAdd++;
    }

    return ResumenImport(
      productosNuevos: nuevosProd,
      proveedoresNuevos: nuevosProv,
      preciosAnadidos: preciosAdd,
      omitidos: omitidos,
    );
  }
}

class ResumenImport {
  final int productosNuevos;
  final int proveedoresNuevos;
  final int preciosAnadidos;
  final int omitidos;
  ResumenImport({
    required this.productosNuevos,
    required this.proveedoresNuevos,
    required this.preciosAnadidos,
    required this.omitidos,
  });
}
