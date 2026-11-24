import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Una APK más nueva que la instalada, publicada en GitHub Releases.
class NewApk {
  /// El número de la versión: el 25 de "Panaderoso v25".
  final int number;

  /// Enlace directo para descargar la APK.
  final Uri download;

  const NewApk(this.number, this.download);
}

/// Novedades de la app. Hay dos tipos:
///
/// - **Mejoras** (parches de Shorebird): cambios de pantallas y de lógica. Se bajan solas
///   al abrir la app y se ven la siguiente vez que se abre. No hay que instalar nada.
/// - **APK nueva**: cuando cambia algo que un parche no puede llevar (permisos, plugins,
///   imágenes, ícono). Se publica en GitHub Releases y la app ofrece descargarla.
class Updates {
  Updates._();

  static const repo = 'TheRobotMan74/panaderoso-pedidos';

  /// GitHub contesta este enlace con una redirección a la última versión (".../tag/v25").
  /// Así no se usa la API de GitHub, que tiene límite de consultas por hora.
  static final _latest = Uri.parse('https://github.com/$repo/releases/latest');

  static ShorebirdUpdater? _shorebirdInstance;
  static ShorebirdUpdater get _shorebird => _shorebirdInstance ??= ShorebirdUpdater();

  /// Enlace de descarga de la APK de la versión [number].
  static Uri apkUrl(int number) =>
      Uri.parse('https://github.com/$repo/releases/download/v$number/panaderoso.apk');

  /// Saca el número de versión de un enlace como ".../releases/tag/v25". Null si no es de una versión.
  static int? numberFromTagUrl(String url) {
    final m = RegExp(r'/releases/tag/v(\d+)/?$').firstMatch(url.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Número de la versión instalada (el de "Panaderoso v25"). 0 si no se sabe.
  static Future<int> installedNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Tienda que instaló la app en Android: "com.android.vending" es Google Play.
  static const playStore = 'com.android.vending';

  /// true si la app se instaló desde Google Play (no con la APK de GitHub).
  static Future<bool> installedFromPlay() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return isPlayInstaller(info.installerStore);
    } catch (_) {
      return false;
    }
  }

  /// true si [installer] (el que instaló la app) es Google Play.
  static bool isPlayInstaller(String? installer) => installer == playStore;

  /// La versión más nueva publicada en GitHub, o null si no hay internet o no se pudo leer.
  static Future<int?> latestPublishedNumber() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(_latest);
      req.followRedirects = false;
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      final location = res.headers.value(HttpHeaders.locationHeader);
      return location == null ? null : numberFromTagUrl(location);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// La APK nueva si hay una más reciente que la instalada. Solo en la app instalada
  /// (no al programar ni en las pruebas).
  static Future<NewApk?> checkNewApk() async {
    // La versión web (iPhone) se actualiza sola al abrirla: no hay APK que bajar.
    if (kIsWeb || !kReleaseMode || !Platform.isAndroid) return null;
    // Instalada desde Google Play: Play se encarga de las versiones nuevas (sus reglas no
    // dejan que la app ofrezca bajar otra APK). Las mejoras de Shorebird sí llegan igual.
    if (await installedFromPlay()) return null;
    final installed = await installedNumber();
    if (installed <= 0) return null;
    final latest = await latestPublishedNumber();
    if (latest == null || latest <= installed) return null;
    return NewApk(latest, apkUrl(latest));
  }

  /// Revisa si hay una mejora y la baja. Regresa true cuando ya está bajada y solo falta
  /// cerrar y volver a abrir la app para verla.
  ///
  /// La app de todos modos baja las mejoras sola al abrirse; esto solo sirve para avisar.
  static Future<bool> downloadPatch() async {
    if (!kReleaseMode) return false;
    try {
      final sb = _shorebird;
      if (!sb.isAvailable) return false;
      var status = await sb.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        try {
          await sb.update();
        } on UpdateException catch (_) {
          // Puede que ya se estuviera bajando sola; abajo se vuelve a revisar.
        }
        status = await sb.checkForUpdate();
      }
      return status == UpdateStatus.restartRequired;
    } catch (_) {
      return false;
    }
  }

  /// Número de la mejora puesta ahorita (1, 2, 3…), o null si no tiene ninguna.
  static Future<int?> currentPatch() async {
    if (!kReleaseMode) return null;
    try {
      final sb = _shorebird;
      if (!sb.isAvailable) return null;
      return (await sb.readCurrentPatch())?.number;
    } catch (_) {
      return null;
    }
  }

  /// Texto para mostrar en Ajustes, como "Versión 25 · mejora 2".
  static String label(int version, int? patch) => [
        if (version > 0) 'Versión $version' else 'Versión de prueba',
        if (patch != null && patch > 0) 'mejora $patch',
      ].join(' · ');

  /// Lo mismo que [label], leyendo la versión y la mejora del celular.
  static Future<String> versionLabel() async => label(await installedNumber(), await currentPatch());
}
