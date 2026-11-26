import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../logic/eta.dart';
import '../../logic/schedule.dart';
import '../../logic/geo.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../../web/map_fallback.dart';
import '../push_reminder.dart';
import '../status_chip.dart';
import '../theme.dart';
import '../widgets.dart';
import 'my_orders_page.dart' show whatsAppUrl;

/// El cliente ve en el mapa por dónde va su pedido.
///
/// Todo es en vivo, sin salir y volver a entrar: la ubicación del repartidor,
/// cuántas entregas faltan, el tiempo estimado y el estado del pedido.
class TrackingPage extends StatefulWidget {
  final BakeryOrder order;

  /// Casa del cliente, por si el pedido es de antes de que hubiera mapa.
  final double? homeLat;
  final double? homeLng;

  const TrackingPage({super.key, required this.order, this.homeLat, this.homeLng});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

/// Sin ubicación nueva por más de esto, se le dice al cliente que puede estar
/// entregando o sin señal (en vez de que parezca que se trabó).
const _staleAfter = Duration(minutes: 4);

class _TrackingPageState extends State<TrackingPage> with SingleTickerProviderStateMixin {
  StreamSubscription<TrackingInfo>? _sub;
  StreamSubscription<BakeryOrder?>? _orderSub;
  StreamSubscription<AppConfig>? _cfgSub;
  Timer? _retry;
  Timer? _tick;
  TrackingInfo? _info;
  late BakeryOrder _order = widget.order;
  String _whatsapp = '';
  GoogleMapController? _map;
  bool _fitted = false;

  // La bolita del repartidor se desliza de su lugar anterior al nuevo.
  late final _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  LatLng? _from;
  LatLng? _to;
  DateTime _lastFrame = DateTime(2000);

  LatLng? get _home {
    final o = _order;
    if (o.hasLocation) return LatLng(o.lat!, o.lng!);
    if (widget.homeLat != null && widget.homeLng != null) {
      return LatLng(widget.homeLat!, widget.homeLng!);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _listen();
    // El estado del pedido (confirmado, en camino, entregado) también llega solo.
    _orderSub = Repo.instance.order(widget.order.id).listen((o) {
      if (o != null && mounted) setState(() => _order = o);
    }, onError: (_) {});
    _cfgSub = Repo.instance.config().listen((c) {
      if (mounted) setState(() => _whatsapp = c.whatsapp);
    }, onError: (_) {});
    // Para que "hace X min" y el tiempo estimado bajen aunque no llegue ubicación nueva.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    _move.addListener(() {
      // Unas 15 veces por segundo es suficiente para que se vea suave en el mapa.
      final now = DateTime.now();
      if (_move.isCompleted || now.difference(_lastFrame).inMilliseconds >= 66) {
        _lastFrame = now;
        if (mounted) setState(() {});
      }
    });
  }

  /// Si el repartidor todavía no sale, no hay permiso de ver su ubicación:
  /// se vuelve a intentar cada 20 segundos (hasta que se entregue el pedido).
  void _listen() {
    _sub?.cancel();
    _sub = Repo.instance.tracking().listen(
      (info) {
        if (!mounted) return;
        if (info.hasPosition) {
          final next = LatLng(info.lat!, info.lng!);
          if (_to == null) {
            _from = next;
            _to = next;
          } else if (next != _to) {
            _from = _driverAt ?? _to;
            _to = next;
            _move.forward(from: 0);
          }
        }
        setState(() => _info = info);
        _fitIfNeeded();
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _info = const TrackingInfo());
        _retry?.cancel();
        if (_order.isPending) _retry = Timer(const Duration(seconds: 20), _listen);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _orderSub?.cancel();
    _cfgSub?.cancel();
    _retry?.cancel();
    _tick?.cancel();
    _move.dispose();
    super.dispose();
  }

  bool get _driverVisible => _info != null && _info!.active && _info!.hasPosition && _order.isPending;

  /// Dónde se dibuja la bolita ahora mismo (a medio camino mientras se desliza).
  LatLng? get _driverAt {
    final a = _from, b = _to;
    if (a == null || b == null) return null;
    final t = Curves.easeInOut.transform(_move.value);
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  void _fitIfNeeded({bool force = false}) {
    if ((_fitted && !force) || _map == null || !_driverVisible) return;
    final d = LatLng(_info!.lat!, _info!.lng!);
    final h = _home;
    _fitted = true;
    if (h == null) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(d, 15));
      return;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(
        d.latitude < h.latitude ? d.latitude : h.latitude,
        d.longitude < h.longitude ? d.longitude : h.longitude,
      ),
      northeast: LatLng(
        d.latitude > h.latitude ? d.latitude : h.latitude,
        d.longitude > h.longitude ? d.longitude : h.longitude,
      ),
    );
    // Abajo va la tarjeta: se deja más espacio para que no tape las bolitas.
    _map!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
  }

