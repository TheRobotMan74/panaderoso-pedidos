import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/day_requests.dart';
import 'package:panaderoso_pedidos/models.dart';

DayRequest req(String uid, String date, String band,
        {String place = '', Map<String, int> items = const {}, bool seen = false, bool notified = false}) =>
    DayRequest(
      id: DayRequest.idFor(uid, date),
      customerId: uid,
      customerName: uid,
      date: date,
      band: band,
      place: place,
      items: items,
      seen: seen,
      notified: notified,
    );

void main() {
  final now = DateTime(2026, 11, 24, 10);

  test('fechas para sugerir: de mañana a 21 días', () {
    final d = suggestableDates(now);
    expect(d.first, '2026-11-25');
    expect(d.length, requestDaysAhead);
    expect(d.last, '2026-12-15');
  });

  test('agrupa por día, quita los pasados y cuenta horas, lugares y pan', () {
    final groups = groupRequests([
      req('ana', '2026-11-28', 'manana', items: {'Chocolatín': 3}),
      req('beto', '2026-11-28', 'temprano', items: {'Chocolatín': 2, 'Donas': 4}),
      req('caro', '2026-11-28', 'manana', place: 'FIME'),
      req('dan', '2026-11-26', 'tarde'),
      req('eli', '2026-11-20', 'tarde'), // ya pasó
    ], now);
    expect(groups.map((g) => g.date), ['2026-11-26', '2026-11-28']);
    final g = groups[1];
    expect(g.customers, 3);
    expect(g.bands.map((b) => (b.$1.key, b.$2)), [('temprano', 1), ('manana', 2)]);
    expect(g.places, [('', 2), ('FIME', 1)]);
    expect(g.pieces, [('Chocolatín', 5), ('Donas', 4)]);
    expect(g.totalPieces, 9);
    expect(g.suggestedHours, (6 * 60, 12 * 60));
  });

  test('a quién avisar y cuántas nuevas', () {
    final all = [
      req('ana', '2026-11-28', 'manana', seen: true),
      req('beto', '2026-11-28', 'tarde', notified: true, seen: true),
      req('caro', '2026-11-29', 'tarde'),
      req('dan', '2026-11-01', 'tarde'),
    ];
    expect(toNotify(all, ['2026-11-28']).map((r) => r.customerId), ['ana']);
    expect(unseenRequests(all, now), 1);
  });

  test('resumen y nota', () {
    expect(requestSummary(req('a', '2026-11-28', 'manana', items: {'Donas': 1})),
        'En la mañana (9:00 a 12:00) · a domicilio · 1 pieza');
    expect(requestSummary(req('a', '2026-11-28', 'noche', place: 'FIME')), 'En la noche (18:00 a 21:00) · en FIME');
    expect(cleanRequestNote('  hola   mundo '), 'hola mundo');
    expect(cleanRequestNote('x' * 500).length, requestNoteMaxChars);
  });

  test('id y mapa', () {
    final r = DayRequest.fromMap('u_2026-11-28', {
      'customerId': 'u',
      'date': '2026-11-28',
      'band': 'tarde',
      'items': {'Donas': 2},
    });
    expect(r.pieces, 2);
    expect(DayRequest.idFor('u', '2026-11-28'), r.id);
    expect(r.toMap()['seen'], false);
  });
}
