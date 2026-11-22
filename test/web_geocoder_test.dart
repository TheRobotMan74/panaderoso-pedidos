import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:panaderoso_pedidos/services/web_geocoder.dart';

void main() {
  group('addressFromNominatim', () {
    test('calle y número, colonia y ciudad', () {
      expect(
        addressFromNominatim({
          'road': 'Avenida Madero',
          'house_number': '100',
          'suburb': 'Centro',
          'city': 'Morelia',
          'state': 'Michoacán',
        }),
        'Avenida Madero 100, Centro, Morelia',
      );
    });

    test('sin número, pueblo en lugar de ciudad, sin repetidos', () {
      expect(
        addressFromNominatim({'road': 'Hidalgo', 'neighbourhood': 'Tarímbaro', 'town': 'Tarímbaro'}),
        'Hidalgo, Tarímbaro',
      );
    });

    test('nada', () {
      expect(addressFromNominatim(null), '');
      expect(addressFromNominatim({}), '');
    });
  });

  test('WebGeocoder busca solo en México y en español', () async {
    final asked = <Uri>[];
    final geo = WebGeocoder(
      client: MockClient((req) async {
        asked.add(req.url);
        if (req.url.path == '/search') {
          return http.Response.bytes(
              utf8.encode(jsonEncode([
                {
                  'lat': '19.70',
                  'lon': '-101.19',
                  'address': {'road': 'Madero', 'house_number': '5', 'city': 'Morelia'},
                },
              ])),
              200);
        }
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'address': {'road': 'Juárez', 'city': 'Morelia'},
            })),
            200);
      }),
    );

    final p = await geo.search('Madero 5 Morelia');
    expect(p!.lat, 19.70);
    expect(p.lng, -101.19);
    expect(p.address, 'Madero 5, Morelia');
    expect(asked.single.queryParameters['countrycodes'], 'mx');
    expect(asked.single.queryParameters['accept-language'], 'es');

    expect(await geo.reverse(19.7, -101.19), 'Juárez, Morelia');
  });

  test('WebGeocoder: sin resultados regresa null', () async {
    final geo = WebGeocoder(client: MockClient((_) async => http.Response('[]', 200)));
    expect(await geo.search('xyz'), isNull);
  });
}
