import 'package:material_ui/material_ui.dart';

import '../../logic/shipping.dart';
import '../../models.dart';
import '../../services/repo.dart';

/// Datos para transferencias y reglas de envío.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppConfig>(
      stream: Repo.instance.config(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return _SettingsForm(initial: snap.data!);
      },
    );
  }
}

class _SettingsForm extends StatefulWidget {
  final AppConfig initial;
  const _SettingsForm({required this.initial});

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final _bank = TextEditingController(text: widget.initial.bankName);
  late final _clabe = TextEditingController(text: widget.initial.clabe);
  late final _holder = TextEditingController(text: widget.initial.accountHolder);
  late final _perKm =
      TextEditingController(text: widget.initial.shipping.pricePerKm.toStringAsFixed(2));
  late bool _shippingEnabled = widget.initial.shipping.enabled;

  Future<void> _save() async {
    final old = widget.initial.shipping;
    await Repo.instance.saveConfig(AppConfig(
      bankName: _bank.text.trim(),
      clabe: _clabe.text.replaceAll(' ', ''),
      accountHolder: _holder.text.trim(),
      shipping: ShippingRules(
        enabled: _shippingEnabled,
        pricePerKm: double.tryParse(_perKm.text.replaceAll(',', '.')) ?? old.pricePerKm,
        tiers: old.tiers,
        roundTo: old.roundTo,
      ),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guardado')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final free = widget.initial.shipping.freeFromPieces();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Datos para transferencia', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _holder,
          decoration: const InputDecoration(labelText: 'A nombre de', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bank,
          decoration: const InputDecoration(labelText: 'Banco', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clabe,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'CLABE', border: OutlineInputBorder()),
        ),
        const Divider(height: 40),
        Text('Envío', style: theme.textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cobrar envío'),
          subtitle: const Text('Apagado: el envío es gratis para todos'),
          value: _shippingEnabled,
          onChanged: (v) => setState(() => _shippingEnabled = v),
        ),
        TextField(
          controller: _perKm,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Precio por km',
            prefixText: r'$ ',
            helperText: r'Gasolina: $25 por litro ÷ 9 km por litro ≈ $2.80',
            border: OutlineInputBorder(),
          ),
        ),
        if (free != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Envío gratis desde $free piezas.', style: theme.textTheme.bodySmall),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'El cobro por distancia se activa en la fase 2, cuando la app tenga el mapa.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
