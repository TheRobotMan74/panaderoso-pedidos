import 'dart:async';

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
import 'web/owner_on_android.dart';
import 'web/platform.dart';
import 'web/web_config.dart';

/// true cuando Firebase ya quedó conectado y se puede usar la app.
bool _firebaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');
  if (kIsWeb) {
    // Versión web (Safari del iPhone): todo lo suyo vive en _startWeb.
    _firebaseReady = await _startWeb();
  } else if (DefaultFirebaseOptions.isConfigured) {
    _firebaseReady = true;
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

/// Arranque de la versión web. Regresa false si no se pudo conectar con Firebase.
Future<bool> _startWeb() async {
  // Firebase Hosting entrega los datos del proyecto web; no hay que copiarlos aquí.
  final cfg = await WebPlatform.firebaseHostingConfig();
  if (cfg == null || (cfg['apiKey'] ?? '').isEmpty || (cfg['appId'] ?? '').isEmpty) return false;
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: cfg['apiKey']!,
        appId: cfg['appId']!,
        messagingSenderId: cfg['messagingSenderId'] ?? '',
        projectId: cfg['projectId'] ?? 'panaderoso',
        authDomain: cfg['authDomain'],
        storageBucket: cfg['storageBucket'],
        measurementId: cfg['measurementId'],
      ),
    ).timeout(const Duration(seconds: 25));
  } catch (e) {
    debugPrint('Firebase web no arrancó: $e');
    return false;
  }
  // App Check en la web: el "pase" lo da reCAPTCHA (invisible). En modo monitoreo,
  // sin llave o si falla, la app funciona igual.
  if (WebConfig.recaptchaSiteKey.isNotEmpty) {
    try {
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaEnterpriseProvider(WebConfig.recaptchaSiteKey),
      );
    } catch (e) {
      debugPrint('App Check web no se pudo activar: $e');
    }
  }
  try {
    await FirebaseAuth.instance.setLanguageCode('es');
  } catch (_) {}
  // El mapa carga en segundo plano: la app abre sin esperarlo.
  unawaited(WebPlatform.loadGoogleMaps(WebConfig.mapsKey));
  return true;
}

class PanaderosoApp extends StatelessWidget {
  const PanaderosoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Panaderoso',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: Push.messengerKey,
      theme: buildPanTheme(),
      home: _firebaseReady
          ? const AuthGate()
          : (kIsWeb ? const _WebOfflinePage() : const _NotConfiguredPage()),
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
  Widget build(BuildContext context) {
    // El panel del dueño (reparto con GPS, pedidos, cupos) vive en la app de Android.
    if (kIsWeb && widget.user.role == Role.dueno) return const OwnerOnAndroidPage();
    return UpdateWatcher(
      child: widget.user.role == Role.dueno
          ? OwnerHome(user: widget.user)
          : CustomerHome(user: widget.user),
    );
  }
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

/// Versión web sin conexión con Firebase (casi siempre: sin internet).
class _WebOfflinePage extends StatelessWidget {
  const _WebOfflinePage();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Pan.crema,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FloatingBear(size: 96),
                const SizedBox(height: 18),
                Text('No pudimos abrir Panaderoso',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Revisa tu internet y vuelve a abrir la app.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
