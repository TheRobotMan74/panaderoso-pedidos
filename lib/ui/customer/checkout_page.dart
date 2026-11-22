import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/cart.dart';
import '../../logic/schedule.dart';
import '../../logic/stock.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../order_placed.dart';
import '../product_image.dart';
import '../stock_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

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
  /// La captura elegida, ya leída (así sirve igual en Android y en la web del iPhone).
  Uint8List? _proof;
  int _proofKey = 0;
  bool _busy = false;

  Future<void> _pickProof() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _proof = bytes;
      _proofKey++;
    });
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
      if (!mounted) {
        widget.cart.clear();
        return;
      }
      // Primero el festejo (con el pedido todavía a la vista) y luego se vacía el carrito.
      await showOrderPlaced(context);
      widget.cart.clear();
      if (!mounted) return;
      Navigator.pop(context, true);
    } on RejectedByServer catch (e) {
      // Por ejemplo: alguien más se llevó los últimos panes justo antes.
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
          builder: (context, cfgSnap) => StreamBuilder<List<Product>>(
            stream: Repo.instance.products(),
            builder: (context, prodSnap) => StreamBuilder<Map<String, DayStock>>(
              stream: Repo.instance.dayStocks(fromDate: dateKey(DateTime.now())),
              builder: (context, stockSnap) {
                if (!daysSnap.hasData || !cfgSnap.hasData) {
                  return const SkeletonList(count: 3);
                }
                final days = orderableDays(daysSnap.data!, DateTime.now());
                final selected = days.where((d) => d.date == _date).firstOrNull;
                return _body(
                  days,
                  selected,
                  cfgSnap.data!,
                  products: prodSnap.data ?? const [],
                  stocks: stockSnap.data ?? const {},
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    List<DeliveryDay> days,
    DeliveryDay? day,
    AppConfig cfg, {
    required List<Product> products,
    required Map<String, DayStock> stocks,
  }) {
    final theme = Theme.of(context);
    final cart = widget.cart;
    final byId = {for (final p in products) p.id: p};
    final need = needByGroup(cart.items, byId);
    final over = day == null ? const <String>[] : overLimit(day, stocks[day.date], need);
    final needsProof = _payment == PaymentMethod.transferencia && _proof == null;
    final canPlace =
        !_busy && day != null && _slot != null && !needsProof && !cart.isEmpty && over.isEmpty;
    final d = Motion.of(context, Motion.medio);

    String? hint;
    if (day == null) {
      hint = 'Elige el día de entrega.';
    } else if (over.isNotEmpty) {
      hint = 'Ese día ya no alcanza el pan para tu pedido. Quita algunas piezas o elige otro día.';
    } else if (_slot == null) {
      hint = 'Elige un horario.';
    } else if (needsProof) {
      hint = 'Sube la captura de tu transferencia para continuar.';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // ----- Productos -----
        FadeSlideIn(
          child: PanCard(
            child: Column(
              children: [
                for (final i in cart.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Pan.mielClara,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(productArt(i.name).$1, style: const TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('${i.qty} × ${i.name}', style: theme.textTheme.titleSmall),
                        ),
                        Text(money(i.total), style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: _DashedLine()),
                Row(
                  children: [
                    Text('Envío', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Pan.salviaClara,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Gratis',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3F6B33))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Total', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    Text(money(cart.subtotal),
                        style: theme.textTheme.headlineSmall!.copyWith(color: Pan.caramelo)),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ----- Día y horario -----
        const SectionTitle('¿Qué día te lo llevamos?'),
        if (days.isEmpty)
          const PanCard(
            child: Row(
              children: [
                Text('🗓️', style: TextStyle(fontSize: 28)),
                SizedBox(width: 12),
                Expanded(child: Text('Por ahora no hay días de entrega abiertos. Vuelve pronto.')),
              ],
            ),
          )
        else
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => FadeSlideIn(
                index: i + 1,
                child: _DayCard(
                  day: days[i],
                  fits: overLimit(days[i], stocks[days[i].date], need).isEmpty,
                  left: _leftFor(days[i], stocks[days[i].date], need),
                  selected: days[i].date == _date,
                  onTap: () => setState(() {
                    _date = days[i].date;
                    _slot = null;
                  }),
                ),
              ),
            ),
          ),
        AnimatedSize(
          duration: d,
          curve: Motion.curva,
          alignment: Alignment.topCenter,
          child: day == null
              ? const SizedBox(width: double.infinity)
              : Column(
                  key: ValueKey(day.date),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stockBox(day, stocks[day.date], need, byId),
                    const SectionTitle('Horario'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (i, s) in day.slots.indexed)
                          FadeSlideIn(
                            index: i,
                            offset: 10,
                            skipWhenScrolled: false,
                            child: _Pill(
                              icon: Icons.schedule_rounded,
                              label: slotLabel(s, minutes: day.slotMinutes),
                              selected: s == _slot,
                              onTap: () => setState(() => _slot = s),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),

        // ----- Pago -----
        const SectionTitle('¿Cómo vas a pagar?'),
        Row(
          children: [
            Expanded(
              child: _PayOption(
                emoji: '🏦',
                label: 'Transferencia',
                selected: _payment == PaymentMethod.transferencia,
                onTap: () => setState(() => _payment = PaymentMethod.transferencia),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PayOption(
                emoji: '💵',
                label: 'Efectivo al recibir',
                selected: _payment == PaymentMethod.efectivo,
                onTap: () => setState(() => _payment = PaymentMethod.efectivo),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: d,
          curve: Motion.curva,
          alignment: Alignment.topCenter,
          child: _payment == PaymentMethod.transferencia
              ? Padding(padding: const EdgeInsets.only(top: 10), child: _transferBox(cfg))
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Notas para la entrega (opcional)',
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 22),
        HoneyButton(
          icon: Icons.shopping_bag_rounded,
          label: _busy ? 'Enviando…' : 'Hacer pedido · ${money(cart.subtotal)}',
          busy: _busy,
          onPressed: canPlace ? () => _place(day) : null,
        ),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.rapido),
          child: hint == null || days.isEmpty
              ? const SizedBox(height: 8)
              : Padding(
                  key: ValueKey(hint),
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(hint, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ),
        ),
      ],
    );
  }

  /// Lo que queda ese día de los panes que lleva el carrito (null = sin límite).
  int? _leftFor(DeliveryDay day, DayStock? stock, Map<String, int> need) {
    final lefts = [for (final k in need.keys) ?remainingFor(day, stock, k)];
    if (lefts.isEmpty) return null;
    return lefts.reduce((a, b) => a + b);
  }

  /// Contador en vivo de los panes que quedan ese día, solo de lo que lleva el carrito.
  Widget _stockBox(DeliveryDay day, DayStock? stock, Map<String, int> need, Map<String, Product> byId) {
    final groups = [
      for (final g in stockGroups(byId.values.toList()))
        if (need.containsKey(g.key) && day.stock.containsKey(g.key)) g,
    ];
    if (groups.isEmpty) return const SizedBox(width: double.infinity);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: PanCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pan disponible ese día', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final g in groups) ...[
              StockMeter(
                label: g.label,
                detail: g.shared ? g.productNames : null,
                left: remainingFor(day, stock, g.key) ?? 0,
                limit: day.stock[g.key]!,
              ),
              if (need[g.key]! > (remainingFor(day, stock, g.key) ?? 0))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    (remainingFor(day, stock, g.key) ?? 0) == 0
                        ? 'Ya no quedan de ${g.label} ese día. Prueba otro día.'
                        : 'Llevas ${need[g.key]} y solo ${remainingText(remainingFor(day, stock, g.key)!)}. '
                            'Quita ${need[g.key]! - remainingFor(day, stock, g.key)!} o elige otro día.',
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: Pan.terracota, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _transferBox(AppConfig cfg) {
    final theme = Theme.of(context);
    return PanCard(
      margin: EdgeInsets.zero,
      color: const Color(0xFFFFF7E4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cfg.clabe.isEmpty)
            const Text('Pide los datos de la cuenta por WhatsApp.')
          else ...[
            Text('Transfiere ${money(widget.cart.subtotal)} a:', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(cfg.accountHolder, style: theme.textTheme.titleMedium),
            Text(cfg.bankName, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              decoration: BoxDecoration(
                color: Pan.papel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF0E0C2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText('CLABE ${cfg.clabe}',
                        style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                  ),
                  IconButton(
                    tooltip: 'Copiar CLABE',
                    icon: const Icon(Icons.copy_rounded, color: Pan.caramelo),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: cfg.clabe));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('CLABE copiada ✓')));
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.medio),
            child: _proof == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(_proofKey),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(_proof!,
                          height: 160, width: double.infinity, fit: BoxFit.cover, cacheHeight: 480),
                    ),
                  ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickProof,
              icon: Icon(_proof == null ? Icons.upload_rounded : Icons.check_circle_rounded),
              label: Text(_proof == null ? 'Subir captura' : 'Cambiar captura'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjetita de día: "LUN / 23 / nov". Se pinta de miel al elegirla.
class _DayCard extends StatelessWidget {
  final DeliveryDay day;
  final bool selected;
  final VoidCallback onTap;

  /// Si el carrito cabe en el cupo de ese día.
  final bool fits;

  /// Panes que quedan ese día de lo que lleva el carrito (null = sin límite).
  final int? left;
  const _DayCard({
    required this.day,
    required this.selected,
    required this.onTap,
    this.fits = true,
    this.left,
  });

  @override
  Widget build(BuildContext context) {
    final date = parseDateKey(day.date);
    return Pressable(
      onTap: onTap,
      haptic: true,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medio),
        curve: Motion.curva,
        width: 78,
        decoration: BoxDecoration(
          gradient: selected ? Pan.gradienteMiel : null,
          color: selected ? null : Pan.papel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : const Color(0xFFEADCC4)),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x55E8960F), blurRadius: 14, offset: Offset(0, 6))]
              : Pan.sombra,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(DateFormat('EEE', 'es_MX').format(date).replaceAll('.', '').toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: selected ? Pan.tostado : Pan.canela)),
            Text('${date.day}',
                style: TextStyle(
                    fontFamily: 'Fraunces', fontSize: 30, fontWeight: FontWeight.w700, color: Pan.cacao, height: 1.15)),
            Text(DateFormat('MMM', 'es_MX').format(date).replaceAll('.', ''),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Pan.tostado : Pan.canela)),
            if (!fits || left != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: AnimatedCount(
                  !fits ? (left == 0 ? 'Agotado' : 'No alcanza') : 'Quedan $left',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: !fits ? Pan.terracota : (selected ? Pan.cacao : Pan.salvia),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medio),
          curve: Motion.curva,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Pan.cacao : Pan.papel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? Pan.cacao : const Color(0xFFEADCC4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? Pan.miel : Pan.canela),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: selected ? Pan.crema : Pan.cacao)),
            ],
          ),
        ),
      );
}

class _PayOption extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PayOption({required this.emoji, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medio),
          curve: Motion.curva,
          height: 92,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF4D6) : Pan.papel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Pan.miel : const Color(0xFFEADCC4), width: selected ? 2 : 1),
            boxShadow: Pan.sombra,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 26, height: 1)),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.15)),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: Motion.of(context, Motion.medio),
                  curve: Motion.rebote,
                  child: const Icon(Icons.check_circle_rounded, color: Pan.caramelo, size: 22),
                ),
              ),
            ],
          ),
        ),
      );
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            for (var i = 0; i < c.maxWidth ~/ 9; i++)
              Container(
                width: 5,
                height: 1.5,
                margin: const EdgeInsets.only(right: 4),
                color: const Color(0xFFE2CFAF),
              ),
          ],
        ),
      );
}
