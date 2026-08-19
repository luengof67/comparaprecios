import 'dart:convert';

import '../models/compra.dart';
// Import directo: `unidadBase.nombre` es un extension getter de este archivo.
import '../models/producto.dart';
import '../models/proveedor.dart';
import '../utils/formato_parser.dart';
import 'casador_service.dart';
import 'firestore_service.dart';

/// Importa el JSON que exporta TRAZA desde Informes → "Exportar para
/// ComparaPrecios". Cada albarán se convierte en una COMPRA, y `registrarCompra`
/// se encarga de crear el precio por línea que alimenta las comparativas.
///
/// Hermano de ImportarCocinaService, no sustituto: aquel lee `{precios:[…]}`
/// plano y solo crea precios. Este lee albaranes con líneas y crea compras.

/// De dónde ha salido el factor de conversión de una línea.
enum OrigenFactor {
  /// El formato ya es la unidad base ("KG", "L", "UD"): factor 1, nada que hacer.
  unidadBase,

  /// Estaba aprendido en el alias de ese proveedor. No se pregunta.
  alias,

  /// Deducido del texto del albarán. Es una propuesta: hay que confirmarla.
  propuesto,

  /// El formato es de otra familia que el producto (formato "L" en un producto
  /// que se compara por kg). Casi siempre significa que el casado está mal.
  incompatible,

  /// No se ha podido deducir. Hay que teclearlo una vez.
  desconocido,
}

/// Una línea de albarán con su casado, pendiente de revisar.
class LineaTraza {
  final String textoAlbaran; // el nombre tal como venía en el papel
  final double cantidad; // en formato si lo hay, si no en unidad base
  final String formato; // "caja", "docena"… vacío = unidad base
  final double precio; // precio unitario leído (por formato o por unidad)
  final double importe; // total de la línea

  /// El campo `formato` es en realidad la unidad base ("KG", "L", "UD").
  /// En ese caso la cantidad ya viene en unidad base y no hay que convertir:
  /// es el caso del género de peso variable (carne, pescado).
  final bool formatoEsBase;

  // Casado, editable en la revisión:
  String? productoId; // null = producto nuevo, se creará con este nombre
  String productoNombre; // nombre del producto casado (o el del albarán)
  UnidadBase unidad; // unidad base del producto casado (o la deducida)
  TipoCasado casado;
  bool aprenderAlias; // guardar textoAlbaran como alias de este proveedor
  bool importar;

  /// Cuántas unidades base tiene un formato ("caja de 6 kg" → 6).
  /// 0 = sin definir. Solo se usa cuando hay formato de verdad.
  double pesoFormato;

  /// De dónde salió `pesoFormato`. La pantalla lo usa para saber si enseñar
  /// la casilla en rojo (hay que teclearlo) o en gris (ya viene propuesto).
  OrigenFactor origenFactor;

  LineaTraza({
    required this.textoAlbaran,
    required this.cantidad,
    required this.formato,
    required this.precio,
    required this.importe,
    this.formatoEsBase = false,
    this.productoId,
    required this.productoNombre,
    required this.unidad,
    required this.casado,
    this.aprenderAlias = false,
    this.importar = false,
    this.pesoFormato = 0,
    this.origenFactor = OrigenFactor.desconocido,
  });

  /// Hay formato de verdad (un envase) cuando el campo viene relleno Y no es
  /// la propia unidad base. "CAJA" sí; "KG" no.
  bool get tieneFormato => formato.trim().isNotEmpty && !formatoEsBase;

  /// Una línea con formato no puede entrar hasta saber cuánto pesa, porque
  /// `precioUnitario` de LineaCompra es SIEMPRE por unidad base. Meter
  /// 18 €/caja donde el producto está en €/kg ensucia todas las comparativas.
  bool get necesitaPeso => tieneFormato && pesoFormato <= 0;

  /// El factor es una propuesta sin confirmar: conviene que se vea distinto.
  bool get factorPropuesto => origenFactor == OrigenFactor.propuesto;

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

  /// Precio tal como venía en el papel, para enseñarlo en pequeño debajo del
  /// unitario: "24,00 € · caja 6 kg". Así se reconoce contra el albarán.
  String descripcionOrigen() {
    if (!tieneFormato) return '';
    final n = pesoFormato == pesoFormato.roundToDouble()
        ? pesoFormato.toStringAsFixed(0)
        : pesoFormato.toStringAsFixed(2);
    if (pesoFormato <= 0) return formato;
    return '$formato $n ${unidad.nombre}';
  }

  /// La aritmética del albarán no cuadra: cantidad x precio no da el importe.
  /// No dice nada del formato (esa cuenta se cumple igual en cajas que en
  /// kilos), pero sí delata un número mal leído por el OCR.
  bool get aritmeticaRara =>
      importe > 0 &&
      cantidad > 0 &&
      precio > 0 &&
      !FormatoParser.cuadraLinea(cantidad, precio, importe);

  /// ¿Se puede registrar esta línea tal como está?
  bool get lista => !necesitaPeso && cantidadBase > 0 && precioUnitario > 0;
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

  /// Líneas que traen un factor solo propuesto: conviene repasarlas.
  int get porConfirmar => lineas.where((l) => l.factorPropuesto).length;
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

