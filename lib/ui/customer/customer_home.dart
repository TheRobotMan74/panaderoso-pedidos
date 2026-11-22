import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/cart.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../profile_page.dart';
import 'checkout_page.dart';
import 'my_orders_page.dart';

class CustomerHome extends StatefulWidget {
  final AppUser user;
  const CustomerHome({super.key, required this.user});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  final _cart = Cart();
  int _tab = 0;

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  void _openCheckout() async {
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CheckoutPage(user: widget.user, cart: _cart)),
    );
    if (placed == true && mounted) setState(() => _tab = 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Panaderoso' : 'Mis pedidos'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'perfil') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProfilePage(uid: widget.user.uid, existing: widget.user, editing: true),
                  ),
                );
              } else if (v == 'salir') {
                FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'perfil', child: Text('Mis datos de entrega')),
              PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      body: _tab == 0 ? _Catalog(cart: _cart) : MyOrdersPage(
              uid: widget.user.uid,
              homeLat: widget.user.lat,
              homeLng: widget.user.lng,
            ),
      floatingActionButton: _tab == 0
          ? ListenableBuilder(
              listenable: _cart,
              builder: (context, _) => _cart.isEmpty
                  ? const SizedBox.shrink()
                  : FloatingActionButton.extended(
                      onPressed: _openCheckout,
                      icon: const Icon(Icons.shopping_basket),
                      label: Text('${_cart.pieces} pzas · ${money(_cart.subtotal)}'),
                    ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bakery_dining), label: 'Pan'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Mis pedidos'),
        ],
      ),
    );
  }
}

class _Catalog extends StatelessWidget {
  final Cart cart;
  const _Catalog({required this.cart});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: Repo.instance.products(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final products = snap.data!;
        if (products.isEmpty) {
          return const Center(child: Text('Todavía no hay productos.'));
        }
        return ListenableBuilder(
          listenable: cart,
          builder: (context, _) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _ProductCard(product: products[i], cart: cart),
          ),
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final Cart cart;
  const _ProductCard({required this.product, required this.cart});

  @override
  Widget build(BuildContext context) {
    final qty = cart.qtyOf(product.id);
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          ProductImage(url: product.imageUrl, size: 96),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.titleMedium),
                  if (product.description.isNotEmpty)
                    Text(product.description, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(money(product.price), style: theme.textTheme.titleSmall),
                  if (!product.available)
                    Text('Agotado', style: TextStyle(color: theme.colorScheme.error)),
                ],
              ),
            ),
          ),
          if (product.available)
            Row(
              children: [
                if (qty > 0)
                  IconButton(onPressed: () => cart.remove(product), icon: const Icon(Icons.remove)),
                if (qty > 0) Text('$qty', style: theme.textTheme.titleMedium),
                IconButton(
                  onPressed: () => cart.add(product),
                  icon: const Icon(Icons.add_circle),
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
