import 'package:material_ui/material_ui.dart';

import '../../logic/demand.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';

/// Cuántos pedidos y piezas hay por día y por horario, para planear las charolas.
class DemandPage extends StatelessWidget {
  const DemandPage({super.key});

  @override
  Widget build(BuildContext context) {
    final today = dateKey(DateTime.now());
    return StreamBuilder<List<DeliveryDay>>(
      stream: Repo.instance.deliveryDays(fromDate: today),
      builder: (context, daysSnap) => StreamBuilder<List<BakeryOrder>>(
        stream: Repo.instance.ordersFrom(today),
        builder: (context, ordersSnap) {
          if (!daysSnap.hasData || !ordersSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final days = daysSnap.data!;
          final orders = ordersSnap.data!;
          // Días publicados y también días con pedidos (por si se cerró uno con pedidos).
          final dates = {...days.map((d) => d.date), ...orders.map((o) => o.deliveryDate)}.toList()
            ..sort();
          if (dates.isEmpty) {
            return const Center(child: Text('No hay días de entrega próximos.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final date in dates)
                _DayCard(
                  demand: demandForDay(
                    date,
                    orders,
                    slotOrder: days.where((d) => d.date == date).firstOrNull?.slots ?? const [],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DayDemand demand;
  const _DayCard({required this.demand});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = demand.totalByProduct.keys.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dayLabel(demand.date), style: theme.textTheme.titleLarge),
            Text('${demand.orders} pedidos · ${demand.pieces} piezas'),
            const SizedBox(height: 8),
            if (products.isEmpty)
              const Text('Sin pedidos todavía.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 40,
                  columns: [
                    const DataColumn(label: Text('Horario')),
                    const DataColumn(label: Text('Pedidos'), numeric: true),
                    for (final p in products) DataColumn(label: Text(p), numeric: true),
                  ],
                  rows: [
                    for (final s in demand.slots)
                      DataRow(cells: [
                        DataCell(Text(slotLabel(s.slot))),
                        DataCell(Text('${s.orders}')),
                        for (final p in products) DataCell(Text('${s.piecesByProduct[p] ?? 0}')),
                      ]),
                    DataRow(cells: [
                      const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text('${demand.orders}',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      for (final p in products)
                        DataCell(Text('${demand.totalByProduct[p]}',
                            style: const TextStyle(fontWeight: FontWeight.bold))),
                    ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
