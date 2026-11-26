import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../services/repo.dart';
import 'theme.dart';
import 'widgets.dart';

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
  bool _sendingReset = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      if (_creating) {
        await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      } else {
        await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
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
    setState(() {
      _sendingReset = true;
      _error = null;
    });
    try {
      await Repo.instance.sendPasswordReset(email);
    } on FirebaseAuthException catch (e) {
      // Si el correo no existe no se dice nada, para no revelar quién tiene cuenta.
      if (e.code != 'user-not-found') {
        if (mounted) setState(() => _error = _message(e.code));
        return;
      }
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
    if (!mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Te mandamos un correo para cambiar tu contraseña. '
            'Si no lo ves en unos minutos, revisa tu carpeta de spam.'),
      ),
    );
  }

  String _message(String code) => switch (code) {
        'invalid-email' => 'El correo no es válido.',
        'email-already-in-use' => 'Ya hay una cuenta con ese correo. Entra con él.',
        'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Correo o contraseña incorrectos.',
        'network-request-failed' => 'Sin internet. Revisa tu conexión.',
        _ => 'No se pudo entrar ($code).',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _WarmBackdrop()),
          SafeArea(
            bottom: false,
            child: ReadableList(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
              maxWidth: 480,
              builder: (context, pad) => ListView(
                padding: pad,
                children: [
                  const SizedBox(height: 28),
                  const Center(child: FloatingBear(size: 132)),
                  const SizedBox(height: 22),
                  FadeSlideIn(
                    index: 1,
                    child: Text('Panaderoso',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall!.copyWith(color: Pan.tostado)),
                  ),
                  FadeSlideIn(
                    index: 2,
                    child: Text('Pan recién horneado, hasta tu puerta',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge!.copyWith(color: Pan.canela)),
                  ),
                  const SizedBox(height: 32),
                  FadeSlideIn(
                    index: 3,
                    child: PanCard(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
                      child: AnimatedSize(
                        duration: Motion.of(context, Motion.medio),
                        curve: Motion.curva,
                        alignment: Alignment.topCenter,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AnimatedCount(
                              _creating ? 'Crea tu cuenta' : '¡Qué gusto verte!',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Correo',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _busy ? null : _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              FadeSlideIn(
                                key: ValueKey(_error),
                                offset: 8,
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        size: 18, color: theme.colorScheme.error),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(_error!,
                                          style: TextStyle(
                                              color: theme.colorScheme.error, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            HoneyButton(
                              label: _creating ? 'Crear cuenta' : 'Entrar',
                              icon: _creating ? Icons.person_add_alt_1_rounded : Icons.arrow_forward_rounded,
                              busy: _busy,
                              onPressed: _submit,
                            ),
                            const SizedBox(height: 4),
                            if (!_creating)
                              TextButton(
                                onPressed: _sendingReset ? null : _resetPassword,
                                child: Text(_sendingReset ? 'Mandando el correo…' : 'Olvidé mi contraseña'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FadeSlideIn(
                    index: 4,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _creating = !_creating;
                                _error = null;
                              }),
                      child: Text(_creating ? 'Ya tengo cuenta, entrar' : '¿Primera vez? Crea tu cuenta'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo crema con dos manchas de miel difuminadas (se pinta una sola vez).
class _WarmBackdrop extends StatelessWidget {
  const _WarmBackdrop();

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.9, -0.95),
              radius: 1.0,
              colors: [Color(0xFFFFE3A3), Color(0x00FBF4E6)],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-1.1, 0.9),
                radius: 0.9,
                colors: [Color(0xFFF8DDBA), Color(0x00FBF4E6)],
              ),
            ),
          ),
        ),
      );
}
