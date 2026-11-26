import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

    testWidgets('girar la tablet (pasar el ancho de 1140) no borra la pantalla en la que ibas', (tester) async {
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
  });
}
