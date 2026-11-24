import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../models.dart';
import '../web/platform.dart';
import 'repo.dart';

/// Notificaciones: guarda en la cuenta el "token" de este celular (la dirección a
/// la que functions/index.js manda los avisos) y el dueño se suscribe al tema
/// "dueno" para enterarse de cada pedido nuevo.
///
/// Se revisa todo cada vez que se abre la app o se vuelve a ella ([refresh]):
/// - si las notificaciones están prendidas, se vuelve a guardar el token (por si
///   se perdió, cambió, o el servidor lo quitó porque ya no servía);
/// - se guarda `pushOk` en la cuenta: true solo si están prendidas Y quedó
///   guardado el token, false si están apagadas. Así el 🔕 del dueño se corrige solo.
///
/// Ojo: se usa el token clásico de FCM (getToken). La versión anterior guardaba el
/// "FID" de onRegistered, que no es un token, y por eso no llegaban los avisos
/// a los clientes de Android (el servidor los rechazaba).
class Push {
  /// true = prendidas, false = apagadas, null = todavía no se sabe (o es la web).
  static final enabled = ValueNotifier<bool?>(null);

  static AppUser? _user;
  static String? _token;
  static StreamSubscription<String>? _tokenRefresh;
  static AppLifecycleListener? _lifecycle;
  static Future<void>? _checking;

  /// Lo último que quedó guardado en la cuenta ('uid|token|ok') y cuándo, para no
  /// escribir en cada regreso a la app (pero sí de vez en cuando, por si se borró).
  static String? _savedKey;
  static DateTime? _savedAt;
  static const _reSaveAfter = Duration(hours: 6);

  static Future<void> register(AppUser user) async {
    if (_user?.uid != user.uid) _savedKey = null;
    _user = user;
    final fm = FirebaseMessaging.instance;
    _lifecycle ??= AppLifecycleListener(onResume: () => refresh().catchError((_) {}));
    // Si el token cambia (Android a veces lo renueva), se guarda el nuevo.
    // ignore: deprecated_member_use
    _tokenRefresh ??= fm.onTokenRefresh.listen((t) {
      _token = t;
      _savedKey = null;
      refresh().catchError((_) {});
    });
    if (!kIsWeb) {
      // Cada paso por separado: si uno falla (por ejemplo, Android ya está
      // mostrando el permiso de ubicación), los demás siguen.
      try {
        await fm.requestPermission();
      } catch (_) {}
      try {
        if (user.role == Role.dueno) {
          await fm.subscribeToTopic('dueno');
        } else {
          await fm.unsubscribeFromTopic('dueno');
        }
      } catch (_) {}
    }
    // iPhone (web): Safari solo deja pedir permiso cuando la persona toca un botón.
    // Eso lo hace el aviso de arriba (WebAppBanner → enableWeb). Aquí solo se
    // vuelve a guardar el token si ya había dado permiso antes.
    await refresh();
  }

  /// Revisa si las notificaciones están prendidas y deja la cuenta al día.
  /// Si se llama varias veces a la vez, se hace una sola revisión.
  static Future<void> refresh() => _checking ??= _check().whenComplete(() => _checking = null);

  static Future<void> _check() async {
    final user = _user;
    if (user == null) return;
    final fm = FirebaseMessaging.instance;

    bool? ok;
    if (kIsWeb) {
      final p = WebPlatform.notificationPermission;
      ok = p == 'granted' ? true : (p == 'denied' ? false : null);
    } else {
      final s = await fm.getNotificationSettings();
      ok = s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
      enabled.value = ok;
    }
    if (ok == null) return; // Web: todavía no le pregunta. No se marca nada.
    if (!ok) {
      await _save(user.uid, null, false);
      return;
    }

    var t = _token;
    if (t == null || t.isEmpty) {
      try {
        // ignore: deprecated_member_use
        t = await fm.getToken().timeout(const Duration(seconds: 20));
      } catch (_) {
        t = null; // Sin internet: se vuelve a intentar al regresar a la app.
      }
      if (t == null || t.isEmpty) return;
      _token = t;
    }
    await _save(user.uid, t, true);
  }

  static Future<void> _save(String uid, String? token, bool ok) async {
    final key = '$uid|$token|$ok';
    final at = _savedAt;
    if (_savedKey == key && at != null && DateTime.now().difference(at) < _reSaveAfter) return;
    // Si no hay internet en ese momento, se reintenta un par de veces.
    for (var i = 0; i < 3; i++) {
      try {
        await Repo.instance.savePush(uid, ok: ok, token: token);
        _savedKey = key;
        _savedAt = DateTime.now();
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: 5 * (i + 1)));
      }
    }
  }

  /// Botón "Activar": pide el permiso. Regresa true si quedaron prendidas.
  /// Si Android ya no deja preguntar (lo negó antes), regresa false y la
  /// pantalla ofrece [openSettings].
  static Future<bool> ask() async {
    if (kIsWeb) {
      final u = _user;
      return u != null && await enableWeb(u);
    }
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
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
    _savedKey = null;
    _savedAt = null;
    enabled.value = null;
    if (u != null && t != null) {
      await Repo.instance.removeFcmToken(u.uid, t).timeout(const Duration(seconds: 4));
    }
  }

  /// Versión web: pide permiso (debe llamarse justo al tocar un botón) y guarda el token.
  /// Regresa true si quedaron activados los avisos.
  /// Los avisos los muestra web/firebase-messaging-sw.js aunque la app esté cerrada.
  static Future<bool> enableWeb(AppUser user) async {
    final s = await FirebaseMessaging.instance.requestPermission();
    _user ??= user;
    await refresh();
    return s.authorizationStatus == AuthorizationStatus.authorized && _token != null;
  }
}

/// Cierra sesión quitando antes los avisos de este celular de la cuenta.
Future<void> signOutAndForgetPush() async {
  try {
    await Push.forget();
  } catch (_) {}
  await FirebaseAuth.instance.signOut();
}
