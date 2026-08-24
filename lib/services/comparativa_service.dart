import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';

/// Arma la tabla "producto x proveedor" con el ultimo precio conocido de cada
/// uno. No sabe nada de pantallas ni de PDFs: la pantalla de informes y el
/// informe impreso pintan los MISMOS datos calculados aqui, para que no puedan
/// desviarse el uno del otro.

/// El ultimo precio conocido de un producto en un proveedor.
class CeldaComparativa {
  final String proveedorId;
  final String proveedorNombre;
  final int proveedorColor;

  /// Precio por unidad base (€/kg, €/L, €/ud). Es el numero que se compara.
  final double precioUnitario;

  /// Lo que costaba el envase en el albaran ("24,00 € la caja").
  final double precioPaquete;

  /// Formato del proveedor ("caja", "saco"...) y cuantas unidades base trae.
  final String formato;
  final double cantidadFormato;

  final DateTime fecha;
  final FuentePrecio fuente;

  /// Dias que han pasado desde que se anoto este precio.
  final int dias;

  /// El precio es mas viejo que el plazo de vigencia: se enseña, pero no
  /// entra en la comparacion. Un dato de hace medio año puede parecer el mas
  /// barato solo porque nadie ha vuelto a anotar el de ese proveedor.
  final bool obsoleto;

  const CeldaComparativa({
    required this.proveedorId,
    required this.proveedorNombre,
    required this.proveedorColor,
    required this.precioUnitario,
    required this.precioPaquete,
    required this.formato,
    required this.cantidadFormato,
    required this.fecha,
    required this.fuente,
    required this.dias,
    required this.obsoleto,
  });

  bool get tieneFormato => formato.trim().isNotEmpty && cantidadFormato > 0;

  /// Linea pequeña bajo el precio unitario: "24,00 € · caja 6 kg".
  /// Sirve para reconocer el dato contra el albaran de papel sin echar cuentas.
  String descripcionFormato(UnidadBase base) {
    if (!tieneFormato) return '';
    final n = cantidadFormato == cantidadFormato.roundToDouble()
        ? cantidadFormato.toStringAsFixed(0)
        : cantidadFormato.toStringAsFixed(2);
    return '${precioPaquete.toStringAsFixed(2)} € · $formato $n ${base.nombre}';
  }
}

/// Un producto con el precio de cada proveedor que lo sirve.
class FilaComparativa {
  final Producto producto;

  /// Todas las celdas, ordenadas de mas barata a mas cara. Las obsoletas van
  /// al final, porque no compiten.
  final List<CeldaComparativa> celdas;

  FilaComparativa({required this.producto, required this.celdas});

  /// Solo las que entran en la comparacion.
  List<CeldaComparativa> get vigentes =>
      celdas.where((c) => !c.obsoleto).toList();

  /// Hace falta al menos un par de precios frescos para poder comparar.
  bool get comparable => vigentes.length >= 2;

  CeldaComparativa? get masBarato => vigentes.isEmpty ? null : vigentes.first;

  CeldaComparativa? get segundo =>
      vigentes.length >= 2 ? vigentes[1] : null;

  /// Cuanto se ahorra por unidad base comprandole al mas barato en vez de al
  /// siguiente. Se compara contra el segundo, no contra el mas caro: es la
  /// decision real, porque al mas caro no le ibas a comprar de todas formas.
  double get diferencia {
    final b = masBarato, s = segundo;
    if (b == null || s == null) return 0;
    return s.precioUnitario - b.precioUnitario;
  }

  double get diferenciaPorcentaje {
    final s = segundo;
    if (s == null || s.precioUnitario <= 0) return 0;
    return diferencia / s.precioUnitario * 100;
  }

  /// Ahorro en euros a la semana, usando la cantidad que sueles comprar.
  /// 0 si el producto no tiene cantidad puesta: sin eso, el porcentaje no se
  /// puede traducir a dinero.
  double get ahorroSemanal => diferencia * producto.cantidadEfectiva;

  /// El precio mas fresco de la fila, para saber como de al dia esta.
  int get diasDelMasReciente => celdas.isEmpty
      ? 0
      : celdas.map((c) => c.dias).reduce((a, b) => a < b ? a : b);
}

/// Un bloque de filas bajo el nombre de una categoria.
class GrupoComparativa {
  final String categoria;
  final List<FilaComparativa> filas;

  GrupoComparativa({required this.categoria, required this.filas});

  double get ahorroSemanal =>
      filas.fold(0, (s, f) => s + f.ahorroSemanal);
}

/// El informe entero, ya listo para pintar.
class Comparativa {
  /// Productos con dos o mas proveedores vigentes, agrupados por categoria.
  final List<GrupoComparativa> grupos;

  /// Productos con un solo proveedor (o con todos los precios caducados).
  /// No hay nada que comparar; van aparte para no llenar la tabla de filas
  /// con una sola celda.
  final List<FilaComparativa> sinComparar;

  final int diasVigencia;
  final DateTime generado;

  Comparativa({
    required this.grupos,
    required this.sinComparar,
    required this.diasVigencia,
    required this.generado,
  });

  int get productosComparados =>
      grupos.fold(0, (s, g) => s + g.filas.length);

