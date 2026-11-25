import '../models.dart';
import 'schedule.dart';

/// Franja de hora aproximada que puede sugerir un cliente.
class RequestBand {
  final String key;
  final String name;
  final int start;
  final int end;
  const RequestBand(this.key, this.name, this.start, this.end);

  /// "6:00 a 9:00".
  String get hours => '${clockLabel(start)} a ${clockLabel(end)}';
}

/// Las franjas, en orden del día. Las mismas llaves están en firestore.rules.
const requestBands = [
  RequestBand('temprano', 'Temprano', 6 * 60, 9 * 60),
  RequestBand('manana', 'En la mañana', 9 * 60, 12 * 60),
  RequestBand('mediodia', 'Al mediodía', 12 * 60, 15 * 60),
  RequestBand('tarde', 'En la tarde', 15 * 60, 18 * 60),
  RequestBand('noche', 'En la noche', 18 * 60, 21 * 60),
];

RequestBand? bandFor(String key) => requestBands.where((b) => b.key == key).firstOrNull;

/// Cuántos días hacia adelante se puede sugerir (de mañana en adelante).
const requestDaysAhead = 21;

/// Largo máximo de la nota del cliente (igual en firestore.rules).
const requestNoteMaxChars = 200;

/// Fechas que el cliente puede sugerir: de mañana a [requestDaysAhead] días.
List<String> suggestableDates(DateTime now) => [
      for (var i = 1; i <= requestDaysAhead; i++) dateKey(DateTime(now.year, now.month, now.day + i)),
    ];

/// Las sugerencias de un mismo día, juntas, para que el dueño decida si lo abre.
class RequestedDay {
  final String date;
  final List<DayRequest> requests;
  const RequestedDay(this.date, this.requests);

  int get customers => requests.length;

  /// Cuántos clientes quieren cada franja, en orden del día (solo las que alguien pidió).
  List<(RequestBand, int)> get bands => [
        for (final b in requestBands)
          if (requests.where((r) => r.band == b.key).length case final n when n > 0) (b, n),
      ];

  /// Dónde lo quieren: '' = a domicilio. Del más pedido al menos.
  List<(String, int)> get places {
    final m = <String, int>{};
    for (final r in requests) {
      m[r.place] = (m[r.place] ?? 0) + 1;
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// Piezas que le gustaría a la gente, por pan. Del más pedido al menos.
  List<(String, int)> get pieces {
    final m = <String, int>{};
    for (final r in requests) {
      for (final e in r.items.entries) {
        m[e.key] = (m[e.key] ?? 0) + e.value;
      }
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  }

  int get totalPieces => requests.fold(0, (a, r) => a + r.pieces);

  /// Los que todavía no saben que se abrió el día.
  List<DayRequest> get pending => requests.where((r) => !r.notified).toList();

  /// Horario sugerido para abrir: del inicio de la franja más temprana pedida
  /// al final de la más tarde.
  (int, int) get suggestedHours {
    final b = bands.map((x) => x.$1).toList();
    if (b.isEmpty) return (8 * 60, 11 * 60);
    return (b.first.start, b.last.end);
  }

  bool get hasNew => requests.any((r) => !r.seen);
}

/// Agrupa por día las sugerencias de hoy en adelante, del día más cercano al más lejano.
List<RequestedDay> groupRequests(Iterable<DayRequest> all, DateTime now) {
  final today = dateKey(now);
  final byDate = <String, List<DayRequest>>{};
  for (final r in all) {
    if (r.date.compareTo(today) < 0) continue;
    byDate.putIfAbsent(r.date, () => []).add(r);
  }
  final dates = byDate.keys.toList()..sort();
  return [
    for (final d in dates)
      RequestedDay(d, byDate[d]!..sort((a, b) => a.customerName.compareTo(b.customerName))),
  ];
}

/// Sugerencias nuevas (que el dueño no ha visto) de hoy en adelante.
int unseenRequests(Iterable<DayRequest> all, DateTime now) {
  final today = dateKey(now);
  return all.where((r) => !r.seen && r.date.compareTo(today) >= 0).length;
}

/// Clientes que pidieron alguno de [dates] y todavía no saben que se abrió.
List<DayRequest> toNotify(Iterable<DayRequest> all, Iterable<String> dates) {
  final set = dates.toSet();
  return all.where((r) => set.contains(r.date) && !r.notified).toList();
}

/// El mensaje que les llega a quienes pidieron el día. [dayText] es "viernes 28 de noviembre".
String openedDayMessage(String dayText) =>
    '¡Abrimos el $dayText como lo pediste! 🥐 Ya puedes hacer tu pedido en la app.';

/// Limpia la nota. Vacía si no escribió nada.
String cleanRequestNote(String text) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > requestNoteMaxChars ? t.substring(0, requestNoteMaxChars) : t;
}

/// Lo que dice una sugerencia en corto: "En la mañana (9:00 a 12:00) · FIME · 4 piezas".
String requestSummary(DayRequest r) {
  final b = bandFor(r.band);
  return [
    if (b != null) '${b.name} (${b.hours})',
    r.place.isEmpty ? 'a domicilio' : 'en ${r.place}',
    if (r.pieces > 0) '${r.pieces} ${r.pieces == 1 ? 'pieza' : 'piezas'}',
  ].join(' · ');
}
