import 'package:material_ui/material_ui.dart';

import '../logic/stock.dart';
import 'theme.dart';
import 'widgets.dart';

/// Barrita de cupo en vivo: "Masa de croissant · quedan 12 de 30".
/// Baja sola con cada pedido y sube si se cancela o se borra uno.
class StockMeter extends StatelessWidget {
  final String label;
  final String? detail;
  final int left;
  final int limit;
  const StockMeter({super.key, required this.label, this.detail, required this.left, required this.limit});

  @override
  Widget build(BuildContext context) {
    final frac = limit <= 0 ? 0.0 : (left / limit).clamp(0.0, 1.0);
    final color = left <= 0 ? Pan.terracota : (frac <= 0.2 ? Pan.caramelo : Pan.salvia);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
              const SizedBox(width: 8),
              AnimatedCount(
                left <= 0 ? 'Agotado' : '${remainingText(left)} de $limit',
                alignment: Alignment.centerRight,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color),
              ),
            ],
          ),
          if (detail != null && detail!.isNotEmpty)
            Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: frac),
              duration: Motion.of(context, Motion.lento),
              curve: Motion.curva,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                color: color,
                backgroundColor: Pan.harina,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Letrero grande: "Quedan 40 panes disponibles" con el número que cambia en vivo.
class StockTotal extends StatelessWidget {
  final int left;
  const StockTotal({super.key, required this.left});

  @override
  Widget build(BuildContext context) {
    final soldOut = left <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: soldOut ? const Color(0xFFF7E1DC) : const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(soldOut ? '🧺' : '🥐', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedCount(
              soldOut ? 'Ya no quedan panes' : '${capitalizeFirst(remainingText(left))} disponibles',
              alignment: Alignment.centerLeft,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: soldOut ? Pan.terracota : Pan.tostado,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String capitalizeFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
