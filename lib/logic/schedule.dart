import '../models.dart';

/// Fecha como AAAA-MM-DD, que también es el id de cada día de entrega.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Hora límite por defecto: el día anterior a las [hour] (la horneada es un día antes).
DateTime defaultCutoff(String date, {int hour = 18}) {
  final d = parseDateKey(date);
  return DateTime(d.year, d.month, d.day - 1, hour);
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

/// Días a los que el cliente todavía puede pedir, ordenados por fecha.
List<DeliveryDay> orderableDays(List<DeliveryDay> days, DateTime now) {
  final list = days
      .where((d) => d.open && d.slots.isNotEmpty && now.isBefore(d.orderCutoff))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return list;
}
