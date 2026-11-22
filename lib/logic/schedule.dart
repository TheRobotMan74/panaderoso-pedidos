import '../models.dart';

/// Fecha como AAAA-MM-DD, que también es el id de cada día de entrega.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Horarios de una hora entre [startHour] y [endHour], por ejemplo 8 a 11 → 08:00, 09:00, 10:00.
List<String> hourlySlots(int startHour, int endHour) => [
      for (var h = startHour; h < endHour; h++) '${h.toString().padLeft(2, '0')}:00',
    ];

/// Texto del horario, por ejemplo "08:00" con 60 minutos → "8:00 a 9:00".
String slotLabel(String slot, {int minutes = 60}) {
  final p = slot.split(':').map(int.parse).toList();
  final start = p[0] * 60 + p[1];
  final end = start + minutes;
  String fmt(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  return '${fmt(start)} a ${fmt(end)}';
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
