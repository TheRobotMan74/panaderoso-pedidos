import 'package:flutter/foundation.dart';

import '../models.dart';

/// Carrito del cliente: producto → cantidad. Los panes con sabores (donas)
/// guardan cuántas de cada sabor, y su cantidad es la suma.
class Cart extends ChangeNotifier {
  final Map<String, Product> _products = {};
  final Map<String, int> _qty = {};
  final Map<String, Map<String, int>> _flavors = {};

  int qtyOf(String productId) => _qty[productId] ?? 0;

  /// Cuántas de [flavor] lleva de ese pan.
  int flavorQty(String productId, String flavor) => _flavors[productId]?[flavor] ?? 0;

  void setQty(Product p, int qty) {
    if (qty <= 0) {
      _qty.remove(p.id);
      _products.remove(p.id);
      _flavors.remove(p.id);
    } else {
      _qty[p.id] = qty;
      _products[p.id] = p;
    }
    notifyListeners();
  }

  void add(Product p) => setQty(p, qtyOf(p.id) + 1);
  void remove(Product p) => setQty(p, qtyOf(p.id) - 1);

  /// Pone cuántas de un sabor; la cantidad del pan es la suma de sus sabores.
  void setFlavorQty(Product p, String flavor, int qty) {
    final f = _flavors.putIfAbsent(p.id, () => {});
    if (qty <= 0) {
      f.remove(flavor);
    } else {
      f[flavor] = qty;
    }
    setQty(p, f.values.fold(0, (a, b) => a + b));
  }

  void addFlavor(Product p, String flavor) => setFlavorQty(p, flavor, flavorQty(p.id, flavor) + 1);
  void removeFlavor(Product p, String flavor) => setFlavorQty(p, flavor, flavorQty(p.id, flavor) - 1);

  void clear() {
    _qty.clear();
    _products.clear();
    _flavors.clear();
    notifyListeners();
  }

  bool get isEmpty => _qty.isEmpty;
  int get pieces => _qty.values.fold(0, (a, b) => a + b);

  List<OrderItem> get items => [
        for (final e in _qty.entries)
          OrderItem(
            productId: e.key,
            name: _products[e.key]!.name,
            price: _products[e.key]!.price,
            qty: e.value,
            flavors: _products[e.key]!.hasFlavors ? _orderedFlavors(_products[e.key]!) : null,
          ),
      ];

  /// En el orden de los sabores del pan.
  Map<String, int> _orderedFlavors(Product p) {
    final f = _flavors[p.id] ?? const {};
    return {
      for (final name in p.flavors)
        if ((f[name] ?? 0) > 0) name: f[name]!,
      // Si el dueño quitó un sabor mientras estaba en el carrito, se manda igual
      // y el servidor le avisa al cliente que ya no hay.
      for (final e in f.entries)
        if (!p.flavors.contains(e.key) && e.value > 0) e.key: e.value,
    };
  }

  double get subtotal => items.fold(0.0, (s, i) => s + i.total);
}
