import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../promo_widgets.dart';
import '../status_chip.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tracking_page.dart';

class MyOrdersPage extends StatelessWidget {
  final String uid;

  /// Casa del cliente (para el mapa de pedidos hechos antes de que hubiera mapa).
  final double? homeLat;
  final double? homeLng;

  const MyOrdersPage({super.key, required this.uid, this.homeLat, this.homeLng});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BakeryOrder>>(
      stream: Repo.instance.myOrders(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            title: 'Ups, no cargaron tus pedidos',
            message: 'Revisa tu internet e intenta de nuevo.\n${snap.error}',
          );
        }
        if (!snap.hasData) return const SkeletonList(count: 3);
        final orders = snap.data!;
        if (orders.isEmpty) {
          return const EmptyState(
            title: 'Aún no tienes pedidos',
            message: 'Cuando pidas tu pan, aquí verás cómo va, paso a paso.',
          );
        }
        // Arriba lo que viene (el más próximo primero); abajo, ya sin pasos ni
        // botones, lo entregado, lo cancelado y lo de días que ya pasaron.
        final today = dateKey(DateTime.now());
        bool isPast(BakeryOrder o) => !o.isPending || o.deliveryDate.compareTo(today) < 0;
        final upcoming = orders.where((o) => !isPast(o)).toList()
          ..sort((a, b) {
            final c = a.deliveryDate.compareTo(b.deliveryDate);
            return c != 0 ? c : a.slot.compareTo(b.slot);
          });
        final past = orders.where(isPast).toList()..sort((a, b) => b.deliveryDate.compareTo(a.deliveryDate));
        return StreamBuilder<AppConfig>(
          stream: Repo.instance.config(),
          builder: (context, cfg) {
            final whatsapp = cfg.data?.whatsapp ?? '';
            final children = <Widget>[
              for (final o in upcoming)
                _OrderCard(order: o, homeLat: homeLat, homeLng: homeLng, whatsapp: whatsapp),
              if (past.isNotEmpty) const SectionTitle('Pedidos anteriores'),
              for (final o in past) _OrderCard(order: o, past: true),
            ];
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: children.length,
              itemBuilder: (context, i) => FadeSlideIn(index: i, child: children[i]),
            );
          },
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final BakeryOrder order;
  final double? homeLat;
  final double? homeLng;

  /// WhatsApp de la panadería ('' = sin botón).
  final String whatsapp;

  /// Ya entregado, cancelado o de un día que pasó: solo se ve lo que pidió,
  /// sin pasos ni botones, para que no parezca que sigue en camino.
  final bool past;
  const _OrderCard({required this.order, this.homeLat, this.homeLng, this.whatsapp = '', this.past = false});

  Future<void> _openWhatsApp(BuildContext context) async {
    final o = order;
    final text = 'Hola Panaderoso 🐻, soy ${o.customerName}. Te escribo por mi pedido del '
        '${dayLabel(o.deliveryDate)} (${slotLabel(o.slot, minutes: o.slotMinutes)}).';
    final ok = await launchUrl(whatsAppUrl(whatsapp, text), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp. ¿Lo tienes instalado?')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final theme = Theme.of(context);
    // El día de la entrega se puede ver por dónde va el repartidor.
    final canTrack = !past &&
        o.isPending &&
        (o.status == OrderStatus.enCamino || o.deliveryDate == dateKey(DateTime.now()));
    final isCash = o.paymentMethod == PaymentMethod.efectivo;
    return PanCard(
      margin: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(capitalize(dayLabel(o.deliveryDate)),
                        style: theme.textTheme.titleLarge!.copyWith(fontSize: 20)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 15, color: Pan.canela),
                        const SizedBox(width: 4),
                        Text(slotLabel(o.slot, minutes: o.slotMinutes), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              if (past && o.isPending) const _PastChip() else StatusChip(status: o.status),
            ],
          ),
          if (!past && o.wasMoved && o.isPending) ...[
            const SizedBox(height: 12),
            _MovedNotice(order: o),
          ],
          if (!past && o.status != OrderStatus.cancelado) ...[
            const SizedBox(height: 16),
            OrderProgress(status: o.status),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF4E6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final it in o.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(productArt(it.name).$1, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${it.qty} × ${it.name}', style: theme.textTheme.bodyMedium)),
                        if (it.isGift)
                          GiftTag(kind: it.gift, compact: true)
                        else
                          Text(money(it.total), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                if (o.shippingFee > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Text('🛵', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Envío', style: theme.textTheme.bodyMedium)),
                        Text(money(o.shippingFee), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(isCash ? Icons.payments_rounded : Icons.account_balance_rounded,
                  size: 17, color: Pan.canela),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${isCash ? 'Efectivo' : 'Transferencia'}${o.paymentVerified ? ' · pago verificado ✓' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(money(o.total),
                  style: theme.textTheme.titleLarge!.copyWith(color: Pan.caramelo, fontSize: 19)),
            ],
          ),
          if (!past && whatsapp.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openWhatsApp(context),
                icon: const Icon(Icons.chat_rounded, size: 20),
                label: const Text('Escríbenos por WhatsApp'),
              ),
            ),
          ],
          if (canTrack) ...[
            const SizedBox(height: 12),
            HoneyButton(
              icon: Icons.map_rounded,
              label: 'Ver dónde va mi pedido',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TrackingPage(order: o, homeLat: homeLat, homeLng: homeLng),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// En vez del estado, para un pedido de un día que ya pasó y nunca se marcó entregado.
class _PastChip extends StatelessWidget {
  const _PastChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(color: const Color(0xFFEDE6DC), borderRadius: BorderRadius.circular(20)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 15, color: Color(0xFF7D7064)),
            SizedBox(width: 4),
            Text('Ya pasó',
                style: TextStyle(color: Color(0xFF7D7064), fontWeight: FontWeight.w800, fontSize: 12.5)),
          ],
        ),
      );
}

/// "Cambiamos tu entrega": cuando el dueño movió el día o el horario.
class _MovedNotice extends StatelessWidget {
  final BakeryOrder order;
  const _MovedNotice({required this.order});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final before = '${dayLabel(o.movedFromDate!)}'
        '${o.movedFromSlot == null ? '' : ', ${slotLabel(o.movedFromSlot!, minutes: o.movedFromMinutes)}'}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Pan.cieloClaro,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_calendar_rounded, color: Pan.cielo, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cambiamos tu entrega',
                    style: TextStyle(fontWeight: FontWeight.w800, color: Pan.cielo)),
                const SizedBox(height: 2),
                Text(
                  'Ahora llega el ${dayLabel(o.deliveryDate)}, de ${slotLabel(o.slot, minutes: o.slotMinutes)}. '
                  'Antes era el $before.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Enlace de WhatsApp con mensaje ya escrito. Acepta el número con o sin 52, espacios o guiones.
Uri whatsAppUrl(String number, String text) {
  var digits = number.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) digits = '52$digits';
  return Uri.https('wa.me', '/$digits', {'text': text});
}
