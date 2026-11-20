import 'package:flutter/foundation.dart';

import '../models.dart';

/// Carrito del cliente: producto → cantidad.
class Cart extends ChangeNotifier {
  final Map<String, Product> _products = {};
  final Map<String, int> _qty = {};

  int qtyOf(String productId) => _qty[productId] ?? 0;

  void setQty(Product p, int qty) {
    if (qty <= 0) {
      _qty.remove(p.id);
      _products.remove(p.id);
    } else {
      _qty[p.id] = qty;
      _products[p.id] = p;
    }
    notifyListeners();
  }

  void add(Product p) => setQty(p, qtyOf(p.id) + 1);
  void remove(Product p) => setQty(p, qtyOf(p.id) - 1);

  void clear() {
    _qty.clear();
    _products.clear();
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
          ),
      ];

  double get subtotal => items.fold(0.0, (s, i) => s + i.total);
}
