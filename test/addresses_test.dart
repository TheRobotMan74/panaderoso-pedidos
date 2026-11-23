import 'package:flutter_test/flutter_test.dart';
import 'package:panaderoso_pedidos/models.dart';

void main() {
  group('direcciones guardadas', () {
    test('cuenta de antes: su única dirección es la principal', () {
      final u = AppUser.fromMap('u1', {
        'name': 'Ana',
        'address': 'Calle 1',
        'addressNotes': 'portón negro',
        'lat': 20.0,
        'lng': -100.0,
      });
      expect(u.addresses, hasLength(1));
      expect(u.addresses.first.address, 'Calle 1');
      expect(u.addresses.first.notes, 'portón negro');
      expect(u.addresses.first.label, 'Casa');
    });

    test('sin dirección todavía (registro): lista vacía', () {
      expect(AppUser.fromMap('u1', {'name': 'Ana'}).addresses, isEmpty);
    });

    test('con varias: la principal siempre es la de address/lat/lng', () {
      final u = AppUser.fromMap('u1', {
        // Una versión vieja de la app cambió la principal sin tocar la lista.
        'address': 'Calle Nueva 5',
        'lat': 21.0,
        'lng': -101.0,
        'addresses': [
          {'id': 'a', 'label': 'Casa', 'address': 'Calle 1', 'lat': 20.0, 'lng': -100.0},
          {'id': 'b', 'label': 'Trabajo', 'address': 'Av. 2', 'lat': 20.5, 'lng': -100.5},
          {'id': 'c', 'label': 'Otra', 'address': 'Av. 3', 'lat': 20.6, 'lng': -100.6},
          {'id': 'd', 'label': 'De más', 'address': 'Av. 4', 'lat': 20.7, 'lng': -100.7},
        ],
      });
      final list = u.addresses;
      expect(list, hasLength(maxAddresses));
      expect(list.first.id, 'a');
      expect(list.first.address, 'Calle Nueva 5');
      expect(list.first.lat, 21.0);
      expect(list[1].label, 'Trabajo');
    });

    test('sameAs reconoce la dirección de un pedido', () {
      const a = SavedAddress(id: 'a', label: 'Casa', address: 'Calle 1 ', lat: 20.0, lng: -100.0);
      expect(a.sameAs(address: 'Calle 1', lat: 20.0, lng: -100.0), isTrue);
      expect(a.sameAs(address: 'Calle 1', lat: 20.1, lng: -100.0), isFalse);
      expect(a.sameAs(address: 'Calle 1'), isFalse);
    });
  });
}
