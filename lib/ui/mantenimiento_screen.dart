import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/firestore_service.dart';
import '../services/respaldo_service.dart';

/// Herramientas de mantenimiento de la base de datos.
///
/// De momento: copia de seguridad. Aqui iran despues los proveedores
/// huerfanos (ids que quedaron sin ficha tras borrar duplicados).
class MantenimientoScreen extends StatefulWidget {
  final FirestoreService db;
  const MantenimientoScreen({super.key, required this.db});

  @override
  State<MantenimientoScreen> createState() => _MantenimientoScreenState();
}

class _MantenimientoScreenState extends State<MantenimientoScreen> {
  bool _copiando = false;
  ResultadoRespaldo? _ultima;
  String? _error;
  List<FileSystemEntity> _guardadas = const [];

  @override
  void initState() {
    super.initState();
    _cargarGuardadas();
  }

  Future<void> _cargarGuardadas() async {
    try {
      final l = await RespaldoService.copiasGuardadas();
      if (mounted) setState(() => _guardadas = l);
    } catch (_) {
      // Si no se puede leer la carpeta, no pasa nada: solo es informativo.
    }
  }

  Future<void> _copiar() async {
    setState(() {
      _copiando = true;
      _error = null;
    });
    try {
      final r = await RespaldoService.exportar();
      if (!mounted) return;
      setState(() {
        _ultima = r;
        _copiando = false;
      });
      await _cargarGuardadas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _copiando = false;
      });
    }
  }

  /// Abre el explorador de Windows con el archivo ya seleccionado.
  Future<void> _abrirCarpeta(String ruta) async {
    try {
      await Process.run('explorer.exe', ['/select,', ruta]);
    } catch (e) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: ruta));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ruta copiada al portapapeles.'),
      ));
    }
  }

  Future<void> _compartir(String ruta) async {
    try {
      await Share.shareXFiles([XFile(ruta)],
          text: 'Respaldo de ComparaPrecios');
    } catch (e) {
      // En Windows compartir no siempre esta disponible: al menos que se
      // pueda copiar la ruta y abrir la carpeta a mano.
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: ruta));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se ha podido compartir. Ruta copiada al portapapeles.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mantenimiento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.save_outlined),
                      const SizedBox(width: 8),
                      Text('Copia de seguridad',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Guarda todos los proveedores, productos, precios y compras '
                    'en un archivo JSON. Hazla antes de cualquier limpieza: '
                    'borrar o fusionar no se puede deshacer.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _copiando ? null : _copiar,
                    icon: _copiando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_copiando
                        ? 'Descargando…'
                        : 'Crear copia de seguridad'),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No se ha podido hacer la copia',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade900)),
                    const SizedBox(height: 6),
                    Text(_error!, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
          if (_ultima != null) ...[
            const SizedBox(height: 12),
            _resultado(_ultima!),
          ],
          if (_guardadas.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Copias en el dispositivo (${_guardadas.length})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final f in _guardadas.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined, size: 20),
                title: Text(f.path.split(Platform.pathSeparator).last,
                    style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: Icon(
                      Platform.isWindows ? Icons.folder_open : Icons.share,
                      size: 20),
                  onPressed: () => Platform.isWindows
                      ? _abrirCarpeta(f.path)
                      : _compartir(f.path),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _resultado(ResultadoRespaldo r) {
    return Card(
      color: r.sospechoso ? Colors.orange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.sospechoso ? Icons.warning_amber : Icons.check_circle,
                  color: r.sospechoso
                      ? Colors.orange.shade800
                      : Colors.green.shade800,
                ),
                const SizedBox(width: 8),
                Text(
                  r.sospechoso ? 'Copia vacía' : 'Copia hecha',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (r.sospechoso)
              const Text(
                'No se ha descargado ningún documento. Revisa la conexión y '
                'vuelve a intentarlo: esta copia no sirve de nada.',
                style: TextStyle(fontSize: 13),
              )
            else ...[
              for (final e in r.conteo.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key, style: const TextStyle(fontSize: 13)),
                      Text('${e.value}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${r.totalDocumentos} documentos · ${r.tamano}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SelectableText(
              r.ruta,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (Platform.isWindows)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Abrir carpeta'),
                    onPressed: () => _abrirCarpeta(r.ruta),
                  )
                else
                  OutlinedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Compartir'),
                    onPressed: () => _compartir(r.ruta),
                  ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar ruta'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: r.ruta));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ruta copiada')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
