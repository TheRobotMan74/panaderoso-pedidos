import 'package:material_ui/material_ui.dart';

import '../../logic/promos.dart';
import '../../logic/shipping.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../location_picker_page.dart';
import '../theme.dart';
import '../update_watcher.dart';
import '../widgets.dart';

/// Datos para transferencias y reglas de envío.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppConfig>(
      stream: Repo.instance.config(),
      builder: (context, snap) {
        if (!snap.hasData) return const SkeletonList(count: 3);
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
  late final _whatsapp = TextEditingController(text: widget.initial.whatsapp);
  late final _perKm =
      TextEditingController(text: widget.initial.shipping.pricePerKm.toStringAsFixed(2));
  late bool _shippingEnabled = widget.initial.shipping.enabled;
  late final _nearMeters =
      TextEditingController(text: widget.initial.nearAlertMeters.toString());
  late double? _baseLat = widget.initial.baseLat;
  late final _etaSpeed = TextEditingController(text: _short(widget.initial.etaSpeedKmh));
  late final _etaStop = TextEditingController(text: _short(widget.initial.etaStopMinutes));

  static String _short(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  late bool _routeReturn = widget.initial.routeReturn;
  late double? _baseLng = widget.initial.baseLng;
  late bool _loyaltyOn = widget.initial.promos.loyaltyEnabled;
  late final _loyaltyGoal =
      TextEditingController(text: widget.initial.promos.loyaltyGoal.toString());
  late bool _welcomeOn = widget.initial.promos.welcomeEnabled;
  late final _welcomeMin =
      TextEditingController(text: widget.initial.promos.welcomeMinPieces.toString());
  late String _giftId = widget.initial.promos.giftProductId;

  Future<void> _pickBase() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          lat: _baseLat,
          lng: _baseLng,
          title: '¿De dónde sales a repartir?',
          confirmLabel: 'Salgo de aquí',
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _baseLat = picked.lat;
      _baseLng = picked.lng;
    });
    await Repo.instance.saveBaseLocation(picked.lat, picked.lng);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Punto de salida guardado')));
  }

  Future<void> _save() async {
    final old = widget.initial.shipping;
    await Repo.instance.saveConfig(AppConfig(
      bankName: _bank.text.trim(),
      clabe: _clabe.text.replaceAll(' ', ''),
      accountHolder: _holder.text.trim(),
      whatsapp: _whatsapp.text.replaceAll(RegExp(r'\D'), ''),
      shipping: ShippingRules(
        enabled: _shippingEnabled,
        pricePerKm: double.tryParse(_perKm.text.replaceAll(',', '.')) ?? old.pricePerKm,
        tiers: old.tiers,
        roundTo: old.roundTo,
        roadFactor: old.roadFactor,
      ),
      nearAlertMeters: (int.tryParse(_nearMeters.text.trim()) ?? widget.initial.nearAlertMeters)
          .clamp(100, 10000),
      baseLat: _baseLat,
      baseLng: _baseLng,
      routeReturn: _routeReturn,
      etaSpeedKmh: (double.tryParse(_etaSpeed.text.replaceAll(',', '.')) ?? widget.initial.etaSpeedKmh)
          .clamp(5, 90),
      etaStopMinutes:
          (double.tryParse(_etaStop.text.replaceAll(',', '.')) ?? widget.initial.etaStopMinutes)
              .clamp(0, 30),
      promos: PromoRules(
        loyaltyEnabled: _loyaltyOn,
        loyaltyGoal: (int.tryParse(_loyaltyGoal.text.trim()) ?? widget.initial.promos.loyaltyGoal)
            .clamp(2, 100),
        welcomeEnabled: _welcomeOn,
        welcomeMinPieces:
            (int.tryParse(_welcomeMin.text.trim()) ?? widget.initial.promos.welcomeMinPieces)
                .clamp(1, 50),
        giftProductId: _giftId,
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const SectionTitle('Datos para transferencia', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
        TextField(
          controller: _holder,
          decoration: const InputDecoration(labelText: 'A nombre de'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bank,
          decoration: const InputDecoration(labelText: 'Banco'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clabe,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'CLABE'),
        ),
        const Divider(height: 40),
        const SectionTitle('WhatsApp', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
        TextField(
          controller: _whatsapp,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'WhatsApp de la panadería',
            helperText: 'Los clientes te pueden escribir desde su pedido. Vacío = sin botón.',
          ),
        ),
        const Divider(height: 40),
        const SectionTitle('Envío', padding: EdgeInsets.fromLTRB(4, 4, 4, 4)),
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
        const Divider(height: 40),
        const SectionTitle('Reparto', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
        TextField(
          controller: _nearMeters,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Avisar al cliente cuando estés a',
            suffixText: 'metros',
            helperText: '1000 m son como 2 o 3 minutos en carro',
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.home_work_rounded, color: Pan.caramelo),
          title: const Text('Punto de salida'),
          subtitle: Text(_baseLat == null
              ? 'Marca tu casa o la panadería: de ahí empieza la ruta del día'
              : 'Marcado en el mapa. La ruta del día empieza aquí.'),
          trailing: OutlinedButton(
            onPressed: _pickBase,
            child: Text(_baseLat == null ? 'Marcar' : 'Cambiar'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _routeReturn,
          onChanged: (v) => setState(() => _routeReturn = v),
          title: const Text('Regreso al punto de salida al terminar'),
          subtitle: const Text('La ruta se arma pensando también en el camino de vuelta'),
        ),
        const SizedBox(height: 8),
        Text(
          'Tiempo estimado de llegada: el cliente ve en su mapa en cuántos minutos llegas, '
          'según dónde vas y las entregas que faltan antes de la suya.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _etaSpeed,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Velocidad promedio',
                  suffixText: 'km/h',
                  helperText: 'En ciudad, 20 a 30',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _etaStop,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tardas en cada entrega',
                  suffixText: 'min',
                  helperText: 'Estacionar, entregar, cobrar',
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 40),
        const SectionTitle('Promociones', padding: EdgeInsets.fromLTRB(4, 4, 4, 4)),
        Text(
          'El pan gratis se agrega solo al pedido y cuenta en la demanda para hornear. '
          'Solo aplica a pedidos nuevos.',
          style: theme.textTheme.bodySmall,
        ),
        StreamBuilder<List<Product>>(
          stream: Repo.instance.products(),
          builder: (context, snap) {
            final products = snap.data ?? const <Product>[];
            final auto = giftProduct(const PromoRules(), products);
            final ids = products.map((p) => p.id).toSet();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<String>(
                initialValue: ids.contains(_giftId) ? _giftId : '',
                decoration: const InputDecoration(labelText: 'Pan que se regala'),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(auto == null ? 'Chocolatín' : '${auto.name} (normal)'),
                  ),
                  for (final p in products) DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _giftId = v ?? ''),
              ),
            );
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tarjeta de lealtad'),
          subtitle: const Text('Cada cierto número de piezas compradas, 1 pan gratis'),
          value: _loyaltyOn,
          onChanged: (v) => setState(() => _loyaltyOn = v),
        ),
        TextField(
          controller: _loyaltyGoal,
          enabled: _loyaltyOn,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '1 pan gratis cada',
            suffixText: 'piezas',
            helperText: 'Cuentan las piezas compradas desde que salió la promoción',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pan gratis en el primer pedido'),
          subtitle: const Text('Uno por cuenta y uno por domicilio'),
          value: _welcomeOn,
          onChanged: (v) => setState(() => _welcomeOn = v),
        ),
        TextField(
          controller: _welcomeMin,
          enabled: _welcomeOn,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Pedido mínimo para el regalo',
            suffixText: 'piezas',
          ),
        ),
        const SizedBox(height: 24),
        HoneyButton(label: 'Guardar', icon: Icons.check_rounded, onPressed: _save),
        const SizedBox(height: 28),
        const VersionLabel(),
      ],
    );
  }
}
