import 'dart:math';

import '../models.dart';

/// Cupos de pan por día.
///
/// Los productos que salen de la misma masa comparten un solo cupo: si el dueño
/// pone "Masa de croissant" a chocolatín, jamón y queso y pizza, el cupo de 30
/// es para los tres juntos (20 + 5 + 5, o 30 de chocolatín). Un producto sin
/// grupo tiene su propio cupo.
///
/// La llave de cada grupo tiene que ser igual a la de functions/index.js.
String stockKey(Product p) {
  final g = p.stockGroup.trim().toLowerCase();
  return g.isEmpty ? 'p:${p.id}' : 'g:$g';
}

class StockGroup {
  final String key;

  /// Nombre que se muestra: el del grupo, o el del producto si va solo.
  final String label;
  final List<Product> products;

  const StockGroup({required this.key, required this.label, required this.products});

  bool get shared => key.startsWith('g:');

  /// "Chocolatín, Croissant de pizza y Croissant de jamón y queso".
  String get productNames {
    final names = products.map((p) => p.name).toList();
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  }
}

/// Grupos de cupo en el orden del catálogo.
List<StockGroup> stockGroups(List<Product> products) {
  final byKey = <String, List<Product>>{};
  for (final p in products) {
    byKey.putIfAbsent(stockKey(p), () => []).add(p);
  }
  return [
    for (final e in byKey.entries)
      StockGroup(
        key: e.key,
        label: e.key.startsWith('g:') ? e.value.first.stockGroup.trim() : e.value.first.name,
        products: e.value,
      ),
  ];
}

/// Nombres de grupos de masa que ya existen (para elegirlos en una lista).
List<String> groupNames(List<Product> products) {
  final seen = <String>{};
  final out = <String>[];
  for (final p in products) {
    final g = p.stockGroup.trim();
    if (g.isNotEmpty && seen.add(g.toLowerCase())) out.add(g);
  }
  return out;
}

/// Piezas que pide un carrito o pedido, juntadas por grupo de cupo.
Map<String, int> needByGroup(List<OrderItem> items, Map<String, Product> productsById) {
  final need = <String, int>{};
  for (final i in items) {
    final p = productsById[i.productId];
    final key = p == null ? 'p:${i.productId}' : stockKey(p);
    need[key] = (need[key] ?? 0) + i.qty;
  }
  return need;
}

/// Cuántos panes quedan de un grupo ese día. Null = sin límite.
int? remainingFor(DeliveryDay day, DayStock? stock, String key) {
  final limit = day.stock[key];
  if (limit == null) return null;
  return max(0, limit - (stock?.used[key] ?? 0));
}

/// Grupos donde se pide más de lo que queda.
List<String> overLimit(DeliveryDay day, DayStock? stock, Map<String, int> need) => [
      for (final e in need.entries)
        if (e.value > (remainingFor(day, stock, e.key) ?? e.value)) e.key,
    ];

/// Suma de lo que queda en todos los grupos con cupo. Null si ninguno tiene cupo.
int? totalRemaining(DeliveryDay day, DayStock? stock) {
  if (day.stock.isEmpty) return null;
  return day.stock.keys.fold<int>(0, (s, k) => s + (remainingFor(day, stock, k) ?? 0));
}

/// "quedan 40 panes" / "queda 1 pan" / "agotado".
String remainingText(int n) => n <= 0 ? 'agotado' : (n == 1 ? 'queda 1 pan' : 'quedan $n panes');
