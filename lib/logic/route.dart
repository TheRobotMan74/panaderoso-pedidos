import 'geo.dart';

/// Un punto en el mapa (latitud, longitud).
typedef Point = (double lat, double lng);

/// Ordena las entregas de un día para recorrer la menor distancia posible,
/// respetando los horarios: primero todas las de 8:00, luego las de 9:00, etc.
///
/// Dentro de cada horario se usa "el más cercano primero" y luego se mejora
/// la ruta quitando cruces (2-opt). Todo se calcula en el celular, sin pagar
/// ningún servicio; la distancia es en línea recta, que para rutas dentro de
/// la ciudad da un orden muy parecido al de las calles.
///
/// [start] es el punto de salida (tu casa o la panadería). Si no hay, se
/// empieza por la entrega que deja la ruta más corta.
/// Las entregas sin ubicación quedan al final de su horario.
List<T> routeOrder<T>(
  List<T> items, {
  required String Function(T) slot,
  required Point? Function(T) position,
  Point? start,
}) {
  final slots = items.map(slot).toSet().toList()..sort();
  final result = <T>[];
  var current = start;
  for (final s in slots) {
    final inSlot = items.where((i) => slot(i) == s).toList();
    final located = inSlot.where((i) => position(i) != null).toList();
    final unlocated = inSlot.where((i) => position(i) == null).toList();
    final ordered = _bestPath(located, position, current);
    result
      ..addAll(ordered)
      ..addAll(unlocated);
    if (ordered.isNotEmpty) current = position(ordered.last);
  }
  return result;
}

/// Metros totales recorriendo [items] en ese orden desde [start].
double routeLength<T>(List<T> items, Point? Function(T) position, {Point? start}) {
  var total = 0.0;
  var prev = start;
  for (final i in items) {
    final p = position(i);
    if (p == null) continue;
    if (prev != null) total += _d(prev, p);
    prev = p;
  }
  return total;
}

double _d(Point a, Point b) => distanceMeters(a.$1, a.$2, b.$1, b.$2);

List<T> _bestPath<T>(List<T> items, Point? Function(T) position, Point? start) {
  if (items.length <= 1) return items;
  if (start != null) return _twoOpt(_nearestFirst(items, position, start), position, start);
  // Sin punto de salida: probar empezar por cada entrega y quedarse con la más corta.
  List<T>? best;
  var bestLen = double.infinity;
  for (final first in items) {
    final rest = [...items]..remove(first);
    final path = _twoOpt([first, ..._nearestFirst(rest, position, position(first)!)], position, null);
    final len = routeLength(path, position);
    if (len < bestLen) {
      bestLen = len;
      best = path;
    }
  }
  return best!;
}

List<T> _nearestFirst<T>(List<T> items, Point? Function(T) position, Point from) {
  final left = [...items];
  final out = <T>[];
  var at = from;
  while (left.isNotEmpty) {
    left.sort((a, b) => _d(at, position(a)!).compareTo(_d(at, position(b)!)));
    final next = left.removeAt(0);
    out.add(next);
    at = position(next)!;
  }
  return out;
}

/// Voltea tramos de la ruta mientras eso la haga más corta (quita cruces).
List<T> _twoOpt<T>(List<T> path, Point? Function(T) position, Point? start) {
  var best = [...path];
  var bestLen = routeLength(best, position, start: start);
  var improved = true;
  var rounds = 0;
  while (improved && rounds++ < 50) {
    improved = false;
    // Con punto de salida fijo se puede voltear desde la primera entrega;
    // sin él, la primera también puede cambiar.
    for (var i = 0; i < best.length - 1; i++) {
      for (var k = i + 1; k < best.length; k++) {
        final candidate = [
          ...best.sublist(0, i),
          ...best.sublist(i, k + 1).reversed,
          ...best.sublist(k + 1),
        ];
        final len = routeLength(candidate, position, start: start);
        if (len + 0.01 < bestLen) {
          best = candidate;
          bestLen = len;
          improved = true;
        }
      }
    }
  }
  return best;
}
