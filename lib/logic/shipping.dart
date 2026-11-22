import 'geo.dart';

/// Cálculo del costo de envío.
///
/// envío = km de ida × precio por km × porcentaje que paga el cliente,
/// redondeado hacia arriba a múltiplos de [roundTo].
/// El porcentaje depende de cuántas piezas lleva el pedido.
class ShippingTier {
  /// Desde cuántas piezas aplica este porcentaje.
  final int minPieces;

  /// Fracción del costo que paga el cliente (1.0 = completo, 0 = gratis).
  final double customerShare;

  const ShippingTier(this.minPieces, this.customerShare);

  Map<String, dynamic> toMap() =>
      {'minPieces': minPieces, 'customerShare': customerShare};

  factory ShippingTier.fromMap(Map<String, dynamic> m) => ShippingTier(
        (m['minPieces'] as num).toInt(),
        (m['customerShare'] as num).toDouble(),
      );
}

class ShippingRules {
  /// Si es false, el envío es gratis para todos.
  final bool enabled;

  /// Pesos por kilómetro (gasolina: $25 por litro ÷ 9 km por litro ≈ 2.80).
  final double pricePerKm;

  /// Rangos por piezas, de menor a mayor.
  final List<ShippingTier> tiers;

  /// Redondeo hacia arriba, en pesos.
  final int roundTo;

  /// Las calles no van en línea recta: los km en línea recta se multiplican por esto
  /// para acercarse a lo que de verdad se maneja (1.3 = 30% más).
  final double roadFactor;

  const ShippingRules({
    this.enabled = false,
    this.pricePerKm = 2.8,
    this.tiers = defaultTiers,
    this.roundTo = 5,
    this.roadFactor = 1.3,
  });

  static const defaultTiers = [
    // 1 pieza paga el envío completo; de 2 a 5 solo una parte chica (25%);
    // desde media docena es gratis (ganancia ≈ $25 por pieza → $150 cubren cualquier viaje).
    ShippingTier(1, 1.0),
    ShippingTier(2, 0.25),
    ShippingTier(6, 0.0),
  ];

  /// Fracción que paga el cliente para un pedido con [pieces] piezas.
  double shareFor(int pieces) {
    var share = 1.0;
    final sorted = [...tiers]..sort((a, b) => a.minPieces.compareTo(b.minPieces));
    for (final t in sorted) {
      if (pieces >= t.minPieces) share = t.customerShare;
    }
    return share;
  }

  /// Costo de envío en pesos enteros.
  int feeFor({required double km, required int pieces}) {
    if (!enabled || km <= 0 || pieces <= 0) return 0;
    final raw = km * pricePerKm * shareFor(pieces);
    if (raw <= 0) return 0;
    final step = roundTo <= 0 ? 1 : roundTo;
    // Restar un poquito evita que 10.0000001 se vuelva 15.
    return ((raw - 1e-9) / step).ceil() * step;
  }

  /// Km de ida (aproximados por calle) del punto de salida a la casa del cliente.
  double kmBetween(double fromLat, double fromLng, double toLat, double toLng) =>
      distanceMeters(fromLat, fromLng, toLat, toLng) / 1000 * roadFactor;

  /// Envío de un pedido de [pieces] piezas desde el punto de salida a la casa.
  /// 0 si está apagado o falta el punto de salida o la casa en el mapa.
  /// El servidor (función hacerPedido) hace exactamente la misma cuenta.
  int feeForTrip({
    required double? baseLat,
    required double? baseLng,
    required double? homeLat,
    required double? homeLng,
    required int pieces,
  }) {
    if (baseLat == null || baseLng == null || homeLat == null || homeLng == null) return 0;
    return feeFor(km: kmBetween(baseLat, baseLng, homeLat, homeLng), pieces: pieces);
  }

  /// Piezas desde las que el envío es gratis, o null si nunca lo es.
  int? freeFromPieces() {
    final free = tiers.where((t) => t.customerShare == 0).toList()
      ..sort((a, b) => a.minPieces.compareTo(b.minPieces));
    return free.isEmpty ? null : free.first.minPieces;
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'pricePerKm': pricePerKm,
        'tiers': tiers.map((t) => t.toMap()).toList(),
        'roundTo': roundTo,
        'roadFactor': roadFactor,
      };

  factory ShippingRules.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ShippingRules();
    final tiers = (m['tiers'] as List?)
        ?.map((e) => ShippingTier.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    return ShippingRules(
      enabled: m['enabled'] as bool? ?? false,
      pricePerKm: (m['pricePerKm'] as num?)?.toDouble() ?? 2.8,
      tiers: (tiers == null || tiers.isEmpty) ? defaultTiers : tiers,
      roundTo: (m['roundTo'] as num?)?.toInt() ?? 5,
      roadFactor: (m['roadFactor'] as num?)?.toDouble() ?? 1.3,
    );
  }
}
