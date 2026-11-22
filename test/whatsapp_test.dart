import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/ui/customer/my_orders_page.dart';

void main() {
  test('WhatsApp: 10 dígitos lleva 52 adelante y el mensaje va escrito', () {
    final u = whatsAppUrl('443 123-4567', 'Hola 🐻');
    expect(u.host, 'wa.me');
    expect(u.path, '/524431234567');
    expect(u.queryParameters['text'], 'Hola 🐻');
  });

  test('WhatsApp: si ya trae 52 no se repite', () {
    expect(whatsAppUrl('+52 443 123 4567', 'x').path, '/524431234567');
  });
}
