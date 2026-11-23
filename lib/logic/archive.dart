import '../models.dart';

/// Archivador: qué pedidos ya no van en la lista de pendientes del dueño
/// sino en el Historial. No se borra nada: solo cambia dónde se ven.
///
/// Un día ya está "terminado" cuando:
/// - su fecha ya pasó, o
/// - es hoy, ya se entregó todo (sin contar cancelados) y el día ya no recibe
///   pedidos: ya se salió a repartir (día cerrado) o el día se quitó de Días.
///   Si el día sigue abierto puede llegar otro pedido, así que no se archiva.
///
/// [days] son los días de entrega por fecha. Si todavía no cargan
/// ([daysLoaded] = false) no se archiva nada de hoy, para no parpadear.
bool dayFinished(
  String date,
  Iterable<BakeryOrder> dayOrders, {
  required String today,
  required Map<String, DeliveryDay> days,
  bool daysLoaded = true,
}) {
  final c = date.compareTo(today);
  if (c < 0) return true;
  if (c > 0 || !daysLoaded) return false;
  final live = dayOrders.where((o) => o.status != OrderStatus.cancelado).toList();
  if (live.isEmpty) return false;
  if (live.any((o) => o.status != OrderStatus.entregado)) return false;
  final day = days[date];
  return day == null || day.closed;
}

/// Fechas (de [orders]) cuyos pedidos ya van al Historial.
Set<String> finishedDates(
  List<BakeryOrder> orders, {
  required String today,
  required Map<String, DeliveryDay> days,
  bool daysLoaded = true,
}) {
  final byDate = <String, List<BakeryOrder>>{};
  for (final o in orders) {
    byDate.putIfAbsent(o.deliveryDate, () => []).add(o);
  }
  return {
    for (final e in byDate.entries)
      if (dayFinished(e.key, e.value, today: today, days: days, daysLoaded: daysLoaded)) e.key,
  };
}

/// Totales de un grupo de pedidos archivados (un día o un mes).
/// Solo cuenta como venta lo entregado; los cancelados no cuentan.
class SalesSummary {
  /// Días distintos con algo entregado.
  final int days;
  final int delivered;
  final int pieces;

  /// Piezas regaladas (lealtad y bienvenida).
  final int giftPieces;

  /// Total de lo entregado (con envío).
  final double sold;
  final double cash;
  final double transfer;
  final double shipping;

  /// Entregado pero sin marcar como cobrado (efectivo) o verificado (transferencia).
  final double unpaid;
  final int unpaidCount;

  /// Pedidos de días pasados que nunca se marcaron como entregados.
  final int notDelivered;

  const SalesSummary({
    this.days = 0,
    this.delivered = 0,
    this.pieces = 0,
    this.giftPieces = 0,
    this.sold = 0,
    this.cash = 0,
    this.transfer = 0,
    this.shipping = 0,
    this.unpaid = 0,
    this.unpaidCount = 0,
    this.notDelivered = 0,
  });

  factory SalesSummary.of(Iterable<BakeryOrder> orders) {
    final dates = <String>{};
    var delivered = 0, pieces = 0, gifts = 0, unpaidCount = 0, notDelivered = 0;
    double sold = 0, cash = 0, transfer = 0, shipping = 0, unpaid = 0;
    for (final o in orders) {
      if (o.status == OrderStatus.cancelado) continue;
      if (o.status != OrderStatus.entregado) {
        notDelivered++;
        continue;
      }
      dates.add(o.deliveryDate);
      delivered++;
      pieces += o.pieces;
      gifts += o.giftCount();
      sold += o.total;
      shipping += o.shippingFee;
      final isCash = o.paymentMethod == PaymentMethod.efectivo;
      if (isCash) {
        cash += o.total;
      } else {
        transfer += o.total;
      }
      if (!(isCash ? o.cashCollected : o.paymentVerified)) {
        unpaid += o.total;
        unpaidCount++;
      }
    }
    return SalesSummary(
      days: dates.length,
      delivered: delivered,
      pieces: pieces,
      giftPieces: gifts,
      sold: sold,
      cash: cash,
      transfer: transfer,
      shipping: shipping,
      unpaid: unpaid,
      unpaidCount: unpaidCount,
      notDelivered: notDelivered,
    );
  }
}
