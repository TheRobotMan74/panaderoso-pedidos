import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/services/updates.dart';

void main() {
  group('Actualizaciones', () {
    test('lee el número de versión del enlace de GitHub', () {
      const base = 'https://github.com/TheRobotMan74/panaderoso-pedidos/releases';
      expect(Updates.numberFromTagUrl('$base/tag/v25'), 25);
      expect(Updates.numberFromTagUrl('$base/tag/v130/'), 130);
      expect(Updates.numberFromTagUrl('$base/tag/prueba'), isNull);
      expect(Updates.numberFromTagUrl('$base/latest'), isNull);
    });

    test('enlace directo de la APK', () {
      expect(
        Updates.apkUrl(25).toString(),
        'https://github.com/TheRobotMan74/panaderoso-pedidos/releases/download/v25/panaderoso.apk',
      );
    });

    test('texto de la versión', () {
      expect(Updates.label(25, null), 'Versión 25');
      expect(Updates.label(25, 2), 'Versión 25 · mejora 2');
      expect(Updates.label(0, null), 'Versión de prueba');
    });

    test('fuera de la app instalada no busca nada', () async {
      expect(await Updates.checkNewApk(), isNull);
      expect(await Updates.downloadPatch(), isFalse);
      expect(await Updates.currentPatch(), isNull);
    });
  });
}
