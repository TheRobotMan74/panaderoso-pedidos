import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/day_route.dart';
import '../../logic/geo.dart';
import '../../logic/route.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'day_route_map.dart';

/// Acomodar a mano el orden de entrega de un día.
///
/// Se mantiene presionada una parada y se arrastra a su nuevo lugar; el mapa
/// y los kilómetros se actualizan al momento. "Optimizar" vuelve a la ruta que
/// arma la app. Al guardar, la lista de pedidos, el mapa y lo que ve cada
/// cliente ("faltan 2 entregas antes de la tuya") siguen este orden.
class RouteEditorPage extends StatefulWidget {
  final String date;
  final List<BakeryOrder> initial;
  final AppConfig cfg;

  /// true = el orden que llega ya estaba acomodado a mano.
  final bool manual;

  const RouteEditorPage({
    super.key,
    required this.date,
    required this.initial,
    required this.cfg,
    required this.manual,
  });

  @override
  State<RouteEditorPage> createState() => _RouteEditorPageState();
}

class _RouteEditorPageState extends State<RouteEditorPage> {
  late List<BakeryOrder> _route = [...widget.initial];
  late final List<BakeryOrder> _auto = autoRoute(widget.initial, widget.cfg);
  bool _dirty = false;
  bool _saving = false;

  List<String> get _slots => _route.map((o) => o.slot).toSet().toList()..sort();

  bool get _isAuto => _sameOrder(_route, _auto);

  static bool _sameOrder(List<BakeryOrder> a, List<BakeryOrder> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// [to] ya viene ajustado (como si [from] ya no estuviera en la lista).
  void _move(int from, int to) {
    HapticFeedback.selectionClick();
    setState(() {
      final o = _route.removeAt(from);
      _route.insert(to, o);
      _dirty = true;
    });
  }

  void _optimize() {
    HapticFeedback.mediumImpact();
    setState(() {
      _route = [..._auto];
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Si quedó igual que la automática, no se guarda "a mano": así los
      // pedidos que lleguen después también se acomodan solos.
      await Repo.instance.saveRouteOrder(widget.date, _isAuto ? const [] : _route.map((o) => o.id).toList());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _dirty = false;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAuto ? 'Listo: la ruta se acomoda sola ✓' : 'Orden guardado ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar. Intenta de nuevo. ($e)')));
    }
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('El orden que acomodaste se pierde.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir acomodando')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
        ],
      ),
    );
    if (leave == true && mounted) {
      _dirty = false;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = basePoint(widget.cfg);
    final km = dayRouteMeters(_route, widget.cfg);
    final autoKm = dayRouteMeters(_auto, widget.cfg);
    final early = earlyStops<BakeryOrder>(_route, (o) => o.slot);
    final slots = _slots;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Ruta del ${dayLabel(widget.date).split(' ').take(2).join(' ')}')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: PanCard(
                padding: EdgeInsets.zero,
                margin: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Pan.radio),
                  child: DayRouteMap(
                    date: widget.date,
                    stops: _route,
                    base: base,
                    returnToBase: widget.cfg.routeReturn,
                    compact: true,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedCount(
                      '≈ ${distanceLabel(km)}${widget.cfg.routeReturn && base != null ? ' con regreso' : ''}',
                      style: theme.textTheme.titleMedium,
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  if (!_isAuto)
                    Text('Automática: ${distanceLabel(autoKm)}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Mantén presionada una parada y arrástrala a su lugar.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              // SliverReorderableList (y no ReorderableListView) para no meter
              // íconos nuevos a la app: así el cambio llega como mejora, sin APK nueva.
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    sliver: SliverReorderableList(
                      itemCount: _route.length,
                      onReorderItem: _move,
                      proxyDecorator: (child, _, _) => Material(
                        type: MaterialType.transparency,
                        child: Transform.scale(scale: 1.03, child: child),
                      ),
                      itemBuilder: (context, i) {
                        final o = _route[i];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(o.id),
                          index: i,
                          child: _StopRow(
                            order: o,
                            stop: i + 1,
                            color: colorForSlot(slots, o.slot),
                            early: early[i],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving || _isAuto ? null : _optimize,
                        child: const Text('Optimizar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: HoneyButton(
                        label: 'Guardar',
                        icon: Icons.check_rounded,
                        busy: _saving,
                        onPressed: _dirty || (widget.manual && _isAuto) ? _save : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una parada en la lista para acomodar.
class _StopRow extends StatelessWidget {
  final BakeryOrder order;
  final int stop;
  final Color color;
  final bool early;

  const _StopRow({
    required this.order,
    required this.stop,
    required this.color,
    required this.early,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = order.status == OrderStatus.entregado;
    return PanCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: done ? const Color(0xFF9E9E9E) : color, shape: BoxShape.circle),
            child: Text(
              '$stop',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customerName,
                  style: theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  order.address.isEmpty ? 'Sin dirección' : order.address,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      slotLabel(order.slot, minutes: order.slotMinutes),
                      style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700, color: color),
                    ),
                    if (!order.hasLocation) Text('· sin casa en el mapa', style: theme.textTheme.bodySmall),
                    if (done) Text('· entregado', style: theme.textTheme.bodySmall),
                    if (early && !done)
                      Text(
                        '· llegas antes de su horario',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: Pan.terracota,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
