import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/logic/cart.dart';
import 'package:panaderoso_pedidos/logic/demand.dart';
import 'package:panaderoso_pedidos/logic/flavors.dart';
import 'package:panaderoso_pedidos/logic/promos.dart';
import 'package:panaderoso_pedidos/logic/stock.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/owner/demand_page.dart';
import 'package:panaderoso_pedidos/ui/theme.dart';

const donas = Product(id: 'donas', name: 'Donas', price: 25);
const choco = Product(id: 'choco', name: 'Chocolatín', price: 30);

BakeryOrder _order(String slot, List<OrderItem> items, {OrderStatus status = OrderStatus.recibido}) =>
    BakeryOrder(
      id: '',
      customerId: 'c',
      customerName: 'Cliente',
      phone: '',
      address: '',
      items: items,
      deliveryDate: '2026-11-27',
      slot: slot,
      paymentMethod: PaymentMethod.efectivo,
      status: status,
    );

void main() {
  group('sabores del pan', () {
    test('las donas traen glaseado, chocolate y caramelo si el dueño no los ha tocado', () {
      expect(donas.flavors, ['Glaseado', 'Chocolate', 'Caramelo']);
      expect(const Product(id: 'd', name: 'Dona glaseada', price: 1).hasFlavors, isTrue);
      expect(choco.hasFlavors, isFalse);
      expect(const Product(id: 'x', name: 'Croissant de jamón y queso', price: 1).hasFlavors, isFalse);
    });

    test('lo que guarda el dueño manda (también "sin sabores")', () {
      expect(donas.copyWith(flavors: const []).hasFlavors, isFalse);
      expect(
          donas.copyWith(flavors: const ['Fresa', ' fresa ', '', 'Nutella']).flavors, ['Fresa', 'Nutella']);
      expect(choco.copyWith(flavors: const ['Relleno de chocolate']).flavors, ['Relleno de chocolate']);
    });

    test('se guardan en el producto y se leen igual', () {
      final p = Product.fromMap('d', donas.copyWith(flavors: const ['Fresa', 'Caramelo']).toMap());
      expect(p.flavors, ['Fresa', 'Caramelo']);
      // Sin tocarlos no se escribe el campo (así siguen saliendo los de siempre).
      expect(donas.toMap().containsKey('sabores'), isFalse);
      expect(Product.fromMap('d', donas.toMap()).flavors, defaultDonutFlavors);
    });
  });

  group('carrito con sabores', () {
    test('3 donas = 2 de chocolate y 1 de caramelo, y comparten el cupo de las donas', () {
      final cart = Cart();
      cart.addFlavor(donas, 'Caramelo');
      cart.addFlavor(donas, 'Chocolate');
      cart.addFlavor(donas, 'Chocolate');
      cart.add(choco);
      expect(cart.qtyOf('donas'), 3);
      expect(cart.pieces, 4);
      final dona = cart.items.firstWhere((i) => i.productId == 'donas');
      // En el orden del pan (glaseado, chocolate, caramelo).
      expect(dona.flavors, {'Chocolate': 2, 'Caramelo': 1});
      expect(dona.flavors!.keys.toList(), ['Chocolate', 'Caramelo']);
      expect(dona.toMap()['sabores'], {'Chocolate': 2, 'Caramelo': 1});
      expect(cart.items.firstWhere((i) => i.productId == 'choco').flavors, isNull);
      expect(cart.items.firstWhere((i) => i.productId == 'choco').toMap().containsKey('sabores'), isFalse);
      expect(needByGroup(cart.items, {'donas': donas, 'choco': choco}), {'p:donas': 3, 'p:choco': 1});
      expect(cart.subtotal, 3 * 25 + 30);

      cart.removeFlavor(donas, 'Chocolate');
      cart.removeFlavor(donas, 'Caramelo');
      expect(cart.qtyOf('donas'), 1);
      cart.removeFlavor(donas, 'Chocolate');
      expect(cart.qtyOf('donas'), 0);
      expect(cart.items.map((i) => i.productId), ['choco']);
    });

    test('las donas no suman a la tarjeta de lealtad, tengan el sabor que tengan', () {
      final cart = Cart()
        ..setFlavorQty(donas, 'Glaseado', 4)
        ..setQty(choco, 2);
      expect(loyaltyPiecesOf(const PromoRules(), cart.items), 2);
    });
  });

  group('cómo se muestran', () {
    test('renglón del pedido', () {
      const it = OrderItem(
        productId: 'donas',
        name: 'Donas',
        price: 25,
        qty: 3,
        flavors: {'Caramelo': 1, 'Chocolate': 2},
      );
      expect(flavorSummary(it), '2 Chocolate, 1 Caramelo');
      expect(itemLabel(it), '3 Donas (2 Chocolate, 1 Caramelo)');
      expect(itemLabel(it, times: '× '), '3 × Donas (2 Chocolate, 1 Caramelo)');
      expect(
          itemLabel(const OrderItem(productId: 'c', name: 'Chocolatín', price: 30, qty: 2)), '2 Chocolatín');
    });

    test('versión vieja de la app: las piezas sin sabor salen como "sin sabor elegido"', () {
      final it = OrderItem.fromMap({
        'productId': 'donas',
        'name': 'Donas',
        'price': 25,
        'qty': 3,
        'sabores': <String, Object?>{},
      });
      expect(it.flavors, isEmpty);
      expect(itemLabel(it), '3 Donas (3 sin sabor elegido)');
      // Pedido de antes de los sabores: como siempre.
      final old = OrderItem.fromMap({'productId': 'donas', 'name': 'Donas', 'price': 25, 'qty': 3});
      expect(old.flavors, isNull);
      expect(itemLabel(old), '3 Donas');
    });

    test('orden: glaseado, chocolate, caramelo, luego los demás; sin elegir al final', () {
      expect(sortFlavors(['Fresa', noFlavor, 'Caramelo', 'Glaseado', 'Chocolate']),
          ['Glaseado', 'Chocolate', 'Caramelo', 'Fresa', noFlavor]);
      expect(sortFlavors(['Caramelo', 'Fresa'], ['Fresa', 'Caramelo']), ['Fresa', 'Caramelo']);
    });
  });

  group('demanda por sabor', () {
    OrderItem d(Map<String, int>? f, [int? qty]) => OrderItem(
          productId: 'donas',
          name: 'Donas',
          price: 25,
          qty: qty ?? f!.values.fold(0, (a, b) => a + b),
          flavors: f,
        );

    test('cuántas donas de cada sabor por día y por horario', () {
      final orders = [
        _order('10:00', [
          d({'Chocolate': 2, 'Caramelo': 1})
        ]),
        _order('10:00', [
          d({'Glaseado': 2}),
          const OrderItem(productId: 'choco', name: 'Chocolatín', price: 30, qty: 4),
        ]),
        _order('11:00', [
          d({'Chocolate': 1, 'Glaseado': 1})
        ]),
        // Pedido viejo sin sabores ese mismo día y uno cancelado.
        _order('11:00', [d(null, 2)]),
        _order(
            '11:00',
            [
              d({'Caramelo': 5})
            ],
            status: OrderStatus.cancelado),
      ];
      final dd = demandForDay('2026-11-27', orders, slotOrder: const ['10:00', '11:00', '12:00']);
      expect(dd.totalByProduct['Donas'], 9);
      expect(dd.flavorsByProduct['Donas'], {'Chocolate': 3, 'Caramelo': 1, 'Glaseado': 3, noFlavor: 2});
      expect(dd.flavorsOf('Donas'), ['Glaseado', 'Chocolate', 'Caramelo', noFlavor]);
      expect(dd.flavorsOf('Chocolatín'), isEmpty);
      expect(dd.flavorsByProduct.containsKey('Chocolatín'), isFalse);

      final t = dd.flavorTable('Donas');
      expect(t.slots.map((s) => s.slot), ['10:00', '11:00']); // el de 12:00 no lleva donas
      expect(t.slots[0].piecesByProduct, {'Chocolate': 2, 'Caramelo': 1, 'Glaseado': 2});
      expect(t.slots[1].piecesByProduct, {'Chocolate': 1, 'Glaseado': 1, noFlavor: 2});
      expect(t.pieces, 9);
    });

    test('un día solo con pedidos de antes no muestra sabores', () {
      final dd = demandForDay('2026-11-27', [
        _order('10:00', [d(null, 3)])
      ]);
      expect(dd.flavorsByProduct, isEmpty);
    });

    testWidgets('Demanda: chips de sabores y tabla por horario de cada sabor', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final dd = demandForDay('2026-11-27', [
        _order('10:00', [
          d({'Chocolate': 2, 'Caramelo': 1})
        ]),
        _order('11:00', [
          d({'Glaseado': 4})
        ]),
      ]);
      final flavors = dd.flavorsOf('Donas');
      await tester.pumpWidget(MaterialApp(
        theme: buildPanTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                FlavorChips(counts: dd.flavorsByProduct['Donas']!, order: flavors),
                SlotDemandTable(
                  demand: dd.flavorTable('Donas'),
                  products: flavors,
                  firstColumn: 'Donas',
                  emojiFor: flavorEmoji,
                  labelFor: flavorName,
                ),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Chocolate'), findsOneWidget);
      expect(find.text('Total'), findsNWidgets(2)); // columna y renglón
      expect(find.text('7'), findsOneWidget); // total de donas
      expect(find.text('4'), findsNWidgets(3)); // donas de las 11, glaseado de las 11 y su total
    });
  });
}
