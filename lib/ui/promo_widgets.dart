import 'package:material_ui/material_ui.dart';

import '../logic/promos.dart';
import '../models.dart';
import '../services/repo.dart';
import 'theme.dart';
import 'widgets.dart';

/// Etiqueta verde "Gratis" para los panes regalados.
class GiftTag extends StatelessWidget {
  final String? kind;
  final bool compact;
  const GiftTag({super.key, this.kind, this.compact = false});

  static String label(String? kind) => switch (kind) {
        giftWelcome => 'Bienvenida',
        giftLoyalty => 'Tarjeta',
        _ => 'Gratis',
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: compact ? 2 : 3),
        decoration: BoxDecoration(
          color: Pan.salviaClara,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          compact ? '🎁 ${label(kind)}' : '🎁 Gratis · ${label(kind)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 11 : 12,
            color: const Color(0xFF3F6B33),
          ),
        ),
      );
}

/// Tarjeta de lealtad del cliente: "7 de 10 piezas", con un punto por pieza.
/// También avisa del pan de bienvenida si todavía no ha pedido.
/// No se muestra nada si el dueño apagó las dos promociones.
class LoyaltyCardView extends StatelessWidget {
  final String uid;
  const LoyaltyCardView({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppConfig>(
      stream: Repo.instance.config(),
      builder: (context, cfgSnap) => StreamBuilder<List<Product>>(
        stream: Repo.instance.products(),
        builder: (context, prodSnap) => StreamBuilder<List<BakeryOrder>>(
          stream: Repo.instance.myOrdersAll(uid),
          builder: (context, ordersSnap) {
            final rules = cfgSnap.data?.promos;
            final gift = rules == null ? null : giftProduct(rules, prodSnap.data ?? const []);
            final orders = ordersSnap.data;
            Widget child = const SizedBox(width: double.infinity);
            if (rules != null && gift != null && orders != null) {
              final welcome = rules.welcomeEnabled && isFirstOrder(orders);
              if (welcome || rules.loyaltyEnabled) {
                child = _card(context, rules, gift, orders, welcome);
              }
            }
            return AnimatedSize(
              duration: Motion.of(context, Motion.medio),
              curve: Motion.curva,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
        ),
      ),
    );
  }

  Widget _card(BuildContext context, PromoRules rules, Product gift, List<BakeryOrder> orders, bool welcome) {
    final theme = Theme.of(context);
    final card = LoyaltyCard.from(orders);
    final goal = rules.loyaltyGoal;
    final done = card.progress(goal);
    final pending = card.pending(goal);
    final name = gift.name;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: PanCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (welcome)
              Text(
                '🎁 Tu primer pedido a domicilio de ${rules.welcomeMinPieces} piezas o más lleva 1 $name de regalo',
                style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w800, color: Pan.salvia),
              ),
            if (welcome && rules.loyaltyEnabled) const SizedBox(height: 10),
            if (rules.loyaltyEnabled) ...[
              Row(
                children: [
                  Expanded(
                    child: Text('Tarjeta de lealtad',
                        style: theme.textTheme.titleSmall!.copyWith(color: Pan.tostado)),
                  ),
                  Text('$done de $goal',
                      style: theme.textTheme.titleSmall!.copyWith(color: Pan.caramelo)),
                ],
              ),
              const SizedBox(height: 8),
              LoyaltyDots(done: done, goal: goal),
              const SizedBox(height: 8),
              Text(
                pending > 0
                    ? '¡Ya te ganaste $pending $name! Va gratis en tu siguiente pedido.'
                    : 'Cada $goal piezas, 1 $name gratis. Te faltan ${card.missing(goal)}.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Un puntito por pieza: los llenos son las que ya lleva.
class LoyaltyDots extends StatelessWidget {
  final int done;
  final int goal;
  const LoyaltyDots({super.key, required this.done, required this.goal});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = 5.0;
        final size = ((c.maxWidth - gap * (goal - 1)) / goal).clamp(6.0, 22.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < goal; i++)
              AnimatedContainer(
                duration: Motion.of(context, Motion.medio),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < done ? Pan.miel : Pan.harina,
                  border: i == goal - 1 ? Border.all(color: Pan.caramelo, width: 1.5) : null,
                ),
              ),
          ],
        );
      });
}
