import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:panaderoso_pedidos/logic/eta.dart';
import 'package:panaderoso_pedidos/logic/geo.dart';
import 'package:panaderoso_pedidos/models.dart';
import 'package:panaderoso_pedidos/ui/customer/tracking_page.dart';
import 'package:panaderoso_pedidos/ui/push_reminder.dart';

BakeryOrder _order(
  String id,
  String customer, {
  double? lat,
  double? lng,
  OrderStatus status = OrderStatus.enCamino,
  String slot = '10:00',
}) => BakeryOrder(
  id: id,
  customerId: customer,
  customerName: 'Cliente $customer',
  phone: '',
  address: '',
  items: const [OrderItem(productId: 'p', name: 'Chocolatín', price: 30, qty: 2)],
  deliveryDate: '2026-11-23',
  slot: slot,
  paymentMethod: PaymentMethod.efectivo,
  status: status,
  lat: lat,
  lng: lng,
);

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  group('tiempo estimado', () {
    // Unos 1.1 km hacia el norte por cada 0.01 grados de latitud.
    const driver = (25.70, -100.30);
    const a = (25.71, -100.30);
    const b = (25.72, -100.30);

    test('suma manejo y minutos de cada entrega anterior, en el orden de la ruta', () {
      final eta = etaMinutes(
        [('ana', a), ('beto', b)],
        driver,
        speedKmh: 30,
        stopMinutes: 4,
        roadFactor: 1.3,
      );
      final leg = distanceMeters(driver.$1, driver.$2, a.$1, a.$2) * 1.3 / 500; // 30 km/h = 500 m/min
      expect(eta['ana'], leg.ceil());
      // Beto: manejo a Ana + 4 min entregando + manejo de Ana a él.
      expect(eta['beto'], (leg + 4 + leg).ceil());
    });

    test('dos pedidos del mismo cliente: cuenta la primera parada', () {
      final eta = etaMinutes([('ana', a), ('beto', b), ('ana', b)], driver);
      expect(eta.length, 2);
      expect(eta['ana']! < eta['beto']!, isTrue);
    });

    test('parada sin casa marcada suma unos minutos fijos', () {
      final eta = etaMinutes([('x', null), ('ana', driver)], driver, stopMinutes: 3, unknownLegMinutes: 6);
      expect(eta['x'], 6);
      expect(eta['ana'], 9);
    });

    test('con la ruta del día ignora lo ya entregado', () {
      final route = [
        _order('1', 'ana', lat: a.$1, lng: a.$2, status: OrderStatus.entregado),
        _order('2', 'beto', lat: b.$1, lng: b.$2),
      ];
      final eta = etaForRoute(route, a, const AppConfig(etaSpeedKmh: 30, etaStopMinutes: 4));
      expect(eta.containsKey('ana'), isFalse);
      final leg = distanceMeters(a.$1, a.$2, b.$1, b.$2) * 1.3 / 500;
      expect(eta['beto'], leg.ceil());
    });

    test('el reloj sigue aunque no lleguen ubicaciones nuevas, sin bajar de 1', () {
      final t = DateTime(2026, 11, 23, 10);
      expect(etaRemaining(20, t, t.add(const Duration(minutes: 5))), 15);
      expect(etaRemaining(5, t, t.add(const Duration(minutes: 30))), 1);
      expect(etaRemaining(12, null, t), 12);
    });

    test('textos', () {
      expect(etaLabel(4), 'unos 4 min');
      expect(etaLabel(23), 'unos 25 min');
      expect(etaLabel(60), '1 hora');
      expect(etaLabel(83), '1 h 25 min');
    });

    test('se guarda en la configuración', () {
      final c = AppConfig.fromMap(const AppConfig(etaSpeedKmh: 32, etaStopMinutes: 2.5).toMap());
      expect(c.etaSpeedKmh, 32);
      expect(c.etaStopMinutes, 2.5);
      expect(AppConfig.fromMap(const {}).etaSpeedKmh, 25);
    });
  });

  group('tarjeta de "¿Dónde va mi pedido?"', () {
    final now = DateTime(2026, 11, 23, 10, 0);
    const home = (25.72, -100.30);

    TrackingInfo live({Map<String, int> eta = const {}, Map<String, int> ahead = const {}, DateTime? at}) =>
        TrackingInfo(
          active: true,
          lat: 25.70,
          lng: -100.30,
          updatedAt: at ?? now.subtract(const Duration(seconds: 30)),
          eta: eta,
          etaAt: at ?? now.subtract(const Duration(seconds: 30)),
          ahead: ahead,
        );

    test('con tiempo estimado: minutos, hora y entregas antes', () {
      final v = trackingView(
        order: _order('1', 'ana'),
        info: live(eta: {'ana': 25}, ahead: {'ana': 2}),
        home: home,
        now: now,
      );
      expect(v.title, 'Llega en unos 25 min');
      expect(v.lines[0], startsWith('Hora aproximada: 10:25'));
      expect(v.lines[0], contains('km'));
      expect(v.lines[1], 'Faltan 2 entregas antes de la tuya');
      expect(v.lines[2], startsWith('En vivo'));
      expect(v.live, isTrue);
      expect(v.stale, isFalse);
    });

    test('sin tiempo estimado (versión vieja del dueño) queda la distancia', () {
      final v = trackingView(order: _order('1', 'ana'), info: live(), home: home, now: now);
      expect(v.title, startsWith('Tu pan está a'));
    });

    test('ya casi llega', () {
      final v = trackingView(
        order: _order('1', 'ana'),
        info: live(eta: {'ana': 2}),
        home: home,
        now: now,
      );
      expect(v.title, '¡Ya casi llega!');
    });

    test('ubicación vieja: avisa que puede estar entregando', () {
      final v = trackingView(
        order: _order('1', 'ana'),
        info: live(eta: {'ana': 30}, at: now.subtract(const Duration(minutes: 10))),
        home: home,
        now: now,
      );
      expect(v.stale, isTrue);
      expect(v.lines.last, contains('puede estar entregando'));
      // Pasaron 10 de los 30 minutos.
      expect(v.title, 'Llega en unos 20 min');
    });

    test('entregado aunque ya no se pueda leer la ubicación', () {
      final v = trackingView(
        order: _order('1', 'ana', status: OrderStatus.entregado),
        info: const TrackingInfo(),
        home: home,
        now: now,
      );
      expect(v.title, '¡Tu pedido ya fue entregado!');
      expect(v.live, isFalse);
    });

    test('todavía no sale', () {
      final v = trackingView(
        order: _order('1', 'ana', status: OrderStatus.confirmado),
        info: const TrackingInfo(),
        home: home,
        now: now,
      );
      expect(v.title, 'El repartidor todavía no sale');
    });
  });

  test('recordatorio de avisos: una de cada 3 veces que se abre la app', () {
    expect([for (var n = 1; n <= 7; n++) remindOnOpen(n)], [true, false, false, true, false, false, true]);
  });
}
