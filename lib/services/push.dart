import 'package:firebase_messaging/firebase_messaging.dart';

import '../models.dart';
import 'repo.dart';

/// Notificaciones: guarda el token del celular, y el dueño se suscribe
/// al tema "dueno" para enterarse de cada pedido nuevo.
/// Quien manda los avisos es la función de functions/index.js.
class Push {
  static Future<void> register(AppUser user) async {
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
}