  /// Si el campo `formato` del albarán es en realidad una unidad base
  /// ("KG", "L", "UD"), devuelve cuál. Si es un envase ("CAJA"), null.
  static UnidadBase? formatoComoUnidadBase(String formato) {
    final f = _norm(formato);
    const kg = ['kg', 'kgs', 'k', 'kilo', 'kilos', 'kilogramo', 'kilogramos'];
    const l = ['l', 'lt', 'ltr', 'litro', 'litros'];
    const u = [
      'ud', 'uds', 'u', 'unidad', 'unidades', 'pza', 'pzas', 'pieza', 'piezas'
    ];
    if (kg.contains(f)) return UnidadBase.kg;
    if (l.contains(f)) return UnidadBase.litro;
    if (u.contains(f)) return UnidadBase.unidad;
    return null;
  }

  /// Deduce cuánto pesa un formato a partir del texto del albarán
  /// ("TOMATE RAMA CAJA 6KG" → 6 si el producto va en kg).
  /// Devuelve 0 cuando no lo ve claro: es una propuesta, no una certeza.
  /// Se conserva el nombre porque lo usa la pantalla de revisión; por dentro
  /// ya trabaja FormatoParser, que reconoce muchos más casos.
  static double pesoDeTexto(String texto, String formato, UnidadBase unidad) {
    final d = FormatoParser.detectar('$texto $formato', unidad);
    return d?.factor ?? 0;
  }

  /// Decide el factor de una línea, por orden de fiabilidad:
  ///   1. el formato ya es la unidad base  -> 1
  ///   2. está aprendido en el alias        -> ese, sin preguntar
  ///   3. se deduce del texto               -> propuesta a confirmar
  ///   4. nada                              -> preguntar una vez
  static void _resolverFactor(
    LineaTraza linea,
    Producto? producto,
    String? proveedorId,
  ) {
    if (!linea.tieneFormato) {
      linea.pesoFormato = 1;
      linea.origenFactor = OrigenFactor.unidadBase;
      return;
    }

    // El formato es de otra familia que el producto: no se convierte nada.
    final comoBase = formatoComoUnidadBase(linea.formato);
    if (comoBase != null && comoBase != linea.unidad) {
      linea.pesoFormato = 0;
      linea.origenFactor = OrigenFactor.incompatible;
      return;
    }

    final alias =
        producto?.aliasPara(linea.textoAlbaran, proveedorId: proveedorId);
    if (alias != null && alias.tieneFactor) {
      linea.pesoFormato = alias.factor;
      linea.origenFactor = OrigenFactor.alias;
      return;
    }

    final d = FormatoParser.detectar(
        '${linea.textoAlbaran} ${linea.formato}', linea.unidad);
    if (d != null && d.factor > 0) {
      linea.pesoFormato = d.factor;
      linea.origenFactor = OrigenFactor.propuesto;
      return;
    }

    linea.pesoFormato = 0;
    linea.origenFactor = OrigenFactor.desconocido;
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

        // Un formato que ES la unidad base del producto no es un envase:
        // la cantidad ya viene en kilos o litros y no hay que convertir.
        final comoBase = formatoComoUnidadBase(formato);
        final esBase = comoBase != null && comoBase == unidad;

        final linea = LineaTraza(
          textoAlbaran: texto,
          cantidad: _num(l['cantidad']),
          formato: formato,
          precio: _num(l['precio']),
          importe: _num(l['importe']),
          formatoEsBase: esBase,
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
        _resolverFactor(linea, p, prov?.id);
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
        // proveedor para que el próximo albarán entre solo. Y con él va el
        // factor, que es lo que evita volver a teclear el peso de la caja.
        if (await _aprenderAlias(db, prodPorId[prid], prid, l, pid)) {
          alias++;
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

  /// Guarda el texto del albarán como alias del producto para ese proveedor,
  /// junto con el formato y su factor.
  ///
  /// Se escribe en dos situaciones: cuando el alias es nuevo, y cuando ya
  /// existía pero sin factor (o con otro distinto), que es como se corrige un
  /// peso de caja mal puesto. `agregarAlias` sustituye en vez de duplicar.
  static Future<bool> _aprenderAlias(
    FirestoreService db,
    Producto? p,
    String productoId,
    LineaTraza l,
    String proveedorId,
  ) async {
    final t = l.textoAlbaran.trim();
    if (t.isEmpty) return false;

    final formato = l.tieneFormato ? l.formato.trim() : '';
    final factor = l.tieneFormato ? l.pesoFormato : 0.0;

    // Producto recién creado en esta misma importación: no hay alias previo.
    if (p == null) {
      if (!l.aprenderAlias && formato.isEmpty) return false;
      await db.agregarAlias(
        productoId,
        AliasProducto(
          texto: t,
          proveedorId: proveedorId,
          formato: formato,
          factor: factor,
        ),
      );
      return true;
    }

    final actual = p.aliasPara(t, proveedorId: proveedorId);
    final existe = actual != null && actual.proveedorId == proveedorId;
    final mismoFactor = existe && (actual.factor - factor).abs() < 0.0001;

    // Ni es nuevo ni cambia el factor: no hay nada que escribir.
    if (existe && mismoFactor) return false;
    if (!existe && !l.aprenderAlias && formato.isEmpty) return false;

    await db.agregarAlias(
      productoId,
      AliasProducto(
        texto: t,
        proveedorId: proveedorId,
        formato: formato,
        factor: factor,
      ),
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
