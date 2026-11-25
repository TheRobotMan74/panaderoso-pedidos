import 'package:material_ui/material_ui.dart';

import '../../models.dart';
import '../../services/repo.dart';
import '../location_picker_page.dart';
import '../theme.dart';

/// Al abrir un día: ¿a domicilio o especial (todos recogen en un mismo lugar)?
/// Para el especial se escribe el nombre del lugar, se marca en el mapa y,
/// si se quiere, se guarda para usarlo otra vez con un toque.
class PickupPointFields extends StatefulWidget {
  final PickupPoint? initial;

  /// Cada cambio: el lugar completo (nombre + mapa) o null si falta algo / es a domicilio.
  final ValueChanged<PickupPoint?> onChanged;

  /// Se llama con true cuando eligió "Especial" (aunque todavía no esté completo).
  final ValueChanged<bool>? onModeChanged;

  const PickupPointFields({super.key, this.initial, required this.onChanged, this.onModeChanged});

  @override
  State<PickupPointFields> createState() => PickupPointFieldsState();
}

class PickupPointFieldsState extends State<PickupPointFields> {
  late bool _special = widget.initial != null;
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _notes = TextEditingController(text: widget.initial?.notes ?? '');
  late double? _lat = widget.initial?.lat;
  late double? _lng = widget.initial?.lng;
  String _mapAddress = '';

  /// Guardar el lugar en "frecuentes" al abrir el día.
  bool remember = true;

  bool get special => _special;

  PickupPoint? get point {
    final name = _name.text.trim();
    if (!_special || name.isEmpty || _lat == null || _lng == null) return null;
    return PickupPoint(name: name, lat: _lat!, lng: _lng!, notes: _notes.text.trim());
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(point);

  void _use(PickupPoint p) {
    setState(() {
      _name.text = p.name;
      _notes.text = p.notes;
      _lat = p.lat;
      _lng = p.lng;
      _mapAddress = '';
    });
    _emit();
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          lat: _lat,
          lng: _lng,
          title: '¿Dónde vas a entregar?',
          confirmLabel: 'Aquí entrego',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lat = picked.lat;
      _lng = picked.lng;
      _mapAddress = picked.address;
    });
    _emit();
  }

  Future<void> _forget(PickupPoint p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Quitar "${p.name}" de tus lugares?'),
        content: const Text('Los días que ya abriste ahí no cambian.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, quitar')),
        ],
      ),
    );
    if (ok == true) await Repo.instance.removePickupPoint(p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('¿Dónde entregas?')),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('A domicilio')),
                ButtonSegment(value: true, label: Text('Especial')),
              ],
              selected: {_special},
              onSelectionChanged: (s) {
                setState(() => _special = s.first);
                widget.onModeChanged?.call(_special);
                _emit();
              },
            ),
          ],
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.medio),
          curve: Motion.curva,
          alignment: Alignment.topCenter,
          child: !_special
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      'Todos los pedidos de ese día se entregan en un solo lugar (por ejemplo FIME). '
                      'Los clientes no ponen su dirección, no se cobra envío y el pan de bienvenida '
                      'no aplica (sí cuenta para la tarjeta de lealtad).',
                      style: theme.textTheme.bodySmall,
                    ),
                    StreamBuilder<List<PickupPoint>>(
                      stream: Repo.instance.pickupPoints(),
                      builder: (context, snap) {
                        final saved = snap.data ?? const <PickupPoint>[];
                        if (saved.isEmpty) return const SizedBox(height: 8);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final p in saved)
                                GestureDetector(
                                  onLongPress: () => _forget(p),
                                  child: ChoiceChip(
                                    label: Text('📍 ${p.name}'),
                                    selected: _name.text.trim().toLowerCase() == p.name.toLowerCase() &&
                                        _lat == p.lat &&
                                        _lng == p.lng,
                                    onSelected: (_) => _use(p),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del lugar',
                        hintText: 'Ej. FIME',
                        prefixIcon: Icon(Icons.location_on_rounded),
                      ),
                      onChanged: (_) => setState(_emit),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notes,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Dónde te encuentran (opcional)',
                        hintText: 'Ej. Entrada principal, junto a la cafetería',
                        prefixIcon: Icon(Icons.sticky_note_2_outlined),
                      ),
                      onChanged: (_) => _emit(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickOnMap,
                        icon: Icon(_lat == null ? Icons.edit_location_alt : Icons.check_circle_rounded),
                        label: Text(_lat == null
                            ? 'Marcar el lugar en el mapa'
                            : (_mapAddress.isEmpty ? 'Lugar marcado · cambiar' : 'Marcado: $_mapAddress')),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: remember,
                      onChanged: (v) => setState(() => remember = v ?? true),
                      title: const Text('Guardar este lugar para la próxima'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
