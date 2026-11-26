import '../models.dart';

/// Sabores de un pan: el cliente elige cuántas de cada uno (por ejemplo 3 donas =
/// 2 de chocolate y 1 de caramelo). Todos los sabores comparten el cupo del pan.
///
/// El dueño los cambia en Ajustes → Sabores (o al editar el pan). Mientras no los
/// toque, las donas traen estos tres. Igual que saboresDe en functions/index.js.
const defaultDonutFlavors = ['Glaseado', 'Chocolate', 'Caramelo'];

/// Hasta cuántos sabores puede tener un pan.
const maxFlavors = 12;

/// Llave de las piezas sin sabor elegido (pedidos de versiones viejas de la app).
const noFlavor = '';

String _plain(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .trim();

/// "Donas", "Dona glaseada"… (para darles sus sabores de siempre).
bool looksLikeDonut(String name) => RegExp(r'\bdonas?\b').hasMatch(_plain(name));

/// Sabores de un pan. [explicit] es lo que guardó el dueño (null = nunca los tocó).
List<String> flavorsFor(String name, List<String>? explicit) {
  if (explicit == null) return looksLikeDonut(name) ? defaultDonutFlavors : const [];
  return cleanFlavors(explicit);
}

/// Sin vacíos ni repetidos (sin importar mayúsculas o acentos), máximo [maxFlavors].
List<String> cleanFlavors(Iterable<String> names) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in names) {
    final n = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty || n.length > 40 || !seen.add(_plain(n))) continue;
    out.add(n);
    if (out.length == maxFlavors) break;
  }
  return out;
}

/// El sabor de la lista que es "el mismo" que [name] (sin importar mayúsculas ni acentos).
String? matchFlavor(List<String> flavors, String name) {
  final p = _plain(name);
  for (final f in flavors) {
    if (_plain(f) == p) return f;
  }
  return null;
}

/// Orden para mostrar: el de [order] (los sabores del pan), luego glaseado,
/// chocolate y caramelo, luego por nombre; "sin elegir" siempre al final.
List<String> sortFlavors(Iterable<String> keys, [List<String> order = const []]) {
  int rank(String k) {
    if (k == noFlavor) return 1 << 20;
    final i = order.indexWhere((o) => _plain(o) == _plain(k));
    if (i >= 0) return i;
    final d = defaultDonutFlavors.indexWhere((o) => _plain(o) == _plain(k));
    return d >= 0 ? 100 + d : 1000;
  }

  return keys.toList()
    ..sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : _plain(a).compareTo(_plain(b));
    });
}

/// Cómo se llama cada sabor en pantalla.
String flavorName(String key) => key == noFlavor ? 'Sin elegir' : key;

/// Dibujito del sabor.
String flavorEmoji(String key) {
  final n = _plain(key);
  if (key == noFlavor) return '❓';
  if (n.contains('chocol') || n.contains('nutella') || n.contains('cacao')) return '🍫';
  if (n.contains('caramel') || n.contains('cajeta') || n.contains('miel') || n.contains('dulce de leche')) {
    return '🍯';
  }
  if (n.contains('fresa')) return '🍓';
  if (n.contains('vainilla') || n.contains('crema')) return '🍦';
  if (n.contains('limon')) return '🍋';
  if (n.contains('cafe') || n.contains('moka')) return '☕';
  if (n.contains('coco')) return '🥥';
  if (n.contains('nuez') || n.contains('cacahuate') || n.contains('almendra')) return '🥜';
  return '🍩';
}

/// Sabores de un renglón del pedido, en orden, con las piezas que no traen
/// sabor como [noFlavor]. Vacío si ese pan no tiene sabores.
List<MapEntry<String, int>> itemFlavors(OrderItem it) {
  final f = it.flavors;
  if (f == null) return const [];
  final chosen = f.values.fold(0, (a, b) => a + b);
  final all = {...f, if (it.qty > chosen) noFlavor: it.qty - chosen};
  return [for (final k in sortFlavors(all.keys)) MapEntry(k, all[k]!)];
}

/// "2 Chocolate, 1 Caramelo". Vacío si ese pan no tiene sabores.
String flavorSummary(OrderItem it) => [
      for (final e in itemFlavors(it))
        e.key == noFlavor ? '${e.value} sin sabor elegido' : '${e.value} ${e.key}',
    ].join(', ');

/// "3 Donas (2 Chocolate, 1 Caramelo)" o "2 Chocolatín".
String itemLabel(OrderItem it, {String times = ''}) {
  final s = flavorSummary(it);
  return '${it.qty} $times${it.name}${s.isEmpty ? '' : ' ($s)'}';
}

/// Lo de un pedido en un renglón: "2 Chocolatín, 3 Donas (2 Chocolate, 1 Caramelo)".
String itemsLabel(List<OrderItem> items) => items.map(itemLabel).join(', ');
