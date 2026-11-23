import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../logic/day_route.dart';
import '../logic/eta.dart';
import '../logic/schedule.dart';
import '../models.dart';
import 'repo.dart';

/// Reparto en vivo del dueño: comparte su ubicación mientras reparte.
///
/// Usa un "servicio en primer plano" de Android: aparece una notificación fija
/// mientras se comparte, y así sigue funcionando con la pantalla apagada o en
/// otra app (Maps, WhatsApp) sin pedir el permiso de ubicación "todo el tiempo".
///
/// Para cuidar batería y la cuota gratis de Firebase, solo se escribe cuando el
/// carro avanza unos 30 m, y como mucho una vez cada 10 segundos.
class DeliveryTracker extends ChangeNotifier {
  DeliveryTracker._();
  static final instance = DeliveryTracker._();

  static const _minWriteGap = Duration(seconds: 10);

  StreamSubscription<Position>? _positions;
  StreamSubscription<List<BakeryOrder>>? _orders;
  StreamSubscription<AppConfig>? _config;
  StreamSubscription<List<DeliveryDay>>? _days;
  DateTime _lastWrite = DateTime(2000);
  List<String> _viewers = [];

  // Para decirle a cada cliente cuántas entregas van antes de la suya.
  List<BakeryOrder> _todayOrders = [];
  AppConfig _cfg = const AppConfig();
  DeliveryDay? _day;
  Map<String, int> _ahead = {};

  // Para el tiempo estimado de llegada de cada cliente.
  List<BakeryOrder> _route = [];
  (double, double)? _lastPos;
  Map<String, int> _eta = {};

  /// Se llama cuando el reparto termina solo (ya no quedan pedidos del día).
  void Function(String message)? onAutoStop;

  bool get running => _positions != null;

  /// Revisa GPS y permiso. Regresa un mensaje para el dueño si algo falta.
  static Future<String?> checkPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return 'Prende la ubicación (GPS) del celular y vuelve a intentar.';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return 'Da permiso de ubicación a Panaderoso en Ajustes y vuelve a intentar.';
    }
    if (p == LocationPermission.denied || p == LocationPermission.unableToDetermine) {
      return 'Sin permiso de ubicación no se puede compartir el reparto.';
    }
    return null;
  }

  /// Pedidos de hoy que faltan por entregar.
  static Future<List<BakeryOrder>> pendingToday() async {
    final today = dateKey(DateTime.now());
    final orders = await Repo.instance.ordersFrom(today).first;
    return _pendingOn(orders, today);
  }

  static List<BakeryOrder> _pendingOn(List<BakeryOrder> orders, String date) =>
      orders.where((o) => o.deliveryDate == date && o.isPending).toList();

  static List<String> _viewersOf(List<BakeryOrder> orders) =>
      orders.map((o) => o.customerId).toSet().toList()..sort();

  /// Empieza a compartir. Los pedidos confirmados de hoy pasan a "En camino"
  /// (eso ya le manda aviso a cada cliente).
  /// Con [resume] solo reanuda un reparto que quedó abierto, sin cambiar pedidos.
  Future<void> start({required int alertMeters, bool resume = false}) async {
    if (running) return;
    final today = dateKey(DateTime.now());
    final pending = await pendingToday();
    _viewers = _viewersOf(pending);

    // Desde que sale a repartir ya no se aceptan pedidos para hoy.
    await Repo.instance.closeDeliveryDay(today).catchError((_) {});

    if (!resume) {
      await Repo.instance.startTracking(date: today, viewers: _viewers, alertMeters: alertMeters);
      for (final o in pending.where((o) => o.status == OrderStatus.confirmado)) {
        await Repo.instance.updateOrder(o.id, {'status': OrderStatus.enCamino.name});
      }
    }

    _lastWrite = DateTime(2000);
    _positions = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Repartiendo pan',
          notificationText: 'Tus clientes ven en el mapa por dónde vas.',
          notificationChannelName: 'Reparto en vivo',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen(_onPosition, onError: (_) {});

    // Si se entregan o cancelan pedidos, se actualiza quién puede ver el mapa.
    _config = Repo.instance.config().listen((c) {
      _cfg = c;
      _updateAhead();
    }, onError: (_) {});
    _days = Repo.instance.deliveryDays(fromDate: today).listen((days) {
      _day = days.where((d) => d.date == today).firstOrNull;
      _updateAhead();
    }, onError: (_) {});
    _orders = Repo.instance.ordersFrom(today).listen((orders) {
      _todayOrders = orders.where((o) => o.deliveryDate == today && o.status != OrderStatus.cancelado).toList();
      _updateAhead();
      final viewers = _viewersOf(_pendingOn(orders, today));
      if (viewers.isEmpty) {
        stop().then((_) => onAutoStop?.call(
            'Entregaste todo lo de hoy. Dejamos de compartir tu ubicación.'));
        return;
      }
      if (!listEquals(viewers, _viewers)) {
        _viewers = viewers;
        Repo.instance.updateTrackingViewers(viewers).catchError((_) {});
      }
    });
    notifyListeners();

    // Primera ubicación de inmediato, sin esperar a que el carro avance.
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _onPosition(first);
    } catch (_) {}
  }

  /// Recalcula, con el orden de la ruta del dueño, cuántas entregas faltan
  /// antes de la de cada cliente, y lo manda solo si cambió.
  ///
  /// También recalcula los minutos estimados de llegada con la última ubicación
  /// (por ejemplo, al marcar un pedido entregado los de atrás se adelantan).
  void _updateAhead() {
    if (_todayOrders.isEmpty) return;
    _route = dayRoute(_todayOrders, _cfg, day: _day);
    final ahead = aheadByCustomer(_route);
    final eta = _computeEta();
    final aheadChanged = !mapEquals(ahead, _ahead);
    final etaChanged = eta != null && !mapEquals(eta, _eta);
    if (!aheadChanged && !etaChanged) return;
    _ahead = ahead;
    if (eta != null) _eta = eta;
    Repo.instance.updateTrackingAhead(ahead, eta: etaChanged ? eta : null).catchError((_) {});
  }

  Map<String, int>? _computeEta() {
    final pos = _lastPos;
    if (pos == null || _route.isEmpty) return null;
    return etaForRoute(_route, pos, _cfg);
  }

  void _onPosition(Position p) {
    final now = DateTime.now();
    if (now.difference(_lastWrite) < _minWriteGap) return;
    _lastWrite = now;
    _lastPos = (p.latitude, p.longitude);
    final eta = _computeEta();
    if (eta != null) _eta = eta;
    Repo.instance.updateTrackingPosition(p.latitude, p.longitude, eta: eta).catchError((_) {});
  }

  Future<void> stop() async {
    await _positions?.cancel();
    await _orders?.cancel();
    await _config?.cancel();
    await _days?.cancel();
    _positions = null;
    _orders = null;
    _config = null;
    _days = null;
    _ahead = {};
    _eta = {};
    _route = [];
    _lastPos = null;
    _todayOrders = [];
    notifyListeners();
    await Repo.instance.stopTracking();
  }
}
