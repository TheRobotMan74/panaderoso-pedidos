import 'logic/promos.dart';
import 'logic/shipping.dart';

/// Rol del usuario dentro de la app.
enum Role { cliente, dueno }

Role roleFromString(String? s) => s == 'dueno' ? Role.dueno : Role.cliente;

class AppUser {
  final String uid;
  final String name;
  final String phone;
  final String address;
  final String addressNotes;
  final Role role;

  /// Ubicación de la casa, marcada en el mapa. Null en cuentas viejas.
  final double? lat;
  final double? lng;

  /// Último pedido al que dijo "Ahora no" en la invitación a calificar
  /// (para no volver a preguntarle por ese mismo pedido).
  final String? reviewSkipped;

  const AppUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.address,
    this.addressNotes = '',
    this.role = Role.cliente,
    this.lat,
    this.lng,
    this.reviewSkipped,
    this.savedAddresses = const [],
  });

  /// Direcciones guardadas (de 1 a [maxAddresses]). La primera es la principal
  /// y siempre es la misma que address/lat/lng.
  final List<SavedAddress> savedAddresses;

  bool get hasLocation => lat != null && lng != null;

  /// Sus direcciones, la principal primero. Las cuentas de antes (que solo tienen
  /// una dirección) dan una lista con esa sola.
  List<SavedAddress> get addresses {
    final main = SavedAddress(
      id: savedAddresses.isEmpty ? 'principal' : savedAddresses.first.id,
      label: savedAddresses.isEmpty ? 'Casa' : savedAddresses.first.label,
      address: address,
      notes: addressNotes,
      lat: lat,
      lng: lng,
    );
    if (address.isEmpty && !hasLocation) return const [];
    return [main, ...savedAddresses.skip(1)].take(maxAddresses).toList();
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
        uid: uid,
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        address: m['address'] as String? ?? '',
        addressNotes: m['addressNotes'] as String? ?? '',
        role: roleFromString(m['role'] as String?),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        reviewSkipped: m['reviewSkipped'] as String?,
        savedAddresses: [
          for (final a in (m['addresses'] as List? ?? const []))
            if (a is Map) SavedAddress.fromMap(Map<String, dynamic>.from(a)),
        ],
      );

  /// El rol no se escribe desde la app: solo se cambia en la consola de Firebase.
  Map<String, dynamic> toProfileMap() => {
        'name': name,
        'phone': phone,
        'address': address,
        'addressNotes': addressNotes,
        'lat': lat,
        'lng': lng,
      };
}

/// Hasta cuántas direcciones puede guardar un cliente.
const maxAddresses = 3;

/// Una dirección guardada del cliente ("Casa", "Trabajo"...).
class SavedAddress {
  /// Para reconocerla aunque cambie de lugar en la lista.
  final String id;
  final String label;
  final String address;
  final String notes;
  final double? lat;
  final double? lng;

  const SavedAddress({
    required this.id,
    required this.label,
    required this.address,
    this.notes = '',
    this.lat,
    this.lng,
  });

  bool get hasLocation => lat != null && lng != null;

  /// La misma dirección (mismo punto y mismo texto), para saber cuál usa un pedido.
  bool sameAs({required String address, double? lat, double? lng}) {
    bool near(double? a, double? b) => (a == null && b == null) || (a != null && b != null && (a - b).abs() < 1e-6);
    return this.address.trim() == address.trim() && near(this.lat, lat) && near(this.lng, lng);
  }

  factory SavedAddress.fromMap(Map<String, dynamic> m) => SavedAddress(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        address: m['address'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'address': address,
        'notes': notes,
        'lat': lat,
        'lng': lng,
      };
}

class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final String? imageUrl;
  final bool available;
  final int sortOrder;

  /// Grupo de masa con el que comparte cupo (por ejemplo "Masa de croissant").
  /// Vacío = tiene su propio cupo.
  final String stockGroup;

