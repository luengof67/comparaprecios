import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/precio.dart';
import '../models/producto.dart';
import '../services/firestore_service.dart';
import 'formato.dart';

/// Solo LEE. Lista los productos cuya unidad base puede no coincidir con lo que
/// dice su nombre, para revisarlos antes de mandar los precios a ESCANDALLO.
/// No modifica ningún dato.
class UnidadesEscandalloScreen extends StatefulWidget {
  final FirestoreService db;
  const UnidadesEscandalloScreen({super.key, required this.db});

  @override
  State<UnidadesEscandalloScreen> createState() =>
      _UnidadesEscandalloScreenState();
}

class _Hallazgo {
  final Producto p;
  final double? precio;
  final String nota;
  final bool seguro; // true = equivale 1:1, se puede cambiar sin riesgo
  _Hallazgo(this.p, this.precio, this.nota, this.seguro);
}

class _UnidadesEscandalloScreenState extends State<UnidadesEscandalloScreen> {
  bool _cargando = true;
  String? _error;
  List<_Hallazgo> _desajustes = [];
  List<Producto> _sinPrecio = [];

  static final _re = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(kg|kgs|g|gr|grs|l|lt|ltr|cl|ml)\b',
      caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// (cantidad en kg o l, familia) o null si el nombre no trae medida.
  (double, UnidadBase)? _medida(String nombre) {
    final m = _re.firstMatch(nombre);
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (n == null || n <= 0) return null;
    switch (m.group(2)!.toLowerCase()) {
      case 'kg':
      case 'kgs':
        return (n, UnidadBase.kg);
      case 'g':
      case 'gr':
      case 'grs':
        return (n / 1000, UnidadBase.kg);
      case 'l':
      case 'lt':
      case 'ltr':
        return (n, UnidadBase.litro);
      case 'cl':
        return (n / 100, UnidadBase.litro);
      default:
        return (n / 1000, UnidadBase.litro);
    }
  }

  Future<void> _cargar() async {
    try {
      final productos = await widget.db.productos().first;
      final precios = await widget.db.precios().first;
      final ultimo = <String, Precio>{};
      for (final pr in precios) {
        if (pr.precioUnitario <= 0) continue;
        final a = ultimo[pr.productoId];
        if (a == null || pr.fecha.isAfter(a.fecha)) ultimo[pr.productoId] = pr;
      }

      final des = <_Hallazgo>[];
      final sin = <Producto>[];
      for (final p in productos) {
        final u = ultimo[p.id];
        if (u == null) {
          sin.add(p);
          continue;
        }
        final med = _medida(p.nombre);
        if (med == null) continue;
        final (cant, fam) = med;
        if (fam == p.unidadBase) {
          // Misma familia: solo avisa si el nombre dice otra cantidad que 1.
          if ((cant - 1).abs() > 0.001) {
            des.add(_Hallazgo(
                p,
                u.precioUnitario,
                'El nombre dice ${_n(cant)} ${fam.nombre}, pero el precio es '
                'por 1 ${fam.nombre}. Correcto si compras a granel; si es un '
                'envase, el precio de un envase sería ${euros3(u.precioUnitario * cant)}.',
                false));
          }
        } else if (p.unidadBase == UnidadBase.unidad) {
          if ((cant - 1).abs() < 0.001) {
            des.add(_Hallazgo(
                p,
                u.precioUnitario,
                'En "ud" pero el nombre dice 1 ${fam.nombre}: 1 ud = 1 '
                '${fam.nombre}. Se puede pasar a ${fam.nombre} sin cambiar '
                'ningún precio.',
                true));
          } else {
            des.add(_Hallazgo(
                p,
                u.precioUnitario,
                'En "ud" pero el nombre dice ${_n(cant)} ${fam.nombre}. '
                'ESCANDALLO recibe ${euros3(u.precioUnitario)} por ud; por '
                '${fam.nombre} sería ${euros3(u.precioUnitario / cant)}.',
                false));
          }
        } else {
          des.add(_Hallazgo(
              p,
              u.precioUnitario,
              'Se compara por ${p.unidadBase.nombre} y el nombre habla de '
              '${fam.nombre}. Revisa que sea lo que quieres.',
              false));
        }
      }
      des.sort((a, b) => a.p.nombre.toLowerCase().compareTo(b.p.nombre.toLowerCase()));
      sin.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _desajustes = des;
        _sinPrecio = sin;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _texto() {
    final b = StringBuffer('PRODUCTOS A REVISAR (unidad vs nombre)\n\n');
    for (final h in _desajustes) {
      b.writeln('- ${h.p.nombre} [${h.p.unidadBase.nombre}]'
          '${h.seguro ? ' (cambio sin riesgo)' : ''}: ${h.nota}');
    }
    b.writeln('\nSIN PRECIO (no se exportan a ESCANDALLO): ${_sinPrecio.length}');
    for (final p in _sinPrecio) {
      b.writeln('- ${p.nombre}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unidades y ESCANDALLO'),
        actions: [
          if (!_cargando && _error == null)
            IconButton(
              tooltip: 'Copiar la lista',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _texto()));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lista copiada.')));
              },
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Solo consulta: esta pantalla no cambia nada. Compara la '
                      'unidad de cada producto con lo que dice su nombre.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Text('A revisar (${_desajustes.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_desajustes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Nada raro encontrado.'),
                      ),
                    ..._desajustes.map((h) => Card(
                          child: ListTile(
                            leading: Icon(
                                h.seguro
                                    ? Icons.check_circle_outline
                                    : Icons.warning_amber_outlined,
                                color: h.seguro ? Colors.green : Colors.orange),
                            title: Text(
                                '${h.p.nombre}  ·  ${h.p.unidadBase.etiqueta}'),
                            subtitle: Text(h.nota),
                          ),
                        )),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                          'Sin precio, no van a ESCANDALLO (${_sinPrecio.length})'),
                      children: _sinPrecio
                          .map((p) => ListTile(
                              dense: true,
                              title: Text(p.nombre),
                              subtitle: Text(
                                  '${p.categoria} · ${p.unidadBase.etiqueta}')))
                          .toList(),
                    ),
                  ],
                ),
    );
  }
}
