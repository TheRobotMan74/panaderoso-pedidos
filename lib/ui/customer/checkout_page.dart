import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/cart.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';

/// Confirmar pedido: día, horario, forma de pago y captura de transferencia.
class CheckoutPage extends StatefulWidget {
  final AppUser user;
  final Cart cart;
  const CheckoutPage({super.key, required this.user, required this.cart});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _notes = TextEditingController();
  String? _date;
  String? _slot;
  PaymentMethod _payment = PaymentMethod.transferencia;
  File? _proof;
  bool _busy = false;

  Future<void> _pickProof() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (x != null) setState(() => _proof = File(x.path));
  }

  Future<void> _place(DeliveryDay day) async {
    setState(() => _busy = true);
    try {
      String? proofPath;
      if (_payment == PaymentMethod.transferencia && _proof != null) {
        proofPath = await Repo.instance.uploadPaymentProof(widget.user.uid, _proof!);
      }
      final u = widget.user;
      await Repo.instance.createOrder(BakeryOrder(
        id: '',
        customerId: u.uid,
        customerName: u.name,
        phone: u.phone,
        address: u.address,
        addressNotes: u.addressNotes,
        items: widget.cart.items,
        deliveryDate: day.date,
        slot: _slot!,
        paymentMethod: _payment,
        paymentProofPath: proofPath,
        // Fase 1: envío gratis. El cálculo por distancia (logic/shipping.dart)
        // se conecta en la fase 2, junto con el mapa.
        shippingFee: 0,
        notes: _notes.text.trim(),
        lat: u.lat,
        lng: u.lng,
      ));
      widget.cart.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Pedido enviado! Te avisamos cuando lo confirmemos.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar el pedido. Intenta de nuevo. ($e)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tu pedido')),
      body: StreamBuilder<List<DeliveryDay>>(
        stream: Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now())),
        builder: (context, daysSnap) => StreamBuilder<AppConfig>(
          stream: Repo.instance.config(),
          builder: (context, cfgSnap) {
            if (!daysSnap.hasData || !cfgSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final days = orderableDays(daysSnap.data!, DateTime.now());
            final selected = days.where((d) => d.date == _date).firstOrNull;
            return _body(days, selected, cfgSnap.data!);
          },
        ),
      ),
    );
  }

  Widget _body(List<DeliveryDay> days, DeliveryDay? day, AppConfig cfg) {
    final theme = Theme.of(context);
    final cart = widget.cart;
    final needsProof = _payment == PaymentMethod.transferencia && _proof == null;
    final canPlace = !_busy && day != null && _slot != null && !needsProof && !cart.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ----- Productos -----
        for (final i in cart.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${i.qty} × ${i.name}'),
            trailing: Text(money(i.total)),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Envío'),
          trailing: const Text('Gratis'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Total', style: theme.textTheme.titleMedium),
          trailing: Text(money(cart.subtotal), style: theme.textTheme.titleMedium),
        ),
        const Divider(),

        // ----- Día y horario -----
        Text('¿Qué día te lo llevamos?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (days.isEmpty)
          const Text('Por ahora no hay días de entrega abiertos. Vuelve pronto.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in days)
                ChoiceChip(
                  label: Text(dayLabel(d.date)),
                  selected: d.date == _date,
                  onSelected: (_) => setState(() {
                    _date = d.date;
                    _slot = null;
                  }),
                ),
            ],
          ),
        if (day != null) ...[
          const SizedBox(height: 12),
          Text('Horario', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in day.slots)
                ChoiceChip(
                  label: Text(slotLabel(s, minutes: day.slotMinutes)),
                  selected: s == _slot,
                  onSelected: (_) => setState(() => _slot = s),
                ),
            ],
          ),
        ],
        const Divider(height: 32),

        // ----- Pago -----
        Text('¿Cómo vas a pagar?', style: theme.textTheme.titleMedium),
        RadioGroup<PaymentMethod>(
          groupValue: _payment,
          onChanged: (v) => setState(() => _payment = v!),
          child: const Column(
            children: [
              RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: PaymentMethod.transferencia,
                title: Text('Transferencia'),
              ),
              RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: PaymentMethod.efectivo,
                title: Text('Efectivo al recibir'),
              ),
            ],
          ),
        ),
        if (_payment == PaymentMethod.transferencia) _transferBox(cfg),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Notas para la entrega (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: canPlace ? () => _place(day) : null,
          child: Text(_busy ? 'Enviando…' : 'Hacer pedido'),
        ),
        if (needsProof && day != null && _slot != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Sube la captura de tu transferencia para continuar.',
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _transferBox(AppConfig cfg) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cfg.clabe.isEmpty)
              const Text('Pide los datos de la cuenta por WhatsApp.')
            else ...[
              Text('Transfiere ${money(widget.cart.subtotal)} a:', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(cfg.accountHolder, style: theme.textTheme.titleSmall),
              Text(cfg.bankName),
              Row(
                children: [
                  Expanded(child: SelectableText('CLABE ${cfg.clabe}')),
                  IconButton(
                    tooltip: 'Copiar CLABE',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: cfg.clabe));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('CLABE copiada')));
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (_proof != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(_proof!, height: 160, fit: BoxFit.cover),
              ),
            OutlinedButton.icon(
              onPressed: _pickProof,
              icon: const Icon(Icons.upload),
              label: Text(_proof == null ? 'Subir captura' : 'Cambiar captura'),
            ),
          ],
        ),
      ),
    );
  }
}
