import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Datos del navegador donde corre la versión web.
class WebPlatform {
  WebPlatform._();

  /// iPhone o iPad (los iPad nuevos dicen ser Mac, pero tienen pantalla táctil).
  static bool get isIos {
    final ua = web.window.navigator.userAgent;
    if (RegExp(r'iPhone|iPad|iPod').hasMatch(ua)) return true;
    return ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1;
  }

  /// true cuando se abrió desde el ícono de la pantalla de inicio (no desde una pestaña).
  static bool get isStandalone {
    if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
    final standalone = web.window.navigator.getProperty<JSAny?>('standalone'.toJS);
    return standalone.isA<JSBoolean>() && (standalone as JSBoolean).toDart;
  }

  /// 'granted', 'denied', 'default' o 'unsupported' (Safari fuera de la pantalla de inicio).
  static String get notificationPermission {
    if (!web.window.has('Notification')) return 'unsupported';
    return web.Notification.permission;
  }

  static bool _mapsReady = false;

  /// true cuando ya cargó Google Maps para web.
  static bool get mapsReady => _mapsReady;

  /// Carga Google Maps (Maps JavaScript API) con la llave web. false si no se pudo.
  static Future<bool> loadGoogleMaps(String key) async {
    if (key.isEmpty) return false;
    if (_mapsReady) return true;
    final script = web.HTMLScriptElement()
      ..src =
          'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeComponent(key)}'
          '&language=es&region=MX&loading=async&callback=Function.prototype';
    final done = script.onLoad.first.then((_) => true);
    final failed = script.onError.first.then((_) => false);
    web.document.head!.append(script);
    final ok = await Future.any([done, failed]).timeout(const Duration(seconds: 15), onTimeout: () => false);
    if (!ok) return false;
    // Con loading=async, google.maps se termina de armar un instante después.
    for (var i = 0; i < 50; i++) {
      final google = web.window.getProperty<JSObject?>('google'.toJS);
      if (google != null && google.has('maps') && (google.getProperty<JSObject>('maps'.toJS)).has('Map')) {
        _mapsReady = true;
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// Datos del proyecto de Firebase para la web. Firebase Hosting los sirve solo en
  /// /__/firebase/init.json, así que no hay que copiarlos al código.
  static Future<Map<String, String>?> firebaseHostingConfig() async {
    try {
      final res = await http.get(Uri.base.resolve('/__/firebase/init.json')).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          if (e.value is String) e.key: e.value as String,
      };
    } catch (_) {
      return null;
    }
  }
}
