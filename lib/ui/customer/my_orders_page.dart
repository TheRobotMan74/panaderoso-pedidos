import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../logic/feedback.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../feedback_widgets.dart';
import '../format.dart';
import '../product_image.dart';
import '../promo_widgets.dart';
import '../status_chip.dart';
import '../theme.dart';
import '../widgets.dart';
import 'addresses.dart';
import 'tracking_page.dart';

class MyOrdersPage extends StatefulWidget {
  final String uid;

  /// Casa del cliente (para el mapa de pedidos hechos antes de que hubiera mapa).
  final double? homeLat;
  final double? homeLng;

  const MyOrdersPage({super.key, required this.uid, this.homeLat, this.homeLng});

  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> {
  late final _orders = Repo.instance.myOrders(widget.uid);
  late final _reviews = Repo.instance.myReviews(widget.uid);
  late final _days = Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final homeLat = widget.homeLat, homeLng = widget.homeLng;
    return StreamBuilder<List<BakeryOrder>>(
      stream: _orders,
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
        return StreamBuilder<List<Review>>(
          stream: _reviews,
          builder: (context, reviewsSnap) => StreamBuilder<List<DeliveryDay>>(
            stream: _days,
            builder: (context, daysSnap) => StreamBuilder<AppConfig>(
            stream: Repo.instance.config(),
            builder: (context, cfg) {
            // Días en que ya salió el reparto: ahí ya no se cambia la dirección.
            final closed = {for (final d in daysSnap.data ?? const <DeliveryDay>[]) if (d.closed) d.date};
            final whatsapp = cfg.data?.whatsapp ?? '';
            final reviews = {for (final r in reviewsSnap.data ?? const <Review>[]) r.orderId: r};
            final now = DateTime.now();
            final children = <Widget>[
              for (final o in upcoming)
                _OrderCard(
                  order: o,
                  homeLat: homeLat,
                  homeLng: homeLng,
                  whatsapp: whatsapp,
                  config: cfg.data,
                  // Se puede cambiar a dónde llega mientras no salga el reparto de ese día.
                  canChangeAddress: daysSnap.hasData &&
                      !closed.contains(o.deliveryDate) &&
                      !o.isPickup &&
                      (o.status == OrderStatus.recibido || o.status == OrderStatus.confirmado),
                ),
              if (past.isNotEmpty) const SectionTitle('Pedidos anteriores'),
              for (final o in past)
                _OrderCard(
                  order: o,
                  past: true,
                  // Mientras cargan las reseñas no se ofrece calificar (para no duplicar).
                  canReview: reviewsSnap.hasData && canReview(o, now),
                  review: reviews[o.id],
                ),
            ];
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: children.length,
              itemBuilder: (context, i) => FadeSlideIn(index: i, child: children[i]),
            );
            },
          ),
          ),
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

  /// Ya se puede calificar (entregado o de un día que pasó).
  final bool canReview;

  /// Su reseña, si ya lo calificó.
  final Review? review;

  /// Todavía se puede cambiar a qué dirección se entrega.
  final bool canChangeAddress;

  /// Para calcular el envío a la dirección nueva.
  final AppConfig? config;
  const _OrderCard({
    required this.order,
    this.homeLat,
    this.homeLng,
    this.whatsapp = '',
    this.past = false,
    this.canReview = false,
    this.review,
    this.canChangeAddress = false,
    this.config,
  });

  Future<void> _changeAddress(BuildContext context) async {
    final o = order;
    final current = SavedAddress(id: '', label: '', address: o.address, lat: o.lat, lng: o.lng);
    final user = await Repo.instance.userStream(o.customerId).first;
    if (!context.mounted) return;
    final selectedId = user?.addresses
        .where((a) => current.sameAs(address: a.address, lat: a.lat, lng: a.lng))
        .firstOrNull
        ?.id;
    final a = await pickAddress(
      context,
      uid: o.customerId,
      selectedId: selectedId,
      title: '¿A dónde llevamos este pedido?',
    );
    if (a == null || !context.mounted) return;
    if (a.sameAs(address: o.address, lat: o.lat, lng: o.lng) && a.notes == o.addressNotes) return;

    // Cuánto queda el envío (el servidor hace la misma cuenta).
    final cfg = config;
    final newFee = cfg == null
        ? o.shippingFee
        : cfg.shipping.feeForTrip(
            baseLat: cfg.baseLat,
            baseLng: cfg.baseLng,
            homeLat: a.lat,
            homeLng: a.lng,
            pieces: o.loyaltyPieces ?? o.paidPieces,
          );
    final diff = newFee - o.shippingFee;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('¿Llevarlo a "${a.label}"?'),
        content: Text([
          a.address,
          if (diff != 0) 'El envío cambia de ${money(o.shippingFee.toDouble())} a ${money(newFee.toDouble())}.',
          if (diff > 0 && o.paymentMethod == PaymentMethod.transferencia)
            'Como ya pagaste por transferencia, la diferencia (${money(diff.toDouble())}) se paga al recibir.',
          if (diff < 0 && o.paymentMethod == PaymentMethod.transferencia)
            'Como ya pagaste por transferencia, Panaderoso te ajusta la diferencia (${money(-diff.toDouble())}).',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, cambiar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Repo.instance.changeOrderAddress(o.id, a);
      messenger.showSnackBar(SnackBar(content: Text('Listo, lo llevamos a "${a.label}" 🐻')));
    } on RejectedByServer catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo cambiar la dirección. Intenta de nuevo. ($e)')));
    }
  }

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
        (o.status == OrderStatus.enCamino || dayDateOf(o.deliveryDate) == dateKey(DateTime.now()));
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
          if (!past && o.address.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 17, color: Pan.canela),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(o.address,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ),
                if (canChangeAddress)
                  TextButton(onPressed: () => _changeAddress(context), child: const Text('Cambiar')),
              ],
            ),
          ],
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
          if (review != null) ...[
            const SizedBox(height: 8),
            _MyReview(review: review!, onEdit: () => showReviewSheet(context, order: o, existing: review)),
          ] else if (canReview) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showReviewSheet(context, order: o),
                icon: const Icon(Icons.star_rounded, size: 20),
                label: const Text('Calificar este pedido'),
              ),
            ),
          ],
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

/// "Tu reseña ★★★★★" debajo de un pedido ya calificado.
class _MyReview extends StatelessWidget {
  final Review review;
  final VoidCallback onEdit;
  const _MyReview({required this.review, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = review;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: Pan.mielClara.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (r.photoPath != null) ...[
            ReviewPhoto(path: r.photoPath!, size: 48),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Tu reseña ', style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w800)),
                    StarsView(rating: r.rating, size: 16),
                  ],
                ),
                if (r.comment.isNotEmpty)
                  Text(r.comment, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Cambiar')),
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
