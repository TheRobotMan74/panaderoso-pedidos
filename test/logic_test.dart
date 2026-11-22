import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/demand.dart';
import 'package:panaderoso_pedidos/logic/geo.dart';
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
        2: [5, 10, 15],
        5: [5, 10, 15],
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

    test('envío gratis desde media docena', () {
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

  group('Mapa y reparto', () {
    test('distancia en línea recta', () {
      // Zócalo CDMX → Bellas Artes: unos 900 m.
      final d = distanceMeters(19.4326, -99.1332, 19.4352, -99.1412);
      expect(d, inInclusiveRange(850, 950));
      expect(distanceMeters(19.4, -99.1, 19.4, -99.1), 0);
    });

    test('textos de distancia y tiempo', () {
      expect(distanceLabel(347), '350 m');
      expect(distanceLabel(2440), '2.4 km');
      final now = DateTime(2026, 11, 22, 10);
      expect(agoLabel(now.subtract(const Duration(seconds: 20)), now), 'hace un momento');
      expect(agoLabel(now.subtract(const Duration(minutes: 3)), now), 'hace 3 min');
    });

    test('el pedido guarda la ubicación y empieza sin aviso de cercanía', () {
      final o = BakeryOrder(
        id: '',
        customerId: 'c',
        customerName: 'Cliente',
        phone: '',
        address: 'Calle 1',
        items: const [OrderItem(productId: 'p', name: 'Dona', price: 20, qty: 1)],
        deliveryDate: '2026-11-23',
        slot: '08:00',
        paymentMethod: PaymentMethod.efectivo,
        lat: 19.4,
        lng: -99.1,
      );
      final m = o.toNewOrderMap();
      expect(m['lat'], 19.4);
      expect(m['nearNotified'], false);
      final back = BakeryOrder.fromMap('x', m);
      expect(back.hasLocation, true);
      expect(back.isPending, true);
    });

    test('cuentas viejas sin mapa', () {
      final u = AppUser.fromMap('u', {'name': 'A', 'phone': '1', 'address': 'Calle'});
      expect(u.hasLocation, false);
      expect(AppConfig.fromMap(null).nearAlertMeters, 1000);
    });
  });
}
