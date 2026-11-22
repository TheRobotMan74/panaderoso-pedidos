import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../logic/route.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../status_chip.dart';
import '../theme.dart';
import '../widgets.dart';
import 'day_route_map.dart';

/// Pedidos en vivo, agrupados por día y horario.
/// Dentro de cada horario van en orden de ruta (la más corta desde tu punto de salida),
/// y al final está el mapa del día con las casas numeradas.
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppConfig>(
      stream: Repo.instance.config(),
      builder: (context, cfgSnap) => _orders(context, cfgSnap.data ?? const AppConfig()),
    );
  }

  /// Ordena cada día por horario y, dentro del horario, por ruta.
  static List<BakeryOrder> _routed(List<BakeryOrder> orders, Point? base) {
    final dates = orders.map((o) => o.deliveryDate).toSet().toList()..sort();
    return [
      for (final d in dates)
        ...routeOrder<BakeryOrder>(
          orders.where((o) => o.deliveryDate == d).toList(),
          slot: (o) => o.slot,
          position: (o) => o.hasLocation ? (o.lat!, o.lng!) : null,
          start: base,
        ),
    ];
  }

  Widget _orders(BuildContext context, AppConfig cfg) {
    final Point? base =
        cfg.baseLat != null && cfg.baseLng != null ? (cfg.baseLat!, cfg.baseLng!) : null;
    return StreamBuilder<List<BakeryOrder>>(
      stream: Repo.instance.ordersFrom(dateKey(DateTime.now())),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(title: 'No cargaron los pedidos', message: '${snap.error}');
        }
        if (!snap.hasData) return const SkeletonList(count: 3);
        final orders = _routed(
          snap.data!.where((o) => o.status != OrderStatus.cancelado).toList(),
          base,
        );
        if (orders.isEmpty) {
          return const EmptyState(
            title: 'Todo tranquilo por aquí',
            message: 'No hay pedidos pendientes. Cuando llegue uno, aparece aquí al momento.',
          );
        }
        final children = <Widget>[];
        String? lastDate;
        String? lastSlot;
        var stop = 0;
        for (final o in orders) {
          if (o.deliveryDate != lastDate) {
            lastDate = o.deliveryDate;
            lastSlot = null;
            stop = 0;
            final count = orders.where((x) => x.deliveryDate == o.deliveryDate).length;
            children.add(
              SectionTitle(
                capitalize(dayLabel(o.deliveryDate)),
                trailing: Text(
                  '$count ${count == 1 ? 'pedido' : 'pedidos'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
          }
          if (o.slot != lastSlot) {
            lastSlot = o.slot;
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Pan.harina, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: Pan.tostado),
                          const SizedBox(width: 4),
                          Text(
                            slotLabel(o.slot),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Pan.tostado),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          stop++;
          final daySlots = orders
              .where((x) => x.deliveryDate == o.deliveryDate)
              .map((x) => x.slot)
              .toSet()
              .toList()
            ..sort();
          children.add(_OrderCard(
            key: ValueKey(o.id),
            order: o,
            stop: stop,
            stopColor: colorForSlot(daySlots, o.slot),
          ));
        }
        // Mapa del día más próximo (hoy, o el siguiente día con pedidos).
        final mapDate = orders.first.deliveryDate;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DayRouteMap(
            date: mapDate,
            stops: orders.where((o) => o.deliveryDate == mapDate).toList(),
            base: base,
          ),
        ));
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: children.length,
          itemBuilder: (context, i) => FadeSlideIn(index: i, child: children[i]),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final BakeryOrder order;

  /// Número de parada en la ruta del día.
  final int stop;
  final Color stopColor;
  const _OrderCard({super.key, required this.order, required this.stop, required this.stopColor});

  static const _next = {
    OrderStatus.recibido: (OrderStatus.confirmado, 'Confirmar'),
    OrderStatus.confirmado: (OrderStatus.enCamino, 'Salir a entregar'),
    OrderStatus.enCamino: (OrderStatus.entregado, 'Marcar entregado'),
  };

  Future<void> _showProof(BuildContext context) async {
    final url = await Repo.instance.paymentProofUrl(order.paymentProofPath!);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Captura de ${order.customerName}'),
        content: InteractiveViewer(child: Image.network(url)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          if (!order.paymentVerified)
            FilledButton(
              onPressed: () {
                Repo.instance.updateOrder(order.id, {'paymentVerified': true});
                Navigator.pop(ctx);
              },
              child: const Text('Pago verificado'),
            ),
        ],
      ),
    );
  }

  /// Abre Google Maps con la ruta a la casa del cliente.
  Future<void> _directions() async {
    final o = order;
    final dest = o.hasLocation ? '${o.lat},${o.lng}' : Uri.encodeComponent('${o.address}, México');
    await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar este pedido?'),
        content: Text('Se le avisará a ${order.customerName}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (ok == true) {
      await Repo.instance.updateOrder(order.id, {'status': OrderStatus.cancelado.name});
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final theme = Theme.of(context);
    final next = _next[o.status];
    final isCash = o.paymentMethod == PaymentMethod.efectivo;
    final (accent, _, _) = statusStyle(o.status);
    return PanCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Pan.radio),
        child: Stack(
          children: [
            // Franja de color según el estado (toma el alto de la tarjeta).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(duration: Motion.of(context, Motion.medio), width: 6, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StopBadge(
                        stop: stop,
                        color: o.status == OrderStatus.entregado ? const Color(0xFF9E9E9E) : stopColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(o.customerName, style: theme.textTheme.titleMedium)),
                      StatusChip(status: o.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _line(Icons.place_outlined, o.address, theme.textTheme.bodyMedium!),
                  if (o.addressNotes.isNotEmpty)
                    _line(Icons.sticky_note_2_outlined, o.addressNotes, theme.textTheme.bodySmall!),
                  _line(Icons.phone_outlined, o.phone, theme.textTheme.bodySmall!, selectable: true),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final it in o.items)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4D6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${productArt(it.name).$1} ${it.qty} ${it.name}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                  if (o.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('📝 ${o.notes}', style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        money(o.total),
                        style: theme.textTheme.titleLarge!.copyWith(color: Pan.caramelo, fontSize: 19),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        isCash ? Icons.payments_rounded : Icons.account_balance_rounded,
                        size: 17,
                        color: Pan.canela,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isCash
                              ? (o.cashCollected ? 'Efectivo, cobrado' : 'Efectivo, por cobrar')
                              : (o.paymentVerified
                                    ? 'Transferencia verificada'
                                    : 'Transferencia por revisar'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (next != null)
                        FilledButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Repo.instance.updateOrder(o.id, {'status': next.$1.name});
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          child: Text(next.$2),
                        ),
                      if (o.status != OrderStatus.entregado)
                        OutlinedButton.icon(
                          onPressed: _directions,
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: const Text('Cómo llegar'),
                        ),
                      if (!isCash && o.paymentProofPath != null)
                        OutlinedButton(
                          onPressed: () => _showProof(context),
                          child: const Text('Ver captura'),
                        ),
                      if (isCash && !o.cashCollected)
                        OutlinedButton(
                          onPressed: () => Repo.instance.updateOrder(o.id, {'cashCollected': true}),
                          child: const Text('Cobrado'),
                        ),
                      if (o.status != OrderStatus.entregado)
                        TextButton(
                          onPressed: () => _cancel(context),
                          style: TextButton.styleFrom(foregroundColor: Pan.terracota),
                          child: const Text('Cancelar'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, TextStyle style, {bool selectable = false}) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: Pan.canela),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: selectable ? SelectableText(text, style: style) : Text(text, style: style),
        ),
      ],
    ),
  );
}

/// Circulito con el número de parada (igual al del mapa del día).
class _StopBadge extends StatelessWidget {
  final int stop;
  final Color color;
  const _StopBadge({required this.stop, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          '$stop',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
        ),
      );
}
