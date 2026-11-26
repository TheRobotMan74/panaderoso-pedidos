import 'package:material_ui/material_ui.dart';

import '../../logic/cart.dart';
import '../../logic/flavors.dart';
import '../../models.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'customer_home.dart';

/// El cliente elige cuántas de cada sabor (por ejemplo 3 donas = 2 de chocolate
/// y 1 de caramelo). Se abre desde el "+" del catálogo en los panes con sabores.
Future<void> showFlavorSheet(BuildContext context, Product product, Cart cart) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Pan.papel,
      builder: (_) => _FlavorSheet(product: product, cart: cart),
    );

class _FlavorSheet extends StatelessWidget {
  final Product product;
  final Cart cart;
  const _FlavorSheet({required this.product, required this.cart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          final qty = cart.qtyOf(product.id);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('¿De qué sabor?', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text('${product.name} · ${money(product.price)} cada una', style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                FlavorRows(product: product, cart: cart),
                const SizedBox(height: 14),
                HoneyButton(
                  icon: qty == 0 ? null : Icons.check_rounded,
                  label: qty == 0
                      ? 'Elige cuántas de cada sabor'
                      : 'Listo · $qty ${qty == 1 ? 'pieza' : 'piezas'} · ${money(product.price * qty)}',
                  onPressed: qty == 0 ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Un renglón por sabor con su [− 2 +]. Se usa en la hoja y en el detalle del pan.
class FlavorRows extends StatelessWidget {
  final Product product;
  final Cart cart;
  final double stepperSize;
  const FlavorRows({super.key, required this.product, required this.cart, this.stepperSize = 40});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Column(
        children: [
          for (final f in product.flavors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cart.flavorQty(product.id, f) > 0 ? Pan.mielClara : Pan.crema,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(flavorEmoji(f), style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f, style: theme.textTheme.titleMedium)),
                  QtyStepper(
                    qty: cart.flavorQty(product.id, f),
                    size: stepperSize,
                    onAdd: () => cart.addFlavor(product, f),
                    onRemove: () => cart.removeFlavor(product, f),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Botón del catálogo para un pan con sabores: el "+" abre la hoja de sabores y,
/// ya con piezas, muestra cuántas lleva y se toca para cambiarlas.
class FlavorCartButton extends StatelessWidget {
  final Product product;
  final Cart cart;
  const FlavorCartButton({super.key, required this.product, required this.cart});

  @override
  Widget build(BuildContext context) {
    final qty = cart.qtyOf(product.id);
    if (qty == 0) {
      return QtyStepper(qty: 0, onAdd: () => showFlavorSheet(context, product, cart), onRemove: () {});
    }
    return Tooltip(
      message: 'Cambiar sabores',
      child: Pressable(
        onTap: () => showFlavorSheet(context, product, cart),
        haptic: true,
        child: Container(
          height: 44,
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
          decoration: BoxDecoration(color: Pan.mielClara, borderRadius: BorderRadius.circular(22)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedCount(
                '$qty',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Pan.tostado),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_note_rounded, size: 22, color: Pan.tostado),
            ],
          ),
        ),
      ),
    );
  }
}

/// "2 Chocolate · 1 Caramelo" de lo que lleva en el carrito (nada si no lleva).
class CartFlavorLine extends StatelessWidget {
  final Product product;
  final Cart cart;
  const CartFlavorLine({super.key, required this.product, required this.cart});

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final f in product.flavors)
        if (cart.flavorQty(product.id, f) > 0) '${cart.flavorQty(product.id, f)} $f',
    ];
    return AnimatedSize(
      duration: Motion.of(context, Motion.rapido),
      curve: Motion.curva,
      alignment: Alignment.topLeft,
      child: parts.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                parts.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Pan.tostado,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
    );
  }
}

/// En el resumen del pedido: los sabores debajo del nombre del pan.
class OrderItemFlavors extends StatelessWidget {
  final OrderItem item;
  const OrderItemFlavors({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final s = flavorSummary(item);
    if (s.isEmpty) return const SizedBox.shrink();
    return Text(s, style: Theme.of(context).textTheme.bodySmall);
  }
}
