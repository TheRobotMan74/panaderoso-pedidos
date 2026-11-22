import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Festejo al mandar el pedido: palomita que se dibuja y chispitas de miel.
Future<void> showOrderPlaced(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: const Color(0x993B2A1E),
    transitionDuration: Motion.of(context, const Duration(milliseconds: 380)),
    pageBuilder: (_, _, _) => const _OrderPlaced(),
    transitionBuilder: (context, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Motion.rebote, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(c), child: child),
      );
    },
  );
}

class _OrderPlaced extends StatefulWidget {
  const _OrderPlaced();

  @override
  State<_OrderPlaced> createState() => _OrderPlacedState();
}

class _OrderPlacedState extends State<_OrderPlaced> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  final _seed = math.Random(7);
  late final _bits = List.generate(26, (_) => _Bit.random(_seed));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.off(context)) {
      _c.value = 1;
    } else if (_c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 310,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
          decoration: BoxDecoration(
            color: Pan.papel,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                height: 120,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => CustomPaint(painter: _CheckPainter(_c.value, _bits)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('¡Pedido enviado!', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Ya lo recibimos. Te avisamos cuando lo confirmemos y cuando vaya en camino.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('¡Gracias!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bit {
  final double angle;
  final double dist;
  final double size;
  final Color color;
  final bool round;
  const _Bit(this.angle, this.dist, this.size, this.color, this.round);

  factory _Bit.random(math.Random r) => _Bit(
        r.nextDouble() * 2 * math.pi,
        44 + r.nextDouble() * 34,
        3 + r.nextDouble() * 4,
        const [Pan.miel, Pan.caramelo, Color(0xFFF7C547), Pan.salvia, Color(0xFFF5B3A6)][r.nextInt(5)],
        r.nextBool(),
      );
}

class _CheckPainter extends CustomPainter {
  final double t;
  final List<_Bit> bits;
  _CheckPainter(this.t, this.bits);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Círculo de miel que crece con rebote.
    final grow = Curves.elasticOut.transform((t / 0.55).clamp(0, 1));
    final r = 38.0 * grow;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = Pan.gradienteMiel.createShader(Rect.fromCircle(center: c, radius: 38)),
    );
    // Palomita que se dibuja.
    final k = Curves.easeOutCubic.transform(((t - 0.3) / 0.4).clamp(0, 1));
    if (k > 0) {
      final p1 = c + const Offset(-15, 1);
      final p2 = c + const Offset(-4, 12);
      final p3 = c + const Offset(17, -11);
      final path = Path()..moveTo(p1.dx, p1.dy);
      final first = (k / 0.4).clamp(0.0, 1.0);
      final a = Offset.lerp(p1, p2, first)!;
      path.lineTo(a.dx, a.dy);
      if (k > 0.4) {
        final b = Offset.lerp(p2, p3, ((k - 0.4) / 0.6).clamp(0.0, 1.0))!;
        path.lineTo(b.dx, b.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Pan.cacao
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    // Chispitas que salen y se desvanecen.
    final s = ((t - 0.15) / 0.85).clamp(0.0, 1.0);
    if (s > 0 && s < 1) {
      final out = Curves.easeOutCubic.transform(s);
      for (final b in bits) {
        final p = c + Offset(math.cos(b.angle), math.sin(b.angle)) * (b.dist * out + 20) + Offset(0, 14 * s * s);
        final paint = Paint()..color = b.color.withValues(alpha: 1 - s);
        if (b.round) {
          canvas.drawCircle(p, b.size / 2, paint);
        } else {
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(b.angle + s * 4);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: b.size * 1.6, height: b.size * 0.8),
                const Radius.circular(2)),
            paint,
          );
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
