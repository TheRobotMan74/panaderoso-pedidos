import 'package:intl/intl.dart';

import '../logic/schedule.dart';

final _money = NumberFormat.currency(locale: 'es_MX', symbol: r'$', decimalDigits: 0);

String money(num v) => _money.format(v);

/// "lunes 23 de noviembre"
String dayLabel(String dateKey) =>
    DateFormat("EEEE d 'de' MMMM", 'es_MX').format(parseDateKey(dateKey));

/// "20 nov, 6:00 p. m."
String dateTimeLabel(DateTime d) => DateFormat("d MMM, h:mm a", 'es_MX').format(d);
