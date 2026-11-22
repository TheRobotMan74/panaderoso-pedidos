import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/customer/customer_home.dart';
import 'package:panaderoso_pedidos/ui/owner/route_editor_page.dart';
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

  testWidgets('ordenar ruta a mano: arrastrar cambia el orden y "Optimizar" lo regresa', (tester) async {
    BakeryOrder o(String id, String slot) => BakeryOrder(
          id: id,
          customerId: id,
          customerName: 'Cliente $id',
          phone: '',
          address: 'Calle $id',
          items: const [],
          deliveryDate: '2026-11-22',
          slot: slot,
          paymentMethod: PaymentMethod.efectivo,
        );
    await initializeDateFormatting('es_MX');
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(MaterialApp(
      theme: buildPanTheme(),
      home: RouteEditorPage(
        date: '2026-11-22',
        initial: [o('a', '13:00'), o('b', '13:00'), o('c', '14:00')],
        cfg: const AppConfig(),
        manual: false,
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Cliente a'), findsOneWidget);
    expect(find.text('Optimizar'), findsOneWidget);

    // Mantener presionada la "c" y subirla hasta arriba.
    final drag = await tester.startGesture(tester.getCenter(find.text('Cliente c')));
    await tester.pump(const Duration(seconds: 1));
    for (var k = 0; k < 20; k++) {
      await drag.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await drag.up();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text('Cliente c')).dy < tester.getTopLeft(find.text('Cliente a')).dy, true);
    expect(find.text('· llegas antes de su horario'), findsOneWidget);

    await tester.tap(find.text('Optimizar'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text('Cliente c')).dy > tester.getTopLeft(find.text('Cliente b')).dy, true);
    await tester.binding.setSurfaceSize(null);
  });
}
