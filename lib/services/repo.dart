import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models.dart';

/// Acceso a los datos en Firebase. Colecciones:
/// users, products, deliveryDays, dayStock, orders, config/app, tracking/current,
/// reviews (una por pedido) y suggestions (ideas de pan nuevo).
class Repo {
  Repo._();
  static final instance = Repo._();

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  // ---------- Usuarios ----------

  Stream<AppUser?> userStream(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromMap(uid, s.data()!) : null);

  Future<void> saveProfile(AppUser u) => _db
      .collection('users')
      .doc(u.uid)
      .set(u.toProfileMap(), SetOptions(merge: true));

  /// Solo nombre y teléfono (las direcciones se guardan aparte).
  Future<void> saveNameAndPhone(String uid, String name, String phone) =>
      _db.collection('users').doc(uid).set({'name': name, 'phone': phone}, SetOptions(merge: true));

  /// Guarda sus direcciones (de 1 a 3). La primera es la principal: también se copia a
  /// address/lat/lng, que es lo que leen las versiones viejas de la app y el servidor.
  Future<void> saveAddresses(String uid, List<SavedAddress> list) {
    if (list.isEmpty) throw ArgumentError('Debe quedar por lo menos una dirección');
    final main = list.first;
    return _db.collection('users').doc(uid).set({
      'addresses': list.take(maxAddresses).map((a) => a.toMap()).toList(),
      'address': main.address,
      'addressNotes': main.notes,
      'lat': main.lat,
      'lng': main.lng,
    }, SetOptions(merge: true));
  }

