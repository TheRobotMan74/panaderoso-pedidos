import 'dart:math' as math;

/// Distancia en metros entre dos puntos (fórmula de haversine, en línea recta).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(a));
}

/// "350 m" o "2.4 km".
String distanceLabel(double meters) => meters < 1000
    ? '${(meters / 10).round() * 10} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';

/// "hace un momento", "hace 3 min", "hace 1 h".
String agoLabel(DateTime? t, DateTime now) {
  if (t == null) return '';
  final mins = now.difference(t).inMinutes;
  if (mins < 1) return 'hace un momento';
  if (mins < 60) return 'hace $mins min';
  return 'hace ${mins ~/ 60} h';
}
