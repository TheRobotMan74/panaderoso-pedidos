import 'dart:math';

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

  /// Qué panes suman a la tarjeta. Vacío = solo el chocolatín.
  final List<String> loyaltyProductIds;

  /// Pan gratis en el primer pedido, si lleva al menos [welcomeMinPieces] piezas.
  /// Uno por cuenta y por domicilio.
  final bool welcomeEnabled;
  final int welcomeMinPieces;

  /// Qué pan se regala. Vacío = el chocolatín.
  final String giftProductId;

  const PromoRules({
    this.loyaltyEnabled = true,
    this.loyaltyGoal = 10,
    this.loyaltyProductIds = const [],
    this.welcomeEnabled = true,
    this.welcomeMinPieces = 2,
    this.giftProductId = '',
  });

  factory PromoRules.fromMap(Map<String, dynamic>? m) {
    int entero(Object? v, int def, int min, int max) => v is num ? v.round().clamp(min, max) : def;
    return PromoRules(
      loyaltyEnabled: m?['loyaltyEnabled'] as bool? ?? true,
      loyaltyGoal: entero(m?['loyaltyGoal'], 10, 2, 100),
      loyaltyProductIds: [
        for (final v in (m?['loyaltyProductIds'] as List?) ?? const [])
          if (v is String && v.isNotEmpty) v,
      ],
      welcomeEnabled: m?['welcomeEnabled'] as bool? ?? true,
      welcomeMinPieces: entero(m?['welcomeMinPieces'], 2, 1, 50),
      giftProductId: m?['giftProductId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'loyaltyEnabled': loyaltyEnabled,
        'loyaltyGoal': loyaltyGoal,
        'loyaltyProductIds': loyaltyProductIds,
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

bool _isChocolatin(String name) => _plain(name).contains('chocolat');

/// true si este pan comprado suma a la tarjeta de lealtad (los regalados nunca suman).
bool countsForLoyalty(PromoRules r, OrderItem i) =>
    !i.isGift &&
    i.qty > 0 &&
    (r.loyaltyProductIds.isEmpty ? _isChocolatin(i.name) : r.loyaltyProductIds.contains(i.productId));

/// Piezas de un pedido (o carrito) que suman a la tarjeta.
int loyaltyPiecesOf(PromoRules r, Iterable<OrderItem> items) =>
    items.where((i) => countsForLoyalty(r, i)).fold(0, (s, i) => s + i.qty);

/// Los panes que suman a la tarjeta, de [products] (el catálogo).
List<Product> loyaltyProducts(PromoRules r, List<Product> products) => r.loyaltyProductIds.isEmpty
    ? products.where((p) => _isChocolatin(p.name)).toList()
    : products.where((p) => r.loyaltyProductIds.contains(p.id)).toList();

/// Cómo se le dice al cliente qué suma: "chocolatines" o "piezas de Dona o Concha".
String loyaltyWhat(PromoRules r, List<Product> products) {
  final ps = loyaltyProducts(r, products);
  if (r.loyaltyProductIds.isEmpty || ps.isEmpty) return 'chocolatines';
  final names = ps.map((p) => p.name).toList();
  final joined =
      names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} o ${names.last}';
  return 'piezas de $joined';
}

/// Avance de la tarjeta de lealtad de un cliente, a partir de sus pedidos.
/// Solo cuentan los pedidos hechos desde que salió la promoción (los que traen
/// `lealtadPiezas`), que no están cancelados, y de ellos solo los panes que suman
/// (ver [countsForLoyalty]; normalmente el chocolatín).
///
/// Se recorre en orden: cada pedido suma sus piezas y cada pan de lealtad que se
/// le dio resta una tarjeta llena. Si se le dio un pan cuando contaba cualquier
/// pan, la tarjeta queda en 0 (no en negativo): lo que ya se regaló no se cobra.
/// La misma cuenta está en functions/index.js (hacerPedido).
class LoyaltyCard {
  /// Piezas que sumaron a la tarjeta, en total (sin contar las regaladas).
  final int pieces;

  /// Panes de lealtad que ya se le pusieron en algún pedido.
  final int given;

  /// Piezas que tiene ahorita en la tarjeta (ya restando los panes que se le dieron).
  final int balance;

  final int goal;

  const LoyaltyCard({this.pieces = 0, this.given = 0, this.balance = 0, this.goal = 10});

  factory LoyaltyCard.from(Iterable<BakeryOrder> orders, PromoRules rules) {
    final goal = rules.loyaltyGoal;
    final list = orders.where((o) => o.status != OrderStatus.cancelado && o.loyaltyPieces != null).toList()
      // Los que todavía no tienen fecha (recién hechos) van al final.
      ..sort((a, b) => (a.createdAt ?? DateTime(9999)).compareTo(b.createdAt ?? DateTime(9999)));
    var pieces = 0;
    var given = 0;
    var balance = 0;
    for (final o in list) {
      final p = loyaltyPiecesOf(rules, o.items);
      final g = o.giftCount(giftLoyalty);
      pieces += p;
      given += g;
      balance = max(0, balance + p - g * goal);
    }
    return LoyaltyCard(pieces: pieces, given: given, balance: balance, goal: goal);
  }

  /// Cuántas piezas lleva hacia el siguiente pan (0 a meta − 1).
  int get progress => balance % goal;

  /// Cuántas le faltan para el siguiente pan.
  int get missing => goal - progress;

  /// Panes ganados que todavía no se le han dado (normalmente 0; puede haber
  /// uno si el dueño bajó la meta o no alcanzó el cupo). Se ponen en su siguiente pedido.
  int get pending => min(10, balance ~/ goal);
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
  required List<OrderItem> items,
}) {
  final paidPieces = items.where((i) => !i.isGift).fold(0, (s, i) => s + i.qty);
  if (paidPieces <= 0) return const GiftPreview();
  var loyalty = 0;
  if (rules.loyaltyEnabled) {
    final card = LoyaltyCard.from(myOrders, rules);
    loyalty = min(10, (card.balance + loyaltyPiecesOf(rules, items)) ~/ rules.loyaltyGoal);
  }
  final welcome = rules.welcomeEnabled && paidPieces >= rules.welcomeMinPieces && isFirstOrder(myOrders);
  return GiftPreview(loyalty: loyalty, welcome: welcome);
}

/// true si el cliente todavía no tiene ningún pedido (sin contar cancelados).
bool isFirstOrder(List<BakeryOrder> myOrders) => myOrders.every((o) => o.status == OrderStatus.cancelado);

/// Tarjeta de un cliente vista desde el panel del dueño.
class CustomerLoyalty {
  final String customerId;
  final String name;
  final String phone;
  final LoyaltyCard card;

  /// Pedidos que no se cancelaron (de antes y después de la promoción).
  final int orders;

  /// Ya recibió el pan de bienvenida (en un pedido no cancelado).
  final bool welcomeUsed;

  /// Panes de lealtad que ya se le dieron.
  int get loyaltyGiven => card.given;

  const CustomerLoyalty({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.card,
    required this.orders,
    required this.welcomeUsed,
  });
}

/// Junta los pedidos por cliente. Los que van más cerca del siguiente pan, primero.
List<CustomerLoyalty> customersLoyalty(Iterable<BakeryOrder> allOrders, PromoRules rules) {
  final byCustomer = <String, List<BakeryOrder>>{};
  for (final o in allOrders) {
    if (o.customerId.isEmpty) continue;
    byCustomer.putIfAbsent(o.customerId, () => []).add(o);
  }
  final list = <CustomerLoyalty>[];
  for (final e in byCustomer.entries) {
    final os = e.value;
    // El nombre y teléfono del pedido más nuevo.
    os.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    final active = os.where((o) => o.status != OrderStatus.cancelado).toList();
    list.add(CustomerLoyalty(
      customerId: e.key,
      name: os.first.customerName,
      phone: os.first.phone,
      card: LoyaltyCard.from(os, rules),
      orders: active.length,
      welcomeUsed: active.any((o) => o.giftCount(giftWelcome) > 0),
    ));
  }
  final goal = rules.loyaltyGoal;
  int key(CustomerLoyalty c) => c.card.pending > 0 ? goal : c.card.progress;
  list.sort((a, b) {
    final k = key(b).compareTo(key(a));
    if (k != 0) return k;
    final p = b.card.pieces.compareTo(a.card.pieces);
    return p != 0 ? p : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}