  Future<void> _openWhatsApp() async {
    final o = _order;
    final text = 'Hola Panaderoso 🐻, soy ${o.customerName}. Te escribo por mi pedido de hoy '
        '(${slotLabel(o.slot, minutes: o.slotMinutes)}).';
    final ok = await launchUrl(
      whatsAppUrl(_whatsapp, text),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp. ¿Lo tienes instalado?')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = _home;
    final info = _info;
    final driver = _driverVisible ? (_driverAt ?? LatLng(info!.lat!, info.lng!)) : null;
    final markers = <Marker>{
      if (home != null)
        Marker(
          markerId: const MarkerId('casa'),
          position: home,
          infoWindow: InfoWindow(title: _order.isPickup ? _order.pickupName : 'Tu casa'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('repartidor'),
          position: driver,
          infoWindow: const InfoWindow(title: 'Tu pan va aquí'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          zIndexInt: 2,
        ),
    };

    final view = trackingView(
      order: _order,
      info: info,
      home: home == null ? null : (home.latitude, home.longitude),
      now: DateTime.now(),
    );
    final delivered = _order.status == OrderStatus.entregado;
    // Tablet o plegable abierto: la tarjeta va a un lado y el mapa ocupa lo demás.
    final wide = MediaQuery.sizeOf(context).width >= Ancho.dosColumnas;
    const panel = 400.0;

    return Scaffold(
      appBar: AppBar(title: const Text('¿Dónde va mi pedido?')),
      body: Stack(
        children: [
          if (!mapsUsable)
            MapFallback(
                message: wide
                    ? 'En la tarjeta te decimos qué tan cerca va tu pan.'
                    : 'Aquí abajo te decimos qué tan cerca va tu pan.')
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: home ?? const LatLng(23.6, -102.5),
                zoom: home == null ? 4.5 : 15,
              ),
              markers: markers,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              padding: wide ? const EdgeInsets.only(left: panel + 24) : const EdgeInsets.only(bottom: 170),
              onMapCreated: (c) {
                _map = c;
                _fitIfNeeded();
              },
            ),
          Positioned(
            left: 12,
            right: wide ? null : 12,
            width: wide ? panel : null,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!delivered) ...[const PushReminder(compact: true), const SizedBox(height: 8)],
                PanCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _Badge(delivered: delivered),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    if (view.live) ...[
                                      PulseDot(size: 8, color: view.stale ? Pan.canela : Pan.salvia),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: AnimatedCount(
                                        view.title,
                                        style: theme.textTheme.titleMedium,
                                        alignment: Alignment.centerLeft,
                                      ),
                                    ),
                                  ],
                                ),
                                for (final line in view.lines) ...[
                                  const SizedBox(height: 2),
                                  Text(line, style: theme.textTheme.bodySmall),
                                ],
                              ],
                            ),
                          ),
                          if (_driverVisible)
                            IconButton(
                              tooltip: 'Centrar',
                              icon: const Icon(Icons.center_focus_strong_rounded, color: Pan.caramelo),
                              onPressed: () => _fitIfNeeded(force: true),
                            ),
                        ],
                      ),
                      if (_order.status != OrderStatus.cancelado) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: OrderProgress(status: _order.status),
                        ),
                      ],
                      if (_whatsapp.isNotEmpty && _order.isPending)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _openWhatsApp,
                            icon: const Icon(Icons.chat_rounded, size: 20),
                            label: const Text('Escríbenos por WhatsApp'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final bool delivered;
  const _Badge({required this.delivered});

  @override
  Widget build(BuildContext context) => Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          gradient: delivered ? null : Pan.gradienteMiel,
          color: delivered ? Pan.salviaClara : null,
          shape: BoxShape.circle,
        ),
        child: Icon(
          delivered ? Icons.check_rounded : Icons.delivery_dining_rounded,
          size: 30,
          color: delivered ? Pan.salvia : Pan.cacao,
        ),
      );
}

