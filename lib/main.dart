import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart'; // generado por flutterfire configure
import 'services/exportar_escandallo.dart';
import 'services/firestore_service.dart';
import 'ui/guia_screen.dart';
import 'ui/importar_cocina_screen.dart';
import 'ui/importar_traza_screen.dart';
import 'ui/mantenimiento_screen.dart';
import 'ui/compras_screen.dart';
import 'ui/dashboard_screen.dart';
import 'ui/informes_screen.dart';
import 'ui/inventario_screen.dart';
import 'ui/lista_compra_screen.dart';
import 'ui/login_screen.dart';
import 'ui/productos_screen.dart';
import 'ui/proveedores_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('es_ES', null);
  runApp(const ComparaPreciosApp());
}

class ComparaPreciosApp extends StatelessWidget {
  const ComparaPreciosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ComparaPrecios',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      home: const _Portero(),
    );
  }
}

/// Decide qué mostrar según haya sesión o no:
/// - sin sesión → intenta reconectar sola con lo guardado; si no hay nada
///   guardado o falla, pantalla de login
/// - con sesión → la app
///
/// El intento de reconexión existe por un fallo conocido y sin arreglo
/// oficial de firebase_auth en Android (mas frecuente en algunos Xiaomi):
/// la sesión guardada por Firebase se pierde sola al cerrar la app, aunque el
/// login anterior fuera correcto. La app no puede evitar que Firebase
/// "olvide", pero sí puede volver a entrar sin pedirlo cada vez.
class _Portero extends StatelessWidget {
  const _Portero();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasData) return const RaizScreen();
        return const _ReconectorAutomatico();
      },
    );
  }
}

/// Antes de enseñar el formulario de login, prueba una vez con las
/// credenciales guardadas. Si no hay nada guardado, o si el reintento falla
/// (contraseña cambiada desde otro sitio, cuenta borrada, etc.), se borra lo
/// guardado y se cae al login normal sin quedarse reintentando en bucle.
class _ReconectorAutomatico extends StatefulWidget {
  const _ReconectorAutomatico();

  @override
  State<_ReconectorAutomatico> createState() => _ReconectorAutomaticoState();
}

class _ReconectorAutomaticoState extends State<_ReconectorAutomatico> {
  bool _probando = true;

  @override
  void initState() {
    super.initState();
    _intentar();
  }

  Future<void> _intentar() async {
    final creds = await CredencialesGuardadas.leer();
    if (creds == null) {
      if (mounted) setState(() => _probando = false);
      return;
    }
    final (email, password) = creds;
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Si funciona, el StreamBuilder de arriba detecta la sesión y este
      // widget deja de construirse: no hace falta hacer nada más aquí.
    } catch (_) {
      // Credenciales caducadas o inválidas: se borran para no reintentar
      // en bucle en cada arranque con una contraseña que ya no vale.
      await CredencialesGuardadas.borrar();
      if (mounted) setState(() => _probando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_probando) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return const LoginScreen();
  }
}

class RaizScreen extends StatefulWidget {
  const RaizScreen({super.key});

  @override
  State<RaizScreen> createState() => _RaizScreenState();
}

class _RaizScreenState extends State<RaizScreen> {
  final _db = FirestoreService();
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final titulos = [
      'Comparativa',
      'Lista compra',
      'Compras',
      'Productos',
      'Proveedores'
    ];
    final pantallas = [
      DashboardScreen(db: _db),
      ListaCompraScreen(db: _db),
      ComprasScreen(db: _db),
      ProductosScreen(db: _db),
      ProveedoresScreen(db: _db),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titulos[_tab]),
        actions: [
          IconButton(
            tooltip: 'Informes',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => InformesScreen(db: _db)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'guia') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GuiaScreen()),
                );
              } else if (v == 'exportar') {
                await ExportarEscandallo.exportar(context);
              } else if (v == 'importar') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ImportarCocinaScreen(db: _db)),
                );
             } else if (v == 'importar_traza') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ImportarTrazaScreen(db: _db)),
                );
             } else if (v == 'inventario') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => InventarioScreen(db: _db)),
                );
              } else if (v == 'mantenimiento') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MantenimientoScreen(db: _db)),
                );
              } else if (v == 'salir') {
                // Cerrar sesion a proposito SI borra lo guardado: si no, el
                // reconector automatico volveria a entrar solo un instante
                // despues, y "cerrar sesion" dejaria de servir para nada.
                await CredencialesGuardadas.borrar();
                await FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'importar_traza',
                child: Row(
                  children: [
                    Icon(Icons.receipt_long, size: 20),
                    SizedBox(width: 8),
                    Text('Importar albaranes de TRAZA'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'mantenimiento',
                child: Row(
                  children: [
                    Icon(Icons.build_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Mantenimiento'),
                  ],
                ),
              ),
             const PopupMenuItem(
                value: 'inventario',
                child: Row(
                  children: [
                    Icon(Icons.print_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Hoja de inventario'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'importar',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 20),
                    SizedBox(width: 8),
                    Text('Importar de Compras Cocina'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'exportar',
                child: Row(
                  children: [
                    Icon(Icons.restaurant_menu, size: 20),
                    SizedBox(width: 8),
                    Text('Exportar a ESCANDALLO'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'guia',
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 20),
                    SizedBox(width: 8),
                    Text('Guía de uso'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'salir',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: pantallas[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.compare_arrows), label: 'Comparativa'),
          NavigationDestination(
              icon: Icon(Icons.shopping_cart_outlined), label: 'Lista'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Compras'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), label: 'Productos'),
          NavigationDestination(
              icon: Icon(Icons.store_outlined), label: 'Proveedores'),
        ],
      ),
    );
  }
}
