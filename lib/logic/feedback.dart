import '../models.dart';
import 'flavors.dart';
import 'schedule.dart';

/// Se puede calificar un pedido entregado, o uno de un día que ya pasó
/// (por si el dueño no alcanzó a marcarlo entregado). Los cancelados no.
bool canReview(BakeryOrder o, DateTime now) {
  if (o.status == OrderStatus.cancelado) return false;
  if (o.status == OrderStatus.entregado) return true;
  return o.deliveryDate.compareTo(dateKey(now)) < 0;
}

/// Hasta cuántos días después de la entrega se le pide la reseña en la pantalla de inicio.
const reviewPromptDays = 10;

/// El pedido que se le pide calificar al cliente en el inicio: su último pedido
/// que ya se puede calificar, si es reciente, no tiene reseña y no dijo "Ahora no".
BakeryOrder? orderToReview(
  List<BakeryOrder> orders, {
  required Set<String> reviewed,
  String? skipped,
  required DateTime now,
}) {
  final candidates = orders.where((o) => canReview(o, now)).toList()
    ..sort((a, b) {
      final c = b.deliveryDate.compareTo(a.deliveryDate);
      return c != 0 ? c : b.slot.compareTo(a.slot);
    });
  final last = candidates.firstOrNull;
  if (last == null || reviewed.contains(last.id) || last.id == skipped) return null;
  final oldest = dateKey(DateTime(now.year, now.month, now.day - reviewPromptDays));
  if (last.deliveryDate.compareTo(oldest) < 0) return null;
  return last;
}

/// "2 × Chocolatín", para que el dueño sepa de qué pedido habla la reseña.
List<String> reviewItems(BakeryOrder o) => [for (final it in o.items) itemLabel(it, times: '× ')];

/// Cómo se llama cada calificación.
String ratingLabel(int stars) => switch (stars) {
      1 => 'No me gustó',
      2 => 'Le faltó',
      3 => 'Estuvo bien',
      4 => 'Muy rico',
      _ => '¡Riquísimo!',
    };

/// Promedio y cuántas reseñas hay de cada estrella (índice 0 = 1 estrella).
class RatingSummary {
  final double average;
  final int count;
  final List<int> perStar;
  const RatingSummary(this.average, this.count, this.perStar);

  factory RatingSummary.of(Iterable<Review> reviews) {
    final per = List.filled(5, 0);
    var sum = 0;
    for (final r in reviews) {
      per[r.rating - 1]++;
      sum += r.rating;
    }
    final n = per.fold(0, (a, b) => a + b);
    return RatingSummary(n == 0 ? 0 : sum / n, n, per);
  }
}

/// Largo máximo de una idea de pan y de un comentario.
const suggestionMaxChars = 300;
const reviewMaxChars = 600;

/// Limpia la idea antes de mandarla. Regresa null si viene vacía.
String? cleanSuggestion(String text) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  return t.length > suggestionMaxChars ? t.substring(0, suggestionMaxChars) : t;
}
