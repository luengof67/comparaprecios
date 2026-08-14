import 'dart:convert';

import '../models/compra.dart';
// Import directo: `unidadBase.nombre` es un extension getter de este archivo.
import '../models/producto.dart';
import '../models/proveedor.dart';
import 'casador_service.dart';
import 'firestore_service.dart';

/// Importa el JSON que exporta TRAZA desde Informes → "Exportar para
/// ComparaPrecios". Cada albarán se convierte en una COMPRA, y `registrarCompra`
/// se encarga de crear el precio por línea que alimenta las comparativas.
///
/// Hermano de ImportarCocinaService, no sustituto: aquel lee `{precios:[…]}`
/// plano y solo crea precios. Este lee albaranes con líneas y crea compras.

/// Una línea de albarán con su casado, pendiente de revisar.
class LineaTraza {
  final String textoAlbaran; // el nombre tal como venía en el papel
  final double cantidad; // en formato si lo hay, si no en unidad base
  final String formato; // "caja", "docena"… vacío = unidad base
  final double precio; // precio unitario leído (por formato o por unidad)
  final double importe; // total de la línea

  // Casado, editable en la revisión:
  String? productoId; // null = producto nuevo, se creará con este nombre
  String productoNombre; // nombre del producto casado (o el del albarán)
  UnidadBase unidad; // unidad base del producto casado (o la deducida)
  TipoCasado casado;
  bool aprenderAlias; // guardar textoAlbaran como alias de este proveedor
  bool importar;

  /// Cuántas unidades base tiene un formato ("caja de 6 kg" → 6).
  /// 0 = sin definir. Solo se usa cuando hay formato.
  double pesoFormato;

  LineaTraza({
    required this.textoAlbaran,
    required this.cantidad,
    required this.formato,
    required this.precio,
    required this.importe,
    this.productoId,
    required this.productoNombre,
    required this.unidad,
    required this.casado,
    this.aprenderAlias = false,
    this.importar = false,
    this.pesoFormato = 0,
  });

  bool get tieneFormato => formato.trim().isNotEmpty;

  /// Una línea con formato no puede entrar hasta saber cuánto pesa, porque
  /// `precioUnitario` de LineaCompra es SIEMPRE por unidad base. Meter
  /// 18 €/caja donde el producto está en €/kg ensucia todas las comparativas.
  bool get necesitaPeso => tieneFormato && pesoFormato <= 0;

  /// Cantidad expresada en la unidad base del producto.
  double get cantidadBase => tieneFormato ? cantidad * pesoFormato : cantidad;

  /// Precio por unidad base. Se prefiere el importe total de la línea, que es
  /// el dato real del albarán, y se cae al precio unitario si no viene.
  double get precioUnitario {
    final base = cantidadBase;
    if (base <= 0) return 0;
    if (importe > 0) return importe / base;
    if (!tieneFormato) return precio;
    return pesoFormato > 0 ? precio / pesoFormato : 0;
  }

  /// ¿Se puede registrar esta línea tal como está?
  bool get lista =>
      !necesitaPeso && cantidadBase > 0 && precioUnitario > 0;
}

/// Un albarán completo del JSON, con sus líneas.
class AlbaranTraza {
  final String clave; // "proveedor|albaran|fecha", estable entre escaneos
  final String proveedorNombre;
  final String albaran;
  final DateTime fecha;
  final double? totalPapel; // el total que decía el albarán, para contrastar
  final List<LineaTraza> lineas;

  String? proveedorId; // null = proveedor nuevo, se creará por nombre
  bool duplicado; // ya hay una compra con esta misma clave
  bool importar;

  AlbaranTraza({
    required this.clave,
    required this.proveedorNombre,
    required this.albaran,
    required this.fecha,
    required this.totalPapel,
    required this.lineas,
    this.proveedorId,
    this.duplicado = false,
    this.importar = true,
  });

  List<LineaTraza> get lineasListas =>
      lineas.where((l) => l.importar && l.lista).toList();

  double get total =>
      lineasListas.fold(0, (s, l) => s + l.cantidadBase * l.precioUnitario);

  int get pendientes => lineas.where((l) => !l.importar || !l.lista).length;
}

