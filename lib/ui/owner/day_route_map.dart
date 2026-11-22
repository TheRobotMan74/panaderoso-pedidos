import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../logic/geo.dart';
import '../../logic/route.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Colores por horario (8:00, 9:00, 10:00…), iguales en el mapa y en la leyenda.
const slotColors = [Pan.caramelo, Pan.cielo, Pan.salvia, Pan.ciruela, Pan.terracota, Pan.tostado];

Color colorForSlot(List<String> slots, String slot) =>
    slotColors[slots.indexOf(slot).clamp(0, 99) % slotColors.length];

/// Mapa del día al final de la lista de pedidos: un puntito numerado por casa,
/// del color de su horario, unidos en el orden de la ruta.
class DayRouteMap extends StatefulWidget {
  final String date;

  /// Pedidos del día ya en orden de ruta (el número de parada es su posición + 1).
  final List<BakeryOrder> stops;
  final Point? base;

  const DayRouteMap({super.key, required this.date, required this.stops, this.base});

  @override
  State<DayRouteMap> createState() => _DayRouteMapState();
}

class _DayRouteMapState extends State<DayRouteMap> {
  GoogleMapController? _map;
  Set<Marker> _markers = {};
  String _signature = '';

  List<BakeryOrder> get _located => widget.stops.where((o) => o.hasLocation).toList();

  List<String> get _slots => widget.stops.map((o) => o.slot).toSet().toList()..sort();

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  @override
  void didUpdateWidget(DayRouteMap old) {
    super.didUpdateWidget(old);
    _buildMarkers();
  }

  /// Los íconos con número se dibujan una vez y solo se rehacen si algo cambió.
  Future<void> _buildMarkers() async {
    final sig = [
      widget.base,
      for (final o in widget.stops) '${o.id}${o.lat}${o.lng}${o.status.name}${o.slot}',
    ].join('|');
    if (sig == _signature) return;
    _signature = sig;

    final slots = _slots;
    final markers = <Marker>{};
    if (widget.base != null) {
      markers.add(Marker(
        markerId: const MarkerId('salida'),
        position: LatLng(widget.base!.$1, widget.base!.$2),
        icon: await _pin(label: '🏠', color: Pan.cacao),
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'Salida'),
        zIndexInt: 0,
      ));
    }
    for (var i = 0; i < widget.stops.length; i++) {
      final o = widget.stops[i];
      if (!o.hasLocation) continue;
      final done = o.status == OrderStatus.entregado;
      markers.add(Marker(
        markerId: MarkerId(o.id),
        position: LatLng(o.lat!, o.lng!),
        icon: await _pin(
          label: '${i + 1}',
          color: done ? const Color(0xFF9E9E9E) : colorForSlot(slots, o.slot),
        ),
        anchor: const Offset(0.5, 0.5),
        zIndexInt: done ? 1 : 2,
        infoWindow: InfoWindow(
          title: '${i + 1}. ${o.customerName}',
          snippet: '${slotLabel(o.slot)} · ${o.pieces} pzas${done ? ' · entregado' : ''}',
        ),
      ));
    }
    if (!mounted || sig != _signature) return;
    setState(() => _markers = markers);
  }

  /// Círculo de color con el número de parada adentro.
  Future<BitmapDescriptor> _pin({required String label, required Color color}) async {
    const size = 84.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const c = Offset(size / 2, size / 2);
    canvas.drawCircle(c + const Offset(0, 3), size / 2 - 6, Paint()..color = const Color(0x40000000));
    canvas.drawCircle(c, size / 2 - 6, Paint()..color = Colors.white);
    canvas.drawCircle(c, size / 2 - 12, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: label.length > 2 ? 26 : 32,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: 2.6);
  }

  List<LatLng> get _points => [
        if (widget.base != null) LatLng(widget.base!.$1, widget.base!.$2),
        for (final o in _located) LatLng(o.lat!, o.lng!),
      ];

  void _fit() {
    final pts = _points;
    if (_map == null || pts.isEmpty) return;
    if (pts.length == 1) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    double minLat = pts.first.latitude, maxLat = minLat;
    double minLng = pts.first.longitude, maxLng = minLng;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      48,
    ));
  }

  /// Abre Google Maps con las paradas que faltan, en orden (Maps acepta hasta 9 intermedias).
  Future<void> _openInMaps() async {
    final pending = _located.where((o) => o.isPending).toList();
    if (pending.isEmpty) return;
    final legs = pending.take(10).map((o) => '${o.lat},${o.lng}').toList();
    final dest = legs.removeLast();
    final params = [
      'api=1',
      'travelmode=driving',
      'destination=$dest',
      if (widget.base != null) 'origin=${widget.base!.$1},${widget.base!.$2}',
      if (legs.isNotEmpty) 'waypoints=${Uri.encodeComponent(legs.join('|'))}',
    ];
    await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?${params.join('&')}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final located = _located;
    final missing = widget.stops.length - located.length;
    final slots = _slots;
    final km = routeLength<BakeryOrder>(
          located,
          (o) => (o.lat!, o.lng!),
          start: widget.base,
        ) /
        1000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Ruta del ${dayLabel(widget.date).split(' ').take(2).join(' ')}',
          trailing: located.isEmpty
              ? null
              : Text('≈ ${distanceLabel(km * 1000)}', style: theme.textTheme.bodySmall),
        ),
        PanCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Pan.radio),
            child: SizedBox(
              height: 340,
              child: located.isEmpty
                  ? const EmptyState(
                      title: 'Sin casas marcadas',
                      message: 'Cuando tus clientes marquen su casa en el mapa, aparecen aquí.',
                    )
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(located.first.lat!, located.first.lng!),
                        zoom: 13,
                      ),
                      markers: _markers,
                      polylines: {
                        Polyline(
                          polylineId: const PolylineId('ruta'),
                          points: _points,
                          color: Pan.caramelo.withValues(alpha: 0.75),
                          width: 4,
                          patterns: [PatternItem.dash(18), PatternItem.gap(10)],
                        ),
                      },
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      myLocationButtonEnabled: false,
                      // Para mover el mapa sin que se mueva la lista.
                      gestureRecognizers: {
                        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
                      },
                      onMapCreated: (c) {
                        _map = c;
                        Future.delayed(const Duration(milliseconds: 300), _fit);
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final s in slots)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: colorForSlot(slots, s), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(slotLabel(s), style: theme.textTheme.bodySmall),
                ],
              ),
          ],
        ),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '$missing ${missing == 1 ? 'pedido no tiene' : 'pedidos no tienen'} casa marcada '
              '(van al final de su horario).',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (widget.base == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Tip: marca tu punto de salida en Ajustes → Reparto para que la ruta empiece en tu casa.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: located.isEmpty ? null : _fit,
                icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
                label: const Text('Ver todo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: located.any((o) => o.isPending) ? _openInMaps : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Abrir ruta'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
