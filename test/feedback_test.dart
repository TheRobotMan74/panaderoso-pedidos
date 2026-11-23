import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/logic/feedback.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/feedback_widgets.dart';
import 'package:panaderoso_pedidos/ui/theme.dart';

BakeryOrder _order(String id, String date, {OrderStatus status = OrderStatus.entregado}) => BakeryOrder(
      id: id,
      customerId: 'c1',
      customerName: 'Ana López',
      phone: '',
      address: '',
      items: const [OrderItem(productId: 'p', name: 'Chocolatín', price: 30, qty: 2)],
      deliveryDate: date,
      slot: '08:00',
      paymentMethod: PaymentMethod.efectivo,
      status: status,
    );

void main() {
  final now = DateTime(2026, 11, 23, 10);

  group('Qué pedido se puede calificar', () {
    test('entregado sí, cancelado no, pendiente de hoy no, pendiente de ayer sí', () {
      expect(canReview(_order('a', '2026-11-23'), now), isTrue);
      expect(canReview(_order('a', '2026-11-20', status: OrderStatus.cancelado), now), isFalse);
      expect(canReview(_order('a', '2026-11-23', status: OrderStatus.confirmado), now), isFalse);
      expect(canReview(_order('a', '2026-11-22', status: OrderStatus.confirmado), now), isTrue);
    });

    test('en el inicio se pide solo el último pedido', () {
      final orders = [
        _order('viejo', '2026-11-18'),
        _order('ultimo', '2026-11-21'),
        _order('futuro', '2026-11-25', status: OrderStatus.recibido),
      ];
      expect(orderToReview(orders, reviewed: {}, now: now)?.id, 'ultimo');
      // Si ya calificó el último no se le pide el anterior.
      expect(orderToReview(orders, reviewed: {'ultimo'}, now: now), isNull);
      // "Ahora no" en ese pedido.
      expect(orderToReview(orders, reviewed: {}, skipped: 'ultimo', now: now), isNull);
    });

    test('no se pide si el pedido ya es viejo', () {
      expect(orderToReview([_order('a', '2026-11-13')], reviewed: {}, now: now)?.id, 'a');
      expect(orderToReview([_order('a', '2026-11-12')], reviewed: {}, now: now), isNull);
    });

    test('lo que pidió, en texto', () {
      expect(reviewItems(_order('a', '2026-11-21')), ['2 × Chocolatín']);
    });
  });

  test('promedio y barritas por estrella', () {
    Review r(int stars) => Review(orderId: '$stars', customerId: 'c', customerName: 'A', rating: stars);
    final s = RatingSummary.of([r(5), r(5), r(4), r(1)]);
    expect(s.count, 4);
    expect(s.average, 3.75);
    expect(s.perStar, [1, 0, 0, 1, 2]);
    expect(RatingSummary.of(const []).average, 0);
  });

  test('las ideas se limpian y las vacías no se mandan', () {
    expect(cleanSuggestion('   '), isNull);
    expect(cleanSuggestion('  conchas \n de  vainilla '), 'conchas de vainilla');
    expect(cleanSuggestion('a' * 400)!.length, suggestionMaxChars);
  });

  test('reseña se lee de Firestore aunque falten datos', () {
    final r = Review.fromMap('o1', {'customerId': 'c', 'rating': 9});
    expect(r.rating, 5);
    expect(r.featured, isFalse);
    expect(r.photoPath, isNull);
    final m = Review(orderId: 'o1', customerId: 'c', customerName: 'A', rating: 4).toCustomerMap();
    expect(m['seen'], isFalse);
    expect(m['featured'], isFalse);
    expect(m.containsKey('photoPath'), isTrue);
  });

  testWidgets('las estrellas se pueden tocar', (tester) async {
    var rating = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildPanTheme(),
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) =>
                StarPicker(rating: rating, onChanged: (r) => setState(() => rating = r)),
          ),
        ),
      ),
    ));
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    await tester.tap(find.bySemanticsLabel('4 estrellas'));
    await tester.pumpAndSettle();
    expect(rating, 4);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
  });
}
