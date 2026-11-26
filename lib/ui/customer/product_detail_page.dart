import 'package:material_ui/material_ui.dart';

import '../../logic/cart.dart';
import '../../models.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';
import 'customer_home.dart';
import 'flavor_picker.dart';

/// Detalle del pan: la foto "vuela" desde la lista (Hero) y se elige cuántos.
class ProductDetailPage extends StatelessWidget {
  final Product product;
  final Cart cart;
  const ProductDetailPage({super.key, required this.product, required this.cart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          final qty = cart.qtyOf(product.id);
          return Stack(
            children: [
              ListView(
                padding: EdgeInsets.zero,
                children: [
                  ProductHero(product: product, size: width, big: true),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeSlideIn(
                          index: 2,
                          child: Text(product.name, style: theme.textTheme.headlineMedium),
                        ),
                        const SizedBox(height: 6),
                        FadeSlideIn(
                          index: 3,
                          child: Text(money(product.price),
                              style: theme.textTheme.headlineSmall!.copyWith(color: Pan.caramelo)),
                        ),
                        if (product.description.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          FadeSlideIn(
                            index: 4,
                            child: Text(product.description,
                                style: theme.textTheme.bodyLarge!.copyWith(color: Pan.canela, height: 1.45)),
                          ),
                        ],
                        const SizedBox(height: 22),
                        if (product.available && product.hasFlavors)
                          FadeSlideIn(
                            index: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('¿De qué sabor?', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 4),
                                FlavorRows(product: product, cart: cart, stepperSize: 44),
                              ],
                            ),
                          )
                        else if (product.available)
                          FadeSlideIn(
                            index: 5,
                            child: Row(
                              children: [
                                Text('¿Cuántos?', style: theme.textTheme.titleMedium),
                                const Spacer(),
                                QtyStepper(
                                  qty: qty,
                                  size: 46,
                                  onAdd: () => cart.add(product),
                                  onRemove: () => cart.remove(product),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: top + 8,
                left: 12,
                child: Pressable(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Pan.papel,
                      shape: BoxShape.circle,
                      boxShadow: Pan.sombra,
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: Pan.cacao),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: FadeSlideIn(
                  index: 6,
                  offset: 40,
                  child: product.available && product.hasFlavors && qty == 0
                      ? const HoneyButton(label: 'Elige cuántas de cada sabor')
                      : product.available
                      ? HoneyButton(
                          icon: qty == 0 ? Icons.add_shopping_cart_rounded : Icons.check_rounded,
                          label: qty == 0
                              ? 'Agregar · ${money(product.price)}'
                              : 'Listo · $qty en tu pedido',
                          onPressed: () {
                            if (qty == 0) cart.add(product);
                            Navigator.pop(context);
                          },
                        )
                      : const HoneyButton(label: 'Agotado por hoy'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
