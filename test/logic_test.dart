import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

import 'package:panaderoso_pedidos/logic/day_route.dart';
import 'package:panaderoso_pedidos/logic/demand.dart';
import 'package:panaderoso_pedidos/logic/geo.dart';
import 'package:panaderoso_pedidos/logic/route.dart';
import 'package:panaderoso_pedidos/logic/schedule.dart';
import 'package:panaderoso_pedidos/logic/shipping.dart';
import 'package:panaderoso_pedidos/logic/stock.dart';
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

  group('Cupo de panes', () {
    const choco = Product(id: 'choco', name: 'Chocolatín', price: 30, stockGroup: 'Masa de croissant');
    const jyq = Product(id: 'jyq', name: 'Croissant de jamón y queso', price: 35, stockGroup: 'masa de croissant ');
    const pizza = Product(id: 'pizza', name: 'Croissant de pizza', price: 35, stockGroup: 'Masa de croissant');
    const donas = Product(id: 'donas', name: 'Donas', price: 20);
    final byId = {for (final p in [choco, jyq, pizza, donas]) p.id: p};
    OrderItem item(Product p, int qty) => OrderItem(productId: p.id, name: p.name, price: p.price, qty: qty);

    test('los de la misma masa comparten cupo y las donas van aparte', () {
      final groups = stockGroups([choco, jyq, pizza, donas]);
      expect(groups.length, 2);
      expect(groups[0].key, 'g:masa de croissant');
      expect(groups[0].label, 'Masa de croissant');
      expect(groups[0].products.length, 3);
      expect(groups[0].productNames, 'Chocolatín, Croissant de jamón y queso y Croissant de pizza');
      expect(groups[1].key, 'p:donas');
      expect(groups[1].shared, false);
      // Un producto nuevo sin grupo tiene su propio cupo.
      expect(stockKey(const Product(id: 'orejas', name: 'Orejas', price: 15)), 'p:orejas');
    });

    test('20 de chocolate + 5 + 5 son 30 del mismo cupo', () {
      final need = needByGroup([item(choco, 20), item(jyq, 5), item(pizza, 5), item(donas, 3)], byId);
      expect(need, {'g:masa de croissant': 30, 'p:donas': 3});
    });

    test('cuánto queda y cuándo ya no alcanza', () {
      const day = DeliveryDay(
        date: '2026-11-23',
        open: true,
        slots: ['08:00'],
        stock: {'g:masa de croissant': 30, 'p:donas': 12},
      );
      const stock = DayStock(date: '2026-11-23', used: {'g:masa de croissant': 25, 'p:donas': 12});
      expect(remainingFor(day, stock, 'g:masa de croissant'), 5);
      expect(remainingFor(day, stock, 'p:donas'), 0);
      expect(remainingFor(day, stock, 'p:otro'), isNull);
      expect(totalRemaining(day, stock), 5);
      expect(totalRemaining(day, null), 42);
      expect(overLimit(day, stock, {'g:masa de croissant': 5}), isEmpty);
      expect(overLimit(day, stock, {'g:masa de croissant': 6}), ['g:masa de croissant']);
      expect(overLimit(day, stock, {'p:donas': 1, 'p:otro': 99}), ['p:donas']);
      expect(remainingText(40), 'quedan 40 panes');
      expect(remainingText(1), 'queda 1 pan');
      expect(remainingText(0), 'agotado');
    });

    test('se lee el cupo y el pedido movido desde la base de datos', () {
      final d = DeliveryDay.fromMap('2026-11-23', {
        'open': true,
        'slots': ['08:00'],
        'stock': {'p:donas': 12.0},
      });
      expect(d.stock, {'p:donas': 12});
      expect(d.toMap()['stock'], {'p:donas': 12});
      expect(DayStock.fromMap('x', null).used, isEmpty);
      final o = BakeryOrder.fromMap('o', {
        'deliveryDate': '2026-11-25',
        'slot': '09:00',
        'movedFrom': {'date': '2026-11-23', 'slot': '08:00'},
      });
      expect(o.wasMoved, true);
      expect(o.movedFromDate, '2026-11-23');
      expect(Product.fromMap('p', {'name': 'Donas'}).stockGroup, '');
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

  group('Ruta mejorada', () {
    (String, String, Point?) p(String id, String slot, double lat, double lng) => (id, slot, (lat, lng));
    List<String> ids(List<(String, String, Point?)> r) => r.map((e) => e.$1).toList();
    double len(List<(String, String, Point?)> r, Point? start, {bool back = false}) =>
        routeLength(r, (e) => e.$3, start: start, end: back ? start : null);

    // Como en Monterrey: casa al oriente; a la 1:00 centro (1) y poniente (2,3,4);
    // a las 2:00 una en el centro (5) y otra muy al poniente (6).
    const casa = (25.67, -100.20);
    final dia = [
      p('1', '13:00', 25.668, -100.31),
      p('2', '13:00', 25.70, -100.36),
      p('3', '13:00', 25.715, -100.33),
      p('4', '13:00', 25.72, -100.32),
      p('5', '14:00', 25.665, -100.31),
      p('6', '14:00', 25.78, -100.45),
    ];

    test('ya no deja la parada lejana para el final si conviene pasar antes', () {
      final r = routeOrder(dia, slot: (e) => e.$2, position: (e) => e.$3, start: casa, returnToStart: true);
      // Termina la 1:00 cerca de la 6 y deja la 5 (cerca de casa) al último.
      expect(ids(r).sublist(4), ['6', '5']);
      expect(ids(r).last, '5');
      expect(r.take(4).every((e) => e.$2 == '13:00'), true);
    });

    test('la ruta exacta es la más corta posible (contra probar todas)', () {
      final rnd = Random(7);
      for (var t = 0; t < 30; t++) {
        final n = 3 + rnd.nextInt(4);
        final stops = [
          for (var i = 0; i < n; i++)
            p('$i', rnd.nextBool() ? '08:00' : '09:00', 25 + rnd.nextDouble() / 10, -100 + rnd.nextDouble() / 10),
        ];
        const start = (25.05, -99.95);
        final back = rnd.nextBool();
        final r = routeOrder(stops, slot: (e) => e.$2, position: (e) => e.$3, start: start, returnToStart: back);
        var best = double.infinity;
        void perm(List<(String, String, Point?)> done, List<(String, String, Point?)> left) {
          if (left.isEmpty) {
            for (var i = 1; i < done.length; i++) {
              if (done[i].$2.compareTo(done[i - 1].$2) < 0) return;
            }
            best = min(best, len(done, start, back: back));
            return;
          }
          for (final x in left) {
            perm([...done, x], [...left]..remove(x));
          }
        }

        perm([], stops);
        expect(len(r, start, back: back), closeTo(best, 0.5));
      }
    });

    test('con muchas casas también respeta horarios y no deja a nadie', () {
      final rnd = Random(3);
      final stops = [
        for (var i = 0; i < 40; i++)
          p('$i', ['08:00', '09:00', '10:00'][i % 3], 25 + rnd.nextDouble() / 10, -100 + rnd.nextDouble() / 10),
      ];
      const start = (25.0, -100.0);
      final r = routeOrder(stops, slot: (e) => e.$2, position: (e) => e.$3, start: start, returnToStart: true);
      expect(r.toSet().length, 40);
      for (var i = 1; i < r.length; i++) {
        expect(r[i].$2.compareTo(r[i - 1].$2) >= 0, true);
      }
    });

    test('el orden a mano se respeta y los nuevos se acomodan en su horario', () {
      final r = applySavedOrder<(String, String, Point?)>(
        dia,
        ['6', '1', '2', '3', '4'],
        id: (e) => e.$1,
        slot: (e) => e.$2,
        position: (e) => e.$3,
        start: casa,
      );
      expect(ids(r).sublist(0, 5), ['6', '1', '2', '3', '4']);
      expect(ids(r).last, '5'); // De las 2:00: no puede ir antes de los de la 1:00.
      expect(earlyStops(r, (e) => e.$2), [true, false, false, false, false, false]);
    });

    test('cuántas entregas faltan antes de cada cliente', () {
      BakeryOrder o(String id, String uid, OrderStatus st) => BakeryOrder(
            id: id,
            customerId: uid,
            customerName: uid,
            phone: '',
            address: '',
            items: const [],
            deliveryDate: '2026-11-22',
            slot: '13:00',
            paymentMethod: PaymentMethod.efectivo,
            status: st,
          );
      final a = aheadByCustomer([
        o('1', 'ana', OrderStatus.entregado),
        o('2', 'beto', OrderStatus.enCamino),
        o('3', 'caro', OrderStatus.enCamino),
        o('4', 'beto', OrderStatus.enCamino),
      ]);
      expect(a, {'beto': 0, 'caro': 1});
    });
  });

  group('envío por distancia (igual que el servidor)', () {
    const r = ShippingRules(enabled: true);
    int fee(double lat, double lng, int p) =>
        r.feeForTrip(baseLat: 19.70, baseLng: -101.19, homeLat: lat, homeLng: lng, pieces: p);
    test('mismos resultados que costoEnvio de functions/index.js', () {
      expect(fee(19.75, -101.15, 1), 30);
      expect(fee(19.75, -101.15, 3), 10);
      expect(fee(19.75, -101.15, 6), 0);
      expect(fee(19.70, -101.19, 1), 0);
      expect(fee(19.8, -101.3, 1), 60);
    });
    test('sin punto de salida o sin casa: gratis', () {
      expect(r.feeForTrip(baseLat: null, baseLng: null, homeLat: 19.75, homeLng: -101.15, pieces: 1), 0);
      expect(r.feeForTrip(baseLat: 19.7, baseLng: -101.19, homeLat: null, homeLng: null, pieces: 1), 0);
    });
    test('apagado: gratis', () {
      expect(
          const ShippingRules().feeForTrip(
              baseLat: 19.70, baseLng: -101.19, homeLat: 19.75, homeLng: -101.15, pieces: 1),
          0);
    });
    test('roadFactor se guarda y se lee', () {
      expect(ShippingRules.fromMap(const ShippingRules(roadFactor: 1.5).toMap()).roadFactor, 1.5);
      expect(ShippingRules.fromMap({'enabled': true}).roadFactor, 1.3);
    });
  });
}
