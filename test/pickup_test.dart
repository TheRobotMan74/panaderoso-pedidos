import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panaderoso_pedidos/logic/promos.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/customer/tracking_page.dart';
import 'package:panaderoso_pedidos/ui/pickup_widgets.dart';

BakeryOrder _order({String? pickup, bool arrived = false, OrderStatus status = OrderStatus.recibido}) =>
    BakeryOrder(
      id: 'o',
      customerId: 'c',
      customerName: 'Ana',
      phone: '',
      address: pickup == null ? 'Calle 1' : 'Entrega en $pickup',
      items: const [OrderItem(productId: 'p', name: 'Dona', price: 20, qty: 3)],
      deliveryDate: '2026-11-28',
      slot: '10:00',
      paymentMethod: PaymentMethod.efectivo,
      status: status,
      loyaltyPieces: 3,
      pickupName: pickup,
      arrivalNotified: arrived,
    );

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  test('día especial: lee y guarda el lugar', () {
    final d = DeliveryDay.fromMap('2026-11-28', {
      'open': true,
      'slots': ['10:00'],
      'punto': {'name': 'FIME', 'lat': 25.72, 'lng': -100.31, 'notes': 'Entrada'},
    });
    expect(d.isPickup, isTrue);
    expect(d.pickup!.label, 'Entrega en FIME');
    expect(d.toMap()['punto'], {'name': 'FIME', 'lat': 25.72, 'lng': -100.31, 'notes': 'Entrada'});
    // Sin nombre o sin mapa no cuenta como especial.
    expect(
        DeliveryDay.fromMap('x', {
          'punto': {'name': '', 'lat': 1, 'lng': 2}
        }).isPickup,
        isFalse);
    expect(
        DeliveryDay.fromMap('x', {
          'punto': {'name': 'FIME'}
        }).isPickup,
        isFalse);
    expect(DeliveryDay.fromMap('x', {'open': true}).isPickup, isFalse);
  });

  test('pedido de día especial no gasta el pan de bienvenida', () {
    const rules = PromoRules();
    final orders = [_order(pickup: 'FIME')];
    expect(isFirstOrder(orders), isTrue);
    expect(previewGifts(rules: rules, myOrders: orders, paidPieces: 2).welcome, isTrue);
    expect(previewGifts(rules: rules, myOrders: orders, paidPieces: 2, pickupDay: true).welcome, isFalse);
    expect(isFirstOrder([_order()]), isFalse);
  });

  test('pedido de día especial sí cuenta para la tarjeta', () {
    final card = LoyaltyCard.from([_order(pickup: 'FIME'), _order()]);
    expect(card.pieces, 6);
    final p = previewGifts(
        rules: const PromoRules(), myOrders: [_order(pickup: 'FIME')], paidPieces: 7, pickupDay: true);
    expect(p.loyalty, 1);
  });

  test('seguimiento: ya llegó al lugar', () {
    final v = trackingView(
        order: _order(pickup: 'FIME', arrived: true),
        info: null,
        home: null,
        now: DateTime(2026, 11, 28, 10));
    expect(v.title, '¡Ya estamos en FIME!');
  });

  test('inicio: solo salen los días especiales que se pueden pedir', () {
    final now = DateTime(2026, 11, 24, 12);
    const p = PickupPoint(name: 'FIME', lat: 1, lng: 2);
    final days = [
      const DeliveryDay(date: '2026-11-28', open: true, slots: ['10:00'], pickup: p),
      const DeliveryDay(date: '2026-11-29', open: true, slots: ['10:00']),
      const DeliveryDay(date: '2026-11-30', open: false, slots: ['10:00'], pickup: p),
    ];
    expect(upcomingPickupDays(days, now).map((d) => d.date), ['2026-11-28']);
  });
}
