import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/archive.dart';
import 'package:panaderoso_pedidos/logic/schedule.dart';
import 'package:panaderoso_pedidos/models.dart';

void main() {
  DeliveryDay day(String id, String start, {PickupPoint? pickup}) =>
      DeliveryDay(date: id, open: true, slots: [start], pickup: pickup);

  test('varios repartos el mismo día: ids, fecha y orden', () {
    expect(newDayId('2026-11-25', const []), '2026-11-25');
    expect(newDayId('2026-11-25', ['2026-11-25']), '2026-11-25-2');
    expect(newDayId('2026-11-25', ['2026-11-25', '2026-11-25-2']), '2026-11-25-3');
    expect(dayDateOf('2026-11-25-2'), '2026-11-25');
    expect(parseDateKey('2026-11-25-2'), DateTime(2026, 11, 25));
    expect(day('2026-11-25-2', '12:00').day, '2026-11-25');

    final acuity = day('2026-11-25-2', '07:45', pickup: const PickupPoint(name: 'Acuity', lat: 0, lng: 0));
    final casa = day('2026-11-25', '12:00');
    final otro = day('2026-11-27', '08:00');
    final sorted = [otro, casa, acuity]..sort(compareDays);
    expect(sorted.map((d) => d.date), ['2026-11-25-2', '2026-11-25', '2026-11-27']);
    expect(repartoTag('2026-11-25-2', sorted), '7:45 · Acuity');
    expect(repartoTag('2026-11-25', sorted), '12:00 · a domicilio');
    expect(repartoTag('2026-11-27', sorted), isNull);

    final hoy = orderableDays(sorted, DateTime(2026, 11, 25, 6));
    expect(hoy.length, 3);
  });

  test('un reparto extra de hoy se archiva como el de la fecha', () {
    final o = BakeryOrder(
      id: 'a',
      customerId: 'c',
      customerName: 'C',
      phone: '',
      address: '',
      items: const [],
      deliveryDate: '2026-11-25-2',
      slot: '07:45',
      paymentMethod: PaymentMethod.efectivo,
      status: OrderStatus.entregado,
    );
    const closed = DeliveryDay(date: '2026-11-25-2', open: true, slots: ['07:45'], closed: true);
    expect(
      dayFinished('2026-11-25-2', [o], today: '2026-11-25', days: {'2026-11-25-2': closed}),
      isTrue,
    );
    expect(dayFinished('2026-11-26-2', [o], today: '2026-11-25', days: const {}), isFalse);
  });
}
