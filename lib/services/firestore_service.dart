import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/compra.dart';
import '../models/plantilla.dart';
import '../models/precio.dart';
import '../models/producto.dart';
import '../models/proveedor.dart';

/// Acceso a Firestore. Tres colecciones:
///   proveedores/{id}
///   productos/{id}
///   precios/{id}   (registros historicos)
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _proveedores => _db.collection('proveedores');
  CollectionReference get _productos => _db.collection('productos');
  CollectionReference get _precios => _db.collection('precios');

  // ---- PROVEEDORES ----
  Stream<List<Proveedor>> proveedores() => _proveedores
      .orderBy('nombre')
      .snapshots()
      .map((s) => s.docs.map(Proveedor.fromDoc).toList());

  Future<void> guardarProveedor(Proveedor p) async {
    if (p.id.isEmpty) {
      await _proveedores.add(p.toMap());
    } else {
      await _proveedores.doc(p.id).set(p.toMap(), SetOptions(merge: true));
    }
  }

  /// Aprende como aparece escrito un proveedor en los albaranes.
  ///
  /// El OCR lee el membrete distinto cada vez, asi que sin esto cada forma
  /// crea una ficha nueva. Al elegir el proveedor una vez, ese texto queda
  /// asociado y la proxima importacion lo reconoce solo.
  ///
  /// Se lee y se escribe la lista entera en vez de usar arrayUnion, para
  /// poder comparar normalizado y no acumular el mismo nombre con otras
  /// mayusculas o espacios. Va en transaccion por los dos PCs.
  Future<bool> agregarAliasProveedor(String proveedorId, String texto) async {
    final t = texto.trim();
    if (t.isEmpty) return false;

    final ref = _proveedores.doc(proveedorId);
    final snap = await ref.get();
    final d = snap.data() as Map<String, dynamic>?;
    if (d == null) return false;

    final nombre = (d['nombre'] ?? '').toString();
    final lista = ((d['alias'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    final buscado = Proveedor.norm(t);
    // El nombre propio no hace falta guardarlo como alias.
    if (Proveedor.norm(nombre) == buscado) return false;
    if (lista.any((a) => Proveedor.norm(a) == buscado)) return false;

    lista.add(t);
    await ref.update({'alias': lista});
    return true;
  }

  Future<void> borrarProveedor(String id) => _proveedores.doc(id).delete();

  /// Crea (o restaura) un proveedor con un id CONCRETO, en vez de dejar que
  /// Firestore invente uno. Sirve para recuperar un proveedor borrado sin
  /// perder su historico: si vuelve con el mismo id, sus precios y compras
  /// vuelven a colgar de el solos.
  Future<void> crearProveedorConId(String id, Proveedor p) =>
      _proveedores.doc(id).set(p.toMap(), SetOptions(merge: true));

  /// Escribe [datos] en muchos documentos, partiendo en lotes.
  /// Firestore no admite mas de 500 escrituras por lote; se usa 400 de margen.
  Future<int> _escribirPorLotes(
    List<QueryDocumentSnapshot> docs,
    Map<String, dynamic>? datos,
  ) async {
    var hechos = 0;
    for (var i = 0; i < docs.length; i += 400) {
      final fin = (i + 400) < docs.length ? i + 400 : docs.length;
      final batch = _db.batch();
      for (final d in docs.sublist(i, fin)) {
        if (datos == null) {
          batch.delete(d.reference);
        } else {
          batch.update(d.reference, datos);
        }
      }
      await batch.commit();
      hechos += fin - i;
    }
    return hechos;
  }

  /// Pasa TODO el historico de un proveedor a otro: precios y compras.
  ///
  /// Es lo que hay que hacer cuando el mismo proveedor quedo partido en dos
  /// fichas por un duplicado. Devuelve cuantos documentos se han movido.
  ///
  /// OJO: no se puede deshacer con un boton. Una vez reapuntados, los
  /// documentos no guardan de donde venian.
  Future<({int precios, int compras})> reasignarProveedor({
    required String de,
    required String a,
    required String nombreDestino,
  }) async {
    final pre = await _precios.where('proveedorId', isEqualTo: de).get();
    final nPre = await _escribirPorLotes(pre.docs, {'proveedorId': a});

    // En las compras va tambien el nombre, que se guarda por duplicado para
    // que el historico siga leyendose aunque el proveedor desaparezca.
    final com = await _compras.where('proveedorId', isEqualTo: de).get();
    final nCom = await _escribirPorLotes(
        com.docs, {'proveedorId': a, 'proveedorNombre': nombreDestino});

    return (precios: nPre, compras: nCom);
  }

  /// Fusiona dos proveedores que EXISTEN los dos: mueve todo el historico
  /// de [de] a [a] y despues borra la ficha de [de].
  ///
  /// Es lo que hace falta cuando el mismo proveedor real quedo con dos fichas
  /// (mismo nombre escrito de dos formas). A diferencia de reasignar un id
  /// huerfano, aqui hay una ficha de sobra que hay que quitar de en medio.
  ///
  /// El borrado va al final a proposito: si algo falla moviendo el historico,
  /// la ficha origen sigue ahi y no se pierde el rastro de a quien pertenecia.
  ///
  /// OJO: no se puede deshacer.
  Future<({int precios, int compras})> fusionarProveedores({
    required String de,
    required String a,
    required String nombreDestino,
  }) async {
    if (de == a) {
      throw ArgumentError('No se puede fusionar un proveedor consigo mismo.');
    }

    final r = await reasignarProveedor(
      de: de,
      a: a,
      nombreDestino: nombreDestino,
    );

    await _proveedores.doc(de).delete();
    return r;
  }

  /// Borra los precios de un proveedor. Con [soloTarifa] en true respeta los
  /// que salieron de una compra, que son el gasto real y cambiarian los
  /// informes de esos meses.
  Future<int> borrarPreciosDeProveedor(String proveedorId,
      {bool soloTarifa = true}) async {
    final s = await _precios.where('proveedorId', isEqualTo: proveedorId).get();
    final docs = soloTarifa
        ? s.docs.where((d) {
            final m = d.data() as Map<String, dynamic>;
            return m['fuente'] != 'compra';
          }).toList()
        : s.docs;
    return _escribirPorLotes(docs, null);
  }

  /// Crea un proveedor con solo el nombre y devuelve su id (para importaciones).
  Future<String> crearProveedorNombre(String nombre) async {
    final ref = await _proveedores.add(Proveedor(id: '', nombre: nombre).toMap());
    return ref.id;
  }

  // ---- PRODUCTOS ----
  Stream<List<Producto>> productos() => _productos
      .orderBy('nombreLower')
      .snapshots()
      .map((s) => s.docs.map(Producto.fromDoc).toList());

  Future<String> guardarProducto(Producto p) async {
    if (p.id.isEmpty) {
      final ref = await _productos.add(p.toMap());
      return ref.id;
    } else {
      await _productos.doc(p.id).set(p.toMap(), SetOptions(merge: true));
      return p.id;
    }
  }

  Future<void> borrarProducto(String id) => _productos.doc(id).delete();

  /// Aprende un alias nuevo para un producto, o CORRIGE el que ya hubiera con
  /// el mismo texto y proveedor.
  ///
  /// Antes esto usaba arrayUnion, que compara el mapa entero. Desde que el
  /// alias lleva `formato` y `factor`, corregir un factor equivocado (la caja
  /// pasa de 6 kg a 5 kg) no reemplazaba nada: metia un segundo alias con el
  /// mismo texto y distinto factor, y el casado se quedaba con el que saliera
  /// primero. Por eso ahora se lee la lista, se sustituye el que coincide y se
  /// escribe entera, dentro de una transaccion para no pisar cambios de otro
  /// dispositivo.
  Future<void> agregarAlias(String productoId, AliasProducto alias) async {
    final ref = _productos.doc(productoId);
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>?;
    final raw = (data?['alias'] as List?) ?? const [];
    final lista = raw
        .map((e) => AliasProducto.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    final i = lista.indexWhere((a) => a.mismaClaveQue(alias));
    if (i >= 0) {
      lista[i] = alias;
    } else {
      lista.add(alias);
    }

    await ref.update({'alias': lista.map((a) => a.toMap()).toList()});
  }

  /// Reemplaza toda la lista de alias de un producto (gestión manual).
  Future<void> setAlias(String productoId, List<AliasProducto> alias) =>
      _productos.doc(productoId).update({
        'alias': alias.map((a) => a.toMap()).toList(),
      });

  /// Actualiza solo la cantidad habitual de un producto.
  Future<void> setCantidad(String id, double cantidad) =>
      _productos.doc(id).update({'cantidadHabitual': cantidad});

  /// Actualiza solo la cantidad de esta semana de un producto.
  /// [enFormato] indica si esa cantidad son cajas/sacos (true) o unidad base.
  /// [formato] es el nombre del formato elegido ("caja", "docena"...).
  Future<void> setCantidadSemana(String id, double cantidad,
          {bool enFormato = false, String formato = ''}) =>
      _productos.doc(id).update({
        'cantidadSemana': cantidad,
        'pedirEnFormato': enFormato,
        'formatoSemana': enFormato ? formato : '',
      });

  /// Reinicia la semana: copia la cantidad habitual a la de semana en todos.
  Future<void> reiniciarSemana() async {
    final snap = await _productos.get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final habitual = (d['cantidadHabitual'] ?? 0).toDouble();
      batch.update(doc.reference, {'cantidadSemana': habitual});
    }
    await batch.commit();
  }

  /// Marca o desmarca un producto de la compra actual (solo ese campo).
  Future<void> setEnLista(String id, bool valor) =>
      _productos.doc(id).update({'enLista': valor});

  /// Marca o desmarca TODOS los productos de golpe (de forma eficiente).
  Future<void> setEnListaTodos(bool valor) async {
    final snap = await _productos.get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'enLista': valor});
    }
    await batch.commit();
  }

  // ---- PRECIOS ----
  /// Todos los precios (para calcular el dashboard global).
  Stream<List<Precio>> precios() => _precios
      .orderBy('fecha')
      .snapshots()
      .map((s) => s.docs.map(Precio.fromDoc).toList());

  /// Precios de un producto concreto (para su pantalla de detalle / grafico).
  /// Solo filtramos por productoId (sin orderBy) para no necesitar un indice
  /// compuesto en Firestore; ordenamos por fecha aqui, en el cliente.
  Stream<List<Precio>> preciosDeProducto(String productoId) => _precios
      .where('productoId', isEqualTo: productoId)
      .snapshots()
      .map((s) {
        final lista = s.docs.map(Precio.fromDoc).toList();
        lista.sort((a, b) => a.fecha.compareTo(b.fecha));
        return lista;
      });

  Future<void> registrarPrecio(Precio p) => _precios.add(p.toMap());

  /// Consulta puntual (una vez) de los precios de un producto.
  /// Util para autocompletar el precio al registrar una compra.
  Future<List<Precio>> preciosDeProductoUnaVez(String productoId) async {
    final s = await _precios.where('productoId', isEqualTo: productoId).get();
    return s.docs.map(Precio.fromDoc).toList();
  }

  /// Pone el factor de conversion a un grupo de precios de envase.
  ///
  /// Estos precios se guardaron con cantidad 1, como si una garrafa entera
  /// fuese una unidad. Al decir cuantas unidades base trae de verdad, la
  /// cantidad pasa a ser ese numero y el precio por unidad se recalcula.
  ///
  /// El precio del envase (precioPaquete) no se toca: ese dato salio del
  /// albaran y es correcto. Lo que estaba mal era la equivalencia.
  Future<int> corregirFactorPrecios(
      List<Precio> precios, double factor) async {
    if (factor <= 0) {
      throw ArgumentError('El factor tiene que ser mayor que cero.');
    }
    var hechos = 0;
    for (var i = 0; i < precios.length; i += 400) {
      final fin = (i + 400) < precios.length ? i + 400 : precios.length;
      final batch = _db.batch();
      for (final p in precios.sublist(i, fin)) {
        batch.update(_precios.doc(p.id), {
          'cantidad': factor,
          'precioUnitario': p.precioPaquete / factor,
        });
      }
      await batch.commit();
      hechos += fin - i;
    }
    return hechos;
  }

  Future<void> borrarPrecio(String id) => _precios.doc(id).delete();

  /// Edita un registro de precio existente (precio, cantidad y fecha).
  /// Recalcula el precio unitario.
  Future<void> actualizarPrecio(
    String id, {
    required double precioPaquete,
    required double cantidad,
    required DateTime fecha,
    String? formato,
  }) {
    final unitario = cantidad > 0 ? precioPaquete / cantidad : 0;
    return _precios.doc(id).update({
      'precioPaquete': precioPaquete,
      'cantidad': cantidad,
      'precioUnitario': unitario,
      'formato': formato,
      'fecha': Timestamp.fromDate(fecha),
    });
  }

  // ---- COMPRAS ----
  CollectionReference get _compras => _db.collection('compras');

  Stream<List<Compra>> compras() => _compras
      .orderBy('fecha', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Compra.fromDoc).toList());

  /// Registra una compra Y, en el mismo lote, crea un registro de precio
  /// por cada linea (fuente "compra") para alimentar el historico y la
  /// comparativa. Una sola operacion atomica.
  Future<void> registrarCompra(Compra compra) async {
    final batch = _db.batch();

    // 1) La compra en si.
    batch.set(_compras.doc(), compra.toMap());

    // 2) Un precio por linea, con la fecha de la compra.
    for (final l in compra.lineas) {
      final precio = Precio.nuevo(
        productoId: l.productoId,
        proveedorId: compra.proveedorId,
        precioPaquete: l.precioUnitario, // ya es precio por unidad base
        cantidad: 1,
        fecha: compra.fecha,
        fuente: FuentePrecio.compra,
      );
      batch.set(_precios.doc(), precio.toMap());
    }

    await batch.commit();
  }

  Future<void> borrarCompra(String id) => _compras.doc(id).delete();

  /// Quita una linea de una compra, y con ella el precio que dejo en el
  /// historico.
  ///
  /// Devuelve true si ha habido que borrar la compra entera por quedarse sin
  /// lineas: un albaran de cero euros en los informes no ayuda a nadie.
  ///
  /// El precio se busca por producto, proveedor, dia y origen "compra", que
  /// es como lo dejo registrarCompra. Si ese dia hubo dos compras del mismo
  /// producto al mismo proveedor, se borra uno de los dos: es lo que hay,
  /// porque el precio no guarda de que linea salio.
  Future<bool> borrarLineaDeCompra({
    required Compra compra,
    required int indice,
  }) async {
    if (indice < 0 || indice >= compra.lineas.length) {
      throw ArgumentError('La linea no existe.');
    }
    final linea = compra.lineas[indice];

    // 1) El precio que genero, si lo encontramos.
    final s = await _precios
        .where('productoId', isEqualTo: linea.productoId)
        .get();
    for (final doc in s.docs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['proveedorId'] != compra.proveedorId) continue;
      if (d['fuente'] != 'compra') continue;
      final t = (d['fecha'] as Timestamp?)?.toDate();
      if (t == null ||
          t.year != compra.fecha.year ||
          t.month != compra.fecha.month ||
          t.day != compra.fecha.day) {
        continue;
      }
      await doc.reference.delete();
      break;
    }

    // 2) La linea.
    final quedan = [...compra.lineas]..removeAt(indice);
    if (quedan.isEmpty) {
      await _compras.doc(compra.id).delete();
      return true;
    }

    final total = quedan.fold<double>(0, (s, l) => s + l.total);
    await _compras.doc(compra.id).update({
      'lineas': quedan.map((l) => l.toMap()).toList(),
      'total': total,
    });
    return false;
  }

  /// Actualiza las líneas de una compra existente (recalcula el total).
  Future<void> actualizarCompraLineas(
      String compraId, List<LineaCompra> lineas) {
    final total = lineas.fold<double>(0, (s, l) => s + l.total);
    return _compras.doc(compraId).update({
      'lineas': lineas.map((l) => l.toMap()).toList(),
      'total': total,
    });
  }

  /// Best-effort: corrige el precio del histórico generado por una línea de
  /// compra (mismo producto, proveedor, día y origen "compra").
  Future<void> actualizarPrecioDeCompra({
    required String productoId,
    required String proveedorId,
    required DateTime fecha,
    required double nuevoUnitario,
  }) async {
    final s = await _precios.where('productoId', isEqualTo: productoId).get();
    for (final doc in s.docs) {
      final d = doc.data() as Map<String, dynamic>;
      if (d['proveedorId'] != proveedorId) continue;
      if (d['fuente'] != 'compra') continue;
      final t = (d['fecha'] as Timestamp?)?.toDate();
      if (t == null ||
          t.year != fecha.year ||
          t.month != fecha.month ||
          t.day != fecha.day) {
        continue;
      }
      await doc.reference.update({
        'precioPaquete': nuevoUnitario,
        'cantidad': 1,
        'precioUnitario': nuevoUnitario,
      });
      return;
    }
  }

  // ---- PLANTILLAS DE LISTA ----
  CollectionReference get _plantillas => _db.collection('plantillas');

  Future<List<PlantillaLista>> plantillasUnaVez() async {
    final s = await _plantillas.orderBy('nombre').get();
    return s.docs.map(PlantillaLista.fromDoc).toList();
  }

  Future<void> guardarPlantilla(String nombre, List<LineaPlantilla> lineas) =>
      _plantillas.add(PlantillaLista(id: '', nombre: nombre, lineas: lineas)
          .toMap());

  Future<void> borrarPlantilla(String id) => _plantillas.doc(id).delete();
}
