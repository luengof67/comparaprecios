import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/linea_albaran.dart';

/// Llama al Worker de Cloudflare que lee el albarán con Claude.
class AlbaranService {
  // URL del Worker desplegado en Cloudflare.
  static const String _workerUrl =
      'https://rapid-bread-547c.luengof67.workers.dev/';

  static const int _maxBytes = 1200000; // ~1,2 MB
  static const int _ladoMax = 2000;

  static List<int> _reducir(List<int> bytes) {
    if (bytes.length <= _maxBytes) return bytes;
    try {
      final im = img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
      if (im == null) return bytes;
      final grande = im.width >= im.height ? im.width : im.height;
      final r = grande > _ladoMax
          ? (im.width >= im.height
              ? img.copyResize(im, width: _ladoMax)
              : img.copyResize(im, height: _ladoMax))
          : im;
      return img.encodeJpg(r, quality: 85);
    } catch (_) {
      return bytes; // si no se puede reducir, se envia tal cual
    }
  }

  /// Envía la imagen (bytes) al Worker y devuelve las líneas leídas.
  /// Lanza una excepción con mensaje claro si algo falla.
  static Future<ResultadoAlbaran> leer(
    List<int> bytes, {
    String mediaType = 'image/jpeg',
  }) async {
    // En Windows y en algunos navegadores el selector de fotos NO reduce la
    // imagen, y una foto de varios MB no llega al Worker ("Failed to fetch").
    // Si pesa mucho, se reduce aqui antes de enviarla.
    final reducida = _reducir(bytes);
    if (!identical(reducida, bytes)) mediaType = 'image/jpeg';
    bytes = reducida;
    final b64 = base64Encode(bytes);

    final resp = await http
        .post(
          Uri.parse(_workerUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'imageBase64': b64, 'mediaType': mediaType}),
        )
        .timeout(const Duration(seconds: 90));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw 'Respuesta inesperada del servidor (${resp.statusCode}).';
    }

    if (resp.statusCode != 200 || data['error'] != null) {
      // El Worker ya devuelve un mensaje claro y un código de causa.
      final msg = data['error']?.toString() ??
          'Error ${resp.statusCode} al leer el documento.';
      final codigo = data['codigo']?.toString();
      // Prefijo con emoji según la causa, para verlo de un vistazo.
      final icono = switch (codigo) {
        'rate_limit' => '⏳ ',
        'saldo' => '💳 ',
        'imagen_grande' => '📷 ',
        'sobrecarga' => '⏳ ',
        _ => '',
      };
      throw '$icono$msg';
    }

    return ResultadoAlbaran.fromMap(data);
  }
}
