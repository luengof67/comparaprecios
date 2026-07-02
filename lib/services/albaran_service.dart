import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/linea_albaran.dart';

/// Llama al Worker de Cloudflare que lee el albarán con Claude.
class AlbaranService {
  // URL del Worker desplegado en Cloudflare.
  static const String _workerUrl =
      'https://rapid-bread-547c.luengof67.workers.dev/';

  /// Envía la imagen (bytes) al Worker y devuelve las líneas leídas.
  /// Lanza una excepción con mensaje claro si algo falla.
  static Future<ResultadoAlbaran> leer(
    List<int> bytes, {
    String mediaType = 'image/jpeg',
  }) async {
    final b64 = base64Encode(bytes);

    final resp = await http
        .post(
          Uri.parse(_workerUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'imageBase64': b64, 'mediaType': mediaType}),
        )
        .timeout(const Duration(seconds: 60));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw 'Respuesta inesperada del servidor (${resp.statusCode}).';
    }

    if (resp.statusCode != 200 || data['error'] != null) {
      throw data['error']?.toString() ?? 'Error ${resp.statusCode} al leer el albarán.';
    }

    return ResultadoAlbaran.fromMap(data);
  }
}
