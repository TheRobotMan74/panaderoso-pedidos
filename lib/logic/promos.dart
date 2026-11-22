import '../models.dart';

/// Promociones: tarjeta de lealtad y pan de bienvenida.
///
/// Las mismas cuentas están en functions/index.js (función hacerPedido), que es
/// la que de verdad pone el pan gratis en el pedido. Aquí solo se calculan para
/// mostrarle al cliente su avance y lo que le va a tocar antes de pedir.

/// Marca de un pan regalado dentro del pedido (campo `regalo` del producto).
const giftLoyalty = 'lealtad';
const giftWelcome = 'bienvenida';

/// Reglas que pone el dueño en Ajustes (config/app.promos).
class PromoRules {
  /// Tarjeta de lealtad: cada [loyaltyGoal] piezas compradas, un pan gratis.
  final bool loyaltyEnabled;
  final int loyaltyGoal;

  /// Pan gratis en el primer pedido, si lleva al menos [welcomeMinPieces] piezas.
  /// Uno por cuenta y por domicilio.
  final bool welcomeEnabled;
  final int welcomeMinPieces;

  /// Qué pan se regala. Vacío = el chocolatín.
  final String giftProductId;

  const PromoRules({
    this.loyaltyEnabled = true,
    this.loyaltyGoal = 10,
    this.welcomeEnabled = true,
    this.welcomeMinPieces = 2,
    this.giftProductId = '',
  });

  factory PromoRules.fromMap(Map<String, dynamic>? m) {
    int entero(Object? v, int def, int min, int max) =>
        v is num ? v.round().clamp(min, max) : def;
    return PromoRules(
      loyaltyEnabled: m?['loyaltyEnabled'] as bool? ?? true,
      loyaltyGoal: entero(m?['loyaltyGoal'], 10, 2, 100),
      welcomeEnabled: m?['welcomeEnabled'] as bool? ?? true,
      welcomeMinPieces: entero(m?['welcomeMinPieces'], 2, 1, 50),
      giftProductId: m?['giftProductId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'loyaltyEnabled': loyaltyEnabled,
        'loyaltyGoal': loyaltyGoal,
        'welcomeEnabled': welcomeEnabled,
        'welcomeMinPieces': welcomeMinPieces,
        'giftProductId': giftProductId,
      };
}

String _plain(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u');

/// El pan que se regala: el que eligió el dueño o, si no eligió, el chocolatín.
/// Null si no existe o no está disponible (entonces no se regala nada).
Product? giftProduct(PromoRules r, List<Product> products) {
  Product? p;
  if (r.giftProductId.isNotEmpty) {
    p = products.where((x) => x.id == r.giftProductId).firstOrNull;
  } else {
    p = products.where((x) => _plain(x.name).contains('chocolat')).firstOrNull;
  }
  return p != null && p.available ? p : null;
}

/// Avance de la tarjeta de lealtad de un cliente, a partir de sus pedidos.
/// Solo cuentan los pedidos hechos desde que salió la promoción (los que traen
/// `lealtadPiezas`) y que no están cancelados.
class LoyaltyCard {
  /// Piezas compradas (sin contar las regaladas).
  final int pieces;

  /// Panes de lealtad que ya se le pusieron en algún pedido.
  final int given;

  const LoyaltyCard({this.pieces = 0, this.given = 0});

  factory LoyaltyCard.from(Iterable<BakeryOrder> orders) {
    var pieces = 0;
    var given = 0;
    for (final o in orders) {
      if (o.status == OrderStatus.cancelado || o.loyaltyPieces == null) continue;
      pieces += o.loyaltyPieces!;
      given += o.giftCount(giftLoyalty);
    }
    return LoyaltyCard(pieces: pieces, given: given);
  }

  /// Cuántas piezas lleva hacia el siguiente pan (0 a meta − 1).
  int progress(int goal) => pieces % goal;

  /// Cuántas le faltan para el siguiente pan.
  int missing(int goal) => goal - progress(goal);

  /// Panes ganados que todavía no se le han dado (normalmente 0; puede haber
  /// uno si el dueño bajó la meta). Se ponen en su siguiente pedido.
  int pending(int goal) => (pieces ~/ goal - given).clamp(0, 10);
}

/// Panes gratis que llevaría un pedido nuevo de [paidPieces] piezas.
class GiftPreview {
  final int loyalty;
  final bool welcome;
  const GiftPreview({this.loyalty = 0, this.welcome = false});
  int get total => loyalty + (welcome ? 1 : 0);
}

/// Lo que el servidor le va a regalar a un pedido nuevo (si alcanza el cupo del
/// día y nadie más usó ya el regalo de bienvenida en ese domicilio).
GiftPreview previewGifts({
  required PromoRules rules,
  required List<BakeryOrder> myOrders,
  required int paidPieces,
}) {
  if (paidPieces <= 0) return const GiftPreview();
  var loyalty = 0;
  if (rules.loyaltyEnabled) {
    final card = LoyaltyCard.from(myOrders);
    loyalty = ((card.pieces + paidPieces) ~/ rules.loyaltyGoal - card.given).clamp(0, 10);
  }
  final welcome = rules.welcomeEnabled &&
      paidPieces >= rules.welcomeMinPieces &&
      isFirstOrder(myOrders);
  return GiftPreview(loyalty: loyalty, welcome: welcome);
}

/// true si el cliente todavía no tiene ningún pedido (sin contar cancelados).
bool isFirstOrder(List<BakeryOrder> myOrders) =>
    myOrders.every((o) => o.status == OrderStatus.cancelado);
