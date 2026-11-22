import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models.dart';

/// Acceso a los datos en Firebase. Colecciones:
/// users, products, deliveryDays, orders, config/app, tracking/current.
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

  Future<void> saveDeliveryDay(DeliveryDay d) =>
      _db.collection('deliveryDays').doc(d.date).set(d.toMap());

  Future<void> deleteDeliveryDay(String date) =>
      _db.collection('deliveryDays').doc(date).delete();

  // ---------- Configuración ----------

  Stream<AppConfig> config() => _db
      .collection('config')
      .doc('app')
      .snapshots()
      .map((s) => AppConfig.fromMap(s.data()));

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

  Future<void> createOrder(BakeryOrder o) => _db.collection('orders').add({
        ...o.toNewOrderMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

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
