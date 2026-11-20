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

  const ShippingRules({
    this.enabled = false,
    this.pricePerKm = 2.8,
    this.tiers = defaultTiers,
    this.roundTo = 5,
  });

  static const defaultTiers = [
    ShippingTier(1, 1.0),
    ShippingTier(3, 0.5),
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
    );
  }
}