  const Product({
    required this.id,
    required this.name,
    this.description = '',
    required this.price,
    this.imageUrl,
    this.available = true,
    this.sortOrder = 0,
    this.stockGroup = '',
  });

  Product copyWith({bool? available, String? stockGroup}) => Product(
        id: id,
        name: name,
        description: description,
        price: price,
        imageUrl: imageUrl,
        available: available ?? this.available,
        sortOrder: sortOrder,
        stockGroup: stockGroup ?? this.stockGroup,
      );

  factory Product.fromMap(String id, Map<String, dynamic> m) => Product(
        id: id,
        name: m['name'] as String? ?? '',
        description: m['description'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        imageUrl: m['imageUrl'] as String?,
        available: m['available'] as bool? ?? true,
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
        stockGroup: m['stockGroup'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'available': available,
        'sortOrder': sortOrder,
        'stockGroup': stockGroup,
      };
}

/// Un día de entrega que publica el dueño, con sus horarios.
class DeliveryDay {
  /// Fecha en formato AAAA-MM-DD; también es el id del documento.
  final String date;
  final bool open;

  /// Horarios de inicio, por ejemplo ["08:00", "09:00", "10:00"].
  final List<String> slots;

  /// Duración de cada horario en minutos.
  final int slotMinutes;

  /// true cuando el dueño ya empezó a repartir ese día: ya no se aceptan pedidos.
  /// No hay hora límite: se puede pedir hasta ese momento.
  final bool closed;

  /// Cupo de panes del día por grupo de masa (ver logic/stock.dart).
  /// Un grupo que no aparece no tiene límite.
  final Map<String, int> stock;

  /// Orden de entrega que el dueño acomodó a mano (ids de pedidos).
  /// Vacío = la app arma la ruta sola. No va en [toMap] para que guardar
  /// el día desde el calendario no lo borre.
  final List<String> routeOrder;

  /// Día especial: todos los pedidos se entregan en este lugar (por ejemplo FIME)
  /// y no a domicilio. Null = día normal a domicilio.
  final PickupPoint? pickup;

  /// El dueño ya avisó (o la app detectó) que llegó al punto de entrega.
  final bool arrived;

  const DeliveryDay({
    required this.date,
    required this.open,
    required this.slots,
    this.slotMinutes = 60,
    this.closed = false,
    this.stock = const {},
    this.routeOrder = const [],
    this.pickup,
    this.arrived = false,
  });

  bool get isPickup => pickup != null;

  factory DeliveryDay.fromMap(String id, Map<String, dynamic> m) => DeliveryDay(
        date: id,
        open: m['open'] as bool? ?? false,
        slots: List<String>.from(m['slots'] as List? ?? const []),
        slotMinutes: (m['slotMinutes'] as num?)?.toInt() ?? 60,
        closed: m['closed'] as bool? ?? false,
        stock: _intMap(m['stock']),
        routeOrder: List<String>.from(m['routeOrder'] as List? ?? const []),
        pickup: PickupPoint.fromMap(m['punto']),
        arrived: m['llegue'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'open': open,
        'slots': slots,
        'slotMinutes': slotMinutes,
        'closed': closed,
        'stock': stock,
        'punto': pickup?.toMap(),
      };
}

/// Lugar fijo de entrega de un día especial (FIME, una oficina…).
/// Se guarda en deliveryDays/{fecha}.punto y los frecuentes en config/puntos.
class PickupPoint {
  final String name;
  final double lat;
  final double lng;

  /// Indicaciones para encontrarte ahí ("Entrada principal, junto a la cafetería").
  final String notes;

  const PickupPoint({required this.name, required this.lat, required this.lng, this.notes = ''});

  static PickupPoint? fromMap(Object? v) {
    if (v is! Map) return null;
    final name = (v['name'] as String? ?? '').trim();
    final lat = v['lat'];
    final lng = v['lng'];
    if (name.isEmpty || lat is! num || lng is! num) return null;
    return PickupPoint(
      name: name,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      notes: v['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'lat': lat, 'lng': lng, 'notes': notes};

  /// Lo que se guarda como dirección del pedido.
  String get label => 'Entrega en $name';

  bool sameAs(PickupPoint o) => o.name.toLowerCase() == name.toLowerCase();
}

/// Panes ya apartados en un día, por grupo de masa (documento dayStock/{fecha}).
/// Solo lo escribe el servidor: sube con cada pedido y baja al cancelar o borrar.
class DayStock {
  final String date;
  final Map<String, int> used;

  const DayStock({required this.date, this.used = const {}});

  factory DayStock.fromMap(String id, Map<String, dynamic>? m) =>
      DayStock(date: id, used: _intMap(m?['used']));
}

Map<String, int> _intMap(Object? v) => v is Map
    ? {for (final e in v.entries) if (e.value is num) '${e.key}': (e.value as num).toInt()}
    : const {};

enum PaymentMethod { transferencia, efectivo }

enum OrderStatus { recibido, confirmado, enCamino, entregado, cancelado }

const orderStatusLabels = {
  OrderStatus.recibido: 'Recibido',
  OrderStatus.confirmado: 'Confirmado',
  OrderStatus.enCamino: 'En camino',
  OrderStatus.entregado: 'Entregado',
  OrderStatus.cancelado: 'Cancelado',
};

OrderStatus statusFromString(String? s) => OrderStatus.values
    .firstWhere((e) => e.name == s, orElse: () => OrderStatus.recibido);

class OrderItem {
  final String productId;
  final String name;
  final double price;
  final int qty;

  /// Pan regalado: 'lealtad' (tarjeta) o 'bienvenida' (primer pedido). Null = comprado.
  /// Solo lo pone el servidor (functions/index.js → hacerPedido).
  final String? gift;

  const OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
    this.gift,
  });

  bool get isGift => gift != null;

  double get total => price * qty;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        productId: m['productId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        qty: (m['qty'] as num?)?.toInt() ?? 0,
        gift: m['regalo'] as String?,
      );

  Map<String, dynamic> toMap() =>
      {'productId': productId, 'name': name, 'price': price, 'qty': qty};
}

class BakeryOrder {
  final String id;
  final String customerId;
  final String customerName;
  final String phone;
  final String address;
  final String addressNotes;
  final List<OrderItem> items;
  final String deliveryDate;
  final String slot;
  final PaymentMethod paymentMethod;
  final String? paymentProofPath;
  final bool paymentVerified;
  final bool cashCollected;
  final OrderStatus status;
  final int shippingFee;
  final String notes;
  final DateTime? createdAt;

  /// Ubicación de entrega (copiada del perfil al pedir).
  final double? lat;
  final double? lng;

  /// Ya se le avisó al cliente que el repartidor está cerca.
  final bool nearNotified;

  /// Si el dueño movió el día de entrega: de qué día y horario venía.
  final String? movedFromDate;
  final String? movedFromSlot;

  /// Piezas compradas que cuentan para la tarjeta de lealtad. Solo lo traen los
  /// pedidos hechos desde que salió la promoción (null en los de antes).
  final int? loyaltyPieces;
  /// Duración del horario en minutos (la pone el servidor al pedir o mover; antes siempre era 60).
  final int slotMinutes;
  final int movedFromMinutes;

  /// Nombre del lugar si el pedido es de un día especial (entrega en un punto,
  /// no a domicilio). Lo pone el servidor. Null = a domicilio.
  final String? pickupName;

  /// Ya se le avisó al cliente que el repartidor llegó al punto.
  final bool arrivalNotified;

  const BakeryOrder({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.address,
    this.addressNotes = '',
    required this.items,
    required this.deliveryDate,
    required this.slot,
    required this.paymentMethod,
    this.paymentProofPath,
    this.paymentVerified = false,
    this.cashCollected = false,
    this.status = OrderStatus.recibido,
    this.shippingFee = 0,
    this.notes = '',
    this.createdAt,
    this.lat,
    this.lng,
    this.nearNotified = false,
    this.movedFromDate,
    this.movedFromSlot,
    this.loyaltyPieces,
    this.slotMinutes = 60,
    this.movedFromMinutes = 60,
    this.pickupName,
    this.arrivalNotified = false,
  });

  bool get isPickup => pickupName != null && pickupName!.isNotEmpty;

  bool get wasMoved => movedFromDate != null;

  bool get hasLocation => lat != null && lng != null;

  /// Pendiente de entregar (ni entregado ni cancelado).
  bool get isPending => status != OrderStatus.entregado && status != OrderStatus.cancelado;

  /// Todas las piezas que hay que hornear y llevar (con las regaladas).
  int get pieces => items.fold(0, (s, i) => s + i.qty);

  /// Piezas que el cliente compró (sin las regaladas).
  int get paidPieces => items.where((i) => !i.isGift).fold(0, (s, i) => s + i.qty);

  /// Piezas regaladas de un tipo ([giftLoyalty] o [giftWelcome]), o de todos si es null.
  int giftCount([String? kind]) => items
      .where((i) => i.isGift && (kind == null || i.gift == kind))
      .fold(0, (s, i) => s + i.qty);
  double get subtotal => items.fold(0.0, (s, i) => s + i.total);
  double get total => subtotal + shippingFee;

  factory BakeryOrder.fromMap(String id, Map<String, dynamic> m) => BakeryOrder(
        id: id,
        customerId: m['customerId'] as String? ?? '',
        customerName: m['customerName'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        address: m['address'] as String? ?? '',
        addressNotes: m['addressNotes'] as String? ?? '',
        items: (m['items'] as List? ?? const [])
            .map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        deliveryDate: m['deliveryDate'] as String? ?? '',
        slot: m['slot'] as String? ?? '',
        paymentMethod: m['paymentMethod'] == 'efectivo'
            ? PaymentMethod.efectivo
            : PaymentMethod.transferencia,
        paymentProofPath: m['paymentProofPath'] as String?,
        paymentVerified: m['paymentVerified'] as bool? ?? false,
        cashCollected: m['cashCollected'] as bool? ?? false,
        status: statusFromString(m['status'] as String?),
        shippingFee: (m['shippingFee'] as num?)?.toInt() ?? 0,
        notes: m['notes'] as String? ?? '',
        createdAt: _toDate(m['createdAt']),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        nearNotified: m['nearNotified'] as bool? ?? false,
        movedFromDate: (m['movedFrom'] as Map?)?['date'] as String?,
        movedFromSlot: (m['movedFrom'] as Map?)?['slot'] as String?,
        loyaltyPieces: (m['lealtadPiezas'] as num?)?.toInt(),
        slotMinutes: (m['slotMinutes'] as num?)?.toInt() ?? 60,
        movedFromMinutes: ((m['movedFrom'] as Map?)?['slotMinutes'] as num?)?.toInt() ?? 60,
        pickupName: m['puntoEntrega'] as String?,
        arrivalNotified: m['llegadaAvisada'] as bool? ?? false,
      );

  /// Datos que escribe el cliente al crear el pedido.
  Map<String, dynamic> toNewOrderMap() => {
        'customerId': customerId,
        'customerName': customerName,
        'phone': phone,
        'address': address,
        'addressNotes': addressNotes,
        'items': items.map((i) => i.toMap()).toList(),
        'pieces': pieces,
        'subtotal': subtotal,
        'shippingFee': shippingFee,
        'total': total,
        'deliveryDate': deliveryDate,
        'slot': slot,
        'paymentMethod': paymentMethod.name,
        'paymentProofPath': paymentProofPath,
        'paymentVerified': false,
        'cashCollected': false,
        'status': OrderStatus.recibido.name,
        'notes': notes,
        'lat': lat,
        'lng': lng,
        'nearNotified': false,
      };
}

/// Configuración general que edita el dueño.
class AppConfig {
  final String bankName;
  final String clabe;
  final String accountHolder;

  /// WhatsApp de la panadería (10 dígitos). Vacío = no se muestra el botón.
  final String whatsapp;
  final ShippingRules shipping;

  /// A cuántos metros del domicilio se le avisa al cliente que ya va a llegar.
  final int nearAlertMeters;

  /// Punto de salida del reparto (tu casa o la panadería), para ordenar la ruta.
  final double? baseLat;
  final double? baseLng;

  /// true = al terminar regresas al punto de salida (la ruta lo toma en cuenta).
  final bool routeReturn;

  /// Tarjeta de lealtad y pan de bienvenida.
  final PromoRules promos;

  /// Para el tiempo estimado de llegada que ve el cliente:
  /// velocidad promedio en la ciudad (km/h) y minutos que tardas en cada entrega.
  final double etaSpeedKmh;
  final double etaStopMinutes;

  const AppConfig({
    this.bankName = '',
    this.clabe = '',
    this.accountHolder = '',
    this.whatsapp = '',
    this.shipping = const ShippingRules(),
    this.nearAlertMeters = 1000,
    this.baseLat,
    this.baseLng,
    this.routeReturn = true,
    this.promos = const PromoRules(),
    this.etaSpeedKmh = 25,
    this.etaStopMinutes = 4,
  });

  factory AppConfig.fromMap(Map<String, dynamic>? m) => AppConfig(
        bankName: m?['bankName'] as String? ?? '',
        clabe: m?['clabe'] as String? ?? '',
        accountHolder: m?['accountHolder'] as String? ?? '',
        whatsapp: m?['whatsapp'] as String? ?? '',
        shipping: ShippingRules.fromMap(
            m?['shipping'] == null ? null : Map<String, dynamic>.from(m!['shipping'] as Map)),
        nearAlertMeters: (m?['nearAlertMeters'] as num?)?.toInt() ?? 1000,
        baseLat: (m?['baseLat'] as num?)?.toDouble(),
        baseLng: (m?['baseLng'] as num?)?.toDouble(),
        routeReturn: m?['routeReturn'] as bool? ?? true,
        promos: PromoRules.fromMap(
            m?['promos'] == null ? null : Map<String, dynamic>.from(m!['promos'] as Map)),
        etaSpeedKmh: (m?['etaSpeedKmh'] as num?)?.toDouble() ?? 25,
        etaStopMinutes: (m?['etaStopMinutes'] as num?)?.toDouble() ?? 4,
      );

  Map<String, dynamic> toMap() => {
        'bankName': bankName,
        'clabe': clabe,
        'accountHolder': accountHolder,
        'whatsapp': whatsapp,
        'shipping': shipping.toMap(),
        'nearAlertMeters': nearAlertMeters,
        'baseLat': baseLat,
        'baseLng': baseLng,
        'routeReturn': routeReturn,
        'promos': promos.toMap(),
        'etaSpeedKmh': etaSpeedKmh,
        'etaStopMinutes': etaStopMinutes,
      };
}

/// Ubicación en vivo del repartidor (documento tracking/current).
class TrackingInfo {
  final bool active;
  final double? lat;
  final double? lng;
  final DateTime? updatedAt;

  /// Día del reparto (AAAA-MM-DD).
  final String date;

  /// Clientes con pedido pendiente ese día: solo ellos pueden ver el mapa.
  final List<String> viewers;

  /// Cuántas entregas faltan antes de la de cada cliente (por uid), según el
  /// orden de la ruta del dueño. 0 = es el siguiente.
  final Map<String, int> ahead;

  /// Minutos estimados para llegar con cada cliente (por uid), calculados en el
  /// celular del dueño a la hora [etaAt].
  final Map<String, int> eta;
  final DateTime? etaAt;

  const TrackingInfo({
    this.active = false,
    this.lat,
    this.lng,
    this.updatedAt,
    this.date = '',
    this.viewers = const [],
    this.ahead = const {},
    this.eta = const {},
    this.etaAt,
  });

  bool get hasPosition => lat != null && lng != null;

  factory TrackingInfo.fromMap(Map<String, dynamic>? m) => TrackingInfo(
        active: m?['active'] as bool? ?? false,
        lat: (m?['lat'] as num?)?.toDouble(),
        lng: (m?['lng'] as num?)?.toDouble(),
        updatedAt: _toDate(m?['updatedAt']),
        date: m?['date'] as String? ?? '',
        viewers: List<String>.from(m?['viewers'] as List? ?? const []),
        ahead: _intMap(m?['ahead']),
        eta: _intMap(m?['eta']),
        etaAt: _toDate(m?['etaAt']),
      );
}

/// Reseña de un pedido entregado. Una por pedido: el id del documento es el del pedido.
class Review {
  final String orderId;
  final String customerId;
  final String customerName;

  /// De 1 a 5 estrellas.
  final int rating;
  final String comment;

  /// Foto del pan en Storage (`review-photos/<uid>/...`). Null = sin foto.
  final String? photoPath;

  /// Lo que pidió, para que el dueño sepa de qué habla ("2 × Chocolatín").
  final List<String> items;
  final String deliveryDate;
  final DateTime? createdAt;

  /// Ya la vio el dueño (para el numerito del panel).
  final bool seen;

  /// El dueño la escogió para que la vean los demás clientes.
  final bool featured;

  const Review({
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.rating,
    this.comment = '',
    this.photoPath,
    this.items = const [],
    this.deliveryDate = '',
    this.createdAt,
    this.seen = false,
    this.featured = false,
  });

  factory Review.fromMap(String id, Map<String, dynamic> m) => Review(
        orderId: id,
        customerId: m['customerId'] as String? ?? '',
        customerName: m['customerName'] as String? ?? '',
        rating: ((m['rating'] as num?)?.toInt() ?? 5).clamp(1, 5),
        comment: m['comment'] as String? ?? '',
        photoPath: m['photoPath'] as String?,
        items: List<String>.from(m['items'] as List? ?? const []),
        deliveryDate: m['deliveryDate'] as String? ?? '',
        createdAt: _toDate(m['createdAt']),
        seen: m['seen'] as bool? ?? false,
        featured: m['featured'] as bool? ?? false,
      );

  /// Lo que escribe el cliente. [createdAt] lo pone el servidor.
  Map<String, dynamic> toCustomerMap() => {
        'customerId': customerId,
        'customerName': customerName,
        'rating': rating,
        'comment': comment,
        'photoPath': photoPath,
        'items': items,
        'deliveryDate': deliveryDate,
        'seen': false,
        'featured': false,
      };
}

/// Idea de pan nuevo que manda un cliente.
class Suggestion {
  final String id;
  final String customerId;
  final String customerName;
  final String text;
  final DateTime? createdAt;
  final bool seen;

  /// El dueño le dio "Me gusta la idea": el cliente lo ve en su app.
  final bool liked;

  const Suggestion({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.text,
    this.createdAt,
    this.seen = false,
    this.liked = false,
  });

  factory Suggestion.fromMap(String id, Map<String, dynamic> m) => Suggestion(
        id: id,
        customerId: m['customerId'] as String? ?? '',
        customerName: m['customerName'] as String? ?? '',
        text: m['text'] as String? ?? '',
        createdAt: _toDate(m['createdAt']),
        seen: m['seen'] as bool? ?? false,
        liked: m['liked'] as bool? ?? false,
      );
}

/// Firestore entrega Timestamp; aquí se acepta cualquier cosa con toDate().
DateTime? _toDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}
