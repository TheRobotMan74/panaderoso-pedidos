import 'package:material_ui/material_ui.dart';

import '../../logic/demand.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';

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
            return const SkeletonList(count: 2);
          }
          final days = daysSnap.data!;
          final orders = ordersSnap.data!;
          // Días publicados y también días con pedidos (por si se cerró uno con pedidos).
          final dates = {...days.map((d) => d.date), ...orders.map((o) => o.deliveryDate)}.toList()
            ..sort();
          if (dates.isEmpty) {
            return const EmptyState(
              title: 'Sin días próximos',
              message: 'Abre días de entrega en la pestaña "Días" para empezar a recibir pedidos.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final (i, date) in dates.indexed)
                FadeSlideIn(
                  index: i,
                  child: _DayCard(
                    demand: demandForDay(
                      date,
                      orders,
                      slotOrder: days.where((d) => d.date == date).firstOrNull?.slots ?? const [],
                    ),
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
    final maxQty = products.isEmpty
        ? 1
        : demand.totalByProduct.values.reduce((a, b) => a > b ? a : b);
    return PanCard(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(capitalize(dayLabel(demand.date)), style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Stat(value: demand.orders, label: 'pedidos', emoji: '🧾')),
              const SizedBox(width: 10),
              Expanded(child: _Stat(value: demand.pieces, label: 'piezas', emoji: '🥐')),
            ],
          ),
          const SizedBox(height: 14),
          if (products.isEmpty)
            Text('Sin pedidos todavía.', style: theme.textTheme.bodySmall)
          else ...[
            Text('Para hornear', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final p in products)
              _Bar(
                label: p,
                qty: demand.totalByProduct[p]!,
                fraction: demand.totalByProduct[p]! / maxQty,
              ),
            const SizedBox(height: 10),
            Text('Por horario', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                horizontalMargin: 4,
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
                  DataRow(
                    color: const WidgetStatePropertyAll(Color(0xFFFFF4D6)),
                    cells: [
                      const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
                      DataCell(Text('${demand.orders}', style: const TextStyle(fontWeight: FontWeight.w900))),
                      for (final p in products)
                        DataCell(Text('${demand.totalByProduct[p]}',
                            style: const TextStyle(fontWeight: FontWeight.w900))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final String emoji;
  const _Stat({required this.value, required this.label, required this.emoji});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(color: Pan.crema, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: Motion.of(context, const Duration(milliseconds: 800)),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text('${v.round()}',
                  style: const TextStyle(
                      fontFamily: 'Fraunces', fontWeight: FontWeight.w700, fontSize: 26, color: Pan.cacao)),
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// Barra de miel que crece hasta la cantidad a hornear.
class _Bar extends StatelessWidget {
  final String label;
  final int qty;
  final double fraction;
  const _Bar({required this.label, required this.qty, required this.fraction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(productArt(label).$1, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                      Text('$qty',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Pan.tostado)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                              color: const Color(0xFFF3E7D2), borderRadius: BorderRadius.circular(6)),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: fraction),
                          duration: Motion.of(context, const Duration(milliseconds: 900)),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => Container(
                            width: c.maxWidth * v,
                            height: 8,
                            decoration: BoxDecoration(
                                gradient: Pan.gradienteMiel, borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
