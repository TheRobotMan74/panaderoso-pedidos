import 'package:material_ui/material_ui.dart';

import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../status_chip.dart';

/// Pedidos en vivo, agrupados por día y horario.
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BakeryOrder>>(
      stream: Repo.instance.ordersFrom(dateKey(DateTime.now())),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snap.data!.where((o) => o.status != OrderStatus.cancelado).toList()
          ..sort((a, b) {
            final c = a.deliveryDate.compareTo(b.deliveryDate);
            return c != 0 ? c : a.slot.compareTo(b.slot);
          });
        if (orders.isEmpty) {
          return const Center(child: Text('No hay pedidos pendientes.'));
        }
        final children = <Widget>[];
        String? lastDate;
        String? lastSlot;
        for (final o in orders) {
          if (o.deliveryDate != lastDate) {
            lastDate = o.deliveryDate;
            lastSlot = null;
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(dayLabel(o.deliveryDate),
                  style: Theme.of(context).textTheme.titleLarge),
            ));
          }
          if (o.slot != lastSlot) {
            lastSlot = o.slot;
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(slotLabel(o.slot), style: Theme.of(context).textTheme.titleSmall),
            ));
          }
          children.add(_OrderCard(order: o));
        }
        return ListView(padding: const EdgeInsets.all(12), children: children);
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final BakeryOrder order;
  const _OrderCard({required this.order});

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(o.customerName, style: theme.textTheme.titleMedium)),
                StatusChip(status: o.status),
              ],
            ),
            Text(o.address),
            if (o.addressNotes.isNotEmpty) Text(o.addressNotes, style: theme.textTheme.bodySmall),
            SelectableText('Tel. ${o.phone}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(o.items.map((i) => '${i.qty} ${i.name}').join(', ')),
            if (o.notes.isNotEmpty) Text('Nota: ${o.notes}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(money(o.total), style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Icon(isCash ? Icons.payments : Icons.account_balance, size: 18),
                const SizedBox(width: 4),
                Text(isCash
                    ? (o.cashCollected ? 'Efectivo, cobrado' : 'Efectivo, por cobrar')
                    : (o.paymentVerified ? 'Transferencia verificada' : 'Transferencia por revisar')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (next != null)
                  FilledButton(
                    onPressed: () => Repo.instance.updateOrder(o.id, {'status': next.$1.name}),
                    child: Text(next.$2),
                  ),
                if (!isCash && o.paymentProofPath != null)
                  OutlinedButton(onPressed: () => _showProof(context), child: const Text('Ver captura')),
                if (isCash && !o.cashCollected)
                  OutlinedButton(
                    onPressed: () => Repo.instance.updateOrder(o.id, {'cashCollected': true}),
                    child: const Text('Cobrado'),
                  ),
                if (o.status != OrderStatus.entregado)
                  TextButton(onPressed: () => _cancel(context), child: const Text('Cancelar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
