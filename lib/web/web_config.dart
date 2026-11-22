/// Datos de la versión web (la que se abre en Safari del iPhone).
///
/// Ninguno es secreto: los dos están amarrados a la página panaderoso.web.app,
/// así que no sirven en otro lado. Se crean una sola vez con
/// scripts/preparar-web.sh (ver README, "Versión web para iPhone").
class WebConfig {
  WebConfig._();

  /// Llave de Google Maps para páginas web (Maps JavaScript API).
  /// Vacía = la web funciona igual, pero sin mapa (se busca la dirección con texto).
  static const mapsKey = '';

  /// Llave de reCAPTCHA Enterprise para App Check en la web.
  /// Vacía = la web no manda "pase" de App Check (en modo monitoreo no pasa nada).
  static const recaptchaSiteKey = '';
}
