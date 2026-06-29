import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart'; // generado por flutterfire configure
import 'services/firestore_service.dart';
import 'ui/compras_screen.dart';
import 'ui/dashboard_screen.dart';
import 'ui/informes_screen.dart';
import 'ui/lista_compra_screen.dart';
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
      home: const RaizScreen(),
    );
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
