import 'package:material_ui/material_ui.dart';

import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../status_chip.dart';
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
          return Center(child: Text('No se pudieron cargar tus pedidos.\n${snap.error}'));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snap.data!;
        if (orders.isEmpty) {
          return const Center(child: Text('Aún no tienes pedidos.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          itemBuilder: (context, i) {
            final o = orders[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${dayLabel(o.deliveryDate)}, ${slotLabel(o.slot)}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        StatusChip(status: o.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(o.items.map((i) => '${i.qty} ${i.name}').join(', ')),
                    const SizedBox(height: 4),
                    Text(
                      '${money(o.total)} · '
                      '${o.paymentMethod == PaymentMethod.efectivo ? 'Efectivo' : 'Transferencia'}'
                      '${o.paymentVerified ? ' (pago verificado)' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    // El día de la entrega se puede ver por dónde va el repartidor.
                    if (o.isPending &&
                        (o.status == OrderStatus.enCamino ||
                            o.deliveryDate == dateKey(DateTime.now())))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  TrackingPage(order: o, homeLat: homeLat, homeLng: homeLng),
                            ),
                          ),
                          icon: const Icon(Icons.map),
                          label: const Text('Ver dónde va mi pedido'),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
