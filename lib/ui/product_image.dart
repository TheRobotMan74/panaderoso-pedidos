import 'package:material_ui/material_ui.dart';

import '../models.dart';

/// Foto del producto. Si no tiene foto, un dibujito del pan sobre un fondo cálido.
class ProductImage extends StatelessWidget {
  final String? url;
  final double size;

  /// Nombre del producto, para elegir el dibujito cuando no hay foto.
  final String name;
  final double radius;
  const ProductImage({super.key, required this.url, this.size = 64, this.name = '', this.radius = 0});

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(size: size, name: name);
    final Widget img;
    if (url == null || url!.isEmpty) {
      img = placeholder;
    } else {
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
      img = Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Se pide la foto al tamaño en pantalla: menos memoria en celulares sencillos.
        cacheWidth: px,
        errorBuilder: (_, _, _) => placeholder,
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return Stack(
            fit: StackFit.passthrough,
            children: [
              placeholder,
              AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                child: child,
              ),
            ],
          );
        },
      );
    }
    if (radius == 0) return img;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }
}

class _Placeholder extends StatelessWidget {
  final double size;
  final String name;
  const _Placeholder({required this.size, required this.name});

  @override
  Widget build(BuildContext context) {
    final (emoji, colors) = productArt(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 1.1,
          colors: colors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: TextStyle(fontSize: size * 0.46, height: 1)),
    );
  }
}

/// Dibujito y colores según el nombre del pan.
(String, List<Color>) productArt(String name) {
  final n = name.toLowerCase();
  const miel = [Color(0xFFFFF1CF), Color(0xFFF9D27A)];
  const chocolate = [Color(0xFFF6E2D0), Color(0xFFD9A77F)];
  const fresa = [Color(0xFFFFE6E1), Color(0xFFF5B3A6)];
  const tomate = [Color(0xFFFFE8D6), Color(0xFFF4B07A)];
  if (n.contains('chocol')) return ('🥐', chocolate);
  if (n.contains('pizza')) return ('🍕', tomate);
  if (n.contains('jam') || n.contains('queso')) return ('🥐', miel);
  if (n.contains('dona')) return ('🍩', fresa);
  if (n.contains('cheesecake') || n.contains('pastel')) return ('🍰', fresa);
  if (n.contains('mantecada') || n.contains('muffin') || n.contains('panqu')) return ('🧁', miel);
  if (n.contains('galleta')) return ('🍪', chocolate);
  if (n.contains('pay') || n.contains('tarta')) return ('🥧', miel);
  if (n.contains('oreja') || n.contains('trenza')) return ('🥨', miel);
  if (n.contains('croissant') || n.contains('cuerno')) return ('🥐', miel);
  if (n.contains('baguette') || n.contains('bolillo') || n.contains('telera')) return ('🥖', miel);
  return ('🍞', miel);
}

/// Foto del pan que "vuela" de la lista al detalle (Hero): crece y sus esquinas
/// pasan de redondas (lista) a solo abajo (detalle), sin saltos.
class ProductHero extends StatelessWidget {
  final Product product;
  final double size;

  /// true en la pantalla de detalle (foto grande arriba).
  final bool big;
  const ProductHero({super.key, required this.product, required this.size, this.big = false});

  static const _listRadius = BorderRadius.all(Radius.circular(18));
  static const _bigRadius = BorderRadius.vertical(bottom: Radius.circular(36));

  @override
  Widget build(BuildContext context) => Hero(
        tag: 'producto-${product.id}',
        flightShuttleBuilder: (flightContext, animation, direction, fromContext, toContext) {
          // La foto del tamaño grande, escalada al rectángulo que va volando.
          final full = MediaQuery.sizeOf(flightContext).width;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) => ClipRRect(
              borderRadius: BorderRadius.lerp(_listRadius, _bigRadius, animation.value)!,
              child: child,
            ),
            child: FittedBox(
              fit: BoxFit.cover,
              child: ProductImage(url: product.imageUrl, name: product.name, size: full),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: big ? _bigRadius : _listRadius,
          child: ProductImage(url: product.imageUrl, name: product.name, size: size),
        ),
      );
}
