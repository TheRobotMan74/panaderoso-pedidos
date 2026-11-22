import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/repo.dart';
import 'location_picker_page.dart';

/// Datos del cliente: nombre, teléfono y dirección de entrega.
class ProfilePage extends StatefulWidget {
  final String uid;
  final AppUser? existing;

  /// true cuando se abre desde el menú para editar (muestra botón de regresar).
  final bool editing;

  const ProfilePage({super.key, required this.uid, this.existing, this.editing = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _notes = TextEditingController(text: widget.existing?.addressNotes);
  final _form = GlobalKey<FormState>();
  late double? _lat = widget.existing?.lat;
  late double? _lng = widget.existing?.lng;
  bool _missingPin = false;
  bool _busy = false;

  bool get _isOwner => widget.existing?.role == Role.dueno;

  Future<void> _pickOnMap() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(builder: (_) => LocationPickerPage(lat: _lat, lng: _lng)),
    );
    if (picked == null) return;
    setState(() {
      _lat = picked.lat;
      _lng = picked.lng;
      _missingPin = false;
      // La dirección escrita se llena sola; se puede corregir (por ejemplo el número).
      if (picked.address.isNotEmpty) _address.text = picked.address;
    });
  }

  Future<void> _save() async {
    final formOk = _form.currentState!.validate();
    // El dueño no necesita marcar casa; los clientes sí.
    final pinOk = _isOwner || _lat != null;
    setState(() => _missingPin = !pinOk);
    if (!formOk || !pinOk) return;
    setState(() => _busy = true);
    await Repo.instance.saveProfile(AppUser(
      uid: widget.uid,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      addressNotes: _notes.text.trim(),
      lat: _lat,
      lng: _lng,
    ));
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.editing) Navigator.pop(context);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Falta este dato' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tus datos de entrega'),
        actions: [
          if (!widget.editing)
            TextButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Salir'),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              validator: _required,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono (WhatsApp)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            Text('Tu casa en el mapa', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _MapPreview(lat: _lat, lng: _lng, onTap: _pickOnMap, error: _missingPin),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              validator: _required,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Dirección: calle, número y colonia',
                helperText: 'Se llena sola al marcar el mapa; corrígela si hace falta',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Referencias (opcional)',
                hintText: 'Ej. portón negro, tocar el timbre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}

/// Cuadrito con el mapa de la casa, o el botón para marcarla.
class _MapPreview extends StatelessWidget {
  final double? lat;
  final double? lng;
  final VoidCallback onTap;
  final bool error;
  const _MapPreview({required this.lat, required this.lng, required this.onTap, required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lat == null || lng == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.map),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Marcar mi casa en el mapa'),
            ),
          ),
          if (error)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text('Marca tu casa para que el repartidor llegue directo',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
            ),
        ],
      );
    }
    final at = LatLng(lat!, lng!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 160,
        child: Stack(
          children: [
            GoogleMap(
              // Modo ligero: una imagen fija del mapa, gasta menos.
              liteModeEnabled: true,
              initialCameraPosition: CameraPosition(target: at, zoom: 16),
              markers: {Marker(markerId: const MarkerId('casa'), position: at)},
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onTap: (_) => onTap(),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: FilledButton.tonalIcon(
                onPressed: onTap,
                icon: const Icon(Icons.edit_location_alt),
                label: const Text('Cambiar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
