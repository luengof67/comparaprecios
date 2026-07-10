import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Exporta los precios de ComparaPrecios al formato que importa ESCANDALLO:
///   [ { "nombre": "...", "precio": 0.00, "unidad": "kg"|"l"|"ud" }, ... ]
///
/// Criterio: para cada producto se toma el precio MAS RECIENTE registrado
/// (el del ultimo albaran o alta manual, sea del proveedor que sea), que es
/// lo que realmente estas pagando ahora. Los productos sin ningun precio
/// registrado no se exportan.
class ExportarEscandallo {
  static Future<void> exportar(BuildContext context) async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      final db = FirebaseFirestore.instance;
      final prodSnap = await db.collection('productos').get();
      final precioSnap = await db.collection('precios').get();

      // Precio mas reciente por producto (da igual el proveedor)
      final Map<String, _Vigente> reciente = {};
      for (final doc in precioSnap.docs) {
        final d = doc.data();
        final productoId = d['productoId'] as String?;
        if (productoId == null) continue;
        final fecha = (d['fecha'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final precio = (d['precioUnitario'] as num?)?.toDouble() ?? 0;
        if (precio <= 0) continue;
        final actual = reciente[productoId];
        if (actual == null || fecha.isAfter(actual.fecha)) {
          reciente[productoId] = _Vigente(productoId, precio, fecha);
        }
      }

      // Construir la lista en el formato de ESCANDALLO
      String unidad(String? unidadBase) {
        switch (unidadBase) {
          case 'litro':
            return 'l';
          case 'unidad':
            return 'ud';
          default:
            return 'kg';
        }
      }

      final lista = <Map<String, dynamic>>[];
      for (final doc in prodSnap.docs) {
        final d = doc.data();
        final v = reciente[doc.id];
        if (v == null) continue; // sin precios registrados
        lista.add({
          'nombre': (d['nombre'] ?? '').toString(),
          'precio': double.parse(v.precio.toStringAsFixed(4)),
          'unidad': unidad(d['unidadBase'] as String?),
        });
      }
      lista.sort((a, b) =>
          (a['nombre'] as String).toLowerCase().compareTo((b['nombre'] as String).toLowerCase()));

      if (lista.isEmpty) {
        mensajero.showSnackBar(const SnackBar(
            content: Text('No hay productos con precio para exportar.')));
        return;
      }

      // 4) Guardar el JSON en temporal y compartirlo
      final json = const JsonEncoder.withIndent('  ').convert(lista);
      final dir = await getTemporaryDirectory();
      final archivo = File('${dir.path}/precios_escandallo.json');
      await archivo.writeAsString(json);

      await Share.shareXFiles(
        [XFile(archivo.path, mimeType: 'application/json')],
        text: 'Precios para ESCANDALLO (${lista.length} productos, ultimo precio pagado)',
      );

      mensajero.showSnackBar(SnackBar(
          content: Text('Exportados ${lista.length} productos con su precio mas reciente.')));
    } catch (e) {
      mensajero.showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')));
    }
  }
}

class _Vigente {
  final String productoId;
  final double precio;
  final DateTime fecha;
  _Vigente(this.productoId, this.precio, this.fecha);
}
