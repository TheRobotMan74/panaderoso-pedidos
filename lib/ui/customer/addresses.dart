import 'package:material_ui/material_ui.dart';

import '../../models.dart';
import '../../services/repo.dart';
import '../location_picker_page.dart';
import '../profile_page.dart';
import '../theme.dart';
import '../widgets.dart';

// Direcciones guardadas del cliente: hasta 3, siempre por lo menos 1.
// La primera de la lista es la principal (la que sale escogida al pedir).

/// Nombres rápidos para una dirección.
const addressLabels = ['Casa', 'Trabajo', 'Otra'];

IconData addressIcon(String label) => switch (label.trim().toLowerCase()) {
      'casa' => Icons.home_rounded,
      'trabajo' || 'oficina' || 'negocio' => Icons.home_work_rounded,
      _ => Icons.location_on_rounded,
    };

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// Agrega una dirección nueva a la cuenta. Regresa la que se guardó (o null si no).
Future<SavedAddress?> addAddress(BuildContext context, AppUser user) async {
  final list = user.addresses;
  if (list.length >= maxAddresses) return null;
  final used = list.map((a) => a.label.toLowerCase()).toSet();
  final suggested = addressLabels.firstWhere((l) => !used.contains(l.toLowerCase()), orElse: () => 'Otra');
  final a = await Navigator.push<SavedAddress>(
    context,
    MaterialPageRoute(
        builder: (_) => AddressEditPage(initial: SavedAddress(id: _newId(), label: suggested, address: ''))),
  );
  if (a == null) return null;
  await Repo.instance.saveAddresses(user.uid, [...list, a]);
  return a;
}

/// Pantalla para escribir o corregir una dirección (con su punto en el mapa).
class AddressEditPage extends StatefulWidget {
  final SavedAddress initial;
  const AddressEditPage({super.key, required this.initial});

  @override
  State<AddressEditPage> createState() => _AddressEditPageState();
}

class _AddressEditPageState extends State<AddressEditPage> {
  late final _label = TextEditingController(text: widget.initial.label);
  late final _address = TextEditingController(text: widget.initial.address);
  late final _notes = TextEditingController(text: widget.initial.notes);
  final _form = GlobalKey<FormState>();
  late double? _lat = widget.initial.lat;
  late double? _lng = widget.initial.lng;
  bool _missingPin = false;

  bool get _isNew => widget.initial.address.isEmpty && !widget.initial.hasLocation;

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
      if (picked.address.isNotEmpty) _address.text = picked.address;
    });
  }

  void _save() {
    final formOk = _form.currentState!.validate();
    setState(() => _missingPin = _lat == null);
    if (!formOk || _lat == null) return;
    final label = _label.text.trim();
    Navigator.pop(
      context,
      SavedAddress(
        id: widget.initial.id,
        label: label.isEmpty ? 'Otra' : label,
        address: _address.text.trim(),
        notes: _notes.text.trim(),
        lat: _lat,
        lng: _lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Nueva dirección' : 'Editar dirección')),
      body: ReadableList(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        builder: (context, pad) => Form(
        key: _form,
        child: ListView(
          padding: pad,
          children: [
            const SectionTitle('¿Cómo la llamamos?'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final l in addressLabels)
                  ChoiceChip(
                    avatar: Icon(addressIcon(l), size: 18),
                    label: Text(l),
                    selected: _label.text.trim().toLowerCase() == l.toLowerCase(),
                    onSelected: (_) => setState(() => _label.text = l),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _label,
              maxLength: 20,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nombre (ej. Casa de mi mamá)',
                prefixIcon: Icon(Icons.edit_note_rounded),
                counterText: '',
              ),
            ),
            const SectionTitle('El lugar en el mapa'),
            HomeMapPreview(
              lat: _lat,
              lng: _lng,
              onTap: _pickOnMap,
              error: _missingPin,
              emptyLabel: 'Marcar el lugar en el mapa',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Falta este dato' : null,
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
            const SizedBox(height: 24),
            HoneyButton(label: 'Guardar dirección', icon: Icons.check_rounded, onPressed: _save),
          ],
        ),
      ),
      ),
    );
  }
}

