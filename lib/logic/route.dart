import 'geo.dart';

/// Un punto en el mapa (latitud, longitud).
typedef Point = (double lat, double lng);

/// Ordena las entregas de un día para recorrer la menor distancia posible,
/// respetando los horarios: primero todas las de 8:00, luego las de 9:00, etc.
///
/// A diferencia de "el más cercano primero", aquí se piensa la ruta completa:
/// dónde termina un horario importa para empezar el siguiente (por ejemplo,
/// conviene acabar las de la 1:00 cerca de las de las 2:00), y si [returnToStart]
/// también cuenta el regreso a casa.
///
/// Con pocas casas por horario (hasta [_exactLimit]) se prueban todas las
/// combinaciones y sale la ruta más corta posible. Con más, se usa una búsqueda
/// que va moviendo y volteando paradas mientras la ruta se acorte.
/// Todo se calcula en el celular, sin pagar ningún servicio; la distancia es en
/// línea recta, que para rutas dentro de la ciudad da un orden muy parecido al
/// de las calles.
///
/// [start] es el punto de salida (tu casa o la panadería). Si no hay, se
/// empieza por la entrega que deja la ruta más corta.
/// Las entregas sin ubicación quedan al final de su horario.
List<T> routeOrder<T>(
  List<T> items, {
  required String Function(T) slot,
  required Point? Function(T) position,
  Point? start,
  bool returnToStart = false,
}) {
  final slots = items.map(slot).toSet().toList()..sort();
  final groups = [for (final s in slots) items.where((i) => slot(i) == s && position(i) != null).toList()];
  final unlocated = [for (final s in slots) items.where((i) => slot(i) == s && position(i) == null).toList()];
  final end = returnToStart ? start : null;

  final List<List<T>> ordered;
  if (groups.every((g) => g.length <= _exactLimit)) {
    ordered = _exact(groups, position, start, end);
  } else {
    ordered = _search(groups, position, start, end);
  }
  return [
    for (var k = 0; k < slots.length; k++) ...[...ordered[k], ...unlocated[k]],
  ];
}

/// Metros totales recorriendo [items] en ese orden desde [start]
/// (y de regreso a [end], si se da).
double routeLength<T>(List<T> items, Point? Function(T) position, {Point? start, Point? end}) {
  var total = 0.0;
  var prev = start;
  for (final i in items) {
    final p = position(i);
    if (p == null) continue;
    if (prev != null) total += _d(prev, p);
    prev = p;
  }
  if (end != null && prev != null) total += _d(prev, end);
  return total;
}

/// Junta el orden que guardaste a mano con los pedidos de hoy.
///
/// Los que están en [saved] van en ese orden. Los que llegaron después de
/// guardarlo se meten donde menos alarguen la ruta, sin brincarse su horario
/// (si no tienen casa marcada, al final de su horario).
List<T> applySavedOrder<T>(
  List<T> items,
  List<String> saved, {
  required String Function(T) id,
  required String Function(T) slot,
  required Point? Function(T) position,
  Point? start,
}) {
  final byId = {for (final i in items) id(i): i};
  final result = <T>[
    for (final s in saved)
      if (byId.containsKey(s)) byId[s] as T,
  ];
  final placed = result.map(id).toSet();
  final newcomers = items.where((i) => !placed.contains(id(i))).toList()
    ..sort((a, b) => slot(a).compareTo(slot(b)));
  for (final n in newcomers) {
    final s = slot(n);
    // Lugares donde no queda antes de uno de horario más temprano ni después de uno más tarde.
    var lo = 0;
    for (var i = 0; i < result.length; i++) {
      if (slot(result[i]).compareTo(s) < 0) lo = i + 1;
    }
    var hi = result.length;
    for (var i = result.length - 1; i >= 0; i--) {
      if (slot(result[i]).compareTo(s) > 0) hi = i;
    }
    if (hi < lo) hi = lo; // El orden a mano ya mezcla horarios: no hay hueco perfecto.
    final p = position(n);
    var bestAt = hi;
    if (p != null) {
      var bestCost = double.infinity;
      for (var at = lo; at <= hi; at++) {
        final prev = _locatedBefore(result, at, position) ?? start;
        final next = _locatedFrom(result, at, position);
        final cost =
            (prev == null ? 0.0 : _d(prev, p)) +
            (next == null ? 0.0 : _d(p, next)) -
            (prev == null || next == null ? 0.0 : _d(prev, next));
        if (cost < bestCost - 0.01) {
          bestCost = cost;
          bestAt = at;
        }
      }
    }
    result.insert(bestAt, n);
  }
  return result;
}

