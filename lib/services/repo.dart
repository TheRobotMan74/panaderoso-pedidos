import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models.dart';

/// Acceso a los datos en Firebase. Colecciones:
/// users, products, deliveryDays, dayStock, orders, config/app, tracking/current.
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

  Future<void> saveFcmToken(String uid, String token) =>
      _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

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
  Future<String> uploadPaymentProof(String uid, File file) async {
    final path = 'payment-proofs/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _storage.ref(path).putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  Future<String> paymentProofUrl(String path) => _storage.ref(path).getDownloadURL();

  /// Hace el pedido en el servidor: ahí se revisa y se aparta el cupo en un solo
  /// paso, así dos personas pidiendo al mismo tiempo no pueden pasarse del cupo.
  /// Si ya no alcanza, lanza [RejectedByServer] con el motivo para el cliente.
  Future<void> createOrder(BakeryOrder o) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('hacerPedido').call<void>(o.toNewOrderMap());
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

  /// Pedidos para entregar desde [fromDate] (para el panel del dueño).
  Stream<List<BakeryOrder>> ordersFrom(String fromDate) => _db
      .collection('orders')
      .where('deliveryDate', isGreaterThanOrEqualTo: fromDate)
      .orderBy('deliveryDate')
      .snapshots()
      .map(_toOrders);

  Future<void> updateOrder(String id, Map<String, dynamic> changes) =>
      _db.collection('orders').doc(id).update(changes);

  List<BakeryOrder> _toOrders(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map((d) => BakeryOrder.fromMap(d.id, d.data())).toList();

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

  Future<void> updateTrackingPosition(double lat, double lng) => _tracking.update({
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateTrackingViewers(List<String> viewers) =>
      _tracking.update({'viewers': viewers});

  /// Termina el reparto y borra la ubicación.
  Future<void> stopTracking() => _tracking.set({
        'active': false,
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