/// Renglón con el nombre y la dirección escrita.
class AddressSummary extends StatelessWidget {
  final SavedAddress address;
  final bool main;
  final Widget? trailing;
  const AddressSummary({super.key, required this.address, this.main = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = address;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(color: Pan.mielClara, shape: BoxShape.circle),
          child: Icon(addressIcon(a.label), color: Pan.caramelo, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(a.label, style: theme.textTheme.titleSmall),
                  if (main)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration:
                          BoxDecoration(color: Pan.salviaClara, borderRadius: BorderRadius.circular(8)),
                      child: const Text('Principal',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Pan.salvia)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(a.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// "Mis direcciones": la lista con agregar, editar, hacer principal y borrar.
class AddressesSection extends StatelessWidget {
  final String uid;
  const AddressesSection({super.key, required this.uid});

  Future<void> _edit(BuildContext context, AppUser user, int i) async {
    final list = user.addresses;
    final a = await Navigator.push<SavedAddress>(
      context,
      MaterialPageRoute(builder: (_) => AddressEditPage(initial: list[i])),
    );
    if (a == null) return;
    await Repo.instance.saveAddresses(uid, [...list]..[i] = a);
  }

  Future<void> _makeMain(AppUser user, int i) {
    final list = [...user.addresses];
    final a = list.removeAt(i);
    return Repo.instance.saveAddresses(uid, [a, ...list]);
  }

  Future<void> _delete(BuildContext context, AppUser user, int i) async {
    final list = [...user.addresses];
    if (list.length <= 1) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('¿Borrar "${list[i].label}"?'),
        content: const Text('Tus pedidos que ya hiciste a esta dirección no cambian.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, borrar')),
        ],
      ),
    );
    if (ok != true) return;
    list.removeAt(i);
    await Repo.instance.saveAddresses(uid, list);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: Repo.instance.userStream(uid),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const SkeletonList(count: 1);
        final list = user.addresses;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, a) in list.indexed)
              PanCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                onTap: () => _edit(context, user, i),
                child: AddressSummary(
                  address: a,
                  main: i == 0,
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Opciones',
                    onSelected: (v) => switch (v) {
                      'editar' => _edit(context, user, i),
                      'principal' => _makeMain(user, i),
                      _ => _delete(context, user, i),
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'editar', child: Text('Editar')),
                      if (i > 0) const PopupMenuItem(value: 'principal', child: Text('Usar como principal')),
                      if (list.length > 1) const PopupMenuItem(value: 'borrar', child: Text('Borrar')),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            if (list.length < maxAddresses)
              OutlinedButton.icon(
                onPressed: () => addAddress(context, user),
                icon: const Icon(Icons.add_rounded),
                label: Text('Agregar otra dirección (${list.length} de $maxAddresses)'),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('Ya tienes $maxAddresses direcciones, el máximo. Borra una para agregar otra.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (list.length == 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text('Siempre debe quedar por lo menos una dirección.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        );
      },
    );
  }
}

/// Hoja para escoger a dónde se entrega (y agregar otra dirección si caben).
/// [selectedId]: la que está escogida ahora. Regresa la elegida, o null si cerró.
Future<SavedAddress?> pickAddress(
  BuildContext context, {
  required String uid,
  String? selectedId,
  String title = '¿A dónde te lo llevamos?',
}) =>
    showModalBottomSheet<SavedAddress>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Pan.papel,
      builder: (sheet) => StreamBuilder<AppUser?>(
        stream: Repo.instance.userStream(uid),
        builder: (context, snap) {
          final user = snap.data;
          final list = user?.addresses ?? const <SavedAddress>[];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (user == null) const SkeletonList(count: 1),
                  for (final (i, a) in list.indexed)
                    PanCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      color: a.id == selectedId ? Pan.mielClara.withValues(alpha: 0.5) : null,
                      onTap: () => Navigator.pop(sheet, a),
                      child: AddressSummary(
                        address: a,
                        main: i == 0,
                        trailing: Icon(
                          a.id == selectedId
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: a.id == selectedId ? Pan.salvia : Pan.canela,
                        ),
                      ),
                    ),
                  if (user != null && list.length < maxAddresses) ...[
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final a = await addAddress(context, user);
                        if (a != null && sheet.mounted) Navigator.pop(sheet, a);
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Agregar otra dirección'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