/// Para cada parada que va antes de su horario (porque otra de un horario más
/// temprano va después), regresa true. Sirve para avisar en el orden a mano.
List<bool> earlyStops<T>(List<T> items, String Function(T) slot) {
  final out = List.filled(items.length, false);
  String? minAfter;
  for (var i = items.length - 1; i >= 0; i--) {
    final s = slot(items[i]);
    if (minAfter != null && minAfter.compareTo(s) < 0) out[i] = true;
    if (minAfter == null || s.compareTo(minAfter) < 0) minAfter = s;
  }
  return out;
}

Point? _locatedBefore<T>(List<T> list, int at, Point? Function(T) position) {
  for (var i = at - 1; i >= 0; i--) {
    final p = position(list[i]);
    if (p != null) return p;
  }
  return null;
}

Point? _locatedFrom<T>(List<T> list, int at, Point? Function(T) position) {
  for (var i = at; i < list.length; i++) {
    final p = position(list[i]);
    if (p != null) return p;
  }
  return null;
}

double _d(Point a, Point b) => distanceMeters(a.$1, a.$2, b.$1, b.$2);

/// Hasta cuántas casas por horario se prueban todas las combinaciones
/// (con 10 es instantáneo en cualquier celular).
const _exactLimit = 10;

/// Ruta exacta: la más corta posible respetando el orden de los horarios.
///
/// Para cada horario y cada casa donde podría terminar, se guarda el mejor
/// camino desde el inicio del día (programación dinámica). Dentro de un
/// horario se usa el método de Held-Karp: se recorren todos los subconjuntos.
List<List<T>> _exact<T>(List<List<T>> groups, Point? Function(T) position, Point? start, Point? end) {
  // Puntos de dónde puede venir cada horario: el final del horario anterior.
  // null = todavía no hay de dónde venir (sin punto de salida).
  var prevEnds = <Point?>[start];
  var prevCost = <double>[0];
  var prevPaths = <List<List<T>>>[[]];

  for (final g in groups) {
    if (g.isEmpty) {
      prevPaths = [
        for (final p in prevPaths) [...p, <T>[]],
      ];
      continue;
    }
    final n = g.length;
    final pts = [for (final i in g) position(i)!];
    final dist = [
      for (var a = 0; a < n; a++) [for (var b = 0; b < n; b++) _d(pts[a], pts[b])],
    ];
    final full = (1 << n) - 1;
    final bestCost = List.filled(n, double.infinity);
    final bestPath = List<List<List<T>>?>.filled(n, null);

    for (var e = 0; e < prevEnds.length; e++) {
      final from = prevEnds[e];
      // dp[mask * n + j] = lo menos que cuesta visitar "mask" terminando en j.
      final dp = List.filled((1 << n) * n, double.infinity);
      final parent = List.filled((1 << n) * n, -1);
      for (var j = 0; j < n; j++) {
        dp[(1 << j) * n + j] = from == null ? 0 : _d(from, pts[j]);
      }
      for (var mask = 1; mask <= full; mask++) {
        for (var j = 0; j < n; j++) {
          if (mask & (1 << j) == 0) continue;
          final cur = dp[mask * n + j];
          if (cur == double.infinity) continue;
          for (var k = 0; k < n; k++) {
            if (mask & (1 << k) != 0) continue;
            final m2 = mask | (1 << k);
            final c = cur + dist[j][k];
            if (c < dp[m2 * n + k]) {
              dp[m2 * n + k] = c;
              parent[m2 * n + k] = j;
            }
          }
        }
      }
      for (var j = 0; j < n; j++) {
        final total = prevCost[e] + dp[full * n + j];
        if (total + 0.01 < bestCost[j]) {
          bestCost[j] = total;
          // Reconstruir el camino que termina en j.
          final seq = <T>[];
          var mask = full;
          var at = j;
          while (at != -1) {
            seq.add(g[at]);
            final p = parent[mask * n + at];
            mask &= ~(1 << at);
            at = p;
          }
          bestPath[j] = [...prevPaths[e], seq.reversed.toList()];
        }
      }
    }
    prevEnds = pts;
    prevCost = bestCost;
    prevPaths = [for (final p in bestPath) p!];
  }

  var best = 0;
  var bestTotal = double.infinity;
  for (var e = 0; e < prevEnds.length; e++) {
    final back = end != null && prevEnds[e] != null ? _d(prevEnds[e]!, end) : 0.0;
    final t = prevCost[e] + back;
    if (t < bestTotal) {
      bestTotal = t;
      best = e;
    }
  }
  return prevPaths[best];
}

