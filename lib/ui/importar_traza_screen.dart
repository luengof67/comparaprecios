import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../models/proveedor.dart';
import '../services/firestore_service.dart';
import '../services/casador_service.dart';
import '../services/importar_traza_service.dart';
import 'formato.dart';

enum _Filtro { todos, pendientes, listos, duplicados }

class ImportarTrazaScreen extends StatefulWidget {
  final FirestoreService db;
  const ImportarTrazaScreen({super.key, required this.db});

  @override
  State<ImportarTrazaScreen> createState() => _ImportarTrazaScreenState();
}

class _ImportarTrazaScreenState extends State<ImportarTrazaScreen> {
  bool _cargando = false;
  bool _guardando = false;
  String? _error;
  List<AlbaranTraza> _albaranes = [];
  List<Producto> _productos = [];
  List<Proveedor> _proveedores = [];
  _Filtro _filtro = _Filtro.todos;
  final _jsonCtrl = TextEditingController();

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _procesar() async {
    final texto = _jsonCtrl.text.trim();
    if (texto.isEmpty) {
      setState(() => _error = 'Pega primero el contenido del JSON.');
      return;
    }
    setState(() => _error = null);
    try {
      setState(() => _cargando = true);
      _productos = await widget.db.productos().first;
      _proveedores = await widget.db.proveedores().first;
      final compras = await widget.db.compras().first;
      final albaranes = ImportarTrazaService.parsear(
          texto, _productos, _proveedores, compras);
      setState(() {
        _albaranes = albaranes;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'El texto no es un JSON valido de TRAZA: $e';
        _cargando = false;
      });
    }
  }

  List<AlbaranTraza> get _filtrados {
    switch (_filtro) {
      case _Filtro.todos:
        return _albaranes;
      case _Filtro.pendientes:
        return _albaranes.where((a) => a.pendientes > 0).toList();
      case _Filtro.listos:
        return _albaranes
            .where((a) => a.pendientes == 0 && !a.duplicado)
            .toList();
      case _Filtro.duplicados:
        return _albaranes.where((a) => a.duplicado).toList();
    }
  }

  int get _albaranesMarcados =>
      _albaranes.where((a) => a.importar && !a.duplicado).length;

  int get _lineasMarcadas => _albaranes
      .where((a) => a.importar && !a.duplicado)
      .fold(0, (s, a) => s + a.lineasListas.length);

