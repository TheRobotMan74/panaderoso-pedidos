import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/demand.dart';
import 'package:panaderoso_pedidos/logic/geo.dart';
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
}
