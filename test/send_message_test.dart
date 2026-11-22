import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/owner/send_message_page.dart';

BakeryOrder _o(String id, String uid, String name, String date, String slot,
        {OrderStatus status = OrderStatus.confirmado}) =>
    BakeryOrder(
      id: id,
      customerId: uid,
      customerName: name,
      phone: '',
      address: '',
      items: const [],
      deliveryDate: date,
      slot: slot,
      paymentMethod: PaymentMethod.efectivo,
      status: status,
    );

void main() {
  test('un renglón por cliente, solo pendientes del día, ordenados por hora', () {
    final orders = [
      _o('1', 'ana', 'Ana', '2026-11-23', '10:00'),
      _o('2', 'beto', 'Beto', '2026-11-23', '08:00'),
      _o('3', 'ana', 'Ana', '2026-11-23', '09:30'),
      _o('4', 'caro', 'Caro', '2026-11-23', '08:00', status: OrderStatus.entregado),
      _o('5', 'dani', 'Dani', '2026-11-23', '08:00', status: OrderStatus.cancelado),
      _o('6', 'eva', 'Eva', '2026-11-24', '08:00'),
    ];
    final r = recipientsFor(orders, '2026-11-23');
    expect(r.map((p) => p.uid), ['beto', 'ana']);
    expect(r[1].slots, ['09:30', '10:00']);
    expect(r[1].slotsText, 'Entrega 9:30 · 10:00');
  });

  test('los mensajes rápidos caben en el límite', () {
    for (final q in quickMessages) {
      expect(q.length, lessThanOrEqualTo(maxMessageLength));
    }
  });
}
