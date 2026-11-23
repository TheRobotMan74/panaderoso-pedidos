import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/archive.dart';
import 'package:panaderoso_pedidos/models.dart';

BakeryOrder _o(
  String date, {
  OrderStatus status = OrderStatus.entregado,
  PaymentMethod pay = PaymentMethod.efectivo,
  bool collected = true,
  int qty = 2,
  int fee = 0,
}) =>
    BakeryOrder(
      id: '',
      customerId: 'c',
      customerName: 'Cliente',
      phone: '',
      address: '',
      items: [OrderItem(productId: 'p', name: 'Chocolatín', price: 35, qty: qty)],
      deliveryDate: date,
      slot: '16:00',
      paymentMethod: pay,
      status: status,
      cashCollected: collected,
      shippingFee: fee,
    );

const _today = '2026-11-22';
const _closed = DeliveryDay(date: _today, open: true, slots: ['16:00'], closed: true);
const _open = DeliveryDay(date: _today, open: true, slots: ['16:00']);

void main() {
  group('dayFinished', () {
    test('un día que ya pasó siempre se archiva', () {
      expect(dayFinished('2026-11-20', [_o('2026-11-20', status: OrderStatus.recibido)], today: _today, days: {}),
          isTrue);
    });

    test('un día futuro nunca', () {
      expect(dayFinished('2026-11-25', [_o('2026-11-25')], today: _today, days: {}), isFalse);
    });

    test('hoy: todo entregado y ya se salió a repartir', () {
      expect(dayFinished(_today, [_o(_today), _o(_today)], today: _today, days: {_today: _closed}), isTrue);
    });

    test('hoy: todo entregado y el día se quitó de Días', () {
      expect(dayFinished(_today, [_o(_today)], today: _today, days: {}), isTrue);
    });

    test('hoy: todo entregado pero el día sigue abierto (puede llegar otro)', () {
      expect(dayFinished(_today, [_o(_today)], today: _today, days: {_today: _open}), isFalse);
    });

    test('hoy: falta uno por entregar', () {
      expect(
        dayFinished(_today, [_o(_today), _o(_today, status: OrderStatus.enCamino)],
            today: _today, days: {_today: _closed}),
        isFalse,
      );
    });

    test('hoy: los cancelados no cuentan, pero solo cancelados no archiva', () {
      final cancelled = _o(_today, status: OrderStatus.cancelado);
      expect(dayFinished(_today, [_o(_today), cancelled], today: _today, days: {}), isTrue);
      expect(dayFinished(_today, [cancelled], today: _today, days: {}), isFalse);
    });

    test('hoy: mientras no cargan los días no se archiva', () {
      expect(dayFinished(_today, [_o(_today)], today: _today, days: {}, daysLoaded: false), isFalse);
    });
  });

  test('finishedDates agrupa por día', () {
    final orders = [_o('2026-11-20'), _o(_today), _o('2026-11-25', status: OrderStatus.recibido)];
    expect(finishedDates(orders, today: _today, days: {}), {'2026-11-20', _today});
  });

  test('SalesSummary cuenta solo lo entregado', () {
    final s = SalesSummary.of([
      _o('2026-11-20', qty: 5, fee: 20), // 175 + 20, efectivo cobrado
      _o('2026-11-20', pay: PaymentMethod.transferencia, qty: 2), // 70, sin verificar
      _o('2026-11-22', collected: false, qty: 1), // 35, efectivo sin cobrar
      _o('2026-11-22', status: OrderStatus.cancelado, qty: 9),
      _o('2026-11-21', status: OrderStatus.confirmado, qty: 3),
    ]);
    expect(s.days, 2);
    expect(s.delivered, 3);
    expect(s.pieces, 8);
    expect(s.sold, 300);
    expect(s.cash, 230);
    expect(s.transfer, 70);
    expect(s.shipping, 20);
    expect(s.unpaid, 105);
    expect(s.unpaidCount, 2);
    expect(s.notDelivered, 1);
  });
}