  /// Cambia a dónde se entrega un pedido que todavía no sale. El servidor revisa
  /// que se pueda y vuelve a calcular el envío. Regresa el envío nuevo.
  Future<int> changeOrderAddress(String orderId, SavedAddress a) async {
    try {
      final r = await FirebaseFunctions.instance.httpsCallable('cambiarDireccion').call<Object?>({
        'orderId': orderId,
        'address': a.address,
        'addressNotes': a.notes,
        'lat': a.lat,
        'lng': a.lng,
      });
      return ((r.data as Map?)?['shippingFee'] as num?)?.toInt() ?? 0;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        // La función todavía no está publicada en el servidor.
        throw RejectedByServer('Esta opción todavía no está lista. Escríbenos por WhatsApp para cambiarla.');
      }
      throw RejectedByServer(e.message ?? 'No se pudo cambiar la dirección.');
    }
  }

  Future<void> saveFcmToken(String uid, String token) =>
      _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

  /// Quita el aviso de este celular de la cuenta (al cerrar sesión), para que no
  /// le sigan llegando a este celular los avisos de la cuenta anterior.
  Future<void> removeFcmToken(String uid, String token) =>
      _db.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });

  /// Si el cliente tiene prendidas las notificaciones en su celular
  /// (el dueño ve en Pedidos a quién no le van a llegar los avisos).
  Future<void> savePushStatus(String uid, bool enabled) =>
      _db.collection('users').doc(uid).set({
        'pushOk': enabled,
        'pushCheckedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Clientes que tienen apagadas las notificaciones. Solo el dueño.
  Stream<Set<String>> customersWithoutPush() => _db
      .collection('users')
      .where('pushOk', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());

  /// Todas las cuentas de clientes (para la sección Clientes). Solo el dueño.
  Stream<List<AppUser>> customers() => _db.collection('users').snapshots().map((s) => [
        for (final d in s.docs)
          if (d.data()['role'] != 'dueno') AppUser.fromMap(d.id, d.data()),
      ]);

  /// Manda el correo para cambiar la contraseña. Primero intenta el correo bonito
  /// de Panaderoso (sale del Gmail de la panadería, función "mandarRecuperacion").
  /// Si el servidor no puede, manda el correo normal de Firebase, que también llega en español.
  /// Lanza [FirebaseAuthException] si el correo no es válido o no hay internet.
  Future<void> sendPasswordReset(String email) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('mandarRecuperacion', options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call<void>({'email': email});
      return;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'invalid-argument') throw FirebaseAuthException(code: 'invalid-email');
    } catch (_) {
      // Cualquier otra falla se resuelve abajo con el correo de Firebase.
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  // ---------- Productos ----------

  Stream<List<Product>> products({bool onlyAvailable = false}) =>
      _db.collection('products').orderBy('sortOrder').snapshots().map((s) {
        final list = s.docs.map((d) => Product.fromMap(d.id, d.data())).toList();
        return onlyAvailable ? list.where((p) => p.available).toList() : list;
      });

  /// Cambia solo el grupo de masa de un producto ('' = cupo propio).
  Future<void> setProductGroup(String productId, String group) =>
      _db.collection('products').doc(productId).update({'stockGroup': group.trim()});

  Future<void> saveProduct(Product p) {
    final col = _db.collection('products');
    return p.id.isEmpty ? col.add(p.toMap()) : col.doc(p.id).set(p.toMap());
  }

  Future<String> uploadProductImage(File file) async {
    final ref = _storage.ref('products/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  // ---------- Días de entrega ----------

  Stream<List<DeliveryDay>> deliveryDays({required String fromDate}) => _db
      .collection('deliveryDays')
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: fromDate)
      .snapshots()
      .map((s) => s.docs.map((d) => DeliveryDay.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.date.compareTo(b.date)));

  /// Guarda el día. Si ya existía, se respeta si ya estaba en reparto.
  Future<void> saveDeliveryDay(DeliveryDay d) {
    final m = d.toMap()..remove('closed');
    return _db.collection('deliveryDays').doc(d.date).set(m, SetOptions(merge: true));
  }

  Future<void> setDayOpen(String date, bool open) =>
      _db.collection('deliveryDays').doc(date).update({'open': open});

  /// Cupo del día por grupo de masa. Un grupo sin número no tiene límite.
  Future<void> setDayStock(String date, Map<String, int> stock) =>
      _db.collection('deliveryDays').doc(date).update({'stock': stock});

  /// Panes ya apartados por día (lo lleva el servidor), en vivo.
  Stream<Map<String, DayStock>> dayStocks({required String fromDate}) => _db
      .collection('dayStock')
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: fromDate)
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id: DayStock.fromMap(d.id, d.data())});

  /// Al empezar a repartir: ya no se aceptan pedidos para ese día.
  Future<void> closeDeliveryDay(String date) =>
      _db.collection('deliveryDays').doc(date).update({'closed': true});

  /// Mueve un día a otra fecha y/o le cambia el horario. Sus pedidos y su cupo
  /// se pasan solos y a cada cliente le llega un aviso. Regresa cuántos se avisaron.
  Future<int> moveDeliveryDay({
    required String from,
    required String to,
    required List<String> slots,
    int slotMinutes = 60,
  }) async {
    try {
      final r = await FirebaseFunctions.instance.httpsCallable('moverDia').call<Map<Object?, Object?>>({
        'from': from,
        'to': to,
        'slots': slots,
        'slotMinutes': slotMinutes,
      });
      return (r.data['moved'] as num?)?.toInt() ?? 0;
    } on FirebaseFunctionsException catch (e) {
      throw RejectedByServer(e.message ?? 'No se pudo mover el día.');
    }
  }

  /// Manda un mensaje escrito por el dueño como notificación: a todos los clientes
  /// con pedido pendiente en [date], o solo a [customerIds]. Lo valida el servidor
  /// (solo el dueño). Regresa (a cuántos les llegó, cuántos no tienen avisos).
  Future<(int, int)> sendOwnerMessage(String text, {String? date, List<String>? customerIds}) async {
    try {
      final r = await FirebaseFunctions.instance.httpsCallable('mandarMensaje').call<Map<Object?, Object?>>({
        'mensaje': text,
        'dia': ?date,
        'clientes': ?customerIds,
      });
      return (
        (r.data['enviados'] as num?)?.toInt() ?? 0,
        (r.data['sinAvisos'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      throw RejectedByServer(e.message ?? 'No se pudo mandar el mensaje.');
    }
  }

  /// Guarda el orden de entrega acomodado a mano. Una lista vacía lo borra
  /// y la app vuelve a armar la ruta sola.
  Future<void> saveRouteOrder(String date, List<String> orderIds) =>
      _db.collection('deliveryDays').doc(date).set(
        {'routeOrder': orderIds.isEmpty ? FieldValue.delete() : orderIds},
        SetOptions(merge: true),
      );

  Future<void> deleteDeliveryDay(String date) =>
      _db.collection('deliveryDays').doc(date).delete();

  // ---------- Configuración ----------

  Stream<AppConfig> config() => _db
      .collection('config')
      .doc('app')
      .snapshots()
      .map((s) => AppConfig.fromMap(s.data()));

  /// Guarda el punto de salida del reparto sin tocar lo demás.
  Future<void> saveBaseLocation(double lat, double lng) => _db
      .collection('config')
      .doc('app')
      .set({'baseLat': lat, 'baseLng': lng}, SetOptions(merge: true));

  Future<void> saveConfig(AppConfig c) =>
      _db.collection('config').doc('app').set(c.toMap());

  // ---------- Pedidos ----------

  /// Sube la captura de la transferencia y regresa su ruta en Storage.
  /// Sube la captura de la transferencia (ya leída) y regresa dónde quedó.
  Future<String> uploadPaymentProof(String uid, Uint8List bytes) async {
    final path = 'payment-proofs/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _storage.ref(path).putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  Future<String> paymentProofUrl(String path) => _storage.ref(path).getDownloadURL();

  /// Hace el pedido en el servidor: ahí se revisa y se aparta el cupo en un solo
  /// paso, así dos personas pidiendo al mismo tiempo no pueden pasarse del cupo.
  /// Si ya no alcanza, lanza [RejectedByServer] con el motivo para el cliente.
  /// Regresa cuántos panes gratis le puso el servidor al pedido.
  Future<int> createOrder(BakeryOrder o) async {
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('hacerPedido')
          .call<Object?>(o.toNewOrderMap());
      final regalos = (r.data as Map?)?['regalos'];
      if (regalos is! Map) return 0;
      return regalos.values.whereType<num>().fold<int>(0, (s, n) => s + n.toInt());
    } on FirebaseFunctionsException catch (e) {
      if (const ['resource-exhausted', 'failed-precondition', 'invalid-argument'].contains(e.code)) {
        throw RejectedByServer(e.message ?? 'Ya no hay cupo para ese día.');
      }
      rethrow;
    }
  }

  /// Borra el pedido para siempre: desaparece también en el celular del cliente
  /// y su lugar en el cupo del día se libera.
  Future<void> deleteOrder(String id) => _db.collection('orders').doc(id).delete();

  /// Borra varios pedidos de un jalón (por ejemplo, los de prueba).
  Future<void> deleteOrders(List<String> ids) async {
    for (var i = 0; i < ids.length; i += 200) {
      final batch = _db.batch();
      for (final id in ids.skip(i).take(200)) {
        batch.delete(_db.collection('orders').doc(id));
      }
      await batch.commit();
    }
  }

  Stream<List<BakeryOrder>> myOrders(String uid) => _db
      .collection('orders')
      .where('customerId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(_toOrders);

  /// Un pedido, en vivo (para el mapa de "¿Dónde va mi pedido?").
  Stream<BakeryOrder?> order(String id) => _db
      .collection('orders')
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? BakeryOrder.fromMap(d.id, d.data()!) : null);

  /// Todos los pedidos del cliente, para su tarjeta de lealtad.
  Stream<List<BakeryOrder>> myOrdersAll(String uid) => _db
      .collection('orders')
      .where('customerId', isEqualTo: uid)
      .snapshots()
      .map(_toOrders);

  /// Todos los pedidos (para ver la tarjeta de lealtad de cada cliente). Solo el dueño.
  Stream<List<BakeryOrder>> allOrders() =>
      _db.collection('orders').snapshots().map(_toOrders);

  /// Pedidos para entregar desde [fromDate] (para el panel del dueño).
  Stream<List<BakeryOrder>> ordersFrom(String fromDate) => _db
      .collection('orders')
      .where('deliveryDate', isGreaterThanOrEqualTo: fromDate)
      .orderBy('deliveryDate')
      .snapshots()
      .map(_toOrders);

  /// Pedidos para entregar entre [fromDate] y antes de [toDate] (para el Historial).
  Stream<List<BakeryOrder>> ordersBetween(String fromDate, String toDate) => _db
      .collection('orders')
      .where('deliveryDate', isGreaterThanOrEqualTo: fromDate)
      .where('deliveryDate', isLessThan: toDate)
      .orderBy('deliveryDate')
      .snapshots()
      .map(_toOrders);

  Future<void> updateOrder(String id, Map<String, dynamic> changes) =>
      _db.collection('orders').doc(id).update(changes);

  List<BakeryOrder> _toOrders(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map((d) => BakeryOrder.fromMap(d.id, d.data())).toList();

  // ---------- Reseñas ----------

  CollectionReference<Map<String, dynamic>> get _reviews => _db.collection('reviews');

  List<Review> _toReviews(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map((d) => Review.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(2100)).compareTo(a.createdAt ?? DateTime(2100)));

  /// Las reseñas que ha hecho el cliente.
  Stream<List<Review>> myReviews(String uid) =>
      _reviews.where('customerId', isEqualTo: uid).snapshots().map(_toReviews);

  /// Todas las reseñas, la más nueva primero. Solo el dueño.
  Stream<List<Review>> allReviews() => _reviews.snapshots().map(_toReviews);

  /// Las que el dueño escogió para que las vean todos los clientes.
  Stream<List<Review>> featuredReviews() =>
      _reviews.where('featured', isEqualTo: true).snapshots().map(_toReviews);

  /// Guarda la reseña del cliente. Si ya había una de ese pedido, se cambia
  /// (y le vuelve a salir como nueva al dueño).
  Future<void> saveReview(Review r, {required bool isNew}) {
    final doc = _reviews.doc(r.orderId);
    if (isNew) {
      return doc.set({...r.toCustomerMap(), 'createdAt': FieldValue.serverTimestamp()});
    }
    return doc.update({
      'rating': r.rating,
      'comment': r.comment,
      'photoPath': r.photoPath,
      'seen': false,
      'featured': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadReviewPhoto(String uid, Uint8List bytes) async {
    final path = 'review-photos/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _storage.ref(path).putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  final _photoUrls = <String, Future<String>>{};

  /// Enlace de la foto (se recuerda, para no pedirlo cada vez que se dibuja).
  Future<String> reviewPhotoUrl(String path) => _photoUrls.putIfAbsent(path, () {
        final f = _storage.ref(path).getDownloadURL();
        f.catchError((Object _) {
          _photoUrls.remove(path);
          return '';
        });
        return f;
      });

  /// El cliente no quiere calificar este pedido: ya no se le pregunta en el inicio.
  Future<void> skipReview(String uid, String orderId) =>
      _db.collection('users').doc(uid).set({'reviewSkipped': orderId}, SetOptions(merge: true));

  /// Solo el dueño: mostrarla o no a los clientes.
  Future<void> setReviewFeatured(String orderId, bool featured) =>
      _reviews.doc(orderId).update({'featured': featured});

  Future<void> deleteReview(String orderId) => _reviews.doc(orderId).delete();

  // ---------- Ideas de pan ----------

  CollectionReference<Map<String, dynamic>> get _suggestions => _db.collection('suggestions');

  List<Suggestion> _toSuggestions(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map((d) => Suggestion.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(2100)).compareTo(a.createdAt ?? DateTime(2100)));

  Future<void> sendSuggestion({required String uid, required String name, required String text}) =>
      _suggestions.add({
        'customerId': uid,
        'customerName': name,
        'text': text,
        'seen': false,
        'liked': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Stream<List<Suggestion>> mySuggestions(String uid) =>
      _suggestions.where('customerId', isEqualTo: uid).snapshots().map(_toSuggestions);

  /// Todas las ideas, la más nueva primero. Solo el dueño.
  Stream<List<Suggestion>> allSuggestions() => _suggestions.snapshots().map(_toSuggestions);

  /// Solo el dueño: "Me gusta la idea" (el cliente lo ve en su app).
  Future<void> setSuggestionLiked(String id, bool liked) =>
      _suggestions.doc(id).update({'liked': liked});

  Future<void> deleteSuggestion(String id) => _suggestions.doc(id).delete();

  /// El dueño ya vio estas reseñas e ideas: se quita el numerito del panel.
  Future<void> markFeedbackSeen({List<String> reviews = const [], List<String> suggestions = const []}) async {
    final refs = [
      for (final id in reviews) _reviews.doc(id),
      for (final id in suggestions) _suggestions.doc(id),
    ];
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final ref in refs.skip(i).take(400)) {
        batch.update(ref, {'seen': true});
      }
      await batch.commit();
    }
  }

  // ---------- Reparto en vivo ----------

  DocumentReference<Map<String, dynamic>> get _tracking =>
      _db.collection('tracking').doc('current');

  /// Ubicación del repartidor. El cliente solo la puede leer si tiene pedido ese día;
  /// si no, el stream da error de permisos.
  Stream<TrackingInfo> tracking() =>
      _tracking.snapshots().map((s) => TrackingInfo.fromMap(s.data()));

  Future<void> startTracking({
    required String date,
    required List<String> viewers,
    required int alertMeters,
  }) =>
      _tracking.set({
        'active': true,
        'date': date,
        'viewers': viewers,
        'alertMeters': alertMeters,
        'lat': null,
        'lng': null,
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// [eta]: minutos estimados para llegar con cada cliente (por uid).
  Future<void> updateTrackingPosition(double lat, double lng, {Map<String, int>? eta}) =>
      _tracking.update({
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
        'eta': ?eta,
        if (eta != null) 'etaAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateTrackingViewers(List<String> viewers) =>
      _tracking.update({'viewers': viewers});

  /// Cuántas entregas faltan antes de la de cada cliente (lo ve en su mapa).
  Future<void> updateTrackingAhead(Map<String, int> ahead, {Map<String, int>? eta}) =>
      _tracking.update({
        'ahead': ahead,
        'eta': ?eta,
        if (eta != null) 'etaAt': FieldValue.serverTimestamp(),
      });

  /// Termina el reparto y borra la ubicación.
  Future<void> stopTracking() => _tracking.set({
        'active': false,
        'eta': <String, int>{},
        'viewers': <String>[],
        'lat': null,
        'lng': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  String get currentUid => FirebaseAuth.instance.currentUser!.uid;
}

/// El servidor no aceptó la acción (por ejemplo, ya no hay cupo). [message] es para la persona.
class RejectedByServer implements Exception {
  final String message;
  const RejectedByServer(this.message);

  @override
  String toString() => message;
}
