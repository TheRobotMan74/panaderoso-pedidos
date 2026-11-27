import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/logic/market.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/market/market_pos_page.dart';
import 'package:panaderoso_pedidos/ui/theme.dart';

const _choco = MarketItem(productId: 'choco', name: 'Chocolatín', price: 35, qty: 2);
const _donas = MarketItem(
  productId: 'donas',
  name: 'Donas',
  price: 25,
  qty: 4,
  flavors: {'Chocolate': 1, 'Glaseado': 3, 'Caramelo': 0},
);
const _market = Market(id: 'm1', date: '2026-11-28', place: 'Mercadito Cumbres', items: [_choco, _donas]);

MarketSale _sale(String id, List<OrderItem> items,
        {MarketPay pay = MarketPay.efectivo, bool cancelled = false}) =>
    MarketSale(
      id: id,
      marketId: 'm1',
      date: '2026-11-28',
      items: items,
      total: items.fold(0.0, (s, i) => s + i.total),
      pay: pay,
      cancelled: cancelled,
    );

void main() {
  group('Mercadito: lógica', () {
    test('cada sabor es su propio botón, en orden, y sin los que no llevas', () {
      final units = marketUnits(_market);
      expect(units.map((u) => u.label), ['Chocolatín', 'Donas · Glaseado', 'Donas · Chocolate']);
      expect(units.map((u) => u.brought), [2, 3, 1]);
    });

    test('lo que queda no cuenta las ventas canceladas', () {
      final units = marketUnits(_market);
      final sales = [
        _sale('a', const [
          OrderItem(productId: 'choco', name: 'Chocolatín', price: 35, qty: 1),
          OrderItem(productId: 'donas', name: 'Donas', price: 25, qty: 2, flavors: {'Glaseado': 2}),
        ]),
        _sale('b', const [OrderItem(productId: 'choco', name: 'Chocolatín', price: 35, qty: 1)],
            cancelled: true),
      ];
      final left = remainingByUnit(units, sales);
      expect(left[unitKey('choco', '')], 1);
      expect(left[unitKey('donas', 'Glaseado')], 1);
      expect(left[unitKey('donas', 'Chocolate')], 1);
    });

    test('la cuenta no deja pasar de lo que queda y junta los sabores en un renglón', () {
      final units = marketUnits(_market);
      final t = MarketTicket();
      expect(t.add(unitKey('choco', ''), left: 2), isTrue);
      expect(t.add(unitKey('choco', ''), left: 2), isTrue);
      expect(t.add(unitKey('choco', ''), left: 2), isFalse, reason: 'solo llevas 2');
      t.add(unitKey('donas', 'Chocolate'), left: 1);
      t.add(unitKey('donas', 'Glaseado'), left: 3);
      t.add(unitKey('donas', 'Glaseado'), left: 3);
      expect(t.pieces, 5);
      expect(t.total(units), 2 * 35 + 3 * 25);
      final items = t.toItems(units);
      expect(items, hasLength(2));
      expect(items[0].qty, 2);
      expect(items[1].name, 'Donas');
      expect(items[1].qty, 3);
      expect(items[1].flavors, {'Chocolate': 1, 'Glaseado': 2});
    });

    test('si alguien más vendió, la cuenta se ajusta a lo que queda', () {
      final t = MarketTicket()
        ..add('choco|', left: 5)
        ..add('choco|', left: 5)
        ..add('donas|Glaseado', left: 5);
      expect(t.fitTo({'choco|': 1}), isTrue);
      expect(t.qtyOf('choco|'), 1);
      expect(t.qtyOf('donas|Glaseado'), 0);
      expect(t.fitTo({'choco|': 1}), isFalse);
    });

    test('billetes para calcular el cambio', () {
      expect(cashOptions(85), [85, 100, 200, 500, 1000]);
      expect(cashOptions(35), [35, 50, 100, 200, 500]);
      expect(cashOptions(100), [100, 200, 500, 1000]);
      expect(cashOptions(120), [120, 150, 200, 500, 1000]);
      expect(cashOptions(0), isEmpty);
    });

    test('totales: efectivo, transferencia, piezas, sobrantes y por subir', () {
      final sales = [
        _sale('a', const [OrderItem(productId: 'choco', name: 'Chocolatín', price: 35, qty: 2)]),
        _sale(
            'b',
            const [
              OrderItem(productId: 'donas', name: 'Donas', price: 25, qty: 1, flavors: {'Glaseado': 1})
            ],
            pay: MarketPay.transferencia),
        _sale('c', const [OrderItem(productId: 'donas', name: 'Donas', price: 25, qty: 1)], cancelled: true),
        MarketSale(
          id: 'd',
          marketId: 'm1',
          date: '2026-11-28',
          items: const [OrderItem(productId: 'donas', name: 'Donas', price: 25, qty: 1)],
          total: 25,
          pending: true,
        ),
      ];
      final s = MarketSummary.of(sales, markets: const [_market]);
      expect(s.sales, 3);
      expect(s.pieces, 4);
      expect(s.total, 70 + 25 + 25);
      expect(s.cash, 95);
      expect(s.transfer, 25);
      expect(s.pending, 1);
      expect(s.brought, 6);
      expect(s.left, 2);
    });

    test('al guardar se quitan los panes y sabores en 0', () {
      final clean = cleanMarketItems(const [
        MarketItem(productId: 'x', name: 'Croissant', price: 45, qty: 0),
        MarketItem(
            productId: 'd', name: 'Donas', price: 25, qty: 0, flavors: {'Chocolate': 0, 'Glaseado': 4}),
        MarketItem(productId: 'e', name: 'Donas 2', price: 25, qty: 0, flavors: {'Chocolate': 0}),
        _choco,
      ]);
      expect(clean.map((i) => i.productId), ['d', 'choco']);
      expect(clean.first.qty, 4);
      expect(clean.first.flavors, {'Glaseado': 4});
    });

    test('el mercadito va al Historial al cerrarlo o cuando su día ya pasó', () {
      expect(marketFinished(_market, today: '2026-11-28'), isFalse);
      expect(marketFinished(_market, today: '2026-11-29'), isTrue);
      expect(
        marketFinished(const Market(id: 'x', date: '2026-11-28', open: false), today: '2026-11-28'),
        isTrue,
      );
    });

    test('la cuenta de la tablet tiene su propio rol', () {
      expect(roleFromString('caja'), Role.caja);
      expect(roleFromString('dueno'), Role.dueno);
      expect(roleFromString(null), Role.cliente);
    });
  });

  group('Mercadito: la caja', () {
    Future<List<(List<OrderItem>, double, MarketPay, double?)>> abrirCaja(
      WidgetTester tester, {
      List<MarketSale> sales = const [],
      Size size = const Size(1280, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sold = <(List<OrderItem>, double, MarketPay, double?)>[];
      final ticket = MarketTicket();
      addTearDown(ticket.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildPanTheme(),
        home: MarketPosView(
          market: _market,
          sales: sales,
          ticket: ticket,
          onSell: (items, total, pay, received) {
            sold.add((items, total, pay, received));
            return 'venta-${sold.length}';
          },
          onUndo: (_) {},
          onExit: () {},
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      return sold;
    }

    testWidgets('tocar panes arma la cuenta, cobrar la guarda y queda lista para el siguiente',
        (tester) async {
      final sold = await abrirCaja(tester);
      expect(find.text('Toca un pan para empezar'), findsOneWidget);

      await tester.tap(find.text('Chocolatín').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Chocolatín').first);
      await tester.pump(const Duration(milliseconds: 400));
      // Ya no quedan más chocolatines: el tercer toque no hace nada.
      await tester.tap(find.text('Chocolatín').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Glaseado').first);
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Cobrar \$95'), findsOneWidget);
      await tester.tap(find.text('Cobrar \$95'));
      await tester.pump(const Duration(milliseconds: 600));
      // Paga con $100: su cambio son $5.
      await tester.tap(find.text('\$100'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('\$5'), findsOneWidget);
      await tester.tap(find.text('Listo, cobrado'));
      await tester.pump(const Duration(milliseconds: 800));

      expect(sold, hasLength(1));
      final (items, total, pay, received) = sold.single;
      expect(total, 95);
      expect(pay, MarketPay.efectivo);
      expect(received, 100);
      expect(items.map((i) => '${i.qty} ${i.name}'), ['2 Chocolatín', '1 Donas']);
      expect(items[1].flavors, {'Glaseado': 1});
      expect(find.text('¡Gracias!'), findsOneWidget);

      // Se va solo y la cuenta queda vacía.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('¡Gracias!'), findsNothing);
      expect(find.text('Toca un pan para empezar'), findsOneWidget);
    });

    testWidgets('lo agotado no se puede tocar', (tester) async {
      final sold = await abrirCaja(tester, sales: [
        _sale('a', const [OrderItem(productId: 'choco', name: 'Chocolatín', price: 35, qty: 2)]),
      ]);
      expect(find.text('Agotado'), findsWidgets);
      await tester.tap(find.text('Chocolatín').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Toca un pan para empezar'), findsOneWidget);
      expect(sold, isEmpty);
    });

    testWidgets('en el celular la cuenta va abajo', (tester) async {
      await abrirCaja(tester, size: const Size(390, 800));
      await tester.tap(find.text('Glaseado').first);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Tu cuenta · 1 pieza'), findsOneWidget);
      expect(find.text('Cobrar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
