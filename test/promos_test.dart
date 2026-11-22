import 'package:flutter_test/flutter_test.dart';

import 'package:panaderoso_pedidos/logic/promos.dart';
import 'package:panaderoso_pedidos/models.dart';

BakeryOrder _order(int paid,
        {int loyaltyGift = 0,
        int welcomeGift = 0,
        bool counted = true,
        OrderStatus status = OrderStatus.recibido}) =>
    BakeryOrder(
      id: '',
      customerId: 'c',
      customerName: 'Cliente',
      phone: '',
      address: '',
      items: [
        OrderItem(productId: 'dona', name: 'Dona', price: 20, qty: paid),
        if (loyaltyGift > 0)
          OrderItem(productId: 'choco', name: 'Chocolatín', price: 0, qty: loyaltyGift, gift: giftLoyalty),
        if (welcomeGift > 0)
          OrderItem(productId: 'choco', name: 'Chocolatín', price: 0, qty: welcomeGift, gift: giftWelcome),
      ],
      deliveryDate: '2026-11-25',
      slot: '08:00',
      paymentMethod: PaymentMethod.efectivo,
      status: status,
      loyaltyPieces: counted ? paid : null,
    );

void main() {
  const rules = PromoRules();

  test('reglas por defecto: 10 piezas y mínimo 2', () {
    final r = PromoRules.fromMap(null);
    expect(r.loyaltyGoal, 10);
    expect(r.welcomeMinPieces, 2);
    expect(PromoRules.fromMap({'loyaltyGoal': 0}).loyaltyGoal, 2);
  });

  test('el pan regalado no cuenta como comprado', () {
    final o = _order(3, welcomeGift: 1);
    expect(o.pieces, 4);
    expect(o.paidPieces, 3);
    expect(o.giftCount(giftWelcome), 1);
    expect(o.subtotal, 60);
  });

  test('la tarjeta cuenta piezas, no pedidos, y no cuenta lo de antes ni cancelados', () {
    final card = LoyaltyCard.from([
      _order(4),
      _order(3),
      _order(5, counted: false), // pedido de antes de la promoción
      _order(6, status: OrderStatus.cancelado),
    ]);
    expect(card.pieces, 7);
    expect(card.progress(10), 7);
    expect(card.missing(10), 3);
  });

  test('el pedido que llega a 10 lleva el chocolatín', () {
    final prev = [_order(7)];
    expect(previewGifts(rules: rules, myOrders: prev, paidPieces: 2).loyalty, 0);
    expect(previewGifts(rules: rules, myOrders: prev, paidPieces: 3).loyalty, 1);
    // Ya se lo dieron: el siguiente pedido no lleva otro hasta las 20.
    final after = [_order(7), _order(3, loyaltyGift: 1)];
    expect(LoyaltyCard.from(after).progress(10), 0);
    expect(previewGifts(rules: rules, myOrders: after, paidPieces: 9).loyalty, 0);
    expect(previewGifts(rules: rules, myOrders: after, paidPieces: 10).loyalty, 1);
    // 25 piezas de un jalón = 2 chocolatines.
    expect(previewGifts(rules: rules, myOrders: const [], paidPieces: 25).loyalty, 2);
  });

  test('pan de bienvenida: solo el primer pedido y con el mínimo', () {
    expect(previewGifts(rules: rules, myOrders: const [], paidPieces: 1).welcome, isFalse);
    expect(previewGifts(rules: rules, myOrders: const [], paidPieces: 2).welcome, isTrue);
    expect(previewGifts(rules: rules, myOrders: [_order(2)], paidPieces: 2).welcome, isFalse);
    // Si su único pedido se canceló, sigue siendo su primero.
    expect(
      previewGifts(rules: rules, myOrders: [_order(2, status: OrderStatus.cancelado)], paidPieces: 2)
          .welcome,
      isTrue,
    );
    const off = PromoRules(welcomeEnabled: false, loyaltyEnabled: false);
    expect(previewGifts(rules: off, myOrders: const [], paidPieces: 30).total, 0);
  });

  test('el regalo es el chocolatín si el dueño no eligió otro', () {
    const ps = [
      Product(id: 'a', name: 'Dona', price: 20),
      Product(id: 'b', name: 'Chocolatín', price: 30),
    ];
    expect(giftProduct(rules, ps)?.id, 'b');
    expect(giftProduct(const PromoRules(giftProductId: 'a'), ps)?.id, 'a');
    expect(giftProduct(rules, [ps[0], ps[1].copyWith(available: false)]), isNull);
  });
}
