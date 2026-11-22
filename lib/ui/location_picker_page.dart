import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'widgets.dart';

/// Lo que regresa el mapa: el punto elegido y la dirección que encontró (si encontró).
class PickedLocation {
  final double lat;
  final double lng;
  final String address;
  const PickedLocation(this.lat, this.lng, this.address);
}

/// Elegir la casa en el mapa: se mueve el mapa hasta que el pin quede en la casa.
/// Se puede buscar una dirección o usar la ubicación actual del celular.
///
/// La búsqueda y la dirección escrita usan el buscador que ya trae Android
/// (gratis); el mapa es Google Maps para Android (también sin costo).
class LocationPickerPage extends StatefulWidget {
  final double? lat;
  final double? lng;
  const LocationPickerPage({super.key, this.lat, this.lng});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  /// Si no hay nada mejor, se empieza viendo todo México.
  static const _mexico = CameraPosition(target: LatLng(23.6, -102.5), zoom: 4.5);

  final _geocoding = Geocoding(locale: const Locale('es', 'MX'));
  final _search = TextEditingController();
  GoogleMapController? _map;
  late LatLng _center = widget.lat != null && widget.lng != null
      ? LatLng(widget.lat!, widget.lng!)
      : _mexico.target;
  late bool _chosen = widget.lat != null;
  String _address = '';
  bool _lookingUp = false;
  bool _searching = false;

  /// El mapa se está moviendo: el pin se levanta.
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    if (_chosen) {
      _lookupAddress();
    } else {
      _goToMyLocation(silent: true);
    }
  }

  Future<void> _goToMyLocation({bool silent = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silent) _toast('Prende la ubicación (GPS) del celular.');
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        if (!silent) _toast('Sin permiso de ubicación. Busca tu calle arriba.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _moveTo(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (!silent) _toast('No se pudo saber dónde estás. Busca tu calle arriba.');
    }
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final found = await _geocoding.locationFromAddress('$q, México');
      if (found.isEmpty) {
        _toast('No encontramos esa dirección. Prueba con calle, número y colonia.');
      } else {
        _moveTo(LatLng(found.first.latitude, found.first.longitude));
      }
    } catch (_) {
      _toast('No encontramos esa dirección. Prueba con calle, número y colonia.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _moveTo(LatLng p) {
    if (!mounted) return;
    setState(() {
      _center = p;
      _chosen = true;
    });
    _map?.animateCamera(CameraUpdate.newLatLngZoom(p, 18));
  }

  Future<void> _lookupAddress() async {
    final at = _center;
    setState(() => _lookingUp = true);
    String text = '';
    try {
      final marks = await _geocoding.placemarkFromCoordinates(at.latitude, at.longitude);
      if (marks.isNotEmpty) text = addressFromPlacemark(marks.first);
    } catch (_) {}
    if (!mounted || at != _center) return;
    setState(() {
      _address = text;
      _lookingUp = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('¿Dónde te llevamos el pan?')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _chosen ? CameraPosition(target: _center, zoom: 18) : _mexico,
            onMapCreated: (c) => _map = c,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onCameraMove: (c) => _center = c.target,
            onCameraMoveStarted: () => setState(() {
              _chosen = true;
              _moving = true;
            }),
            onCameraIdle: () {
              if (_moving) setState(() => _moving = false);
              if (_chosen) _lookupAddress();
            },
          ),
          // Pin fijo al centro: se mueve el mapa, no el pin.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 52),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSlide(
                      offset: _moving ? const Offset(0, -0.25) : Offset.zero,
                      duration: Motion.of(context, Motion.rapido),
                      curve: _moving ? Curves.easeOut : Curves.bounceOut,
                      child: const Icon(Icons.location_on_rounded, size: 52, color: Pan.caramelo,
                          shadows: [Shadow(color: Color(0x553B2A1E), blurRadius: 8, offset: Offset(0, 3))]),
                    ),
                    // Sombrita en el piso: se achica cuando el pin se levanta.
                    AnimatedScale(
                      scale: _moving ? 0.6 : 1,
                      duration: Motion.of(context, Motion.rapido),
                      child: Container(
                        width: 14,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0x553B2A1E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 4,
              color: Pan.papel,
              shadowColor: const Color(0x553B2A1E),
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _doSearch(),
                decoration: InputDecoration(
                  hintText: 'Busca tu calle y número',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _doSearch),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 170,
            child: FloatingActionButton.small(
              heroTag: 'mi-ubicacion',
              tooltip: 'Usar mi ubicación',
              onPressed: _goToMyLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 10,
              color: Pan.papel,
              shadowColor: const Color(0x553B2A1E),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedCount(
                        !_chosen
                            ? 'Mueve el mapa hasta que el pin quede en tu casa.'
                            : _lookingUp
                                ? 'Buscando la dirección…'
                                : (_address.isEmpty ? 'Punto marcado en el mapa' : _address),
                        style: theme.textTheme.titleMedium,
                        alignment: Alignment.centerLeft,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      HoneyButton(
                        onPressed: _chosen
                            ? () => Navigator.pop(
                                context, PickedLocation(_center.latitude, _center.longitude, _address))
                            : null,
                        icon: Icons.check_rounded,
                        label: 'Aquí es mi casa',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Av. Juárez 120, Centro, Morelia" a partir de lo que regresa Android.
String addressFromPlacemark(Placemark p) {
  String clean(String? s) => (s ?? '').trim();
  final street = [clean(p.thoroughfare), clean(p.subThoroughfare)]
      .where((s) => s.isNotEmpty)
      .join(' ');
  final parts = [
    street.isNotEmpty ? street : clean(p.street),
    clean(p.subLocality),
    clean(p.locality),
  ].where((s) => s.isNotEmpty).toList();
  // Quitar repetidos (a veces colonia y ciudad vienen iguales).
  final seen = <String>{};
  return parts.where(seen.add).join(', ');
}
