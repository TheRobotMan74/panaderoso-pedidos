import 'package:flutter_test/flutter_test.dart';

import 'package:panaderoso_pedidos/logic/promos.dart';
import 'package:panaderoso_pedidos/models.dart';

BakeryOrder _order(int paid,
        {int loyaltyGift = 0,
        int welcomeGift = 0,
        bool counted = true,
        int donas = 0,
        DateTime? at,
        OrderStatus status = OrderStatus.recibido}) =>
    BakeryOrder(
      id: '',
      customerId: 'c',
      customerName: 'Cliente',
      phone: '',
      address: '',
      items: [
        if (paid > 0) OrderItem(productId: 'choco', name: 'Chocolatín', price: 30, qty: paid),
        if (donas > 0) OrderItem(productId: 'dona', name: 'Dona', price: 20, qty: donas),
        if (loyaltyGift > 0)
          OrderItem(productId: 'choco', name: 'Chocolatín', price: 0, qty: loyaltyGift, gift: giftLoyalty),
        if (welcomeGift > 0)
          OrderItem(productId: 'choco', name: 'Chocolatín', price: 0, qty: welcomeGift, gift: giftWelcome),
      ],
      deliveryDate: '2026-11-25',
      slot: '08:00',
      paymentMethod: PaymentMethod.efectivo,
      status: status,
      createdAt: at,
      loyaltyPieces: counted ? paid + donas : null,
    );

