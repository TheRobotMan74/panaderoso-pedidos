import 'package:firebase_core/firebase_core.dart';

/// Datos del proyecto de Firebase de Panaderoso.
///
/// Se llenan una sola vez, al crear el proyecto en
/// https://console.firebase.google.com (ver README, "Configurar Firebase").
/// Estos datos no son secretos: identifican al proyecto, y la seguridad
/// la ponen las reglas de firestore.rules y storage.rules.
class DefaultFirebaseOptions {
  static const android = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
  );

  /// false mientras falten los datos de arriba.
  static bool get isConfigured =>
      android.apiKey.isNotEmpty && android.appId.isNotEmpty;
}
