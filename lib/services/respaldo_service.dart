import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

/// Vuelca TODA la base de datos a un archivo JSON.
///
/// Lee los documentos en crudo, no a traves de los modelos: asi no se pierde
/// nada aunque un campo no este contemplado en el codigo, y el respaldo sigue
/// sirviendo aunque los modelos cambien mas adelante.
class RespaldoService {
  /// Las colecciones de la app. Si algun dia se añade una, va aqui.
  static const colecciones = [
    'proveedores',
    'productos',
    'precios',
    'compras',
    'plantillas',
  ];

  /// Convierte los tipos propios de Firestore a algo que quepa en un JSON,
  /// dejando marcado de que tipo era para poder devolverlo tal cual.
  static dynamic _plano(dynamic v) {
    if (v is Timestamp) {
      return {'_tipo': 'fecha', 'valor': v.toDate().toIso8601String()};
    }
    if (v is DocumentReference) {
      return {'_tipo': 'ref', 'valor': v.path};
    }
    if (v is GeoPoint) {
      return {'_tipo': 'geo', 'lat': v.latitude, 'lng': v.longitude};
    }
    if (v is Map) {
      return v.map((k, x) => MapEntry(k.toString(), _plano(x)));
    }
    if (v is List) {
      return v.map(_plano).toList();
    }
    return v; // numeros, textos, booleanos y nulos van tal cual
  }

  static String _dosDigitos(int n) => n.toString().padLeft(2, '0');

  static String _nombreArchivo(DateTime d) =>
      'comparaprecios-respaldo-${d.year}${_dosDigitos(d.month)}'
      '${_dosDigitos(d.day)}-${_dosDigitos(d.hour)}${_dosDigitos(d.minute)}.json';

  /// Donde se dejan las copias.
  ///
  /// En Windows, getApplicationDocumentsDirectory() apunta a AppData\Roaming,
  /// que esta escondido y no sirve de nada para una copia de seguridad que
  /// quieres poder encontrar. Ahi se usa la carpeta Documentos de verdad.
  static Future<Directory> carpetaDeCopias() async {
    if (Platform.isWindows) {
      final perfil = Platform.environment['USERPROFILE'];
      if (perfil != null && perfil.isNotEmpty) {
        final docs = Directory('$perfil\\Documents\\ComparaPrecios');
        try {
          if (!await docs.exists()) await docs.create(recursive: true);
          return docs;
        } catch (_) {
          // Si no se puede crear (permisos, OneDrive raro), se cae a la de
          // siempre en vez de fallar la copia entera.
        }
      }
    }
    return getApplicationDocumentsDirectory();
  }

  /// Descarga todo y lo guarda en un archivo. Devuelve donde ha quedado y
  /// cuantos documentos lleva cada coleccion, para poder comprobarlo de un
  /// vistazo antes de fiarse de la copia.
  static Future<ResultadoRespaldo> exportar() async {
    final db = FirebaseFirestore.instance;
    final contenido = <String, dynamic>{};
    final conteo = <String, int>{};

    for (final nombre in colecciones) {
      final snap = await db.collection(nombre).get();
      final docs = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final fila = <String, dynamic>{'_id': d.id};
        final datos = d.data();
        datos.forEach((k, v) => fila[k] = _plano(v));
        docs.add(fila);
      }
      contenido[nombre] = docs;
      conteo[nombre] = docs.length;
    }

    final ahora = DateTime.now();
    final json = {
      'app': 'comparaprecios',
      'formato': 1,
      'generado': ahora.toIso8601String(),
      'colecciones': contenido,
    };

    final texto = const JsonEncoder.withIndent('  ').convert(json);

    final dir = await carpetaDeCopias();
    final archivo = File('${dir.path}${Platform.pathSeparator}'
        '${_nombreArchivo(ahora)}');
    await archivo.writeAsString(texto);

    return ResultadoRespaldo(
      ruta: archivo.path,
      conteo: conteo,
      bytes: await archivo.length(),
      generado: ahora,
    );
  }

  /// Copias que ya estan guardadas en el dispositivo, de la mas nueva a la
  /// mas vieja.
  static Future<List<FileSystemEntity>> copiasGuardadas() async {
    final dir = await carpetaDeCopias();
    final todas = dir
        .listSync()
        .where((f) =>
            f is File &&
            f.path.contains('comparaprecios-respaldo-') &&
            f.path.endsWith('.json'))
        .toList();
    todas.sort((a, b) => b.path.compareTo(a.path));
    return todas;
  }
}

class ResultadoRespaldo {
  final String ruta;
  final Map<String, int> conteo;
  final int bytes;
  final DateTime generado;

  const ResultadoRespaldo({
    required this.ruta,
    required this.conteo,
    required this.bytes,
    required this.generado,
  });

  int get totalDocumentos =>
      conteo.values.fold(0, (s, n) => s + n);

  String get tamano {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Un respaldo con cero documentos casi siempre significa que algo fallo
  /// (sin conexion, sin permisos), no que la base este vacia.
  bool get sospechoso => totalDocumentos == 0;
}
