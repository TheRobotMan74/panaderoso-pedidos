import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/ui/fold_memory.dart';
import 'package:panaderoso_pedidos/ui/theme.dart';

void main() {
  setUp(FoldMemory.resetForTest);

  test('sin tocar usa lo de fábrica; lo tocado se recuerda', () {
    expect(FoldMemory.isOpen('demanda|2099-01-01', byDefault: true), isTrue);
    expect(FoldMemory.isOpen('demanda|2099-01-02', byDefault: false), isFalse);
    FoldMemory.set('demanda|2099-01-01', false);
    expect(FoldMemory.isOpen('demanda|2099-01-01', byDefault: true), isFalse);
  });

  testWidgets('tocar el encabezado pliega y abre la tarjeta', (tester) async {
    const key = 'prueba|2099-01-01';
    await tester.pumpWidget(MaterialApp(
      theme: buildPanTheme(),
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: FoldMemory.changes,
          builder: (context, _, _) {
            final open = FoldMemory.isOpen(key, byDefault: true);
            return Column(children: [
              FoldHeader(open: open, onTap: () => FoldMemory.set(key, !open), child: const Text('Lunes')),
              FoldBody(open: open, child: const Text('Chocolatín 26')),
            ]);
          },
        ),
      ),
    ));
    expect(find.text('Chocolatín 26'), findsOneWidget);
    await tester.tap(find.text('Lunes'));
    await tester.pumpAndSettle();
    expect(find.text('Chocolatín 26'), findsNothing);
    await tester.tap(find.text('Lunes'));
    await tester.pumpAndSettle();
    expect(find.text('Chocolatín 26'), findsOneWidget);
  });
}
