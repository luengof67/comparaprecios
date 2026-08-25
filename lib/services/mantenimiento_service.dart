import '../models/compra.dart';
import '../models/precio.dart';
import '../models/proveedor.dart';

/// Un proveedorId que aparece en precios o compras pero que ya no existe en la
/// coleccion de proveedores. Casi siempre es un proveedor borrado a mano: el
/// documento desaparecio, pero su historico sigue colgando de ese id.
///
/// Importa distinguir dos casos, porque la solucion es distinta:
///   - se borro porque estaba DUPLICADO -> hay que fusionar con el que quedo,
///     o se pierde la mitad del historico de precios de ese proveedor.
///   - se borro porque ya no se le compra -> se pueden tirar sus precios de
///     tarifa, pero NO sus precios de compra, que son el gasto real.
class ProveedorHuerfano {
  final String id;

  /// Nombre rescatado de las compras. Vacio si nunca se le registro una compra
  /// (solo tenia precios de tarifa), en cuyo caso el nombre se perdio.
  final String nombre;

  final int nPrecios;
  final int nCompras;

  /// Cuantos precios hay de cada tipo. Los de `compra` son historico de gasto.
  final Map<FuentePrecio, int> porFuente;

  /// Fecha del ultimo movimiento (precio o compra).
  final DateTime? ultimo;

  /// Lo que se le pago en total, sumando las compras registradas.
  final double gastoTotal;

  /// Productos distintos con precio de este proveedor.
  final int nProductos;

  const ProveedorHuerfano({
    required this.id,
    required this.nombre,
    required this.nPrecios,
    required this.nCompras,
    required this.porFuente,
    required this.ultimo,
    required this.gastoTotal,
    required this.nProductos,
  });

  /// Precios que son historico de compra: no conviene borrarlos, porque
  /// cambiarian los informes de gasto de esos meses.
  int get preciosDeCompra => porFuente[FuentePrecio.compra] ?? 0;

  /// Precios de tarifa (manuales o de albaran suelto). Estos si se pueden
  /// tirar sin tocar el gasto historico.
  int get preciosDeTarifa => nPrecios - preciosDeCompra;

  /// Sin nombre no hay forma de saber quien era: solo quedan los numeros.
  bool get nombreRecuperable => nombre.trim().isNotEmpty;

  String get etiqueta =>
      nombreRecuperable ? nombre : 'Desconocido (${id.substring(0, 6)}…)';
}

/// Un proveedor vivo que podria ser el mismo que un huerfano.
class CandidatoFusion {
  final Proveedor proveedor;

  /// 0 a 1. Cuanto se parecen los nombres.
  final double parecido;

  /// Precios que quedarian duplicados al fusionar: mismo producto y mismo dia
  /// en los dos. No rompen nada, pero dejan dos registros compitiendo y la
  /// comparativa se queda con uno de los dos sin criterio claro.
  final int colisiones;

  const CandidatoFusion({
    required this.proveedor,
    required this.parecido,
    required this.colisiones,
  });
}

class MantenimientoService {
  static String _norm(String s) {
    var t = s.toLowerCase().trim();
    const acentos = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u'
    };
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Palabras que no distinguen a un proveedor de otro: si "Frutas Paco SL" y
  /// "Frutas Paco" solo se diferencian en esto, es el mismo.
  /// Formas juridicas y articulos: no distinguen a un proveedor de otro.
  static const _ruido = {
    'sl', 'sa', 'slu', 'scp', 'cb', 'sll', 'srl',
    'e', 'hijos', 'hijo', 'hnos', 'hermanos', 'y', 'de', 'del',
    'la', 'el', 'los', 'las',
    'soc', 'sdad', 'sociedad', 'limitada', 'anonima', 'unipersonal',
    'cif', 'nif',
  };

  /// Palabras de sector o de zona. Distinguen poco: "Frutas Sur" y
  /// "Carnicas Sur" comparten "sur" y no tienen nada que ver. Pesan menos y
  /// por si solas no bastan para proponer una fusion.
  static const _flojas = {
    'frutas', 'fruta', 'verduras', 'verdura', 'carnicas', 'carnes', 'carne',
    'pescados', 'pescado', 'panaderia', 'aceites', 'aceite', 'bebidas',
    'lacteos', 'congelados', 'alimentacion', 'distribuciones', 'distribucion',
    'suministros', 'comercial', 'grupo',
    'sur', 'norte', 'este', 'oeste', 'levante', 'central', 'centro',
    'iberica', 'espanola',
  };

  static double _peso(String p) => _flojas.contains(p) ? 0.4 : 1.0;

  /// Parte el nombre en palabras con contenido.
  ///
  /// Se tiran las de una sola letra: vienen de los puntos de las siglas
  /// ("serrano s.l" -> "serrano s l") y emparejaban con cualquier otra
  /// sociedad limitada, que no dice absolutamente nada.
  static Set<String> _palabras(String s) => _norm(s)
      .split(' ')
      .where((p) => p.length > 1 && !_ruido.contains(p))
      .toSet();

