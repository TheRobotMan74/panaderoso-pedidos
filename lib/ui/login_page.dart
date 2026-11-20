import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

/// Entrar o crear cuenta con correo y contraseña.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      if (_creating) {
        await auth.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      } else {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Escribe tu correo para mandarte el enlace.');
      return;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Te mandamos un correo para cambiar tu contraseña.')),
    );
  }

  String _message(String code) => switch (code) {
        'invalid-email' => 'El correo no es válido.',
        'email-already-in-use' => 'Ya hay una cuenta con ese correo. Entra con él.',
        'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Correo o contraseña incorrectos.',
        'network-request-failed' => 'Sin internet. Revisa tu conexión.',
        _ => 'No se pudo entrar ($code).',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Icon(Icons.bakery_dining, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Panaderoso', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
            Text('Pan a domicilio', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 32),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_creating ? 'Crear cuenta' : 'Entrar'),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _creating = !_creating),
              child: Text(_creating ? 'Ya tengo cuenta' : 'Soy nuevo, crear cuenta'),
            ),
            if (!_creating)
              TextButton(onPressed: _resetPassword, child: const Text('Olvidé mi contraseña')),
          ],
        ),
      ),
    );
  }
}
