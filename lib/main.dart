import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB5651D)),
        useMaterial3: true,
      ),
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
        if (fbUser == null) return const LoginPage();
        return StreamBuilder<AppUser?>(
          stream: Repo.instance.userStream(fbUser.uid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const _Loading();
            final user = snap.data;
            if (user == null || user.name.isEmpty || user.address.isEmpty) {
              return ProfilePage(uid: fbUser.uid, existing: user);
            }
            return _RoleHome(user: user);
          },
        );
      },
    );
  }
}

class _RoleHome extends StatefulWidget {
  final AppUser user;
  const _RoleHome({required this.user});

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
  Widget build(BuildContext context) => widget.user.role == Role.dueno
      ? OwnerHome(user: widget.user)
      : CustomerHome(user: widget.user);
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
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
