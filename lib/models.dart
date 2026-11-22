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

  const AppUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.address,
    this.addressNotes = '',
    this.role = Role.cliente,
    this.lat,
    this.lng,
  });

  bool get hasLocation => lat != null && lng != null;

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
        uid: uid,
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        address: m['address'] as String? ?? '',
        addressNotes: m['addressNotes'] as String? ?? '',
        role: roleFromString(m['role'] as String?),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
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

  const DeliveryDay({
    required this.date,
    required this.open,
    required this.slots,
    this.slotMinutes = 60,
    this.closed = false,
    this.stock = const {},
    this.routeOrder = const [],
  });

  factory DeliveryDay.fromMap(String id, Map<String, dynamic> m) => DeliveryDay(
        date: id,
        open: m['open'] as bool? ?? false,
        slots: List<String>.from(m['slots'] as List? ?? const []),
        slotMinutes: (m['slotMinutes'] as num?)?.toInt() ?? 60,
        closed: m['closed'] as bool? ?? false,
        stock: _intMap(m['stock']),
        routeOrder: List<String>.from(m['routeOrder'] as List? ?? const []),
      );

  Map<String, dynamic> toMap() => {
        'open': open,
        'slots': slots,
        'slotMinutes': slotMinutes,
        'closed': closed,
        'stock': stock,
      };
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

  const OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
  });

  double get total => price * qty;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        productId: m['productId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        qty: (m['qty'] as num?)?.toInt() ?? 0,
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

  /// Duración del horario en minutos (la pone el servidor al pedir o mover; antes siempre era 60).
  final int slotMinutes;
  final int movedFromMinutes;

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
    this.slotMinutes = 60,
    this.movedFromMinutes = 60,
  });

  bool get wasMoved => movedFromDate != null;

  bool get hasLocation => lat != null && lng != null;

  /// Pendiente de entregar (ni entregado ni cancelado).
  bool get isPending => status != OrderStatus.entregado && status != OrderStatus.cancelado;

  int get pieces => items.fold(0, (s, i) => s + i.qty);
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
        slotMinutes: (m['slotMinutes'] as num?)?.toInt() ?? 60,
        movedFromMinutes: ((m['movedFrom'] as Map?)?['slotMinutes'] as num?)?.toInt() ?? 60,
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

  const TrackingInfo({
    this.active = false,
    this.lat,
    this.lng,
    this.updatedAt,
    this.date = '',
    this.viewers = const [],
    this.ahead = const {},
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
