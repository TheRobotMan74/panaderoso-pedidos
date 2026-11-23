import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../logic/archive.dart';
import '../../logic/day_route.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../fold_memory.dart';
import '../format.dart';
import '../product_image.dart';
import '../promo_widgets.dart';
import '../status_chip.dart';
import '../theme.dart';
import '../widgets.dart';
import 'day_route_map.dart';
import 'history_page.dart';
import 'route_editor_page.dart';

/// Pedidos en vivo, agrupados por día y horario.
/// Cada día va en orden de ruta: la que acomodaste a mano, o si no, la más corta
/// respetando horarios. Al final está el mapa del día con las casas numeradas
/// y el botón para cambiar el orden.
/// Hasta abajo: los cancelados (plegados) y el botón del Historial, donde se
/// archivan los días ya repartidos (ver logic/archive.dart) con lo vendido.
/// Con "Seleccionar varios" se pueden borrar muchos de un jalón (por ejemplo, los de prueba).
/// Cada día y cada horario se pliegan tocando su encabezado (se recuerda en el
/// celular). Empiezan abiertos el día más próximo y sus horarios con algo
/// pendiente; los días siguientes y los horarios ya entregados, plegados.
/// Mientras se selecciona para borrar, todo se abre, para ver qué se borra.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  /// Pedidos palomeados para borrar. Null = no se está seleccionando.
  Set<String>? _selected;
  bool _deleting = false;

  bool get _selecting => _selected != null;

  /// Días de entrega (para el orden de ruta que se haya guardado a mano).
  late final Stream<List<DeliveryDay>> _days =
      Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now()));

  /// Clientes con las notificaciones apagadas (no les llegan los avisos).
  Set<String> _noPush = const {};
  StreamSubscription<Set<String>>? _noPushSub;

  @override
  void initState() {
    super.initState();
    FoldMemory.changes.addListener(_refresh);
    _noPushSub = Repo.instance.customersWithoutPush().listen((ids) {
      if (mounted) setState(() => _noPush = ids);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    FoldMemory.changes.removeListener(_refresh);
    _noPushSub?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      final s = _selected!;
      if (!s.remove(id)) s.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppConfig>(
      stream: Repo.instance.config(),
      builder: (context, cfgSnap) => StreamBuilder<List<DeliveryDay>>(
        stream: _days,
        builder: (context, daysSnap) => _orders(
          context,
          cfgSnap.data ?? const AppConfig(),
          {for (final d in daysSnap.data ?? const <DeliveryDay>[]) d.date: d},
          daysLoaded: daysSnap.hasData,
        ),
      ),
    );
  }

  /// Ordena cada día por ruta (la acomodada a mano, o la que arma la app).
  static List<BakeryOrder> _routed(List<BakeryOrder> orders, AppConfig cfg, Map<String, DeliveryDay> days) {
    final dates = orders.map((o) => o.deliveryDate).toSet().toList()..sort();
    return [
      for (final d in dates)
        ...dayRoute(orders.where((o) => o.deliveryDate == d).toList(), cfg, day: days[d]),
    ];
  }

  void _editRoute(String date, List<BakeryOrder> route, AppConfig cfg, bool manual) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RouteEditorPage(date: date, initial: route, cfg: cfg, manual: manual),
    ));
  }

  Future<void> _deleteSelected(List<BakeryOrder> all) async {
    final ids = [for (final o in all) if (_selected!.contains(o.id)) o.id];
    if (ids.isEmpty) return;
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: Pan.terracota, size: 32),
        title: Text(n == 1 ? '¿Eliminar 1 pedido?' : '¿Eliminar $n pedidos?'),
        content: Text(
          '${n == 1 ? 'Se borra' : 'Se borran'} para siempre, también del celular de cada cliente. '
          'Sus panes vuelven al cupo del día.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Pan.terracota),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(n == 1 ? 'Sí, eliminar' : 'Sí, eliminar $n'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _deleting = true);
    try {
      await Repo.instance.deleteOrders(ids);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _selected = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 1 ? 'Pedido eliminado ✓' : '$n pedidos eliminados ✓'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron eliminar. Intenta de nuevo. ($e)')),
      );
    }
  }

  void _openHistory() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const HistoryPage()));

  Widget _orders(BuildContext context, AppConfig cfg, Map<String, DeliveryDay> days, {required bool daysLoaded}) {
    final base = basePoint(cfg);
    final now = DateTime.now();
    final today = dateKey(now);
    // También trae los de la última semana, para el botón del Historial.
    final since = dateKey(DateTime(now.year, now.month, now.day - 7));
    return StreamBuilder<List<BakeryOrder>>(
      stream: Repo.instance.ordersFrom(since),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(title: 'No cargaron los pedidos', message: '${snap.error}');
        }
        if (!snap.hasData) return const SkeletonList(count: 3);
        final fetched = snap.data!;
        // Días ya repartidos (o que ya pasaron): sus pedidos se van al Historial.
        final finished = finishedDates(fetched, today: today, days: days, daysLoaded: daysLoaded);
        final archived = fetched.where((o) => finished.contains(o.deliveryDate)).toList();
        final orders = _routed(
          fetched
              .where((o) =>
                  o.status != OrderStatus.cancelado &&
                  o.deliveryDate.compareTo(today) >= 0 &&
                  !finished.contains(o.deliveryDate))
              .toList(),
          cfg,
          days,
        );
        final cancelled = fetched
            .where((o) => o.status == OrderStatus.cancelado && o.deliveryDate.compareTo(today) >= 0)
            .toList()
          ..sort((a, b) => b.deliveryDate.compareTo(a.deliveryDate));
        // Lo que se puede palomear para borrar: solo lo que se ve aquí.
        final all = [...orders, ...cancelled];
        final todayDone = finished.contains(today);
        if (orders.isEmpty && cancelled.isEmpty) {
          return EmptyState(
            title: todayDone ? '¡Listo, todo entregado! 🎉' : 'Todo tranquilo por aquí',
            message: todayDone
                ? 'Los pedidos de hoy ya se guardaron en el Historial, con lo que vendiste.'
                : 'No hay pedidos pendientes. Cuando llegue uno, aparece aquí al momento.',
            action: OutlinedButton.icon(
              onPressed: _openHistory,
              icon: const Icon(Icons.inventory_2_rounded),
              label: const Text('Ver Historial'),
            ),
          );
        }
        final selected = _selected ?? const <String>{};
        final picked = all.where((o) => selected.contains(o.id)).length;

        final children = <Widget>[
          _SelectHeader(
            selecting: _selecting,
            allPicked: picked == all.length,
            onStart: () => setState(() => _selected = {}),
            onAll: () => setState(() => _selected = picked == all.length ? {} : all.map((o) => o.id).toSet()),
          ),
        ];
        String? lastDate;
        String? lastSlot;
        var stop = 0;
        var dayOpen = true;
        var slotOpen = true;
        final firstDate = orders.isEmpty ? null : orders.first.deliveryDate;
        for (final o in orders) {
          if (o.deliveryDate != lastDate) {
            lastDate = o.deliveryDate;
            lastSlot = null;
            stop = 0;
            final dayOrders = orders.where((x) => x.deliveryDate == o.deliveryDate).toList();
            final count = dayOrders.length;
            final done = dayOrders.where((x) => x.status == OrderStatus.entregado).length;
            final key = 'pedidos|${o.deliveryDate}';
            dayOpen = _selecting || FoldMemory.isOpen(key, byDefault: o.deliveryDate == firstDate);
            final open = dayOpen;
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FoldHeader(
                  open: open,
                  onTap: _selecting ? null : () => FoldMemory.set(key, !open),
                  semanticsLabel: open ? 'Plegar día' : 'Abrir día',
                  padding: const EdgeInsets.fromLTRB(0, 6, 4, 6),
                  child: SectionTitle(
                    capitalize(dayLabel(o.deliveryDate)),
                    padding: const EdgeInsets.only(left: 4),
                    trailing: Text(
                      '$count ${count == 1 ? 'pedido' : 'pedidos'}'
                      '${done > 0 ? ' · $done ✓' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            );
          }
          if (o.slot != lastSlot) {
            lastSlot = o.slot;
            final slotOrders =
                orders.where((x) => x.deliveryDate == o.deliveryDate && x.slot == o.slot).toList();
            final allDone = slotOrders.every((x) => x.status == OrderStatus.entregado);
            final key = 'pedidos|${o.deliveryDate}|${o.slot}';
            slotOpen = _selecting || FoldMemory.isOpen(key, byDefault: !allDone);
            final open = slotOpen;
            final n = slotOrders.length;
            if (dayOpen) {
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
                child: FoldHeader(
                  open: open,
                  onTap: _selecting ? null : () => FoldMemory.set(key, !open),
                  semanticsLabel: open ? 'Plegar horario' : 'Abrir horario',
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Pan.harina, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: Pan.tostado),
                          const SizedBox(width: 4),
                          Text(
                            slotLabel(o.slot, minutes: o.slotMinutes),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Pan.tostado),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      allDone
                          ? '$n ${n == 1 ? 'entregado' : 'entregados'} ✓'
                          : '$n ${n == 1 ? 'pedido' : 'pedidos'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                ),
              ),
            );
            }
          }
          stop++;
          // Plegado: no se dibuja, pero cuenta para el número de parada.
          if (!dayOpen || !slotOpen) continue;
          final daySlots = orders
              .where((x) => x.deliveryDate == o.deliveryDate)
              .map((x) => x.slot)
              .toSet()
              .toList()
            ..sort();
          children.add(_OrderCard(
            key: ValueKey(o.id),
            order: o,
            stop: stop,
            stopColor: colorForSlot(daySlots, o.slot),
            selecting: _selecting,
            selected: selected.contains(o.id),
            onToggle: () => _toggle(o.id),
            noPush: o.isPending && _noPush.contains(o.customerId),
          ));
        }
        if (orders.isEmpty) {
          children.add(const Padding(
            padding: EdgeInsets.fromLTRB(8, 24, 8, 0),
            child: Text('No hay pedidos pendientes.', textAlign: TextAlign.center),
          ));
        } else if (!_selecting) {
          // Mapa del día más próximo (hoy, o el siguiente día con pedidos).
          final mapDate = orders.first.deliveryDate;
          final stops = orders.where((o) => o.deliveryDate == mapDate).toList();
          final manual = days[mapDate]?.routeOrder.isNotEmpty ?? false;
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DayRouteMap(
              date: mapDate,
              stops: stops,
              base: base,
              returnToBase: cfg.routeReturn,
              manual: manual,
              onEdit: () => _editRoute(mapDate, stops, cfg, manual),
            ),
          ));
        }
        if (cancelled.isNotEmpty) {
          children.add(_FoldedSection(
            icon: Icons.block_rounded,
            title: 'Cancelados (${cancelled.length})',
            subtitle: 'Puedes eliminarlos para que ya no salgan',
            orders: cancelled,
            selecting: _selecting,
            selected: selected,
            onToggle: _toggle,
          ));
        }
        if (!_selecting) {
          children.add(_HistoryLink(recent: archived, onTap: _openHistory));
        }
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: children.length,
                itemBuilder: (context, i) => FadeSlideIn(index: i, child: children[i]),
              ),
            ),
            AnimatedSize(
              duration: Motion.of(context, Motion.medio),
              curve: Motion.curva,
              alignment: Alignment.bottomCenter,
              child: _selecting
                  ? _DeleteBar(
                      count: picked,
                      busy: _deleting,
                      onCancel: () => setState(() => _selected = null),
                      onDelete: () => _deleteSelected(all),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}

/// Arriba de la lista: "Seleccionar varios" o, ya seleccionando, "Todos".
class _SelectHeader extends StatelessWidget {
  final bool selecting;
  final bool allPicked;
  final VoidCallback onStart;
  final VoidCallback onAll;
  const _SelectHeader({
    required this.selecting,
    required this.allPicked,
    required this.onStart,
    required this.onAll,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.rapido),
                child: selecting
                    ? Text(
                        'Toca los pedidos que quieras borrar',
                        key: const ValueKey('sel'),
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700),
                      )
                    : const SizedBox.shrink(key: ValueKey('nada')),
              ),
            ),
            TextButton.icon(
              onPressed: selecting ? onAll : onStart,
              icon: Icon(selecting
                  ? (allPicked ? Icons.remove_done_rounded : Icons.done_all_rounded)
                  : Icons.checklist_rounded),
              label: Text(selecting ? (allPicked ? 'Ninguno' : 'Todos') : 'Seleccionar varios'),
            ),
          ],
        ),
      );
}

