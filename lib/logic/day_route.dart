import '../models.dart';
import 'route.dart';

/// Punto de salida del reparto (Ajustes → Reparto), si está marcado.
Point? basePoint(AppConfig cfg) =>
    cfg.baseLat != null && cfg.baseLng != null ? (cfg.baseLat!, cfg.baseLng!) : null;

Point? orderPoint(BakeryOrder o) => o.hasLocation ? (o.lat!, o.lng!) : null;

/// Rutas ya calculadas (la pantalla se redibuja seguido y la ruta solo cambia
/// si cambian los pedidos, sus casas o el punto de salida).
final _cache = <String, List<String>>{};

/// La ruta que arma la app sola para los pedidos de un día.
List<BakeryOrder> autoRoute(List<BakeryOrder> orders, AppConfig cfg) {
  final key = [
    cfg.baseLat,
    cfg.baseLng,
    cfg.routeReturn,
    for (final o in orders) '${o.id}/${o.slot}/${o.lat}/${o.lng}',
  ].join('|');
  final hit = _cache[key];
  if (hit != null) {
    final byId = {for (final o in orders) o.id: o};
    return [for (final id in hit) byId[id]!];
  }
  final route = routeOrder<BakeryOrder>(
    orders,
    slot: (o) => o.slot,
    position: orderPoint,
    start: basePoint(cfg),
    returnToStart: cfg.routeReturn,
  );
  if (_cache.length > 20) _cache.clear();
  _cache[key] = route.map((o) => o.id).toList();
  return route;
}

/// La ruta de un día: la que acomodaste a mano si hay, o la que arma la app.
/// Es la misma en la lista de pedidos, en el mapa y en lo que ve cada cliente.
List<BakeryOrder> dayRoute(List<BakeryOrder> orders, AppConfig cfg, {DeliveryDay? day}) {
  final saved = day?.routeOrder ?? const <String>[];
  if (saved.isEmpty) return autoRoute(orders, cfg);
  return applySavedOrder<BakeryOrder>(
    orders,
    saved,
    id: (o) => o.id,
    slot: (o) => o.slot,
    position: orderPoint,
    start: basePoint(cfg),
  );
}

/// Metros de la ruta, contando el regreso si así está en Ajustes.
double dayRouteMeters(List<BakeryOrder> route, AppConfig cfg) {
  final base = basePoint(cfg);
  return routeLength<BakeryOrder>(route, orderPoint, start: base, end: cfg.routeReturn ? base : null);
}

/// Para el mapa del cliente: cuántas entregas pendientes van antes de la suya.
Map<String, int> aheadByCustomer(List<BakeryOrder> route) {
  final out = <String, int>{};
  var count = 0;
  for (final o in route) {
    if (!o.isPending) continue;
    out.putIfAbsent(o.customerId, () => count);
    count++;
  }
  return out;
}
