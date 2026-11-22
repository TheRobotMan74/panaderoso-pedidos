import 'package:material_ui/material_ui.dart';

import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Color, fondo e ícono de cada estado del pedido.
(Color, Color, IconData) statusStyle(OrderStatus s) => switch (s) {
      OrderStatus.recibido => (const Color(0xFF9A5B00), Pan.mielClara, Icons.receipt_long_rounded),
      OrderStatus.confirmado => (Pan.cielo, Pan.cieloClaro, Icons.thumb_up_alt_rounded),
      OrderStatus.enCamino => (Pan.ciruela, Pan.ciruelaClara, Icons.delivery_dining_rounded),
      OrderStatus.entregado => (const Color(0xFF3F6B33), Pan.salviaClara, Icons.check_circle_rounded),
      OrderStatus.cancelado => (const Color(0xFF7D7064), const Color(0xFFEDE6DC), Icons.block_rounded),
    };

class StatusChip extends StatelessWidget {
  final OrderStatus status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = statusStyle(status);
    return AnimatedContainer(
      duration: Motion.of(context, Motion.medio),
      curve: Motion.curva,
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == OrderStatus.enCamino)
            PulseDot(color: fg, size: 6)
          else
            Icon(icon, size: 15, color: fg),
          const SizedBox(width: 4),
          Text(orderStatusLabels[status]!,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// Barra de avance del pedido: Recibido → Confirmado → En camino → Entregado.
class OrderProgress extends StatelessWidget {
  final OrderStatus status;
  const OrderProgress({super.key, required this.status});

  static const _steps = [
    OrderStatus.recibido,
    OrderStatus.confirmado,
    OrderStatus.enCamino,
    OrderStatus.entregado,
  ];

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.cancelado) return const SizedBox.shrink();
    final current = _steps.indexOf(status);
    final progress = current / (_steps.length - 1);
    return Column(
      children: [
        SizedBox(
          height: 26,
          child: LayoutBuilder(
            builder: (context, c) {
              const dot = 22.0;
              final track = c.maxWidth - dot;
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: dot / 2,
                    right: dot / 2,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1E4CD),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: dot / 2,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: Motion.of(context, const Duration(milliseconds: 900)),
                      curve: Curves.easeInOutCubic,
                      builder: (context, v, _) => Container(
                        width: track * v,
                        height: 5,
                        decoration: BoxDecoration(
                          gradient: Pan.gradienteMiel,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < _steps.length; i++)
                    Positioned(
                      left: track * i / (_steps.length - 1),
                      child: _StepDot(done: i <= current, now: i == current, size: dot),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: Text(
                  orderStatusLabels[_steps[i]]!,
                  textAlign: i == 0
                      ? TextAlign.left
                      : i == _steps.length - 1
                          ? TextAlign.right
                          : TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == current ? FontWeight.w800 : FontWeight.w600,
                    color: i <= current ? Pan.tostado : const Color(0xFFB8A48B),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool done;
  final bool now;
  final double size;
  const _StepDot({required this.done, required this.now, required this.size});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: Motion.of(context, Motion.lento),
        curve: Motion.rebote,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? Pan.miel : Pan.papel,
          border: Border.all(color: done ? Colors.white : const Color(0xFFE6D6BC), width: 3),
          boxShadow: now
              ? const [BoxShadow(color: Color(0x55F4B41A), blurRadius: 10, spreadRadius: 1)]
              : const [],
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 12, color: Pan.tostado)
            : null,
      );
}
