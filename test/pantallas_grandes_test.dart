import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:panaderoso_pedidos/logic/cart.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/customer/customer_home.dart';
import 'package:panaderoso_pedidos/ui/customer/flavor_picker.dart';
import 'package:panaderoso_pedidos/ui/product_image.dart';
import 'package:panaderoso_pedidos/ui/theme.dart';
import 'package:panaderoso_pedidos/ui/widgets.dart';

/// Guarda un número en su estado: si el widget se vuelve a crear, regresa a 0.
class _Contador extends StatefulWidget {
  const _Contador();
  @override
  State<_Contador> createState() => _ContadorState();
}

class _ContadorState extends State<_Contador> {
  int n = 0;
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: () => setState(() => n++), child: Text('van $n'));
}

void main() {
  group('Pantallas grandes (tablet y plegables)', () {
    test('en el celular la lista queda igual; en tablet se centra', () {
      const base = EdgeInsets.fromLTRB(16, 4, 16, 32);
      expect(ReadableList.pad(390, base), base);
      final tablet = ReadableList.pad(1000, base, maxWidth: 680);
      expect(1000 - tablet.horizontal, 680);
      expect(tablet.left, tablet.right);
      expect(tablet.top, 4);
      expect(tablet.bottom, 32);
    });

    testWidgets('girar la tablet (pasar el ancho de 1140) no borra la pantalla en la que ibas',
        (tester) async {
      Future<void> conAncho(double w) async {
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
          theme: buildPanTheme(),
          builder: (context, child) => WideFrame(child: child!),
          home: const Scaffold(body: Center(child: _Contador())),
        ));
        await tester.pump();
      }

      addTearDown(tester.view.reset);
      await conAncho(800);
      await tester.tap(find.text('van 0'));
      await tester.pump();
      expect(find.text('van 1'), findsOneWidget);
      await conAncho(1280); // tablet acostada: entra el marco
      expect(find.text('van 1'), findsOneWidget);
      expect(tester.getSize(find.byType(Scaffold)).width, WideFrame.maxWidth);
      await conAncho(800); // y de regreso
      expect(find.text('van 1'), findsOneWidget);
    });

    testWidgets('el menú de dos columnas se mide bien con panes con sabores (donas)', (tester) async {
      // Las dos tarjetas de una fila van en IntrinsicHeight: todo lo de adentro
      // tiene que poder medirse sin errores (sabores, botón de sabores, cantidad).
      const donas = Product(id: 'd', name: 'Donas', price: 25);
      const choco = Product(id: 'a', name: 'Chocolatín', price: 35);
      final cart = Cart()
        ..addFlavor(donas, donas.flavors.first)
        ..add(choco);
      addTearDown(cart.dispose);
      expect(donas.hasFlavors, isTrue);
      Widget tarjeta(Product p) => PanCard(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ProductHero(product: p, size: 96),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name),
                      if (p.hasFlavors) CartFlavorLine(product: p, cart: cart),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(r'$25'),
                          const Spacer(),
                          if (p.hasFlavors)
                            FlavorCartButton(product: p, cart: cart)
                          else
                            QtyStepper(qty: cart.qtyOf(p.id), onAdd: () {}, onRemove: () {}),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
      await tester.pumpWidget(MaterialApp(
        theme: buildPanTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 760,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tarjeta(choco)),
                  const SizedBox(width: 12),
                  Expanded(child: tarjeta(donas)),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Donas'), findsOneWidget);
      // Las dos tarjetas quedan del mismo alto.
      final alturas = tester
          .widgetList<PanCard>(find.byType(PanCard))
          .map((c) => tester.getSize(find.byWidget(c)).height)
          .toSet();
      expect(alturas.length, 1);
    });
  });
}
