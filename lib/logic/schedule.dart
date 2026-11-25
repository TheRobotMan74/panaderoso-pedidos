import '../models.dart';

/// Fecha como AAAA-MM-DD, que también es el id del primer reparto de ese día.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Fecha de un id de reparto. Puede haber varios repartos el mismo día:
/// el primero se llama como la fecha ("2026-11-25") y los demás llevan
/// un número al final ("2026-11-25-2", "2026-11-25-3"…). Así los pedidos,
/// la ruta y el cupo de cada reparto van por separado.
String dayDateOf(String dayId) => dayId.length > 10 ? dayId.substring(0, 10) : dayId;

/// Acepta un id de reparto o una fecha.
DateTime parseDateKey(String key) {
  final p = dayDateOf(key).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Id libre para un reparto nuevo en [date]: la fecha si no hay ninguno,
/// si no la fecha con el siguiente número.
String newDayId(String date, Iterable<String> taken) {
  final used = taken.toSet();
  if (!used.contains(date)) return date;
  for (var n = 2;; n++) {
    final id = '$date-$n';
    if (!used.contains(id)) return id;
  }
}

/// Primera hora del reparto en minutos (para ordenar los del mismo día).
int dayStartMinute(DeliveryDay d) =>
    d.slots.isEmpty ? 0 : d.slots.map(slotMinute).reduce((a, b) => a < b ? a : b);

/// Ordena repartos por fecha y, dentro del mismo día, por hora.
int compareDays(DeliveryDay a, DeliveryDay b) {
  final c = a.day.compareTo(b.day);
  if (c != 0) return c;
  final h = dayStartMinute(a).compareTo(dayStartMinute(b));
  return h != 0 ? h : a.date.compareTo(b.date);
}

/// Ordena ids de reparto por fecha y hora de inicio (usa [days] para la hora;
/// los que no están ahí van por id).
int compareDayIds(String a, String b, Map<String, DeliveryDay> days) {
  final c = dayDateOf(a).compareTo(dayDateOf(b));
  if (c != 0) return c;
  final da = days[a], db = days[b];
  if (da != null && db != null) return compareDays(da, db);
  return a.compareTo(b);
}

/// Si ese día hay más de un reparto, cómo distinguir este:
/// "7:45 · Acuity" o "12:00 · a domicilio". Null si es el único del día.
String? repartoTag(String dayId, Iterable<DeliveryDay> days) {
  final date = dayDateOf(dayId);
  final same = days.where((d) => d.day == date).toList();
  if (same.length < 2) return null;
  final d = same.where((d) => d.date == dayId).firstOrNull;
  if (d == null) return null;
  return repartoShort(d);
}

/// "7:45 · Acuity" / "12:00 · a domicilio".
String repartoShort(DeliveryDay d) => '${clockLabel(dayStartMinute(d))} · ${d.pickup?.name ?? 'a domicilio'}';

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
      .where((d) => d.open && !d.closed && d.slots.isNotEmpty && d.day.compareTo(today) >= 0)
      .toList()
    ..sort(compareDays);
  return list;
}