/// Barra de abajo mientras se seleccionan pedidos para borrar.
class _DeleteBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  const _DeleteBar({required this.count, required this.busy, required this.onCancel, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: Pan.papel,
          boxShadow: [BoxShadow(color: Color(0x1F7A4A12), blurRadius: 16, offset: Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              TextButton(onPressed: busy ? null : onCancel, child: const Text('Cancelar')),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Pan.terracota,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: count == 0 || busy ? null : onDelete,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Icon(Icons.delete_rounded),
                  label: AnimatedCount(
                    count == 0
                        ? 'Elige pedidos'
                        : (count == 1 ? 'Eliminar 1 pedido' : 'Eliminar $count pedidos'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Palomita para seleccionar un pedido.
class _Check extends StatelessWidget {
  final bool selected;
  const _Check({required this.selected});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.of(context, Motion.rapido),
        transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
        child: Icon(
          selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          key: ValueKey(selected),
          size: 26,
          color: selected ? Pan.terracota : Pan.canela,
        ),
      );
}

class _OrderCard extends StatelessWidget {
  final BakeryOrder order;

  /// Número de parada en la ruta del día.
  final int stop;
  final Color stopColor;

  /// Modo "Seleccionar varios": tocar la tarjeta la palomea.
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;

  /// El cliente tiene apagadas las notificaciones.
  final bool noPush;

  const _OrderCard({
    super.key,
    required this.order,
    required this.stop,
    required this.stopColor,
    this.selecting = false,
    this.selected = false,
    required this.onToggle,
    this.noPush = false,
  });

  static const _next = {
    OrderStatus.recibido: (OrderStatus.confirmado, 'Confirmar'),
    OrderStatus.confirmado: (OrderStatus.enCamino, 'Salir a entregar'),
    OrderStatus.enCamino: (OrderStatus.entregado, 'Marcar entregado'),
  };

  Future<void> _showProof(BuildContext context) async {
    final url = await Repo.instance.paymentProofUrl(order.paymentProofPath!);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Captura de ${order.customerName}'),
        content: InteractiveViewer(child: Image.network(url)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          if (!order.paymentVerified)
            FilledButton(
              onPressed: () {
                Repo.instance.updateOrder(order.id, {'paymentVerified': true});
                Navigator.pop(ctx);
              },
              child: const Text('Pago verificado'),
            ),
        ],
      ),
    );
  }

  /// Abre Google Maps con la ruta a la casa del cliente.
  Future<void> _directions() async {
    final o = order;
    final dest = o.hasLocation ? '${o.lat},${o.lng}' : Uri.encodeComponent('${o.address}, México');
    await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar este pedido?'),
        content: Text('Se le avisará a ${order.customerName}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (ok == true) {
      await Repo.instance.updateOrder(order.id, {'status': OrderStatus.cancelado.name});
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final theme = Theme.of(context);
    final next = _next[o.status];
    final moved = o.wasMoved
        ? 'Movido del ${dayLabel(o.movedFromDate!)}'
            '${o.movedFromSlot == null ? '' : ', ${slotLabel(o.movedFromSlot!, minutes: o.movedFromMinutes)}'}'
        : null;
    final isCash = o.paymentMethod == PaymentMethod.efectivo;
    final (accent, _, _) = statusStyle(o.status);
    return PanCard(
      padding: EdgeInsets.zero,
      color: selected ? const Color(0xFFFBE6E1) : null,
      onTap: selecting ? onToggle : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Pan.radio),
        child: Stack(
          children: [
            // Franja de color según el estado (toma el alto de la tarjeta).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.medio),
                width: 6,
                color: selected ? Pan.terracota : accent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (selecting)
                        _Check(selected: selected)
                      else
                        _StopBadge(
                          stop: stop,
                          color: o.status == OrderStatus.entregado ? const Color(0xFF9E9E9E) : stopColor,
                        ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(o.customerName, style: theme.textTheme.titleMedium)),
                      StatusChip(status: o.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _line(Icons.place_outlined, o.address, theme.textTheme.bodyMedium!),
                  if (o.addressNotes.isNotEmpty)
                    _line(Icons.sticky_note_2_outlined, o.addressNotes, theme.textTheme.bodySmall!),
                  _line(Icons.phone_outlined, o.phone, theme.textTheme.bodySmall!, selectable: !selecting),
                  if (moved != null) _line(Icons.edit_calendar_rounded, moved, theme.textTheme.bodySmall!),
                  if (noPush)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '🔕 Tiene apagadas las notificaciones: no le llegan los avisos. '
                        'Si hace falta, avísale por WhatsApp.',
                        style: theme.textTheme.bodySmall!.copyWith(color: Pan.canela),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final it in o.items)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: it.isGift ? Pan.salviaClara : const Color(0xFFFFF4D6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            it.isGift
                                ? '🎁 ${it.qty} ${it.name} gratis (${GiftTag.label(it.gift).toLowerCase()})'
                                : '${productArt(it.name).$1} ${it.qty} ${it.name}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                  if (o.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('📝 ${o.notes}', style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        money(o.total),
                        style: theme.textTheme.titleLarge!.copyWith(color: Pan.caramelo, fontSize: 19),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        isCash ? Icons.payments_rounded : Icons.account_balance_rounded,
                        size: 17,
                        color: Pan.canela,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isCash
                              ? (o.cashCollected ? 'Efectivo, cobrado' : 'Efectivo, por cobrar')
                              : (o.paymentVerified
                                    ? 'Transferencia verificada'
                                    : 'Transferencia por revisar'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  // Mientras se seleccionan pedidos para borrar, los botones se esconden
                  // para no picar uno sin querer.
                  AnimatedSize(
                    duration: Motion.of(context, Motion.medio),
                    curve: Motion.curva,
                    alignment: Alignment.topCenter,
                    child: selecting
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (next != null)
                                  FilledButton(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      Repo.instance.updateOrder(o.id, {'status': next.$1.name});
                                    },
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    child: Text(next.$2),
                                  ),
                                if (o.status != OrderStatus.entregado)
                                  OutlinedButton.icon(
                                    onPressed: _directions,
                                    icon: const Icon(Icons.directions_rounded, size: 18),
                                    label: const Text('Cómo llegar'),
                                  ),
                                if (!isCash && o.paymentProofPath != null)
                                  OutlinedButton(
                                    onPressed: () => _showProof(context),
                                    child: const Text('Ver captura'),
                                  ),
                                if (!isCash && o.paymentProofPath == null && !o.paymentVerified)
                                  OutlinedButton(
                                    onPressed: () => Repo.instance.updateOrder(o.id, {'paymentVerified': true}),
                                    child: const Text('Ya me pagó'),
                                  ),
                                if (isCash && !o.cashCollected)
                                  OutlinedButton(
                                    onPressed: () => Repo.instance.updateOrder(o.id, {'cashCollected': true}),
                                    child: const Text('Cobrado'),
                                  ),
                                if (o.status != OrderStatus.entregado)
                                  TextButton(
                                    onPressed: () => _cancel(context),
                                    style: TextButton.styleFrom(foregroundColor: Pan.terracota),
                                    child: const Text('Cancelar'),
                                  ),
                                DeleteOrderButton(order: o),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, TextStyle style, {bool selectable = false}) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: Pan.canela),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: selectable ? SelectableText(text, style: style) : Text(text, style: style),
        ),
      ],
    ),
  );
}

/// Circulito con el número de parada (igual al del mapa del día).
class _StopBadge extends StatelessWidget {
  final int stop;
  final Color color;
  const _StopBadge({required this.stop, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          '$stop',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
        ),
      );
}

/// Borrar un pedido para siempre (por ejemplo, uno de prueba).
/// Desaparece también en el celular del cliente y libera su cupo.
Future<void> confirmDeleteOrder(BuildContext context, BakeryOrder o) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.delete_forever_rounded, color: Pan.terracota, size: 32),
      title: const Text('¿Eliminar este pedido?'),
      content: Text(
        'El pedido de ${o.customerName} (${o.pieces} '
        '${o.pieces == 1 ? 'pieza' : 'piezas'}, ${money(o.total)}) se borra para siempre, '
        'también del celular del cliente. Sus panes vuelven al cupo del día.\n\n'
        'Si solo quieres avisarle que no va, mejor usa "Cancelar".',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Pan.terracota),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sí, eliminar'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  HapticFeedback.mediumImpact();
  try {
    await Repo.instance.deleteOrder(o.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pedido eliminado ✓')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo eliminar. Intenta de nuevo. ($e)')));
    }
  }
}