  /// Cuanto se parecen dos nombres, de 0 a 1. Compara las palabras que llevan
  /// informacion, ignorando formas juridicas y muletillas, y dando menos peso
  /// a las de sector o zona.
  static double parecido(String a, String b) {
    final pa = _palabras(a), pb = _palabras(b);
    if (pa.isEmpty || pb.isEmpty) return 0;
    final comunes = pa.intersection(pb);
    if (comunes.isEmpty) return 0;

    final wa = pa.fold<double>(0, (s, p) => s + _peso(p));
    final wb = pb.fold<double>(0, (s, p) => s + _peso(p));
    final wc = comunes.fold<double>(0, (s, p) => s + _peso(p));
    // Proporcion sobre el nombre mas corto: "Paco" dentro de "Frutas Paco SL"
    // sigue siendo una coincidencia fuerte.
    final s = wc / (wa < wb ? wa : wb);

    // Si lo unico que comparten son palabras de sector o zona, solo cuenta
    // cuando cubren el nombre corto entero ("Frutas Sur" vs "Frutas Sur SL").
    final hayDistintiva = comunes.any((p) => !_flojas.contains(p));
    if (!hayDistintiva && s < 0.999) return 0;

    return s;
  }

  /// Busca los proveedorId que quedaron sin documento.
  static List<ProveedorHuerfano> huerfanos({
    required List<Proveedor> proveedores,
    required List<Precio> precios,
    required List<Compra> compras,
  }) {
    final vivos = proveedores.map((p) => p.id).toSet();

    final ids = <String>{};
    for (final p in precios) {
      if (p.proveedorId.isNotEmpty && !vivos.contains(p.proveedorId)) {
        ids.add(p.proveedorId);
      }
    }
    for (final c in compras) {
      if (c.proveedorId.isNotEmpty && !vivos.contains(c.proveedorId)) {
        ids.add(c.proveedorId);
      }
    }
    if (ids.isEmpty) return const [];

    final salida = <ProveedorHuerfano>[];
    for (final id in ids) {
      final susPrecios = precios.where((p) => p.proveedorId == id).toList();
      final susCompras = compras.where((c) => c.proveedorId == id).toList();

      // El nombre solo sobrevive en las compras; los precios no lo guardan.
      var nombre = '';
      for (final c in susCompras) {
        if (c.proveedorNombre.trim().isNotEmpty) {
          nombre = c.proveedorNombre.trim();
          break;
        }
      }

      final porFuente = <FuentePrecio, int>{};
      for (final p in susPrecios) {
        porFuente.update(p.fuente, (v) => v + 1, ifAbsent: () => 1);
      }

      DateTime? ultimo;
      for (final p in susPrecios) {
        if (ultimo == null || p.fecha.isAfter(ultimo)) ultimo = p.fecha;
      }
      for (final c in susCompras) {
        if (ultimo == null || c.fecha.isAfter(ultimo)) ultimo = c.fecha;
      }

      salida.add(ProveedorHuerfano(
        id: id,
        nombre: nombre,
        nPrecios: susPrecios.length,
        nCompras: susCompras.length,
        porFuente: porFuente,
        ultimo: ultimo,
        gastoTotal: susCompras.fold(0, (s, c) => s + c.total),
        nProductos: susPrecios.map((p) => p.productoId).toSet().length,
      ));
    }

    // Primero los que mas historico arrastran: son los que mas urge resolver.
    salida.sort((a, b) {
      final porPrecios = b.nPrecios.compareTo(a.nPrecios);
      if (porPrecios != 0) return porPrecios;
      return b.nCompras.compareTo(a.nCompras);
    });
    return salida;
  }

  /// Proveedores vivos que podrian ser el mismo que este huerfano, ordenados
  /// por parecido. Si el huerfano no conserva el nombre no se puede proponer
  /// nada: la lista sale vacia y hay que elegir a mano.
  static List<CandidatoFusion> candidatos({
    required ProveedorHuerfano huerfano,
    required List<Proveedor> proveedores,
    required List<Precio> precios,
    double minimo = 0.5,
  }) {
    if (!huerfano.nombreRecuperable) return const [];

    final salida = <CandidatoFusion>[];
    for (final p in proveedores) {
      final s = parecido(huerfano.nombre, p.nombre);
      if (s < minimo) continue;
      salida.add(CandidatoFusion(
        proveedor: p,
        parecido: s,
        colisiones: colisiones(huerfano.id, p.id, precios),
      ));
    }
    salida.sort((a, b) => b.parecido.compareTo(a.parecido));
    return salida;
  }

  /// Cuantos precios quedarian duplicados al fusionar [idHuerfano] dentro de
  /// [idVivo]: mismo producto y mismo dia en los dos.
  static int colisiones(
      String idHuerfano, String idVivo, List<Precio> precios) {
    String clave(Precio p) =>
        '${p.productoId}|${p.fecha.year}-${p.fecha.month}-${p.fecha.day}';

    final delVivo = precios
        .where((p) => p.proveedorId == idVivo)
        .map(clave)
        .toSet();

    return precios
        .where((p) => p.proveedorId == idHuerfano && delVivo.contains(clave(p)))
        .length;
  }
}