/// Lo que dice la tarjeta de abajo del mapa.
class TrackingView {
  final String title;
  final List<String> lines;

  /// El repartidor va en camino y se ve en el mapa (bolita que late).
  final bool live;

  /// Hace rato que no llega su ubicación.
  final bool stale;

  const TrackingView(this.title, this.lines, {this.live = false, this.stale = false});
}

final _clock = DateFormat('h:mm a', 'es_MX');

/// Arma el texto de la tarjeta. Aparte de la pantalla para poder probarlo.
TrackingView trackingView({
  required BakeryOrder order,
  required TrackingInfo? info,
  required (double, double)? home,
  required DateTime now,
}) {
  if (order.status == OrderStatus.entregado) {
    return const TrackingView('¡Tu pedido ya fue entregado!', [
      'Gracias por tu compra. ¡Que lo disfrutes! 🥐',
    ]);
  }
  if (order.status == OrderStatus.cancelado) {
    return const TrackingView('Este pedido se canceló', []);
  }
  // Día especial: todos se entregan en el mismo lugar.
  if (order.isPickup && order.arrivalNotified) {
    return TrackingView(
        '¡Ya estamos en ${order.pickupName}!',
        [
          'Pasa por tu pedido. Tu horario: ${slotLabel(order.slot, minutes: order.slotMinutes)}.',
        ],
        live: true);
  }

  if (info == null) return const TrackingView('Buscando al repartidor…', []);
  if (!(info.active && info.hasPosition)) {
    return TrackingView('El repartidor todavía no sale', [
      'Tu horario: ${slotLabel(order.slot, minutes: order.slotMinutes)}.',
      'Cuando salga, aquí verás por dónde va. Te avisamos cuando esté cerca.',
    ]);
  }

  final lines = <String>[];
  final meters = home == null ? null : distanceMeters(info.lat!, info.lng!, home.$1, home.$2);
  final etaMin = info.eta[order.customerId];
  final ahead = info.ahead[order.customerId];

  String title;
  if (etaMin != null) {
    final left = etaRemaining(etaMin, info.etaAt, now);
    final at = now.add(Duration(minutes: left));
    title = left <= 3 || (meters != null && meters < 300) ? '¡Ya casi llega!' : 'Llega en ${etaLabel(left)}';
    lines.add(
      'Hora aproximada: ${_clock.format(at)}${meters == null ? '' : ' · a ${distanceLabel(meters)}'}',
    );
  } else {
    title = meters == null ? 'Tu pan va en camino' : 'Tu pan está a ${distanceLabel(meters)}';
  }
  if (order.isPickup) lines.insert(0, 'Va rumbo a ${order.pickupName}.');

  if (ahead != null && !order.isPickup) {
    lines.add(
      ahead == 0
          ? '¡Tu entrega es la siguiente!'
          : ahead == 1
              ? 'Falta 1 entrega antes de la tuya'
              : 'Faltan $ahead entregas antes de la tuya',
    );
  }

  final updated = info.updatedAt;
  final stale = updated != null && now.difference(updated) > _staleAfter;
  if (stale) {
    lines.add('Ubicación de ${agoLabel(updated, now)}: puede estar entregando un pedido o sin señal.');
  } else {
    lines.add('En vivo · ubicación ${agoLabel(updated, now)}');
  }
  return TrackingView(title, lines, live: true, stale: stale);
}
