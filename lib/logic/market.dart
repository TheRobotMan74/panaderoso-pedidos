import 'package:flutter/foundation.dart';

import '../models.dart';
import 'flavors.dart';

/// Mercadito: el dueño lleva panes a un puesto y la tablet hace de caja.
///
/// - El dueño abre el mercadito con cuántas piezas lleva de cada pan (y de
///   cada sabor). Eso se guarda en markets/{id}.
/// - Cada venta se guarda en marketSales/{id}, directo desde la tablet (sin
///   servidor), así funciona aunque la señal sea mala: Firestore la guarda en la
///   tablet y la sube sola cuando vuelve.
/// - Lo que queda = lo que llevas − lo vendido (sin las ventas canceladas).

/// Un botón de la caja: un pan, o un sabor de un pan (cada sabor de dona es su
/// propio botón, para vender con un solo toque).
class MarketUnit {
  final MarketItem item;

  /// '' = pan sin sabores.
  final String flavor;
  const MarketUnit(this.item, this.flavor);

  String get key => unitKey(item.productId, flavor);

  /// Cuántas piezas llevas de este botón.
  int get brought => flavor.isEmpty ? item.qty : (item.flavors?[flavor] ?? 0);

  double get price => item.price;

  /// "Chocolatín" o "Donas · Chocolate".
  String get label => flavor.isEmpty ? item.name : '${item.name} · $flavor';
}

String unitKey(String productId, String flavor) => '$productId|$flavor';

/// Los botones de la caja, en el orden del mercadito. Los sabores que no
/// llevas (0 piezas) no salen.
List<MarketUnit> marketUnits(Market m) {
  final out = <MarketUnit>[];
  for (final it in m.items) {
    if (it.hasFlavors) {
      for (final f in sortFlavors(it.flavors!.keys)) {
        if ((it.flavors![f] ?? 0) > 0) out.add(MarketUnit(it, f));
      }
    } else if (it.qty > 0) {
      out.add(MarketUnit(it, ''));
    }
  }
  return out;
}

/// Piezas vendidas por botón (sin contar las ventas canceladas).
Map<String, int> soldByUnit(Iterable<MarketSale> sales) {
  final out = <String, int>{};
  void add(String key, int n) => out.update(key, (v) => v + n, ifAbsent: () => n);
  for (final s in sales) {
    if (s.cancelled) continue;
    for (final it in s.items) {
      final f = it.flavors;
      if (f != null && f.isNotEmpty) {
        f.forEach((flavor, n) => add(unitKey(it.productId, flavor), n));
      } else {
        add(unitKey(it.productId, ''), it.qty);
      }
    }
  }
  return out;
}

/// Lo que queda de cada botón (nunca menos de 0).
Map<String, int> remainingByUnit(List<MarketUnit> units, Iterable<MarketSale> sales) {
  final sold = soldByUnit(sales);
  return {for (final u in units) u.key: (u.brought - (sold[u.key] ?? 0)).clamp(0, 1 << 30)};
}

/// La cuenta que se está armando en la caja. Recuerda el orden en que se
/// tocaron los panes, para que la lista se lea como se fue pidiendo.
class MarketTicket extends ChangeNotifier {
  final Map<String, int> _qty = {};

  int qtyOf(String key) => _qty[key] ?? 0;

  bool get isEmpty => _qty.isEmpty;

  /// Botones que hay en la cuenta.
  Iterable<String> get keys => _qty.keys;

  int get pieces => _qty.values.fold(0, (a, b) => a + b);

  /// Agrega una pieza si todavía hay ([left] = lo que queda de ese botón).
  /// Regresa false si ya no alcanza.
  bool add(String key, {required int left}) {
    if (qtyOf(key) >= left) return false;
    _qty[key] = qtyOf(key) + 1;
    notifyListeners();
    return true;
  }

  void remove(String key) {
    final n = qtyOf(key) - 1;
    if (n <= 0) {
      _qty.remove(key);
    } else {
      _qty[key] = n;
    }
    notifyListeners();
  }

  void clear() {
    if (_qty.isEmpty) return;
    _qty.clear();
    notifyListeners();
  }