  Future<void> _importar() async {
    if (_lineasMarcadas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay ninguna linea lista para importar.')));
      return;
    }
    setState(() => _guardando = true);
    try {
      final r = await ImportarTrazaService.importar(
          widget.db, _albaranes, _productos, _proveedores);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Importacion completada'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Compras registradas: ${r.compras}'),
                Text('Lineas importadas: ${r.lineas}'),
                Text('Lineas fuera: ${r.lineasFuera}'),
                Text('Productos nuevos: ${r.productosNuevos}'),
                Text('Proveedores nuevos: ${r.proveedoresNuevos}'),
                Text('Alias aprendidos: ${r.aliasAprendidos}'),
                if (r.saltados.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Albaranes saltados:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  ...r.saltados.map((s) => Text('- $s')),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Vale')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al importar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar albaranes de TRAZA')),
      bottomNavigationBar: _albaranes.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _importar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text(
                      'Importar $_albaranesMarcados albaranes ($_lineasMarcadas lineas)'),
                ),
              ),
            ),
      body: _albaranes.isEmpty ? _vistaInicio() : _vistaRevision(),
    );
  }

  Widget _vistaInicio() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Trae las compras desde TRAZA:\n'
          '1) En TRAZA, Informes, pulsa "Exportar para ComparaPrecios".\n'
          '2) Abre el archivo .json y copia todo su contenido.\n'
          '3) Pegalo aqui abajo y pulsa "Procesar".\n\n'
          'Cada albaran se registra como una compra, y de ahi salen los '
          'precios del historico. Un albaran ya importado no se repite.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _jsonCtrl,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Pega aqui el JSON',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _cargando ? null : _procesar,
          icon: const Icon(Icons.playlist_add_check),
          label: const Text('Procesar'),
        ),
        const SizedBox(height: 20),
        if (_cargando) const Center(child: CircularProgressIndicator()),
        if (_error != null)
          Card(
            color: Colors.red.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ),
      ],
    );
  }

  Widget _vistaRevision() {
    final lista = _filtrados;
    final pendientes =
        _albaranes.fold<int>(0, (s, a) => s + (a.duplicado ? 0 : a.pendientes));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_albaranes.length} albaranes · $pendientes lineas por revisar',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _chipFiltro('Todos', _Filtro.todos),
              _chipFiltro('Por revisar', _Filtro.pendientes),
              _chipFiltro('Listos', _Filtro.listos),
              _chipFiltro('Ya importados', _Filtro.duplicados),
            ],
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: lista.length,
            itemBuilder: (_, i) => _tarjetaAlbaran(lista[i]),
          ),
        ),
      ],
    );
  }

  Widget _chipFiltro(String label, _Filtro f) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _filtro == f,
        onSelected: (_) => setState(() => _filtro = f),
      ),
    );
  }

  Widget _tarjetaAlbaran(AlbaranTraza a) {
    final total = a.total;
    final papel = a.totalPapel ?? 0;
    // Si el total del papel no cuadra con lo que vamos a registrar, avisamos:
    // casi siempre es que falta alguna linea por revisar.
    final descuadre = papel > 0 && (papel - total).abs() > 0.05;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: a.duplicado
            ? const Icon(Icons.check_circle, color: Colors.grey)
            : Checkbox(
                value: a.importar,
                onChanged: (v) => setState(() => a.importar = v ?? false),
              ),
        title: Text(
          '${a.proveedorNombre.isEmpty ? "Sin proveedor" : a.proveedorNombre}'
          '${a.albaran.isEmpty ? "" : "  nº ${a.albaran}"}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${fecha(a.fecha)} · ${a.lineas.length} lineas · '
                '${total.toStringAsFixed(2)} €'),
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                if (a.duplicado)
                  _mini('ya importado', Colors.grey)
                else if (a.pendientes > 0)
                  _mini('${a.pendientes} por revisar', Colors.orange)
                else
                  _mini('listo', Colors.green),
                if (a.proveedorId == null && a.proveedorNombre.isNotEmpty)
                  _mini('proveedor nuevo', Colors.blue),
                if (descuadre)
                  _mini('el papel sumaba ${papel.toStringAsFixed(2)} €',
                      Colors.orange),
              ],
            ),
          ],
        ),
        children: a.lineas.map((l) => _filaLinea(a, l)).toList(),
      ),
    );
  }

  Widget _filaLinea(AlbaranTraza a, LineaTraza l) {
    final puedeMarcarse = l.lista;
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: l.importar,
        onChanged: puedeMarcarse
            ? (v) => setState(() => l.importar = v ?? false)
            : null,
      ),
      title: Text(l.textoAlbaran, style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.productoId == null
                ? 'nuevo: ${l.productoNombre}'
                : l.productoNombre,
            style: TextStyle(
              fontSize: 12,
              color: l.productoId == null ? Colors.blue : Colors.green,
            ),
          ),
          Text(
            l.tieneFormato
                ? '${_num(l.cantidad)} ${l.formato}'
                    '${l.pesoFormato > 0 ? " × ${_num(l.pesoFormato)} ${l.unidad.nombre}" : ""}'
                    ' · ${l.importe.toStringAsFixed(2)} €'
                : '${_num(l.cantidad)} ${l.unidad.nombre} · '
                    '${l.importe.toStringAsFixed(2)} €',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              if (l.necesitaPeso)
                _mini('falta el peso del formato', Colors.red)
              else if (l.precioUnitario > 0)
                _mini('${euros3(l.precioUnitario)}/${l.unidad.nombre}',
                    Colors.black54),
              if (l.casado == TipoCasado.propuesto) _mini('propuesto', Colors.orange),
              if (l.casado == TipoCasado.sinCoincidencia)
                _mini('sin casar', Colors.red),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: () => _editarLinea(a, l),
    );
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _editarLinea(AlbaranTraza a, LineaTraza l) async {
    final pesoCtrl = TextEditingController(
        text: l.pesoFormato > 0 ? _num(l.pesoFormato) : '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.textoAlbaran,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${_num(l.cantidad)} '
                  '${l.tieneFormato ? l.formato : l.unidad.nombre} · '
                  '${l.importe.toStringAsFixed(2)} €'),
              const Divider(height: 24),
              const Text('Producto', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                l.productoId == null
                    ? 'Se creara nuevo: ${l.productoNombre}'
                    : '${l.productoNombre} (${l.unidad.etiqueta})',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Elegir producto'),
                    onPressed: () async {
                      final p = await _elegirProducto();
                      if (p == null) return;
                      setState(() {
                        l.productoId = p.id;
                        l.productoNombre = p.nombre;
                        l.unidad = p.unidadBase;
                        l.casado = TipoCasado.automatico;
                        l.aprenderAlias = true;
                        if (l.tieneFormato && l.pesoFormato <= 0) {
                          l.pesoFormato = ImportarTrazaService.pesoDeTexto(
                              l.textoAlbaran, l.formato, l.unidad);
                        }
                        l.importar = l.lista;
                      });
                      setSheet(() {
                        pesoCtrl.text =
                            l.pesoFormato > 0 ? _num(l.pesoFormato) : '';
                      });
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Crear nuevo'),
                    onPressed: () async {
                      final u = await _elegirUnidad();
                      if (u == null) return;
                      setState(() {
                        l.productoId = null;
                        l.productoNombre = l.textoAlbaran;
                        l.unidad = u;
                        l.aprenderAlias = false; // el nombre ya sera el suyo
                        if (l.tieneFormato) {
                          l.pesoFormato = ImportarTrazaService.pesoDeTexto(
                              l.textoAlbaran, l.formato, l.unidad);
                        }
                        l.importar = l.lista;
                      });
                      setSheet(() {
                        pesoCtrl.text =
                            l.pesoFormato > 0 ? _num(l.pesoFormato) : '';
                      });
                    },
                  ),
                ],
              ),
              if (l.tieneFormato) ...[
                const Divider(height: 24),
                Text('Cuanto ${l.unidad.nombre} tiene un ${l.formato}',
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: pesoCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixText: l.unidad.nombre,
                    helperText: 'Sin esto no se puede calcular el precio '
                        'por ${l.unidad.nombre}',
                  ),
                  onChanged: (v) {
                    final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    setState(() {
                      l.pesoFormato = n;
                      l.importar = l.lista;
                    });
                    setSheet(() {});
                  },
                ),
              ],
              const Divider(height: 24),
              Text(
                l.lista
                    ? 'Entrara como ${_num(l.cantidadBase)} ${l.unidad.nombre} '
                        'a ${euros3(l.precioUnitario)}/${l.unidad.nombre}'
                    : 'Todavia no se puede importar esta linea',
                style: TextStyle(
                  color: l.lista ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hecho'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    pesoCtrl.dispose();
    if (mounted) setState(() {});
  }

  Future<Producto?> _elegirProducto() async {
    final buscarCtrl = TextEditingController();
    final elegido = await showDialog<Producto>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final q = buscarCtrl.text.toLowerCase().trim();
          final lista = q.isEmpty
              ? _productos
              : _productos
                  .where((p) => p.nombre.toLowerCase().contains(q))
                  .toList();
          return AlertDialog(
            title: const Text('Elegir producto'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: buscarCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDlg(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        title: Text(lista[i].nombre),
                        subtitle: Text(lista[i].unidadBase.etiqueta),
                        onTap: () => Navigator.pop(ctx, lista[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        },
      ),
    );
    buscarCtrl.dispose();
    return elegido;
  }

  Future<UnidadBase?> _elegirUnidad() {
    return showDialog<UnidadBase>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('En que se mide el producto nuevo'),
        children: UnidadBase.values
            .map((u) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, u),
                  child: Text(u.etiqueta),
                ))
            .toList(),
      ),
    );
  }

  Widget _mini(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(t, style: TextStyle(fontSize: 11, color: c)),
      );
}
