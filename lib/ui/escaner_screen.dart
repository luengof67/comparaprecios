import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/linea_albaran.dart';
import '../services/albaran_service.dart';
import '../services/firestore_service.dart';
import 'formato.dart';
import 'revision_albaran_screen.dart';

class EscanerScreen extends StatefulWidget {
  final FirestoreService db;
  const EscanerScreen({super.key, required this.db});

  @override
  State<EscanerScreen> createState() => _EscanerScreenState();
}

class _EscanerScreenState extends State<EscanerScreen> {
  bool _cargando = false;
  String? _error;
  ResultadoAlbaran? _resultado;

  Future<void> _capturar(ImageSource source) async {
    setState(() {
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final XFile? foto = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (foto == null) return; // cancelado

      setState(() => _cargando = true);
      final bytes = await foto.readAsBytes();
      final resultado = await AlbaranService.leer(bytes);
      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear albarán')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Haz una foto del albarán o elige una de la galería. '
            'La IA leerá las líneas y luego podrás revisarlas.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _cargando ? null : () => _capturar(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _cargando ? null : () => _capturar(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_cargando) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            const Center(
              child: Text('Leyendo el albarán…',
                  style: TextStyle(color: Colors.grey)),
            ),
          ],
          if (_error != null)
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudo leer:\n$_error',
                    style: const TextStyle(color: Colors.red)),
              ),
            ),
          if (_resultado != null && !_cargando) ...[
            if (_resultado!.proveedor != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Proveedor detectado: ${_resultado!.proveedor}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            Text('${_resultado!.lineas.length} líneas leídas',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._resultado!.lineas.map((l) => Card(
                  child: ListTile(
                    title: Text(l.descripcion),
                    subtitle: Text([
                      if (l.cantidad != null) '${l.cantidad} ${l.unidad ?? ""}',
                      if (l.unitarioCalculado != null)
                        '${euros3(l.unitarioCalculado!)}/ud',
                      if (l.precioTotal != null) 'total ${euros(l.precioTotal!)}',
                    ].join(' · ')),
                  ),
                )),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RevisionAlbaranScreen(
                    db: widget.db,
                    resultado: _resultado!,
                  ),
                ),
              ),
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Revisar y casar productos'),
            ),
          ],
        ],
      ),
    );
  }
}
