import '../models.dart';

/// Fecha como AAAA-MM-DD, que también es el id de cada día de entrega.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Horarios de una hora entre [startHour] y [endHour], por ejemplo 8 a 11 → 08:00, 09:00, 10:00.
List<String> hourlySlots(int startHour, int endHour) => slotsBetween(startHour * 60, endHour * 60, 60);

/// Minutos desde medianoche → "08:15".
String slotKey(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// "08:15" → 495 minutos desde medianoche.
int slotMinute(String slot) {
  final p = slot.split(':');
  return int.parse(p[0]) * 60 + (p.length > 1 ? int.parse(p[1]) : 0);
}

/// Minutos desde medianoche → "8:15", como se le enseña a la gente.
String clockLabel(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Horarios de [every] minutos entre [startMin] y [endMin] (minutos desde
/// medianoche). Por ejemplo 8:00 a 9:00 cada 15 → 08:00, 08:15, 08:30, 08:45.
/// Si el último no cabe completo, no se incluye.
List<String> slotsBetween(int startMin, int endMin, int every) => [
      if (every > 0)
        for (var m = startMin; m + every <= endMin; m += every) slotKey(m),
    ];

/// Duraciones de horario que puede elegir el dueño.
const slotLengths = [15, 30, 60];

/// Horas que se pueden elegir para abrir y cerrar un día: de 5:00 a 22:00 en cuartos de hora.
final dayTimeChoices = [for (var m = 5 * 60; m <= 22 * 60; m += 15) m];

/// Texto del horario, por ejemplo "08:00" con 60 minutos → "8:00 a 9:00".
String slotLabel(String slot, {int minutes = 60}) {
  final start = slotMinute(slot);
  return '${clockLabel(start)} a ${clockLabel(start + minutes)}';
}

/// Días a los que el cliente todavía puede pedir, ordenados por fecha:
/// abiertos, de hoy en adelante, y sin reparto empezado.
List<DeliveryDay> orderableDays(List<DeliveryDay> days, DateTime now) {
  final today = dateKey(now);
  final list = days
      .where((d) =>
          d.open && !d.closed && d.slots.isNotEmpty && d.date.compareTo(today) >= 0)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return list;
}
