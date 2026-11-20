import 'package:material_ui/material_ui.dart';

import '../models.dart';

class StatusChip extends StatelessWidget {
  final OrderStatus status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      OrderStatus.recibido => Colors.orange,
      OrderStatus.confirmado => Colors.blue,
      OrderStatus.enCamino => Colors.purple,
      OrderStatus.entregado => Colors.green,
      OrderStatus.cancelado => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(orderStatusLabels[status]!,
          style: TextStyle(color: color.shade800, fontWeight: FontWeight.w600)),
    );
  }
}
