import 'package:flutter/material.dart';

/// Guía de uso: el flujo de trabajo completo y cada función explicada.
/// Solo texto, sin dependencias: sirve igual en el móvil y en la web.
class GuiaScreen extends StatelessWidget {
  const GuiaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guía de uso')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: const [
          _Seccion(
            icono: Icons.route,
            titulo: 'El flujo de la semana (resumen)',
            inicioAbierto: true,
            texto:
                '1. MONTAR LISTA: escribe lo que falta, sin pensar en precios. '
                'Elige cantidad y formato (kg, caja, docena…).\n\n'
                '2. LISTA: la app agrupa cada producto con su proveedor más '
                'barato según el histórico. Ajusta lo que quieras y envía el '
                'pedido de cada proveedor por WhatsApp.\n\n'
                '3. ALBARÁN: cuando llega el género, escanea el albarán con la '
                'cámara. Revisa las líneas, corrige lo necesario y guarda.\n\n'
                '4. El precio real del albarán alimenta el histórico: la '
                'próxima comparativa será más precisa. El circuito se mejora '
                'solo con el uso.',
          ),
          _Seccion(
            icono: Icons.inventory_2_outlined,
            titulo: 'Productos (el catálogo)',
            texto:
                'Cada producto tiene una UNIDAD BASE (kg, L o ud): todos los '
                'precios se comparan siempre en esa unidad, aunque compres por '
                'cajas.\n\n'
                'Los ALIAS son los otros nombres con los que aparece en los '
                'albaranes ("aguacate hass", "palta"). El escáner los usa para '
                'casar líneas automáticamente; se aprenden solos al confirmar.\n\n'
                'La CANTIDAD HABITUAL rellena por defecto el diálogo al '
                'añadirlo a la lista.',
          ),
          _Seccion(
            icono: Icons.edit_note,
            titulo: 'Montar lista',
            texto:
                'Escribe y el buscador sugiere productos de tu catálogo '
                '(también por alias). Al elegir uno:\n\n'
                '• CANTIDAD + FORMATO: chips con la unidad base, los formatos '
                'que ese producto ya tiene en el histórico, y los genéricos '
                '(caja, docena, estuche, saco, garrafa, lata). Si pides "2 '
                'cajas", el coste exacto se confirmará con el albarán.\n\n'
                '• MEJOR PRECIO: si hay histórico, un aviso verde te recuerda '
                'quién te lo vendió más barato la última vez y a cuánto. Es '
                'informativo: tú decides.\n\n'
                'PLANTILLAS (iconos de marcador arriba): guarda la lista como '
                '"Pedido del martes" y cárgala otra semana de un toque. La '
                'papelera borra plantillas que ya no uses.',
          ),
          _Seccion(
            icono: Icons.shopping_cart_outlined,
            titulo: 'Lista y reparto por proveedor',
            texto:
                'La pestaña Lista agrupa automáticamente cada producto con su '
                'proveedor MÁS BARATO según el último precio conocido, y '
                'muestra el ahorro frente a la peor opción.\n\n'
                'Puedes editar cantidades tocando cada línea, y mover un '
                'producto a otro proveedor si esa semana lo prefieres (por '
                'calidad, mínimos de pedido, etc.).\n\n'
                'El botón de compartir genera el texto del pedido de cada '
                'proveedor listo para WhatsApp.',
          ),
          _Seccion(
            icono: Icons.photo_camera_outlined,
            titulo: 'Lista por foto (IA)',
            texto:
                'Haz una foto a una lista escrita a mano o impresa y la IA la '
                'convierte en lista de la compra: lee producto y cantidad, y '
                'te propone el casado con tu catálogo para que confirmes línea '
                'a línea antes de aplicar.',
          ),
          _Seccion(
            icono: Icons.document_scanner_outlined,
            titulo: 'Escáner de albaranes',
            texto:
                'Fotografía el albarán al recibir el género. La IA extrae las '
                'líneas (producto, cantidad, precio) y la app las casa con tu '
                'catálogo: verde = casado automático, ámbar = sugerencia para '
                'confirmar, gris = sin coincidencia (elige el producto o crea '
                'uno nuevo).\n\n'
                'ALERTA DE SUBIDAS: bajo cada línea verás el último precio '
                'pagado a ese proveedor. Si el nuevo sube un 10% o más, sale '
                'en ROJO; si baja, en verde. Las subidas silenciosas ya no se '
                'cuelan.\n\n'
                'Al guardar, la compra queda registrada y los precios entran '
                'en el histórico.\n\n'
                'Si el escáner da error: ⏳ espera un minuto (demasiadas '
                'lecturas seguidas), 📷 haz la foto con menos resolución '
                '(demasiado grande), 💳 recarga saldo de la API.',
          ),
          _Seccion(
            icono: Icons.receipt_long_outlined,
            titulo: 'Compras (el registro)',
            texto:
                'Historial de todas las compras guardadas, con sus líneas y '
                'totales. Puedes editar un precio si el albarán se leyó mal: '
                'la corrección se refleja también en el histórico del '
                'producto.',
          ),
          _Seccion(
            icono: Icons.bar_chart,
            titulo: 'Informes y cierre de mes',
            texto:
                'En el icono de gráficas (arriba):\n\n'
                '• COMPARADOR de proveedores: quién te sale más barato en el '
                'conjunto de tu catálogo.\n\n'
                '• CIERRE DE MES (icono PDF): elige un mes y genera el informe '
                'con gasto total, desglose por proveedor y por categoría, top '
                '10 de productos por gasto y las mayores variaciones de '
                'precio. Perfecto para gerencia o para renegociar con un '
                'proveedor con datos en la mano.',
          ),
          _Seccion(
            icono: Icons.show_chart,
            titulo: 'Detalle de producto: evolución y estacionalidad',
            texto:
                'Toca un producto en la Comparativa para ver su ficha:\n\n'
                '• EVOLUCIÓN: cómo se ha movido el precio de cada proveedor en '
                'el tiempo.\n\n'
                '• ESTACIONALIDAD: precio medio por mes del año (aparece '
                'cuando hay datos de al menos 3 meses). El mes más caro en '
                'rojo y el más barato en verde: útil para anticipar cambios '
                'de carta.\n\n'
                '• HISTÓRICO: todos los registros, editables uno a uno.',
          ),
          _Seccion(
            icono: Icons.restaurant_menu,
            titulo: 'ESCANDALLO e importaciones',
            texto:
                'Desde el menú de tres puntos:\n\n'
                '• EXPORTAR A ESCANDALLO: genera el archivo con los últimos '
                'precios para importarlo en la app ESCANDALLO y calcular '
                'costes de platos con precios reales.\n\n'
                '• IMPORTAR DE COMPRAS COCINA: migración desde la app antigua '
                '(productos, proveedores y precios).',
          ),
          _Seccion(
            icono: Icons.devices,
            titulo: 'Móvil, escritorio y sincronización',
            texto:
                'La app funciona en el móvil (APK) y en cualquier ordenador '
                'desde el navegador (versión web instalable: en Chrome, menú ⋮ '
                '→ "Instalar ComparaPrecios").\n\n'
                'Todo se guarda en la nube al instante: lo que apuntes en el '
                'PC aparece en el móvil y al revés. Ideal: montar la lista '
                'tranquilo en el escritorio y pedir por WhatsApp desde el '
                'móvil en cocina.',
          ),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  final bool inicioAbierto;
  const _Seccion({
    required this.icono,
    required this.titulo,
    required this.texto,
    this.inicioAbierto = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: Icon(icono),
        title: Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        initiallyExpanded: inicioAbierto,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: const TextStyle(height: 1.4)),
        ],
      ),
    );
  }
}
