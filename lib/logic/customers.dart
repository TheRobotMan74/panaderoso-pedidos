import '../models.dart';

/// Si al cliente le llegan las notificaciones.
enum PushState { on, off, unknown }

/// Un cliente con lo que ha pedido, para la sección Clientes del dueño.
class CustomerSummary {
  final String uid;
  final String name;
  final String phone;
  final List<SavedAddress> addresses;
  final PushState push;

  /// Pedidos que no se cancelaron (entregados y pendientes).
  final int orders;

  /// Piezas compradas en esos pedidos (sin las regaladas).
  final int pieces;

  /// Fecha de entrega (AAAA-MM-DD) de su pedido más reciente, o null si nunca ha pedido.
  final String? lastDate;

  /// Fechas en las que tiene un pedido pendiente de entregar.
  final Set<String> pendingDates;

  const CustomerSummary({
    required this.uid,
    required this.name,
    required this.phone,
    this.addresses = const [],
    this.push = PushState.unknown,
    this.orders = 0,
    this.pieces = 0,
    this.lastDate,
    this.pendingDates = const {},
  });

  /// Su próximo pedido pendiente desde [today], o null.
  String? nextDate(String today) {
    final next = pendingDates.where((d) => d.compareTo(today) >= 0).toList()..sort();
    return next.isEmpty ? null : next.first;
  }

  String get displayName => name.trim().isEmpty ? 'Sin nombre' : name.trim();

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return name.toLowerCase().contains(q) ||
        (digits.isNotEmpty && phone.replaceAll(RegExp(r'\D'), '').contains(digits)) ||
        addresses.any((a) => a.address.toLowerCase().contains(q) || a.label.toLowerCase().contains(q));
  }
}

PushState pushStateOf(bool? pushOk) => switch (pushOk) {
      true => PushState.on,
      false => PushState.off,
      null => PushState.unknown,
    };

/// Junta las cuentas de clientes con sus pedidos. Un pedido de alguien sin cuenta
/// (por ejemplo, una cuenta que se borró) también aparece, con los datos del pedido.
/// Ordenados: primero los que pidieron más recientemente; los que nunca han pedido, al final.
List<CustomerSummary> summarizeCustomers(List<AppUser> users, List<BakeryOrder> orders) {
  final byUid = <String, List<BakeryOrder>>{};
  for (final o in orders) {
    if (o.customerId.isEmpty || o.status == OrderStatus.cancelado) continue;
    byUid.putIfAbsent(o.customerId, () => []).add(o);
  }
  CustomerSummary build(String uid, String name, String phone, List<SavedAddress> addresses, PushState push) {
    final mine = byUid[uid] ?? const <BakeryOrder>[];
    String? last;
    for (final o in mine) {
      if (last == null || o.deliveryDate.compareTo(last) > 0) last = o.deliveryDate;
    }
    return CustomerSummary(
      uid: uid,
      name: name,
      phone: phone,
      addresses: addresses,
      push: push,
      orders: mine.length,
      pieces: mine.fold(0, (s, o) => s + o.paidPieces),
      lastDate: last,
      pendingDates: {
        for (final o in mine)
          if (o.isPending) o.deliveryDate
      },
    );
  }

  final seen = <String>{};
  final list = <CustomerSummary>[];
  for (final u in users) {
    if (u.role == Role.dueno || !seen.add(u.uid)) continue;
    list.add(build(u.uid, u.name, u.phone, u.addresses, pushStateOf(u.pushOk)));
  }
  for (final e in byUid.entries) {
    if (seen.contains(e.key)) continue;
    final o = e.value.first;
    final addr = SavedAddress(
        id: 'pedido', label: 'Casa', address: o.address, notes: o.addressNotes, lat: o.lat, lng: o.lng);
    list.add(build(e.key, o.customerName, o.phone, o.address.isEmpty ? const [] : [addr], PushState.unknown));
  }
  list.sort((a, b) {
    if (a.lastDate != b.lastDate) {
      if (a.lastDate == null) return 1;
      if (b.lastDate == null) return -1;
      return b.lastDate!.compareTo(a.lastDate!);
    }
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return list;
}

/// Días con pedidos pendientes desde [today] (incluye días especiales de entrega
/// en un punto), con cuántos clientes tiene cada uno. Ordenados por fecha.
List<(String, int)> pendingDays(List<CustomerSummary> customers, String today) {
  final count = <String, int>{};
  for (final c in customers) {
    for (final d in c.pendingDates) {
      if (d.compareTo(today) >= 0) count[d] = (count[d] ?? 0) + 1;
    }
  }
  return (count.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$1.compareTo(b.$1)));
}

/// WhatsApp para pedirle a un cliente que prenda los avisos.
String pushReminderText(String name) {
  final first = name.trim().split(RegExp(r'\s+')).first;
  final hi = first.isEmpty ? '¡Hola!' : '¡Hola $first!';
  return '$hi Te escribo de Panaderoso 🐻🥐. Vi que no te están llegando las notificaciones de la app, '
      'así no te llegan los avisos de cuando vamos en camino ni de cuándo abrimos pedidos. '
      'Para prenderlas: en tu celular ve a Ajustes → Aplicaciones → Panaderoso → Notificaciones y actívalas. '
      '(Si usas la versión web en iPhone: Ajustes → Notificaciones → Panaderoso.) '
      'Si ya las tienes prendidas, solo abre la app de Panaderoso una vez para que se actualice. ¡Gracias!';
}

/// Parte una lista en pedazos de [size] (el servidor acepta hasta 200 clientes por mensaje).
List<List<T>> chunked<T>(List<T> list, int size) => [
      for (var i = 0; i < list.length; i += size)
        list.sublist(i, i + size > list.length ? list.length : i + size),
    ];
