import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/logic/demand.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/owner/demand_page.dart';
import 'package:panaderoso_pedidos/ui/customer/customer_home.dart';
import 'package:panaderoso_pedidos/ui/product_image.dart';
import 'package:panaderoso_pedidos/ui/status_chip.dart';
import 'package:panaderoso_pedidos/ui/stock_widgets.dart';
import 'package:panaderoso_pedidos/ui/theme.dart';
import 'package:panaderoso_pedidos/ui/widgets.dart';

Widget _app(Widget child) => MaterialApp(
      theme: buildPanTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('Diseño', () {
    test('cada pan tiene su dibujito', () {
      expect(productArt('Donas').$1, '🍩');
      expect(productArt('Croissant de pizza').$1, '🍕');
      expect(productArt('Croissant de jamón y queso').$1, '🥐');
      expect(productArt('Cheesecake de fresa').$1, '🍰');
      expect(productArt('Algo nuevo').$1, '🍞');
    });

    test('saludo según la hora', () {
      expect(greeting(DateTime(2026, 1, 1, 2)), 'Buenas noches');
      expect(greeting(DateTime(2026, 1, 1, 8)), 'Buenos días');
      expect(greeting(DateTime(2026, 1, 1, 15)), 'Buenas tardes');
      expect(greeting(DateTime(2026, 1, 1, 21)), 'Buenas noches');
    });

    testWidgets('avance del pedido y estado se dibujan sin errores', (tester) async {
      await tester.pumpWidget(_app(const SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(status: OrderStatus.confirmado),
            OrderProgress(status: OrderStatus.confirmado),
          ],
        ),
      )));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Confirmado'), findsNWidgets(2));
      expect(find.text('Entregado'), findsOneWidget);
    });

    testWidgets('el botón de cantidad suma y resta', (tester) async {
      var qty = 0;
      await tester.pumpWidget(_app(StatefulBuilder(
        builder: (context, setState) => QtyStepper(
          qty: qty,
          onAdd: () => setState(() => qty++),
          onRemove: () => setState(() => qty--),
        ),
      )));
      expect(find.byTooltip('Quitar uno'), findsNothing);
      await tester.tap(find.byTooltip('Agregar uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Agregar uno'));
      await tester.pumpAndSettle();
      expect(qty, 2);
      await tester.tap(find.byTooltip('Quitar uno'));
      await tester.pumpAndSettle();
      expect(qty, 1);
    });

    testWidgets('sin foto se ve el dibujito del pan', (tester) async {
      await tester.pumpWidget(_app(const ProductImage(url: null, name: 'Donas', size: 80)));
      expect(find.text('🍩'), findsOneWidget);
    });
  });

  testWidgets('contador de panes en vivo', (tester) async {
    await tester.pumpWidget(_app(const SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StockTotal(left: 40),
          StockMeter(label: 'Masa de croissant', left: 12, limit: 30),
          StockMeter(label: 'Donas', left: 0, limit: 12),
        ],
      ),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Quedan 40 panes disponibles'), findsOneWidget);
    expect(find.text('quedan 12 panes de 30'), findsOneWidget);
    expect(find.text('Agotado'), findsOneWidget);
  });

  testWidgets('La tabla por horario se arma sin desbordarse en un celular', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final demand = DayDemand(
      '2026-11-22',
      [
        SlotDemand('10:00')
          ..orders = 3
          ..piecesByProduct.addAll({'Chocolatín': 13, 'Croissant de Jamón y Queso': 1, 'Dona': 6}),
        SlotDemand('11:00')
          ..orders = 3
          ..piecesByProduct.addAll({
            'Chocolatín': 10,
            'Croissant de Jamón y Queso': 4,
            'Croissant de Pizza': 2,
            'Dona': 4,
          }),
      ],
      {'Chocolatín': 23, 'Croissant de Jamón y Queso': 5, 'Croissant de Pizza': 2, 'Dona': 10},
    );
    final products = demand.totalByProduct.keys.toList()..sort();
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.all(16),
          child: SlotDemandTable(demand: demand, products: products),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Croissant\nde Jamón\ny Queso'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
  });
}
