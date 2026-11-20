import '../models.dart';

/// Pedidos y piezas de un horario.
class SlotDemand {
  final String slot;
  int orders = 0;
  final Map<String, int> piecesByProduct = {};

  SlotDemand(this.slot);

  int get pieces => piecesByProduct.values.fold(0, (a, b) => a + b);
}

/// Resumen de un día: por horario y total por producto.
class DayDemand {
  final String date;
  final List<SlotDemand> slots;
  final Map<String, int> totalByProduct;

  DayDemand(this.date, this.slots, this.totalByProduct);

  int get orders => slots.fold(0, (a, s) => a + s.orders);
  int get pieces => totalByProduct.values.fold(0, (a, b) => a + b);
}

/// Junta los pedidos de un día. Los cancelados no cuentan.
/// [slotOrder] fija el orden de los horarios publicados (los vacíos también salen).
DayDemand demandForDay(String date, List<BakeryOrder> orders, {List<String> slotOrder = const []}) {
  final bySlot = <String, SlotDemand>{for (final s in slotOrder) s: SlotDemand(s)};
  final total = <String, int>{};
  for (final o in orders) {
    if (o.deliveryDate != date || o.status == OrderStatus.cancelado) continue;
    final sd = bySlot.putIfAbsent(o.slot, () => SlotDemand(o.slot));
    sd.orders++;
    for (final i in o.items) {
      sd.piecesByProduct[i.name] = (sd.piecesByProduct[i.name] ?? 0) + i.qty;
      total[i.name] = (total[i.name] ?? 0) + i.qty;
    }
  }
  final slots = bySlot.values.toList()..sort((a, b) => a.slot.compareTo(b.slot));
  return DayDemand(date, slots, total);
}
