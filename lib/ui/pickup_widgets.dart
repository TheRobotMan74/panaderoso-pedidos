import 'package:material_ui/material_ui.dart';

import '../logic/schedule.dart';
import '../models.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Aviso claro para el cliente: ese día no es a domicilio, se entrega en un lugar.
class PickupDayNotice extends StatelessWidget {
  final DeliveryDay day;

  /// En la pantalla de inicio se dice el día; al pedir ya se sabe.
  final bool showDate;
  final EdgeInsetsGeometry margin;
  const PickupDayNotice({super.key, required this.day, this.showDate = true, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final p = day.pickup!;
    final theme = Theme.of(context);
    return PanCard(
      margin: margin,
      color: const Color(0xFFFFF1CF),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📍', style: TextStyle(fontSize: 26, height: 1.1)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showDate
                      ? '${capitalize(dayLabel(day.date))}: entrega en ${p.name}'
                      : 'Entrega en ${p.name}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Estos horarios son solo para entrega en ${p.name}, no a domicilio. '
                  'Te avisamos cuando vayamos en camino y cuando ya estemos ahí.',
                  style: theme.textTheme.bodySmall,
                ),
                if (p.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p.notes,
                      style:
                          theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700, color: Pan.cacao)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Próximos días especiales que se pueden pedir (para la pantalla de inicio).
List<DeliveryDay> upcomingPickupDays(List<DeliveryDay> days, DateTime now) => [
      for (final d in orderableDays(days, now))
        if (d.isPickup) d
    ];
