import '../models.dart';
import 'flavors.dart';

/// Pedidos y piezas de un horario.
class SlotDemand {
  final String slot;
  int orders = 0;
  final Map<String, int> piecesByProduct = {};

  /// Panes con sabores: producto → sabor → piezas ([noFlavor] = sin elegir).
  final Map<String, Map<String, int>> flavorsByProduct = {};

  SlotDemand(this.slot);

  int get pieces => piecesByProduct.values.fold(0, (a, b) => a + b);
}

/// Resumen de un día: por horario y total por producto.
class DayDemand {
  final String date;
  final List<SlotDemand> slots;
  final Map<String, int> totalByProduct;

  /// Panes con sabores: producto → sabor → piezas del día ([noFlavor] = sin elegir).
  /// Los sabores de cada pan suman lo mismo que su total en [totalByProduct].
  final Map<String, Map<String, int>> flavorsByProduct;

  /// Duración de cada horario del día, en minutos.
  final int slotMinutes;

  DayDemand(this.date, this.slots, this.totalByProduct,
      {this.slotMinutes = 60, this.flavorsByProduct = const {}});

  int get orders => slots.fold(0, (a, s) => a + s.orders);
  int get pieces => totalByProduct.values.fold(0, (a, b) => a + b);

  /// Sabores de un pan en orden ("sin elegir" al final). Vacío si no tiene.
  List<String> flavorsOf(String product) => sortFlavors(flavorsByProduct[product]?.keys ?? const []);

  /// Solo ese pan, con sus sabores como si fueran productos (para la tabla
  /// "por horario" de cada sabor). Salen solo los horarios que lo llevan.
  DayDemand flavorTable(String product) {
    final slotsOut = <SlotDemand>[];
    for (final s in slots) {
      final f = s.flavorsByProduct[product];
      if (f == null || f.isEmpty) continue;
      slotsOut.add(SlotDemand(s.slot)
        ..orders = s.orders
        ..piecesByProduct.addAll(f));
    }
    return DayDemand(date, slotsOut, {...?flavorsByProduct[product]}, slotMinutes: slotMinutes);
  }
}

/// Junta los pedidos de un día. Los cancelados no cuentan.
/// [slotOrder] fija el orden de los horarios publicados (los vacíos también salen).
DayDemand demandForDay(String date, List<BakeryOrder> orders,
    {List<String> slotOrder = const [], int slotMinutes = 60}) {
  final bySlot = <String, SlotDemand>{for (final s in slotOrder) s: SlotDemand(s)};
  final total = <String, int>{};
  final flavors = <String, Map<String, int>>{};
  final live = [for (final o in orders) if (o.deliveryDate == date && o.status != OrderStatus.cancelado) o];
  // Panes que ese día llevan sabores: sus piezas sin sabor (pedidos de antes o de
  // versiones viejas) salen como "sin elegir", así los sabores suman el total.
  final flavored = {for (final o in live) for (final i in o.items) if (i.flavors != null) i.name};
  void addFlavor(Map<String, Map<String, int>> into, String product, String flavor, int n) {
    final m = into.putIfAbsent(product, () => {});
    m[flavor] = (m[flavor] ?? 0) + n;
  }

  for (final o in live) {
    final sd = bySlot.putIfAbsent(o.slot, () => SlotDemand(o.slot));
    sd.orders++;
    for (final i in o.items) {
      sd.piecesByProduct[i.name] = (sd.piecesByProduct[i.name] ?? 0) + i.qty;
      total[i.name] = (total[i.name] ?? 0) + i.qty;
      if (!flavored.contains(i.name)) continue;
      final parts = i.flavors == null ? [MapEntry(noFlavor, i.qty)] : itemFlavors(i);
      for (final e in parts) {
        addFlavor(sd.flavorsByProduct, i.name, e.key, e.value);
        addFlavor(flavors, i.name, e.key, e.value);
      }
    }
  }
  final slots = bySlot.values.toList()..sort((a, b) => a.slot.compareTo(b.slot));
  return DayDemand(date, slots, total, slotMinutes: slotMinutes, flavorsByProduct: flavors);
}
