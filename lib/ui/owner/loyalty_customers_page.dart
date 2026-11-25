import 'package:material_ui/material_ui.dart';

import '../../logic/promos.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../promo_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Tarjeta de lealtad de cada cliente: cuántas piezas lleva, cuántos panes
/// gratis ya se le dieron y si ya usó el de bienvenida.
class LoyaltyCustomersPage extends StatefulWidget {
  const LoyaltyCustomersPage({super.key});

  @override
  State<LoyaltyCustomersPage> createState() => _LoyaltyCustomersPageState();
}

class _LoyaltyCustomersPageState extends State<LoyaltyCustomersPage> {
  final _search = TextEditingController();
  late final _orders = Repo.instance.allOrders();
  late final _config = Repo.instance.config();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tarjetas de lealtad')),
      body: StreamBuilder<AppConfig>(
        stream: _config,
        builder: (context, cfgSnap) => StreamBuilder<List<BakeryOrder>>(
          stream: _orders,
          builder: (context, snap) {
            if (snap.hasError) {
              return const EmptyState(
                title: 'No se pudieron cargar',
                message: 'Revisa tu conexión e intenta de nuevo.',
              );
            }
            if (!snap.hasData || !cfgSnap.hasData) return const SkeletonList(count: 5);
            final rules = cfgSnap.data!.promos;
            final goal = rules.loyaltyGoal;
            final all = customersLoyalty(snap.data!, rules);
            if (all.isEmpty) {
              return const EmptyState(
                title: 'Todavía no hay clientes',
                message: 'Aquí vas a ver la tarjeta de cada quien cuando empiecen a pedir.',
              );
            }
            return ListenableBuilder(
              listenable: _search,
              builder: (context, _) {
                final q = _search.text.trim().toLowerCase();
                final list = q.isEmpty
                    ? all
                    : all.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q)).toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      rules.loyaltyProductIds.isEmpty
                          ? 'Solo suman chocolatines y croissants comprados desde que salió la promoción. '
                              '1 pan gratis cada $goal. Los panes que ya se regalaron no se quitan.'
                          : 'Solo suman los panes que elegiste en Ajustes, comprados desde que salió '
                              'la promoción. 1 pan gratis cada $goal. Los que ya se regalaron no se quitan.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Buscar por nombre o teléfono',
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final c in list) _CustomerCard(c: c, goal: goal),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final CustomerLoyalty c;
  final int goal;
  const _CustomerCard({required this.c, required this.goal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = c.card.pending;
    final done = c.card.progress;
    return PanCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.name.isEmpty ? 'Sin nombre' : c.name, style: theme.textTheme.titleMedium),
              ),
              Text('$done de $goal', style: theme.textTheme.titleSmall!.copyWith(color: Pan.caramelo)),
            ],
          ),
          if (c.phone.isNotEmpty) Text(c.phone, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          LoyaltyDots(done: done, goal: goal),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip('${c.card.pieces} ${c.card.pieces == 1 ? 'pieza suma' : 'piezas suman'}'),
              _Chip('${c.orders} pedido${c.orders == 1 ? '' : 's'}'),
              if (c.loyaltyGiven > 0) _Chip('🎁 ${c.loyaltyGiven} gratis por tarjeta', green: true),
              if (pending > 0) _Chip('Le toca $pending en su siguiente pedido', green: true),
              _Chip(c.welcomeUsed ? '🎁 Ya usó la bienvenida' : 'Sin bienvenida', green: c.welcomeUsed),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool green;
  const _Chip(this.text, {this.green = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: green ? Pan.salviaClara : const Color(0xFFFFF4D6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: green ? const Color(0xFF3F6B33) : Pan.tostado,
          ),
        ),
      );
}
