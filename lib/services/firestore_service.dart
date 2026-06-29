import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Marca o desmarca un producto de la compra actual (solo ese campo).
  Future<void> setEnLista(String id, bool valor) =>
      _productos.doc(id).update({'enLista': valor});

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

  Future<void> borrarPrecio(String id) => _precios.doc(id).delete();
}