class DeleteOrderButton extends StatelessWidget {
  final BakeryOrder order;
  const DeleteOrderButton({super.key, required this.order});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Eliminar pedido',
        onPressed: () => confirmDeleteOrder(context, order),
        icon: const Icon(Icons.delete_outline_rounded, color: Pan.terracota),
      );
}

/// Pedidos plegados al final de la lista (los cancelados).
class _FoldedSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<BakeryOrder> orders;
  final bool selecting;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _FoldedSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.orders,
    required this.selecting,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: PanCard(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: Pan.harina,
        // Recorta el brillo al tocar para que no se salga de las esquinas redondas.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Pan.radio - 6),
          child: ExpansionTile(
            // Al empezar a seleccionar se abre sola, para ver qué palomear.
            key: ValueKey(selecting),
            initiallyExpanded: selecting,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(icon, color: Pan.canela),
            title: Text(title, style: theme.textTheme.titleSmall),
            subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
            children: [
              for (final o in orders)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 12, right: 4),
                  onTap: selecting ? () => onToggle(o.id) : null,
                  title: Text(o.customerName, style: theme.textTheme.titleSmall),
                  subtitle: Text(
                    '${capitalize(dayLabel(o.deliveryDate))} · ${o.pieces} '
                    '${o.pieces == 1 ? 'pieza' : 'piezas'} · ${money(o.total)}'
                    '${o.status == OrderStatus.cancelado ? '' : ' · ${orderStatusLabels[o.status]}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: selecting
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Check(selected: selected.contains(o.id)),
                        )
                      : DeleteOrderButton(order: o),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Al final de la lista: abre el Historial con los días ya repartidos.
class _HistoryLink extends StatelessWidget {
  /// Pedidos archivados de la última semana (para el resumen de la tarjeta).
  final List<BakeryOrder> recent;
  final VoidCallback onTap;
  const _HistoryLink({required this.recent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SalesSummary.of(recent);
    final subtitle = s.delivered == 0
        ? 'Días ya repartidos, con lo que vendiste'
        : 'Esta semana: ${s.delivered} ${s.delivered == 1 ? 'pedido entregado' : 'pedidos entregados'}'
            ' · ${money(s.sold)}';
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: PanCard(
        color: Pan.harina,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_rounded, color: Pan.canela),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Historial', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Pan.canela),
          ],
        ),
      ),
    );
  }
}
