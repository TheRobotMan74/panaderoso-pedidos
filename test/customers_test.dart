import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/logic/customers.dart';
import 'package:panaderoso_pedidos/models.dart';

BakeryOrder _o(String id, String uid, String date,
        {OrderStatus status = OrderStatus.confirmado, int qty = 2}) =>
    BakeryOrder(
      id: id,
      customerId: uid,
      customerName: 'Pedido $uid',
      phone: '81 1234 0000',
      address: 'Calle $uid',
      items: [OrderItem(productId: 'p', name: 'Chocolatín', price: 30, qty: qty)],
      deliveryDate: date,
      slot: '08:00',
      paymentMethod: PaymentMethod.efectivo,
      status: status,
    );

AppUser _u(String uid, String name, {bool? push, Role role = Role.cliente}) => AppUser(
    uid: uid,
    name: name,
    phone: '81 5555 ${uid.hashCode % 10000}',
    address: 'Casa de $name',
    role: role,
    pushOk: push);

void main() {
  final users = [
    _u('ana', 'Ana López', push: true),
    _u('beto', 'Beto', push: false),
    _u('caro', 'Caro'),
    _u('yo', 'Dueño', role: Role.dueno),
  ];
  final orders = [
    _o('1', 'ana', '2026-11-20', status: OrderStatus.entregado),
    _o('2', 'ana', '2026-11-27'),
    _o('3', 'beto', '2026-11-25', qty: 3),
    _o('4', 'beto', '2026-11-26', status: OrderStatus.cancelado),
    _o('5', 'viejo', '2026-11-10', status: OrderStatus.entregado),
  ];

  test('junta cuentas y pedidos, sin el dueño, más reciente primero', () {
    final c = summarizeCustomers(users, orders);
    expect(c.map((x) => x.uid), ['ana', 'beto', 'viejo', 'caro']);
    final ana = c.first;
    expect(ana.orders, 2);
    expect(ana.pieces, 4);
    expect(ana.lastDate, '2026-11-27');
    expect(ana.pendingDates, {'2026-11-27'});
    expect(ana.push, PushState.on);
    expect(ana.nextDate('2026-11-24'), '2026-11-27');
    expect(ana.nextDate('2026-11-28'), isNull);
    final beto = c[1];
    expect(beto.orders, 1, reason: 'el cancelado no cuenta');
    expect(beto.push, PushState.off);
    expect(c[2].name, 'Pedido viejo', reason: 'sin cuenta: datos del pedido');
    expect(c[3].orders, 0);
    expect(c[3].push, PushState.unknown);
  });

  test('días con pedidos pendientes desde hoy', () {
    final c = summarizeCustomers(users, orders);
    expect(pendingDays(c, '2026-11-24'), [('2026-11-25', 1), ('2026-11-27', 1)]);
    expect(pendingDays(c, '2026-11-26'), [('2026-11-27', 1)]);
  });

  test('búsqueda por nombre, teléfono o dirección', () {
    final c = summarizeCustomers(users, orders).first;
    expect(c.matches('ana'), isTrue);
    expect(c.matches('casa de ana'), isTrue);
    expect(c.matches(c.phone.replaceAll(' ', '').substring(2, 8)), isTrue);
    expect(c.matches('zzz'), isFalse);
  });

  test('recordatorio por WhatsApp usa el primer nombre', () {
    expect(pushReminderText('Ana López'), startsWith('¡Hola Ana!'));
    expect(pushReminderText(''), startsWith('¡Hola!'));
  });

  test('parte en pedazos de 200', () {
    final l = List.generate(450, (i) => i);
    expect(chunked(l, 200).map((p) => p.length), [200, 200, 50]);
  });
}