  /// Si el dueño cambió lo que lleva (o alguien más vendió), que la cuenta
  /// no pida más de lo que queda. Regresa true si se tuvo que quitar algo.
  bool fitTo(Map<String, int> left) {
    var changed = false;
    for (final k in _qty.keys.toList()) {
      final max = left[k] ?? 0;
      if (_qty[k]! > max) {
        changed = true;
        if (max <= 0) {
          _qty.remove(k);
        } else {
          _qty[k] = max;
        }
      }
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// Renglones de la cuenta (botón y piezas), en el orden en que se pidieron.
  List<(MarketUnit, int)> lines(List<MarketUnit> units) {
    final byKey = {for (final u in units) u.key: u};
    return [
      for (final e in _qty.entries)
        if (byKey[e.key] case final u?) (u, e.value),
    ];
  }

  double total(List<MarketUnit> units) => lines(units).fold(0.0, (s, l) => s + l.$1.price * l.$2);

  /// La venta como renglones de pedido: un renglón por pan, con sus sabores juntos
  /// ("3 Donas: 2 Chocolate, 1 Caramelo"), igual que en los pedidos a domicilio.
  List<OrderItem> toItems(List<MarketUnit> units) {
    final order = <String>[];
    final qty = <String, int>{};
    final flavors = <String, Map<String, int>>{};
    final itemOf = <String, MarketItem>{};
    for (final (u, n) in lines(units)) {
      final id = u.item.productId;
      if (!itemOf.containsKey(id)) order.add(id);
      itemOf[id] = u.item;
      qty.update(id, (v) => v + n, ifAbsent: () => n);
      if (u.flavor.isNotEmpty) (flavors[id] ??= {})[u.flavor] = n;
    }
    return [
      for (final id in order)
        OrderItem(
          productId: id,
          name: itemOf[id]!.name,
          price: itemOf[id]!.price,
          qty: qty[id]!,
          flavors: flavors[id],
        ),
    ];
  }
}

/// Totales de un mercadito (o de varios, en el Historial).
class MarketSummary {
  /// Ventas hechas (sin las canceladas).
  final int sales;
  final int pieces;

  /// Piezas que llevaste (solo si se le pasan los mercaditos).
  final int brought;
  final double total;
  final double cash;
  final double transfer;

  /// Ventas que siguen en la tablet esperando señal para subirse.
  final int pending;

  const MarketSummary({
    this.sales = 0,
    this.pieces = 0,
    this.brought = 0,
    this.total = 0,
    this.cash = 0,
    this.transfer = 0,
    this.pending = 0,
  });

  int get left => (brought - pieces).clamp(0, 1 << 30);

  factory MarketSummary.of(Iterable<MarketSale> sales, {Iterable<Market> markets = const []}) {
    var n = 0, pieces = 0, pending = 0;
    double total = 0, cash = 0, transfer = 0;
    for (final s in sales) {
      if (s.pending) pending++;
      if (s.cancelled) continue;
      n++;
      pieces += s.pieces;
      total += s.total;
      if (s.pay == MarketPay.efectivo) {
        cash += s.total;
      } else {
        transfer += s.total;
      }
    }
    return MarketSummary(
      sales: n,
      pieces: pieces,
      brought: markets.fold(0, (s, m) => s + m.pieces),
      total: total,
      cash: cash,
      transfer: transfer,
      pending: pending,
    );
  }
}

/// Un mercadito ya va al Historial cuando lo cerraste o cuando su día ya pasó.
bool marketFinished(Market m, {required String today}) => !m.open || m.date.compareTo(today) < 0;

/// Con qué billetes te pueden pagar [total]: el exacto y los siguientes redondos
/// (85 → 85, 100, 200, 500, 1000). Para calcular el cambio con un toque.
List<int> cashOptions(double total) {
  final t = total.ceil();
  if (t <= 0) return const [];
  final out = <int>{t};
  for (final step in const [50, 100]) {
    out.add(((t + step - 1) ~/ step) * step);
  }
  for (final bill in const [200, 500, 1000]) {
    if (bill > t) out.add(bill);
  }
  return (out.toList()..sort()).take(5).toList();
}

/// Lo que llevas, listo para guardar: sin panes en 0, y en los panes con
/// sabores solo los sabores que sí llevas (la cantidad es la suma).
List<MarketItem> cleanMarketItems(Iterable<MarketItem> items) {
  final out = <MarketItem>[];
  for (final it in items) {
    if (!it.hasFlavors) {
      if (it.qty > 0) out.add(it);
      continue;
    }
    final f = {
      for (final e in it.flavors!.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (f.isEmpty) continue;
    out.add(MarketItem(
      productId: it.productId,
      name: it.name,
      price: it.price,
      imageUrl: it.imageUrl,
      qty: f.values.fold(0, (a, b) => a + b),
      flavors: f,
    ));
  }
  return out;
}