List<OrderItem> _cart(int choco, [int donas = 0]) => [
      if (choco > 0) OrderItem(productId: 'choco', name: 'Chocolatín', price: 30, qty: choco),
      if (donas > 0) OrderItem(productId: 'dona', name: 'Dona', price: 20, qty: donas),
    ];

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
    expect(o.subtotal, 90);
  });

  test('la tarjeta cuenta piezas, no pedidos, y no cuenta lo de antes ni cancelados', () {
    final card = LoyaltyCard.from([
      _order(4),
      _order(3),
      _order(5, counted: false), // pedido de antes de la promoción
      _order(6, status: OrderStatus.cancelado),
    ], rules);
    expect(card.pieces, 7);
    expect(card.progress, 7);
    expect(card.missing, 3);
  });

  test('el pedido que llega a 10 lleva el chocolatín', () {
    final prev = [_order(7)];
    expect(previewGifts(rules: rules, myOrders: prev, items: _cart(2)).loyalty, 0);
    expect(previewGifts(rules: rules, myOrders: prev, items: _cart(3)).loyalty, 1);
    // Ya se lo dieron: el siguiente pedido no lleva otro hasta las 20.
    final after = [_order(7), _order(3, loyaltyGift: 1)];
    expect(LoyaltyCard.from(after, rules).progress, 0);
    expect(previewGifts(rules: rules, myOrders: after, items: _cart(9)).loyalty, 0);
    expect(previewGifts(rules: rules, myOrders: after, items: _cart(10)).loyalty, 1);
    // 25 piezas de un jalón = 2 chocolatines.
    expect(previewGifts(rules: rules, myOrders: const [], items: _cart(25)).loyalty, 2);
  });

  test('pan de bienvenida: solo el primer pedido y con el mínimo', () {
    expect(previewGifts(rules: rules, myOrders: const [], items: _cart(1)).welcome, isFalse);
    expect(previewGifts(rules: rules, myOrders: const [], items: _cart(2)).welcome, isTrue);
    expect(previewGifts(rules: rules, myOrders: [_order(2)], items: _cart(2)).welcome, isFalse);
    // Si su único pedido se canceló, sigue siendo su primero.
    expect(
      previewGifts(rules: rules, myOrders: [_order(2, status: OrderStatus.cancelado)], items: _cart(2))
          .welcome,
      isTrue,
    );
    const off = PromoRules(welcomeEnabled: false, loyaltyEnabled: false);
    expect(previewGifts(rules: off, myOrders: const [], items: _cart(30)).total, 0);
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

  test('el dueño ve la tarjeta de cada cliente', () {
    BakeryOrder de(String id, String name, BakeryOrder o) => BakeryOrder(
          id: '',
          customerId: id,
          customerName: name,
          phone: '81',
          address: '',
          items: o.items,
          deliveryDate: o.deliveryDate,
          slot: o.slot,
          paymentMethod: o.paymentMethod,
          status: o.status,
          loyaltyPieces: o.loyaltyPieces,
        );
    final list = customersLoyalty([
      de('ana', 'Ana', _order(3, welcomeGift: 1)),
      de('ana', 'Ana', _order(5)),
      de('beto', 'Beto', _order(9, counted: false)),
      de('caro', 'Caro', _order(12, loyaltyGift: 1)),
      de('caro', 'Caro', _order(2, status: OrderStatus.cancelado)),
    ], rules);
    expect(list.map((c) => c.name), ['Ana', 'Caro', 'Beto']);
    final ana = list[0];
    expect(ana.card.pieces, 8);
    expect(ana.welcomeUsed, isTrue);
    expect(ana.orders, 2);
    final caro = list[1];
    expect(caro.card.progress, 2);
    expect(caro.loyaltyGiven, 1);
    expect(caro.orders, 1);
    expect(list[2].card.pieces, 0);
  });

  test('los croissants también suman, las donas no', () {
    final items = [
      const OrderItem(productId: 'jyq', name: 'Croissant jamón y queso', price: 35, qty: 2),
      const OrderItem(productId: 'piz', name: 'Croissant de pizza', price: 35, qty: 1),
      ..._cart(1, 4),
    ];
    expect(loyaltyPiecesOf(rules, items), 4);
    final ps = [
      const Product(id: 'choco', name: 'Chocolatín', price: 30),
      const Product(id: 'piz', name: 'Croissant de pizza', price: 35),
      const Product(id: 'dona', name: 'Dona', price: 20),
    ];
    expect(loyaltyProducts(rules, ps).map((p) => p.id), ['choco', 'piz']);
  });

  test('solo suman los chocolatines (y croissants)', () {
    final card = LoyaltyCard.from([_order(2, donas: 8)], rules);
    expect(card.pieces, 2);
    expect(card.progress, 2);
    // 8 donas no llenan la tarjeta; 8 chocolatines sí.
    expect(previewGifts(rules: rules, myOrders: [_order(2)], items: _cart(0, 8)).loyalty, 0);
    expect(previewGifts(rules: rules, myOrders: [_order(2)], items: _cart(8)).loyalty, 1);
    expect(loyaltyPiecesOf(rules, _cart(3, 5)), 3);
  });

  test('el dueño puede elegir qué panes suman', () {
    const donas = PromoRules(loyaltyProductIds: ['dona']);
    expect(loyaltyPiecesOf(donas, _cart(3, 5)), 5);
    expect(
        PromoRules.fromMap({
          'loyaltyProductIds': ['dona', 3, '']
        }).loyaltyProductIds,
        ['dona']);
    expect(PromoRules.fromMap(null).loyaltyProductIds, isEmpty);
  });

  test('lo que ya se regaló con la regla vieja no se cobra', () {
    // Como Rene: 20 piezas que no eran chocolatín y ya se llevó 2 gratis.
    final viejo = _order(0, donas: 20, loyaltyGift: 2, at: DateTime(2026, 11, 23));
    final card = LoyaltyCard.from([viejo], rules);
    expect(card.given, 2);
    expect(card.progress, 0);
    expect(card.pending, 0);
    // Empieza de 0, no "debe" 20 chocolatines.
    final despues = [viejo, _order(4, at: DateTime(2026, 11, 26))];
    expect(LoyaltyCard.from(despues, rules).progress, 4);
    expect(previewGifts(rules: rules, myOrders: despues, items: _cart(6)).loyalty, 1);
  });
}
