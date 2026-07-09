import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/compra.dart';
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

  Future<void> borrarProveedor(String id) => _proveedores.doc(id).delete();

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

  /// Aprende un alias nuevo para un producto (lo añade a su lista).
  Future<void> agregarAlias(String productoId, AliasProducto alias) =>
      _productos.doc(productoId).update({
        'alias': FieldValue.arrayUnion([alias.toMap()]),
      });

  /// Reemplaza toda la lista de alias de un producto (gestión manual).
  Future<void> setAlias(String productoId, List<AliasProducto> alias) =>
      _productos.doc(productoId).update({
        'alias': alias.map((a) => a.toMap()).toList(),
      });

  /// Actualiza solo la cantidad habitual de un producto.
  Future<void> setCantidad(String id, double cantidad) =>
      _productos.doc(id).update({'cantidadHabitual': cantidad});

  /// Actualiza solo la cantidad de esta semana de un producto.
  Future<void> setCantidadSemana(String id, double cantidad) =>
      _productos.doc(id).update({'cantidadSemana': cantidad});

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

  Future<void> borrarPrecio(String id) => _precios.doc(id).delete();

  /// Edita un registro de precio existente (precio, cantidad y fecha).
  /// Recalcula el precio unitario.
  Future<void> actualizarPrecio(
    String id, {
    required double precioPaquete,
    required double cantidad,
    required DateTime fecha,
  }) {
    final unitario = cantidad > 0 ? precioPaquete / cantidad : 0;
    return _precios.doc(id).update({
      'precioPaquete': precioPaquete,
      'cantidad': cantidad,
      'precioUnitario': unitario,
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
}
