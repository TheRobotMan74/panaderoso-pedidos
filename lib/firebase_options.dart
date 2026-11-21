import 'package:firebase_core/firebase_core.dart';

/// Datos del proyecto de Firebase de Panaderoso.
///
/// Se llenan una sola vez, al crear el proyecto en
/// https://console.firebase.google.com (ver README, "Configurar Firebase").
/// Estos datos no son secretos: identifican al proyecto, y la seguridad
/// la ponen las reglas de firestore.rules y storage.rules.
class DefaultFirebaseOptions {
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyCRmrLFXwRUUlMsXE9SWtKUooWqYPyI3MI',
    appId: '1:1028279896674:android:2447d6c306b43811985f3b',
    messagingSenderId: '1028279896674',
    projectId: 'panaderoso',
    storageBucket: 'panaderoso.firebasestorage.app',
  );

  /// false mientras falten los datos de arriba.
  static bool get isConfigured =>
      android.apiKey.isNotEmpty && android.appId.isNotEmpty;
}
