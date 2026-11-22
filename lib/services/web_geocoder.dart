import 'dart:convert';

import 'package:http/http.dart' as http;

/// Un lugar encontrado: punto y dirección escrita.
class FoundPlace {
  final double lat;
  final double lng;
  final String address;
  const FoundPlace(this.lat, this.lng, this.address);
}

/// Buscador de direcciones para la versión web (en Android se usa el de Android).
///
/// Usa Nominatim de OpenStreetMap: gratis y sin llave. Sus reglas piden no más de
/// una consulta por segundo y nada de "buscar mientras escribes", así que solo se
/// busca al tocar el botón y las consultas se espacian solas.
class WebGeocoder {
  WebGeocoder({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _host = 'nominatim.openstreetmap.org';
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<dynamic> _get(String path, Map<String, String> query) async {
    final wait = _last.add(const Duration(milliseconds: 1100)).difference(DateTime.now());
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final res = await _client
        .get(Uri.https(_host, path, {...query, 'format': 'jsonv2', 'accept-language': 'es'}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Nominatim ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// Busca una dirección escrita, solo en México. Null si no la encontró.
  Future<FoundPlace?> search(String text) async {
    final list =
        await _get('/search', {'q': text, 'countrycodes': 'mx', 'addressdetails': '1', 'limit': '1'}) as List<dynamic>;
    if (list.isEmpty) return null;
    final m = list.first as Map<String, dynamic>;
    return FoundPlace(
      double.parse(m['lat'] as String),
      double.parse(m['lon'] as String),
      addressFromNominatim(m['address'] as Map<String, dynamic>?),
    );
  }

  /// La dirección escrita de un punto del mapa ('' si no hay).
  Future<String> reverse(double lat, double lng) async {
    final m = await _get('/reverse', {
      'lat': '$lat',
      'lon': '$lng',
      'zoom': '18',
      'addressdetails': '1',
    }) as Map<String, dynamic>;
    return addressFromNominatim(m['address'] as Map<String, dynamic>?);
  }
}

/// "Av. Juárez 120, Centro, Morelia" a partir de lo que regresa Nominatim.
String addressFromNominatim(Map<String, dynamic>? a) {
  if (a == null) return '';
  String pick(List<String> keys) {
    for (final k in keys) {
      final v = (a[k] as String? ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  final street = [
    pick(['road', 'pedestrian', 'footway']),
    pick(['house_number']),
  ].where((s) => s.isNotEmpty).join(' ');
  final parts = [
    street,
    pick(['neighbourhood', 'suburb', 'quarter', 'residential']),
    pick(['city', 'town', 'village', 'municipality']),
  ].where((s) => s.isNotEmpty).toList();
  final seen = <String>{};
  return parts.where(seen.add).join(', ');
}
