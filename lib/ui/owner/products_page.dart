import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Product>>(
        stream: Repo.instance.products(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final products = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              for (final p in products)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: ProductImage(url: p.imageUrl, size: 48),
                    title: Text(p.name),
                    subtitle: Text('${money(p.price)}${p.available ? '' : ' · agotado'}'),
                    trailing: Switch(
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
                    onTap: () => _edit(context, p, products.length),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: StreamBuilder<List<Product>>(
        stream: Repo.instance.products(),
        builder: (context, snap) => FloatingActionButton.extended(
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
                borderRadius: BorderRadius.circular(12),
                child: _newImage != null
                    ? Image.file(_newImage!, width: 160, height: 160, fit: BoxFit.cover)
                    : ProductImage(url: _imageUrl, size: 160),
              ),
            ),
          ),
          TextButton(onPressed: _pick, child: const Text('Elegir foto')),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(
                labelText: 'Descripción (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Precio', prefixText: r'$ ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
