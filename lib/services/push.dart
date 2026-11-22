import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../web/platform.dart';
import 'repo.dart';

/// Notificaciones: guarda el token del celular, y el dueño se suscribe
/// al tema "dueno" para enterarse de cada pedido nuevo.
/// Quien manda los avisos es la función de functions/index.js.
class Push {
  static Future<void> register(AppUser user) async {
    if (kIsWeb) {
      // iPhone: Safari solo deja pedir permiso cuando la persona toca un botón.
      // Eso lo hace el aviso de arriba (WebAppBanner → enableWeb). Aquí solo se
      // vuelve a guardar el token si ya había dado permiso antes.
      if (WebPlatform.notificationPermission == 'granted') await _registerWeb(user);
      return;
    }
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();
    // onRegistered entrega el token ahora y cada vez que cambie.
    fm.onRegistered.listen((t) => Repo.instance.saveFcmToken(user.uid, t));
    await fm.register();
    if (user.role == Role.dueno) {
      await fm.subscribeToTopic('dueno');
    } else {
      await fm.unsubscribeFromTopic('dueno');
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
    _webRefresh ??= fm.onTokenRefresh.listen((t) => Repo.instance.saveFcmToken(user.uid, t));
    // ignore: deprecated_member_use
    final token = await fm.getToken();
    if (token != null && token.isNotEmpty) await Repo.instance.saveFcmToken(user.uid, token);
  }
}
