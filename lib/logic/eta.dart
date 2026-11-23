import '../models.dart';
import 'day_route.dart';
import 'geo.dart';
import 'route.dart';

/// Tiempo estimado de llegada (en minutos) de cada cliente que falta, contando
/// desde donde va el repartidor y siguiendo el orden de la ruta:
///
///   manejo (línea recta × [roadFactor], a [speedKmh]) hasta cada parada
///   + [stopMinutes] por cada entrega que se hace antes de la suya.
///
/// Todo se calcula en el celular del dueño, sin pagar ningún servicio de mapas.
/// [stops] va en el orden de la ruta: (uid del cliente, su casa o null).
/// Si un cliente tiene dos pedidos, cuenta la primera parada.
/// Una parada sin casa marcada cuenta como [unknownLegMinutes] de manejo.
Map<String, int> etaMinutes(
  List<(String, Point?)> stops,
  Point driver, {
  double speedKmh = 25,
  double stopMinutes = 4,
  double roadFactor = 1.3,
  double unknownLegMinutes = 6,
}) {
  final out = <String, int>{};
  final metersPerMinute = speedKmh * 1000 / 60;
  var minutes = 0.0;
  var at = driver;
  for (final (uid, home) in stops) {
    if (home == null) {
      minutes += unknownLegMinutes;
    } else {
      minutes += distanceMeters(at.$1, at.$2, home.$1, home.$2) * roadFactor / metersPerMinute;
      at = home;
    }
    // Llega a su casa: la entrega empieza ahí (sus minutos de entrega no cuentan).
    out.putIfAbsent(uid, () => minutes.ceil());
    minutes += stopMinutes;
  }
  return out;
}

/// Lo mismo, con la ruta del día ya ordenada (solo cuenta lo que falta entregar).
Map<String, int> etaForRoute(List<BakeryOrder> route, Point driver, AppConfig cfg) => etaMinutes(
  [
    for (final o in route)
      if (o.isPending) (o.customerId, orderPoint(o)),
  ],
  driver,
  speedKmh: cfg.etaSpeedKmh,
  stopMinutes: cfg.etaStopMinutes,
  roadFactor: cfg.shipping.roadFactor,
);

/// Minutos que le quedan al cliente, descontando el tiempo que pasó desde que
/// se calculó (si el repartidor está entregando, no llegan ubicaciones nuevas
/// pero el reloj sigue). Nunca baja de 1.
int etaRemaining(int etaMin, DateTime? computedAt, DateTime now) {
  if (computedAt == null) return etaMin < 1 ? 1 : etaMin;
  final passed = now.difference(computedAt).inSeconds / 60;
  final left = (etaMin - passed).round();
  return left < 1 ? 1 : left;
}

/// "unos 5 min", "unos 25 min", "1 h 10 min". Arriba de 20 min se redondea a 5,
/// porque no es exacto.
String etaLabel(int minutes) {
  var m = minutes < 1 ? 1 : minutes;
  if (m > 20) m = ((m + 2) ~/ 5) * 5;
  if (m < 60) return 'unos $m min';
  final h = m ~/ 60, r = m % 60;
  if (r != 0) return '$h h $r min';
  return h == 1 ? '1 hora' : '$h horas';
}