class ImportarTrazaService {
  static String _norm(String s) {
    var t = s.toLowerCase().trim();
    const acentos = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u'
    };
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '.').trim();
    return double.tryParse(s) ?? 0;
  }

  static DateTime _fecha(String? s) {
    if (s == null || s.isEmpty) return DateTime.now();
    return DateTime.tryParse(s) ?? DateTime.now();
  }

  /// Deduce cuánto pesa un formato a partir del texto del albarán
  /// ("TOMATE RAMA CAJA 6KG" → 6 si el producto va en kg).
  /// Devuelve 0 cuando no lo ve claro: es una propuesta, no una certeza.
  static double pesoDeTexto(String texto, String formato, UnidadBase unidad) {
    final t = '${texto.toLowerCase()} ${formato.toLowerCase()}';

    if (unidad == UnidadBase.unidad) {
      if (RegExp(r'\bdocenas?\b').hasMatch(t)) return 12;
      final ud = RegExp(r'(\d+)\s*(uds?|unidades?|piezas?)\b').firstMatch(t);
      if (ud != null) return _num(ud.group(1));
      return 0;
    }

    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kgs?|kg|grs?|gr|g|lts?|lt|l|ml|cl)\b')
        .firstMatch(t);
    if (m == null) return 0;
    final n = _num(m.group(1));
    final u = m.group(2)!;

    if (unidad == UnidadBase.kg) {
      if (u.startsWith('kg')) return n;
      if (u.startsWith('g')) return n / 1000;
      return 0; // una medida en litros no dice el peso
    }
    // litros
    if (u == 'l' || u.startsWith('lt')) return n;
    if (u == 'ml') return n / 1000;
    if (u == 'cl') return n / 100;
    return 0;
  }

  /// Lee el JSON de TRAZA y prepara los albaranes con el casado hecho.
  /// No escribe nada: todo pasa antes por la pantalla de revisión.
  static List<AlbaranTraza> parsear(
    String contenido,
    List<Producto> productos,
    List<Proveedor> proveedores,
    List<Compra> comprasExistentes,
  ) {
    final data = jsonDecode(contenido) as Map<String, dynamic>;
    final crudos = (data['albaranes'] as List?) ?? const [];

    final provPorNombre = {for (final p in proveedores) _norm(p.nombre): p};
    final yaImportados = comprasExistentes
        .map((c) => c.origenClave)
        .whereType<String>()
        .toSet();

    final salida = <AlbaranTraza>[];

    for (final e in crudos) {
      final a = Map<String, dynamic>.from(e);
      final provNombre = (a['proveedor'] ?? '').toString().trim();
      final fecha = _fecha((a['fecha'] ?? a['escaneado'])?.toString());
      final albaran = (a['albaran'] ?? '').toString().trim();

      // La clave la trae TRAZA; si faltara, se reconstruye igual que allí.
      final clave = (a['clave'] ?? '').toString().isNotEmpty
          ? a['clave'].toString()
          : '$provNombre|$albaran|${(a['fecha'] ?? '').toString()}';

      final prov = provPorNombre[_norm(provNombre)];
      final dup = yaImportados.contains(clave);

      final lineas = <LineaTraza>[];
      for (final x in (a['lineas'] as List?) ?? const []) {
        final l = Map<String, dynamic>.from(x);
        final texto = (l['producto'] ?? '').toString().trim();
        if (texto.isEmpty) continue;

        final casado = CasadorService.casar(texto, prov?.id, productos);
        final p = casado.producto;
        final unidad = p?.unidadBase ?? UnidadBase.kg;
        final formato = (l['formato'] ?? '').toString().trim();

        final linea = LineaTraza(
          textoAlbaran: texto,
          cantidad: _num(l['cantidad']),
          formato: formato,
          precio: _num(l['precio']),
          importe: _num(l['importe']),
          productoId: p?.id,
          productoNombre: p?.nombre ?? texto,
          unidad: unidad,
          casado: casado.tipo,
          // Solo se marcan solas las de alias exacto. El casado por parecido
          // acierta mucho, pero confunde "aceite oliva" con "aceite girasol",
          // y en un volcado de un mes eso no se ve venir.
          importar: casado.tipo == TipoCasado.automatico,
          aprenderAlias: casado.tipo != TipoCasado.automatico,
        );
        if (linea.tieneFormato) {
          linea.pesoFormato = pesoDeTexto(texto, formato, unidad);
        }
        lineas.add(linea);
      }

      salida.add(AlbaranTraza(
        clave: clave,
        proveedorNombre: provNombre,
        albaran: albaran,
        fecha: fecha,
        totalPapel: a['total'] == null ? null : _num(a['total']),
        lineas: lineas,
        proveedorId: prov?.id,
        duplicado: dup,
        importar: !dup,
      ));
    }

    salida.sort((a, b) => a.fecha.compareTo(b.fecha));
    return salida;
  }

  /// Registra las compras de los albaranes marcados. Una `registrarCompra` por
  /// albarán: lote atómico, y el precio por línea sale solo de ahí.
  static Future<ResumenTraza> importar(
    FirestoreService db,
    List<AlbaranTraza> albaranes,
    List<Producto> productos,
    List<Proveedor> proveedores,
  ) async {
    final provId = {for (final p in proveedores) _norm(p.nombre): p.id};
    final prodId = {for (final p in productos) _norm(p.nombre): p.id};
    final prodPorId = {for (final p in productos) p.id: p};

    int compras = 0, lineasOk = 0, lineasFuera = 0;
    int nuevosProd = 0, nuevosProv = 0, alias = 0;
    final saltados = <String>[];

    for (final alb in albaranes) {
      if (!alb.importar || alb.duplicado) continue;

      // Proveedor: el casado, o por nombre, o se crea.
      var pid = alb.proveedorId;
      final provKey = _norm(alb.proveedorNombre);
      if (pid == null || pid.isEmpty) {
        pid = provId[provKey];
        if (pid == null && alb.proveedorNombre.isNotEmpty) {
          pid = await db.crearProveedorNombre(alb.proveedorNombre);
          provId[provKey] = pid;
          nuevosProv++;
        }
      }
      if (pid == null) {
        saltados.add('${alb.albaran}: sin proveedor');
        continue;
      }

      final lineasCompra = <LineaCompra>[];

      for (final l in alb.lineas) {
        if (!l.importar || !l.lista) {
          lineasFuera++;
          continue;
        }

        // Producto: el casado, o por nombre, o se crea.
        var prid = l.productoId;
        final prodKey = _norm(l.productoNombre);
        if (prid == null || prid.isEmpty) {
          prid = prodId[prodKey];
          if (prid == null) {
            prid = await db.guardarProducto(Producto(
              id: '',
              nombre: l.productoNombre,
              categoria: 'General',
              unidadBase: l.unidad,
            ));
            prodId[prodKey] = prid;
            nuevosProd++;
          }
        }

        lineasCompra.add(LineaCompra(
          productoId: prid,
          productoNombre: l.productoNombre,
          unidad: l.unidad.nombre,
          cantidad: l.cantidadBase,
          precioUnitario: l.precioUnitario,
        ));
        lineasOk++;

        // El trabajo de casar a mano no se tira: se guarda como alias del
        // proveedor para que el próximo albarán entre solo.
        if (l.aprenderAlias) {
          final p = prodPorId[prid];
          if (p != null && await _aprenderAlias(db, p, l.textoAlbaran, pid)) {
            alias++;
          }
        }
      }

      if (lineasCompra.isEmpty) {
        saltados.add('${alb.albaran}: ninguna línea lista');
        continue;
      }

      await db.registrarCompra(Compra(
        id: '',
        proveedorId: pid,
        proveedorNombre: alb.proveedorNombre,
        fecha: alb.fecha,
        lineas: lineasCompra,
        origenClave: alb.clave,
      ));
      compras++;
    }

    return ResumenTraza(
      compras: compras,
      lineas: lineasOk,
      lineasFuera: lineasFuera,
      productosNuevos: nuevosProd,
      proveedoresNuevos: nuevosProv,
      aliasAprendidos: alias,
      saltados: saltados,
    );
  }

  /// Añade el texto del albarán a los alias del producto, si no estaba ya.
  /// Usa agregarAlias (arrayUnion): escribe solo ese campo, así que no puede
  /// pisar nada del producto ni lo que se haya añadido desde el otro PC.
  static Future<bool> _aprenderAlias(
    FirestoreService db,
    Producto p,
    String texto,
    String proveedorId,
  ) async {
    final t = texto.trim();
    if (t.isEmpty) return false;

    // arrayUnion solo evita duplicados exactos; comparamos normalizado para no
    // acumular el mismo nombre con otras mayúsculas o espacios.
    final existe = p.alias.any(
        (a) => _norm(a.texto) == _norm(t) && a.proveedorId == proveedorId);
    if (existe) return false;

    await db.agregarAlias(
      p.id,
      AliasProducto(texto: t, proveedorId: proveedorId),
    );
    return true;
  }
}

class ResumenTraza {
  final int compras;
  final int lineas;
  final int lineasFuera;
  final int productosNuevos;
  final int proveedoresNuevos;
  final int aliasAprendidos;
  final List<String> saltados;

  ResumenTraza({
    required this.compras,
    required this.lineas,
    required this.lineasFuera,
    required this.productosNuevos,
    required this.proveedoresNuevos,
    required this.aliasAprendidos,
    required this.saltados,
  });
}