  /// Lo que se ahorraria a la semana comprandole a los mas baratos.
  /// Solo cuenta productos con cantidad habitual puesta.
  double get ahorroSemanal => grupos.fold(0, (s, g) => s + g.ahorroSemanal);

  /// Productos que salen mas baratos en un proveedor pero cuya cantidad no
  /// esta definida: el ahorro real no se puede calcular hasta ponerla.
  int get sinCantidad => grupos
      .expand((g) => g.filas)
      .where((f) => f.producto.cantidadEfectiva <= 0 && f.diferencia > 0)
      .length;
}

class ComparativaService {
  /// Plazo por defecto tras el cual un precio deja de competir.
  static const int diasVigenciaPorDefecto = 60;

  /// Construye la comparativa a partir de lo que ya hay en memoria.
  ///
  /// [precios] son TODOS los registros; de cada pareja producto-proveedor se
  /// queda con el mas reciente, que es el "precio actual" de ese proveedor.
  static Comparativa construir({
    required List<Producto> productos,
    required List<Proveedor> proveedores,
    required List<Precio> precios,
    int diasVigencia = diasVigenciaPorDefecto,
    DateTime? hoy,
    String? categoria,
    String busqueda = '',
  }) {
    final ahora = hoy ?? DateTime.now();
    final prov = {for (final p in proveedores) p.id: p};

    // ultimo precio por producto|proveedor
    final ultimos = <String, Precio>{};
    for (final p in precios) {
      if (p.precioUnitario <= 0) continue;
      final k = '${p.productoId}|${p.proveedorId}';
      final actual = ultimos[k];
      if (actual == null || p.fecha.isAfter(actual.fecha)) {
        ultimos[k] = p;
      }
    }

    final porProducto = <String, List<Precio>>{};
    for (final e in ultimos.entries) {
      final productoId = e.key.split('|').first;
      porProducto.putIfAbsent(productoId, () => []).add(e.value);
    }

    final texto = busqueda.toLowerCase().trim();
    final comparables = <FilaComparativa>[];
    final sueltos = <FilaComparativa>[];

    for (final producto in productos) {
      if (categoria != null &&
          categoria.isNotEmpty &&
          producto.categoria != categoria) {
        continue;
      }
      if (texto.isNotEmpty &&
          !producto.nombre.toLowerCase().contains(texto)) {
        continue;
      }

      final suyos = porProducto[producto.id] ?? const <Precio>[];
      if (suyos.isEmpty) continue;

      final celdas = <CeldaComparativa>[];
      for (final p in suyos) {
        final dias = ahora.difference(p.fecha).inDays;
        final pr = prov[p.proveedorId];
        celdas.add(CeldaComparativa(
          proveedorId: p.proveedorId,
          proveedorNombre: pr?.nombre ?? 'Sin proveedor',
          proveedorColor: pr?.color ?? 0xFF1565C0,
          precioUnitario: p.precioUnitario,
          precioPaquete: p.precioPaquete,
          formato: p.formato ?? '',
          cantidadFormato: p.cantidad,
          fecha: p.fecha,
          fuente: p.fuente,
          dias: dias < 0 ? 0 : dias,
          obsoleto: dias > diasVigencia,
        ));
      }

      // Vigentes primero y de mas barato a mas caro; los caducados al final.
      celdas.sort((a, b) {
        if (a.obsoleto != b.obsoleto) return a.obsoleto ? 1 : -1;
        return a.precioUnitario.compareTo(b.precioUnitario);
      });

      final fila = FilaComparativa(producto: producto, celdas: celdas);
      (fila.comparable ? comparables : sueltos).add(fila);
    }

    // Agrupar por categoria, y dentro por ahorro: primero donde mas se gana.
    final porCategoria = <String, List<FilaComparativa>>{};
    for (final f in comparables) {
      porCategoria.putIfAbsent(f.producto.categoria, () => []).add(f);
    }

    final grupos = <GrupoComparativa>[];
    final nombres = porCategoria.keys.toList()..sort();
    for (final c in nombres) {
      final filas = porCategoria[c]!;
      filas.sort((a, b) {
        final porAhorro = b.ahorroSemanal.compareTo(a.ahorroSemanal);
        if (porAhorro != 0) return porAhorro;
        final porDif = b.diferenciaPorcentaje.compareTo(a.diferenciaPorcentaje);
        if (porDif != 0) return porDif;
        return a.producto.nombre
            .toLowerCase()
            .compareTo(b.producto.nombre.toLowerCase());
      });
      grupos.add(GrupoComparativa(categoria: c, filas: filas));
    }

    sueltos.sort((a, b) => a.producto.nombre
        .toLowerCase()
        .compareTo(b.producto.nombre.toLowerCase()));

    return Comparativa(
      grupos: grupos,
      sinComparar: sueltos,
      diasVigencia: diasVigencia,
      generado: ahora,
    );
  }

  /// Las categorias que tienen algun producto con precio, para el desplegable.
  static List<String> categoriasConPrecio(
    List<Producto> productos,
    List<Precio> precios,
  ) {
    final conPrecio = precios.map((p) => p.productoId).toSet();
    final cats = productos
        .where((p) => conPrecio.contains(p.id))
        .map((p) => p.categoria)
        .toSet()
        .toList()
      ..sort();
    return cats;
  }
}
