import 'package:material_ui/material_ui.dart';

import '../../logic/cart.dart';
import '../../models.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';
import 'customer_home.dart';

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
    final height = MediaQuery.sizeOf(context).height;
    final wide = width >= Ancho.dosColumnas;
    // En pantalla ancha la foto va a un lado: que quepa a lo alto y deje lugar a los datos.
    final hero = (width * 0.48).clamp(0.0, height - top - 96).toDouble();
    return Scaffold(
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          final qty = cart.qtyOf(product.id);
          final info = Column(
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
              if (product.available)
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
          );
          return Stack(
            children: [
              if (!wide)
                ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ProductHero(product: product, size: width, big: true),
                    Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 140), child: info),
                  ],
                )
              else
                // Tablet o plegable abierto: la foto a la izquierda y los datos a la derecha.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(24, top + 72, 12, 24),
                      child: ProductHero(
                        product: product,
                        size: hero,
                        big: true,
                        bigRadius: const BorderRadius.all(Radius.circular(36)),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(20, top + 40, 32, 140),
                        children: [info],
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
                left: wide ? hero + 56 : 20,
                right: wide ? 32 : 20,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: FadeSlideIn(
                  index: 6,
                  offset: 40,
                  child: product.available
                      ? HoneyButton(
                          icon: qty == 0 ? Icons.add_shopping_cart_rounded : Icons.check_rounded,
                          label: qty == 0 ? 'Agregar · ${money(product.price)}' : 'Listo · $qty en tu pedido',
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
