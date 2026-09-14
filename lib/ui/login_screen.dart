import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pantalla de acceso. La cuenta se crea desde la consola de Firebase,
/// aquí solo se inicia sesión (no hay registro).
///
/// Guarda el correo y la contraseña cifrados en el dispositivo (no en texto
/// plano) para poder reconectar sola cuando Firebase pierde la sesión por su
/// cuenta al reabrir la app. Esto es un problema documentado y sin arreglo
/// oficial en ciertos Android (Xiaomi entre ellos): Firebase dice que no hay
/// usuario aunque el login anterior fue correcto. La app no puede evitar que
/// Firebase "olvide", pero sí puede volver a entrar sin pedírtelo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Guardado de credenciales, aislado para poder usarlo también al arrancar
/// la app (ver ReconectorAutomatico más abajo) sin duplicar claves ni lógica.
class CredencialesGuardadas {
  static const _almacen = FlutterSecureStorage();
  static const _kEmail = 'cp_email';
  static const _kPassword = 'cp_password';

  static Future<void> guardar(String email, String password) async {
    await _almacen.write(key: _kEmail, value: email);
    await _almacen.write(key: _kPassword, value: password);
  }

  static Future<void> borrar() async {
    await _almacen.delete(key: _kEmail);
    await _almacen.delete(key: _kPassword);
  }

  static Future<(String, String)?> leer() async {
    final email = await _almacen.read(key: _kEmail);
    final password = await _almacen.read(key: _kPassword);
    if (email == null || password == null) return null;
    return (email, password);
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _cargando = false;
  bool _recordar = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final email = _email.text.trim();
    final password = _password.text;
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (_recordar) {
        await CredencialesGuardadas.guardar(email, password);
      } else {
        await CredencialesGuardadas.borrar();
      }
      // No navegamos: el "portero" del arranque detecta la sesión y entra solo.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _mensaje(e.code));
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar sesión. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _mensaje(String code) => switch (code) {
        'invalid-email' => 'El correo no es válido.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Correo o contraseña incorrectos.',
        'network-request-failed' => 'Sin conexión a internet.',
        'too-many-requests' => 'Demasiados intentos. Espera un momento.',
        _ => 'No se pudo iniciar sesión ($code).',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.restaurant_menu,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('ComparaPrecios',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _entrar(),
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _recordar,
                onChanged: (v) => setState(() => _recordar = v ?? true),
                title: const Text('Mantener la sesión iniciada',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Evita tener que volver a escribir la contraseña si el '
                  'teléfono cierra la sesión solo',
                  style: TextStyle(fontSize: 11),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _cargando ? null : _entrar,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _cargando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Entrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
