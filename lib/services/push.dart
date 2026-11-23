import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../models.dart';
import '../web/platform.dart';
import 'repo.dart';

/// Notificaciones: guarda el token del celular, y el dueño se suscribe
/// al tema "dueno" para enterarse de cada pedido nuevo.
/// Quien manda los avisos es la función de functions/index.js.
///
/// Cada vez que la app vuelve a la pantalla se revisa si las notificaciones
/// siguen prendidas ([enabled]); si sí, se vuelve a guardar el token por si se
/// había perdido (antes, si fallaba guardarlo una vez, ya no llegaban avisos).
class Push {
  /// true = prendidas, false = apagadas, null = todavía no se sabe (o es la web).
  static final enabled = ValueNotifier<bool?>(null);

  static AppUser? _user;
  static String? _token;
  static StreamSubscription<String>? _registered;
  static AppLifecycleListener? _lifecycle;
  static bool? _savedStatus;

  static Future<void> register(AppUser user) async {
    _user = user;
    _savedStatus = null;
    if (kIsWeb) {
      // iPhone: Safari solo deja pedir permiso cuando la persona toca un botón.
      // Eso lo hace el aviso de arriba (WebAppBanner → enableWeb). Aquí solo se
      // vuelve a guardar el token si ya había dado permiso antes.
      if (WebPlatform.notificationPermission == 'granted') await _registerWeb(user);
      return;
    }
    final fm = FirebaseMessaging.instance;
    // onRegistered entrega el token ahora y cada vez que cambie. Se escucha una sola vez
    // (antes se sumaba un oyente nuevo cada vez que se entraba a la cuenta).
    _registered ??= fm.onRegistered.listen((t) {
      _token = t;
      final u = _user;
      if (u != null) _saveToken(u.uid, t);
    });
    _lifecycle ??= AppLifecycleListener(onResume: () => refresh().catchError((_) {}));
    await fm.requestPermission();
    await fm.register();
    if (user.role == Role.dueno) {
      await fm.subscribeToTopic('dueno');
    } else {
      await fm.unsubscribeFromTopic('dueno');
    }
    await refresh();
  }

  /// Revisa si las notificaciones están prendidas en el celular. Si el cliente las
  /// acaba de prender, vuelve a registrar el celular para que lleguen desde ya.
  static Future<void> refresh() async {
    final user = _user;
    if (user == null || kIsWeb) return;
    final fm = FirebaseMessaging.instance;
    final s = await fm.getNotificationSettings();
    final ok =
        s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
    final wasOff = enabled.value == false;
    enabled.value = ok;
    if (_savedStatus != ok) {
      _savedStatus = ok;
      Repo.instance.savePushStatus(user.uid, ok).catchError((_) {});
    }
    if (!ok) return;
    if (wasOff) await fm.register();
    final t = _token;
    if (t != null) await _saveToken(user.uid, t);
  }

  /// Botón "Activar": pide el permiso. Regresa true si quedaron prendidas.
  /// Si Android ya no deja preguntar (lo negó antes), regresa false y la
  /// pantalla ofrece [openSettings].
  static Future<bool> ask() async {
    if (kIsWeb) {
      final u = _user;
      return u != null && await enableWeb(u);
    }
    await FirebaseMessaging.instance.requestPermission();
    await refresh();
    return enabled.value == true;
  }

  /// Abre los ajustes de Panaderoso en el celular (ahí está "Notificaciones").
  /// Al regresar a la app se revisa solo.
  static Future<void> openSettings() => Geolocator.openAppSettings();

  /// Al cerrar sesión: este celular deja de recibir los avisos de esa cuenta.
  static Future<void> forget() async {
    final u = _user, t = _token;
    _user = null;
    _savedStatus = null;
    _savedKey = null;
    enabled.value = null;
    if (u != null && t != null) {
      await Repo.instance.removeFcmToken(u.uid, t).timeout(const Duration(seconds: 4));
    }
  }

  /// Cuenta y token que ya quedaron guardados en esta sesión (para no escribir
  /// en cada regreso a la app).
  static String? _savedKey;

  static Future<void> _saveToken(String uid, String token) async {
    final key = '$uid/$token';
    if (_savedKey == key) return;
    // Si no hay internet en ese momento, se reintenta un par de veces.
    for (var i = 0; i < 3; i++) {
      try {
        await Repo.instance.saveFcmToken(uid, token);
        _savedKey = key;
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: 5 * (i + 1)));
      }
    }
  }

  /// Versión web: pide permiso (debe llamarse justo al tocar un botón) y guarda el token.
  /// Regresa true si quedaron activados los avisos.
  static Future<bool> enableWeb(AppUser user) async {
    final s = await FirebaseMessaging.instance.requestPermission();
    if (s.authorizationStatus != AuthorizationStatus.authorized) return false;
    await _registerWeb(user);
    return true;
  }

  static StreamSubscription<String>? _webRefresh;

  /// En la web se usa el token clásico de FCM (sirve igual para la función que manda avisos).
  /// Los avisos los muestra web/firebase-messaging-sw.js aunque la app esté cerrada.
  static Future<void> _registerWeb(AppUser user) async {
    final fm = FirebaseMessaging.instance;
    // ignore: deprecated_member_use
    _webRefresh ??= fm.onTokenRefresh.listen((t) {
      _token = t;
      Repo.instance.saveFcmToken(user.uid, t);
    });
    // ignore: deprecated_member_use
    final token = await fm.getToken();
    if (token != null && token.isNotEmpty) {
      _token = token;
      await Repo.instance.saveFcmToken(user.uid, token);
    }
  }
}

/// Cierra sesión quitando antes los avisos de este celular de la cuenta.
Future<void> signOutAndForgetPush() async {
  try {
    await Push.forget();
  } catch (_) {}
  await FirebaseAuth.instance.signOut();
}
