import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/demand.dart';
import 'package:panaderoso_pedidos/logic/geo.dart';
import 'package:panaderoso_pedidos/logic/route.dart';
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

    test('se puede pedir hasta que empieza el reparto, sin hora límite', () {
      DeliveryDay day(String date, {bool open = true, bool closed = false}) => DeliveryDay(
            date: date,
            open: open,
            closed: closed,
            slots: const ['08:00'],
          );
      final now = DateTime(2026, 11, 23, 9); // lunes 9 AM, ya en el día de entrega
      final days = [
        day('2026-11-25'),
        day('2026-11-23'), // hoy, todavía no sale a repartir
        day('2026-11-22'), // ayer
        day('2026-11-27', open: false),
        day('2026-11-30', closed: true),
      ];
      expect(orderableDays(days, now).map((d) => d.date), ['2026-11-23', '2026-11-25']);
    });

    test('al empezar a repartir el día se cierra', () {
      final d = DeliveryDay.fromMap('2026-11-23', {'open': true, 'slots': ['08:00'], 'closed': true});
      expect(orderableDays([d], DateTime(2026, 11, 23, 7)), isEmpty);
      // Días viejos guardados con hora límite se siguen leyendo.
      final old = DeliveryDay.fromMap('2026-11-25', {'open': true, 'slots': ['08:00'], 'orderCutoff': DateTime(2026, 11, 24, 18)});
      expect(orderableDays([old], DateTime(2026, 11, 24, 20)).length, 1);
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

  group('Ruta del día', () {
    // Casas sobre una misma calle (este-oeste), ~110 m entre cada una.
    (String, String, Point?) casa(String id, String slot, double x) => (id, slot, (19.0, -99.0 + x * 0.001));

    List<String> ids(List<(String, String, Point?)> r) => r.map((e) => e.$1).toList();

    test('va de la más cercana a la más lejana desde la salida', () {
      final stops = [casa('c', '08:00', 3), casa('a', '08:00', 1), casa('d', '08:00', 4), casa('b', '08:00', 2)];
      final r = routeOrder(stops, slot: (e) => e.$2, position: (e) => e.$3, start: (19.0, -99.0));
      expect(ids(r), ['a', 'b', 'c', 'd']);
    });

    test('respeta los horarios aunque otra casa esté más cerca', () {
      final stops = [casa('lejos8', '08:00', 9), casa('cerca9', '09:00', 1), casa('medio8', '08:00', 5)];
      final r = routeOrder(stops, slot: (e) => e.$2, position: (e) => e.$3, start: (19.0, -99.0));
      expect(ids(r), ['medio8', 'lejos8', 'cerca9']);
    });

    test('sin casa marcada va al final de su horario', () {
      final stops = [('sin', '08:00', null), casa('a', '08:00', 1), casa('b', '09:00', 2)];
      final r = routeOrder<(String, String, Point?)>(stops, slot: (e) => e.$2, position: (e) => e.$3);
      expect(ids(r), ['a', 'sin', 'b']);
    });

    test('sin punto de salida empieza por una orilla', () {
      final stops = [casa('c', '08:00', 3), casa('a', '08:00', 1), casa('b', '08:00', 2)];
      final r = routeOrder(stops, slot: (e) => e.$2, position: (e) => e.$3);
      expect(ids(r), anyOf([equals(['a', 'b', 'c']), equals(['c', 'b', 'a'])]));
    });
  });
}
