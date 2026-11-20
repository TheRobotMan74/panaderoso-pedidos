import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/demand.dart';
import 'package:panaderoso_pedidos/logic/schedule.dart';
import 'package:panaderoso_pedidos/logic/shipping.dart';
import 'package:panaderoso_pedidos/models.dart';

BakeryOrder _order(String date, String slot, Map<String, int> items,
        {OrderStatus status = OrderStatus.recibido}) =>
    BakeryOrder(
      id: '',
      customerId: 'c',
      customerName: 'Cliente',
      phone: '',
      address: '',
      items: [
        for (final e in items.entries) OrderItem(productId: e.key, name: e.key, price: 20, qty: e.value),
      ],
      deliveryDate: date,
      slot: slot,
      paymentMethod: PaymentMethod.efectivo,
      status: status,
    );

void main() {
  group('Costo de envío', () {
    const rules = ShippingRules(enabled: true);

    test('coincide con la tabla del documento', () {
      // piezas → [3 km, 8 km, 15 km]
      const expected = {
        1: [10, 25, 45],
        2: [10, 25, 45],
        3: [5, 15, 25],
        5: [5, 15, 25],
        6: [0, 0, 0],
        20: [0, 0, 0],
      };
      expected.forEach((pieces, fees) {
        expect(
          [3.0, 8.0, 15.0].map((km) => rules.feeFor(km: km, pieces: pieces)).toList(),
          fees,
          reason: '$pieces piezas',
        );
      });
    });

    test('apagado es gratis', () {
      expect(const ShippingRules().feeFor(km: 15, pieces: 1), 0);
    });

    test('envío gratis desde 6 piezas', () {
      expect(rules.freeFromPieces(), 6);
    });

    test('se guarda y se lee igual', () {
      final back = ShippingRules.fromMap(rules.toMap());
      expect(back.feeFor(km: 8, pieces: 4), rules.feeFor(km: 8, pieces: 4));
    });
  });

  group('Días y horarios', () {
    test('horarios de una hora de 8 a 11', () {
      expect(hourlySlots(8, 11), ['08:00', '09:00', '10:00']);
      expect(slotLabel('08:00'), '8:00 a 9:00');
    });

    test('la hora límite es el día anterior', () {
      expect(defaultCutoff('2026-11-23', hour: 18), DateTime(2026, 11, 22, 18));
      expect(defaultCutoff('2026-12-01'), DateTime(2026, 11, 30, 18));
    });

    test('solo se puede pedir a días abiertos antes de la hora límite', () {
      DeliveryDay day(String date, {bool open = true}) => DeliveryDay(
            date: date,
            open: open,
            slots: const ['08:00'],
            orderCutoff: defaultCutoff(date),
          );
      final now = DateTime(2026, 11, 22, 19); // domingo 7 PM
      final days = [day('2026-11-25'), day('2026-11-23'), day('2026-11-27', open: false)];
      expect(orderableDays(days, now).map((d) => d.date), ['2026-11-25']);
    });
  });

  group('Demanda', () {
    test('suma piezas por horario y producto, sin cancelados', () {
      final orders = [
        _order('2026-11-23', '08:00', {'Chocolatín': 3, 'Donas': 2}),
        _order('2026-11-23', '08:00', {'Chocolatín': 1}),
        _order('2026-11-23', '10:00', {'Donas': 4}),
        _order('2026-11-23', '10:00', {'Donas': 9}, status: OrderStatus.cancelado),
        _order('2026-11-25', '08:00', {'Donas': 5}),
      ];
      final d = demandForDay('2026-11-23', orders, slotOrder: ['08:00', '09:00', '10:00']);
      expect(d.orders, 3);
      expect(d.pieces, 10);
      expect(d.totalByProduct, {'Chocolatín': 4, 'Donas': 6});
      expect(d.slots.map((s) => s.slot), ['08:00', '09:00', '10:00']);
      expect(d.slots[0].pieces, 6);
      expect(d.slots[1].orders, 0);
    });
  });
}
