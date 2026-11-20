import 'package:material_ui/material_ui.dart';

class ProductImage extends StatelessWidget {
  final String? url;
  final double size;
  const ProductImage({super.key, required this.url, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.bakery_dining, size: size / 2),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Image.network(
      url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