/// Ruta para días con muchas casas: arranca con "el más cercano primero" y
/// luego mejora toda la ruta junta (moviendo paradas de lugar y volteando
/// tramos), siempre sin brincarse los horarios.
List<List<T>> _search<T>(List<List<T>> groups, Point? Function(T) position, Point? start, Point? end) {
  // Ruta inicial.
  final route = <(int, Point)>[]; // (horario, punto)
  final items = <T>[];
  Point? at = start;
  for (var k = 0; k < groups.length; k++) {
    final left = [...groups[k]];
    while (left.isNotEmpty) {
      final from = at;
      if (from != null) {
        left.sort((a, b) => _d(from, position(a)!).compareTo(_d(from, position(b)!)));
      }
      final next = left.removeAt(0);
      items.add(next);
      route.add((k, position(next)!));
      at = position(next);
    }
  }

  double len(List<int> order) {
    var t = 0.0;
    Point? prev = start;
    for (final i in order) {
      final p = route[i].$2;
      if (prev != null) t += _d(prev, p);
      prev = p;
    }
    if (end != null && prev != null) t += _d(prev, end);
    return t;
  }

  bool ok(List<int> order) {
    for (var i = 1; i < order.length; i++) {
      if (route[order[i]].$1 < route[order[i - 1]].$1) return false;
    }
    return true;
  }

  var best = [for (var i = 0; i < route.length; i++) i];
  var bestLen = len(best);
  var improved = true;
  var rounds = 0;
  while (improved && rounds++ < 60) {
    improved = false;
    // Voltear un tramo (quita cruces). Solo dentro de un mismo horario.
    for (var i = 0; i < best.length - 1; i++) {
      for (var k = i + 1; k < best.length; k++) {
        if (route[best[i]].$1 != route[best[k]].$1) break;
        final cand = [...best.sublist(0, i), ...best.sublist(i, k + 1).reversed, ...best.sublist(k + 1)];
        final l = len(cand);
        if (l + 0.01 < bestLen) {
          best = cand;
          bestLen = l;
          improved = true;
        }
      }
    }
    // Mover 1, 2 o 3 paradas seguidas a otro lugar (al derecho o al revés).
    for (var size = 1; size <= 3; size++) {
      for (var i = 0; i + size <= best.length; i++) {
        final seg = best.sublist(i, i + size);
        final rest = [...best.sublist(0, i), ...best.sublist(i + size)];
        for (var j = 0; j <= rest.length; j++) {
          if (j == i) continue;
          for (final s in [seg, seg.reversed.toList()]) {
            final cand = [...rest.sublist(0, j), ...s, ...rest.sublist(j)];
            if (!ok(cand)) continue;
            final l = len(cand);
            if (l + 0.01 < bestLen) {
              best = cand;
              bestLen = l;
              improved = true;
            }
          }
        }
      }
    }
  }

  return [
    for (var k = 0; k < groups.length; k++)
      [
        for (final i in best)
          if (route[i].$1 == k) items[i],
      ],
  ];
}
