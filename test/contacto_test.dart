import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/customer/contact_card.dart';
import 'package:panaderoso_pedidos/ui/format.dart';
import 'package:panaderoso_pedidos/ui/theme.dart';

Widget _app(Widget child, {double width = 360}) => MaterialApp(
      theme: buildPanTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  group('Contacto al final del menú', () {
    test('el teléfono se escribe como en México', () {
      expect(prettyPhone('8129332077'), '81 2933 2077');
      expect(prettyPhone('+52 81 2933-2077'), '81 2933 2077');
      expect(prettyPhone('4431234567'), '443 123 4567');
      expect(prettyPhone('12345'), '12345');
    });

    test('sin nada en Ajustes sale Alfonso con su número', () {
      expect(contactNameOf(null), 'Alfonso Núñez');
      expect(contactPhoneOf(null), '8129332077');
      expect(contactNameOf(const AppConfig(contactName: '  ')), 'Alfonso Núñez');
    });

    test('lo de Ajustes gana y se guarda', () {
      final c = AppConfig.fromMap(const {'contactName': 'Panaderoso', 'whatsapp': '81 1111 2222'});
      expect(contactNameOf(c), 'Panaderoso');
      expect(contactPhoneOf(c), '8111112222');
      expect(AppConfig.fromMap(c.toMap()).contactName, 'Panaderoso');
    });

    test('iniciales del nombre', () {
      expect(initialsOf('Alfonso Núñez'), 'AN');
      expect(initialsOf('panaderoso'), 'P');
      expect(initialsOf('Ángel de la Torre'), 'ÁD');
    });

    for (final width in [320.0, 360.0, 700.0, 960.0]) {
      testWidgets('se dibuja sin errores a ${width.toInt()} de ancho', (tester) async {
        await tester.pumpWidget(
            _app(const ContactCardView(name: 'Alfonso Núñez', phone: '8129332077'), width: width));
        expect(find.text('Alfonso Núñez'), findsOneWidget);
        expect(find.text('81 2933 2077'), findsOneWidget);
        expect(find.text('WhatsApp'), findsOneWidget);
        expect(find.text('Llamar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tocar el número lo copia', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      await tester.pumpWidget(_app(const ContactCardView(name: 'Alfonso Núñez', phone: '81 2933 2077')));
      await tester.tap(find.text('81 2933 2077'));
      await tester.pump();
      expect(copied, '8129332077');
      expect(find.text('Número copiado'), findsOneWidget);
    });
  });
}
