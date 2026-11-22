import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'services/push.dart';
import 'services/repo.dart';
import 'ui/customer/customer_home.dart';
import 'ui/login_page.dart';
import 'ui/owner/owner_home.dart';
import 'ui/profile_page.dart';
import 'ui/theme.dart';
import 'ui/update_watcher.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
    // App Check: cada pedido, foto o consulta lleva un "pase" que dice que viene de
    // nuestra app original (revisado por Google con Play Integrity) y no de un programa
    // copiado. Las APK de prueba usan el pase de pruebas (sale en el registro del celular).
    // Si algo falla, la app sigue abriendo igual.
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kReleaseMode
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
      );
    } catch (e) {
      debugPrint('App Check no se pudo activar: $e');
    }
    // Los correos de Firebase (por ejemplo "restablecer contraseña") y su página van en español.
    try {
      await FirebaseAuth.instance.setLanguageCode('es');
    } catch (_) {}
  }
  runApp(const PanaderosoApp());
}

class PanaderosoApp extends StatelessWidget {
  const PanaderosoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panaderoso',
      debugShowCheckedModeBanner: false,
      theme: buildPanTheme(),
      home: DefaultFirebaseOptions.isConfigured
          ? const AuthGate()
          : const _NotConfiguredPage(),
    );
  }
}

/// Decide qué pantalla ver: iniciar sesión, completar datos, cliente o dueño.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) return const _Loading();
        final fbUser = auth.data;
        if (fbUser == null) return const FadeThroughSwitcher(child: LoginPage());
        return StreamBuilder<AppUser?>(
          stream: Repo.instance.userStream(fbUser.uid),
          builder: (context, snap) {
            final Widget page;
            final user = snap.data;
            // Los clientes deben marcar su casa en el mapa (las cuentas viejas también, una vez).
            final needsPin = user != null && user.role == Role.cliente && !user.hasLocation;
            if (snap.connectionState == ConnectionState.waiting) {
              page = const _Loading(key: ValueKey('cargando'));
            } else if (user == null || user.name.isEmpty || user.address.isEmpty || needsPin) {
              page = ProfilePage(key: const ValueKey('perfil'), uid: fbUser.uid, existing: user);
            } else {
              page = _RoleHome(key: const ValueKey('inicio'), user: user);
            }
            // Del oso de "cargando" a la app con un fundido suave.
            return FadeThroughSwitcher(child: page);
          },
        );
      },
    );
  }
}

class _RoleHome extends StatefulWidget {
  final AppUser user;
  const _RoleHome({super.key, required this.user});

  @override
  State<_RoleHome> createState() => _RoleHomeState();
}

class _RoleHomeState extends State<_RoleHome> {
  Role? _registeredRole;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registerPush();
  }

  @override
  void didUpdateWidget(_RoleHome old) {
    super.didUpdateWidget(old);
    _registerPush();
  }

  void _registerPush() {
    if (_registeredRole == widget.user.role) return;
    _registeredRole = widget.user.role;
    // Si el usuario no da permiso de notificaciones, la app sigue funcionando.
    Push.register(widget.user).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => UpdateWatcher(
        child: widget.user.role == Role.dueno
            ? OwnerHome(user: widget.user)
            : CustomerHome(user: widget.user),
      );
}

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Pan.crema,
        body: Center(child: FloatingBear(size: 112)),
      );
}

class _NotConfiguredPage extends StatelessWidget {
  const _NotConfiguredPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Falta conectar la app con Firebase.\n\n'
              'Llena lib/firebase_options.dart con los datos del proyecto '
              '(ver README, "Configurar Firebase").',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
