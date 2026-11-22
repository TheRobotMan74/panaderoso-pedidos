/// Versión para Android: aquí nada de esto aplica.
class WebPlatform {
  WebPlatform._();

  static bool get isIos => false;
  static bool get isStandalone => true;
  static String get notificationPermission => 'unsupported';
  static bool get mapsReady => false;
  static Future<bool> loadGoogleMaps(String key) async => false;
  static Future<Map<String, String>?> firebaseHostingConfig() async => null;
}
