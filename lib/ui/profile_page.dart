import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/repo.dart';
import '../web/map_fallback.dart';
import 'customer/addresses.dart';
import 'location_picker_page.dart';
import 'theme.dart';
import 'widgets.dart';
import '../services/push.dart';

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

  /// Cliente que ya tiene su dirección: aquí se ven y se cambian todas sus direcciones
  /// (en el registro se pide solo una, como siempre).
  bool get _manyAddresses =>
      widget.editing && !_isOwner && widget.existing != null && widget.existing!.addresses.isNotEmpty;

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
    if (_manyAddresses) {
      if (!_form.currentState!.validate()) return;
      setState(() => _busy = true);
      await Repo.instance.saveNameAndPhone(widget.uid, _name.text.trim(), _phone.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
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
              onPressed: () => signOutAndForgetPush(),
              child: const Text('Salir'),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (!widget.editing)
              FadeSlideIn(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    children: [
                      const BearLogo(size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '¡Bienvenido! Dinos a dónde llevarte el pan.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            TextFormField(
              controller: _name,
              validator: _required,
              decoration: const InputDecoration(
                  labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              validator: _required,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono (WhatsApp)', prefixIcon: Icon(Icons.phone_iphone_rounded)),
            ),
            if (_manyAddresses) ...[
              const SectionTitle('Mis direcciones'),
              AddressesSection(uid: widget.uid),
            ] else ...[
            const SectionTitle('Tu casa en el mapa'),
            HomeMapPreview(lat: _lat, lng: _lng, onTap: _pickOnMap, error: _missingPin),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              validator: _required,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Dirección: calle, número y colonia',
                helperText: 'Se llena sola al marcar el mapa; corrígela si hace falta',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Referencias (opcional)',
                hintText: 'Ej. portón negro, tocar el timbre',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            ],
            const SizedBox(height: 24),
            HoneyButton(
              label: 'Guardar',
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuadrito con el mapa de la casa, o el botón para marcarla.
class HomeMapPreview extends StatelessWidget {
  final double? lat;
  final double? lng;
  final VoidCallback onTap;
  final bool error;
  final String emptyLabel;
  const HomeMapPreview({
    super.key,
    required this.lat,
    required this.lng,
    required this.onTap,
    required this.error,
    this.emptyLabel = 'Marcar mi casa en el mapa',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lat == null || lng == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanCard(
            onTap: onTap,
            margin: EdgeInsets.zero,
            color: error ? const Color(0xFFFBE7E2) : const Color(0xFFFFF4D6),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(gradient: Pan.gradienteMiel, shape: BoxShape.circle),
                  child: const Icon(Icons.location_on_rounded, color: Pan.cacao),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(emptyLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                const Icon(Icons.chevron_right_rounded, color: Pan.caramelo),
              ],
            ),
          ),
          if (error)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text('Marca el lugar para que el repartidor llegue directo',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
            ),
        ],
      );
    }
    final at = LatLng(lat!, lng!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Pan.radio),
      child: SizedBox(
        height: 170,
        child: Stack(
          children: [
            if (!mapsUsable)
              MapFallback(message: 'Casa marcada (${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)})')
            else
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
