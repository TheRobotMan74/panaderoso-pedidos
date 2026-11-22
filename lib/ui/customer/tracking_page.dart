import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/geo.dart';
import '../../models.dart';
import '../../services/repo.dart';

/// El cliente ve en el mapa por dónde va su pedido.
class TrackingPage extends StatefulWidget {
  final BakeryOrder order;

  /// Casa del cliente, por si el pedido es de antes de que hubiera mapa.
  final double? homeLat;
  final double? homeLng;

  const TrackingPage({super.key, required this.order, this.homeLat, this.homeLng});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  StreamSubscription<TrackingInfo>? _sub;
  Timer? _retry;
  Timer? _tick;
  TrackingInfo? _info;
  GoogleMapController? _map;
  bool _fitted = false;

  LatLng? get _home {
    final o = widget.order;
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
    // Para que "hace X min" se actualice aunque no llegue ubicación nueva.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  /// Si el repartidor todavía no sale, no hay permiso de ver su ubicación:
  /// se vuelve a intentar cada 20 segundos.
  void _listen() {
    _sub?.cancel();
    _sub = Repo.instance.tracking().listen(
      (info) {
        setState(() => _info = info);
        _fitIfNeeded();
      },
      onError: (_) {
        setState(() => _info = const TrackingInfo());
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 20), _listen);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retry?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  bool get _driverVisible => _info != null && _info!.active && _info!.hasPosition;

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
    _map!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = _home;
    final info = _info;
    final markers = <Marker>{
      if (home != null)
        Marker(
          markerId: const MarkerId('casa'),
          position: home,
          infoWindow: const InfoWindow(title: 'Tu casa'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      if (_driverVisible)
        Marker(
          markerId: const MarkerId('repartidor'),
          position: LatLng(info!.lat!, info.lng!),
          infoWindow: const InfoWindow(title: 'Tu pan va aquí'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
    };

    final delivered = widget.order.status == OrderStatus.entregado;
    String title;
    String subtitle = '';
    if (info == null) {
      title = 'Buscando al repartidor…';
    } else if (delivered) {
      title = '¡Tu pedido ya fue entregado!';
    } else if (!_driverVisible) {
      title = 'El repartidor todavía no sale';
      subtitle = 'Cuando salga, aquí verás por dónde va. Te avisamos cuando esté cerca.';
    } else {
      title = home == null
          ? 'Tu pan va en camino'
          : 'Tu pan está a ${distanceLabel(distanceMeters(info.lat!, info.lng!, home.latitude, home.longitude))}';
      final ago = agoLabel(info.updatedAt, DateTime.now());
      subtitle = 'Distancia en línea recta · ubicación $ago';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('¿Dónde va mi pedido?')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: home ?? const LatLng(23.6, -102.5),
              zoom: home == null ? 4.5 : 15,
            ),
            markers: markers,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (c) {
              _map = c;
              _fitIfNeeded();
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 8,
              color: theme.colorScheme.surface,
              child: SafeArea(
                top: false,
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  leading: const Icon(Icons.delivery_dining, size: 36),
                  title: Text(title, style: theme.textTheme.titleMedium),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  trailing: _driverVisible
                      ? IconButton(
                          tooltip: 'Centrar',
                          icon: const Icon(Icons.center_focus_strong),
                          onPressed: () => _fitIfNeeded(force: true),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
