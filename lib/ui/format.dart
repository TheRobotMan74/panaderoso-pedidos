import 'package:intl/intl.dart';

import '../logic/schedule.dart';

final _money = NumberFormat.currency(locale: 'es_MX', symbol: r'$', decimalDigits: 0);

String money(num v) => _money.format(v);

/// "lunes 23 de noviembre"
String dayLabel(String dateKey) =>
    DateFormat("EEEE d 'de' MMMM", 'es_MX').format(parseDateKey(dateKey));

/// "20 nov, 6:00 p. m."
String dateTimeLabel(DateTime d) => DateFormat("d MMM, h:mm a", 'es_MX').format(d);

/// "lunes 23" → "Lunes 23".
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Parte un nombre largo en renglones cortos para encabezados angostos:
/// "Croissant de Jamón y Queso" → "Croissant\nde Jamón\ny Queso".
/// Junta palabras mientras quepan en [maxChars]; una palabra larga va sola.
/// Una palabrita ("y", "de") no se queda colgando al final del renglón:
/// se pasa al siguiente junto con la palabra que acompaña.
String wrapShort(String text, {int maxChars = 10}) {
  final words = text.trim().split(RegExp(r'\s+'));
  final lines = <String>[];
  var line = '';
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    var fits = line.isEmpty || line.length + 1 + w.length <= maxChars;
    if (fits && line.isNotEmpty && w.length <= 2 && i + 1 < words.length) {
      fits = line.length + 1 + w.length + 1 + words[i + 1].length <= maxChars;
    }
    if (fits) {
      line = line.isEmpty ? w : '$line $w';
    } else {
      lines.add(line);
      line = w;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines.join('\n');
}
