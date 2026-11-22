import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Product>>(
        stream: Repo.instance.products(),
        builder: (context, snap) {
          if (!snap.hasData) return const SkeletonList(withImage: true, count: 4);
          final products = snap.data!;
          if (products.isEmpty) {
            return const EmptyState(
              title: 'Tu vitrina está vacía',
              message: 'Toca "Producto" para agregar tu primer pan.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              for (final (i, p) in products.indexed)
                FadeSlideIn(
                  index: i,
                  child: PanCard(
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    onTap: () => _edit(context, p, products.length),
                    child: Row(
                      children: [
                        ProductImage(url: p.imageUrl, name: p.name, size: 60, radius: 16),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                '${money(p.price)}${p.available ? '' : ' · agotado'}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: p.available ? Pan.caramelo : Pan.canela,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                      value: p.available,
                      onChanged: (v) => Repo.instance.saveProduct(Product(
                        id: p.id,
                        name: p.name,
                        description: p.description,
                        price: p.price,
                        imageUrl: p.imageUrl,
                        available: v,
                            sortOrder: p.sortOrder,
                          )),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: StreamBuilder<List<Product>>(
        stream: Repo.instance.products(),
        builder: (context, snap) => FloatingActionButton.extended(
          heroTag: 'nuevo-producto',
          onPressed: () => _edit(context, null, snap.data?.length ?? 0),
          icon: const Icon(Icons.add),
          label: const Text('Producto'),
        ),
      ),
    );
  }

  void _edit(BuildContext context, Product? p, int count) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ProductForm(product: p, nextOrder: count)),
    );
  }
}

class _ProductForm extends StatefulWidget {
  final Product? product;
  final int nextOrder;
  const _ProductForm({this.product, required this.nextOrder});

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final _name = TextEditingController(text: widget.product?.name);
  late final _desc = TextEditingController(text: widget.product?.description);
  late final _price = TextEditingController(
      text: widget.product == null ? '' : widget.product!.price.toStringAsFixed(0));
  late String? _imageUrl = widget.product?.imageUrl;
  File? _newImage;
  bool _busy = false;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000, imageQuality: 80);
    if (x != null) setState(() => _newImage = File(x.path));
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    if (_name.text.trim().isEmpty || price == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pon el nombre y el precio.')));
      return;
    }
    setState(() => _busy = true);
    if (_newImage != null) _imageUrl = await Repo.instance.uploadProductImage(_newImage!);
    await Repo.instance.saveProduct(Product(
      id: widget.product?.id ?? '',
      name: _name.text.trim(),
      description: _desc.text.trim(),
      price: price,
      imageUrl: _imageUrl,
      available: widget.product?.available ?? true,
      sortOrder: widget.product?.sortOrder ?? widget.nextOrder,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product == null ? 'Nuevo producto' : 'Editar producto')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pick,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: _newImage != null
                    ? Image.file(_newImage!, width: 180, height: 180, fit: BoxFit.cover, cacheWidth: 540)
                    : ProductImage(url: _imageUrl, name: _name.text, size: 180),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Elegir foto'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio', prefixText: r'$ '),
          ),
          const SizedBox(height: 24),
          HoneyButton(label: 'Guardar', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
