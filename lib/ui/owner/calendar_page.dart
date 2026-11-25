import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/schedule.dart';
import '../../logic/stock.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../stock_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../logic/day_requests.dart';
import 'day_requests_page.dart';
import 'pickup_point_fields.dart';

/// Días de entrega: el dueño abre días con sus horarios y su cupo de panes.
/// Se puede pedir hasta que el dueño pica "Empezar a repartir" ese día
/// o hasta que se acaba el cupo.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final today = dateKey(DateTime.now());
    return Scaffold(
      body: StreamBuilder<List<DeliveryDay>>(
        stream: Repo.instance.deliveryDays(fromDate: today),
        builder: (context, daysSnap) => StreamBuilder<List<Product>>(
          stream: Repo.instance.products(),
          builder: (context, prodSnap) => StreamBuilder<Map<String, DayStock>>(
            stream: Repo.instance.dayStocks(fromDate: today),
            builder: (context, stockSnap) => StreamBuilder<List<BakeryOrder>>(
              stream: Repo.instance.ordersFrom(today),
              builder: (context, ordersSnap) {
                if (!daysSnap.hasData || !prodSnap.hasData) return const SkeletonList(count: 4);
                final days = [...daysSnap.data!]..sort(compareDays);
                final groups = stockGroups(prodSnap.data!);
                final stocks = stockSnap.data ?? const {};
                final orders = ordersSnap.data ?? const <BakeryOrder>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    const FadeSlideIn(child: DayRequestsBanner(onOpenDay: openRequestedDay)),
                    FadeSlideIn(child: _GroupsCard(products: prodSnap.data!, groups: groups)),
                    if (days.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: EmptyState(
                          title: 'No hay días abiertos',
                          message: 'Toca "Abrir días" para publicar tus próximas entregas.',
                        ),
                      ),
                    for (final (i, d) in days.indexed)
                      FadeSlideIn(
                        index: i + 1,
                        child: _DayTile(
                          key: ValueKey(d.date),
                          day: d,
                          allDays: days,
                          groups: groups,
                          stock: stocks[d.date],
                          pendingOrders: orders.where((o) => o.deliveryDate == d.date && o.isPending).length,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<List<Product>>(
        stream: Repo.instance.products(),
        builder: (context, snap) => FloatingActionButton.extended(
          heroTag: 'abrir-dias',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _OpenDaysSheet(groups: stockGroups(snap.data ?? const [])),
          ),
          icon: const Icon(Icons.event_available_rounded),
          label: const Text('Abrir días'),
        ),
      ),
    );
  }
}

/// Abre la hoja de "Abrir días" ya con el día que piden los clientes
/// y un horario que cubre las horas que pidieron.
Future<void> openRequestedDay(BuildContext context, RequestedDay day) async {
  final products = await Repo.instance.products().first;
  if (!context.mounted) return;
  final (start, end) = day.suggestedHours;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _OpenDaysSheet(groups: stockGroups(products), onlyDate: day.date, start: start, end: end),
  );
}

/// Arriba de los días: qué productos comparten masa (y por lo tanto cupo).
class _GroupsCard extends StatelessWidget {
  final List<Product> products;
  final List<StockGroup> groups;
  const _GroupsCard({required this.products, required this.groups});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanCard(
      color: const Color(0xFFFFF7E4),
      onTap: () => _openGroups(context, products),
      child: Row(
        children: [
          const Text('🥣', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cupos por masa', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                if (groups.isEmpty)
                  Text('Agrega productos para ponerles cupo.', style: theme.textTheme.bodySmall)
                else
                  for (final g in groups)
                    Text(
                      g.shared ? '${g.label}: ${g.productNames}' : '${g.label}: cupo propio',
                      style: theme.textTheme.bodySmall,
                    ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Pan.canela),
        ],
      ),
    );
  }
}

void _openGroups(BuildContext context, List<Product> products) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupsSheet(products: products),
    );

class _DayTile extends StatelessWidget {
  final DeliveryDay day;
  final List<DeliveryDay> allDays;
  final List<StockGroup> groups;
  final DayStock? stock;
  final int pendingOrders;
  const _DayTile({
    super.key,
    required this.day,
    required this.allDays,
    required this.groups,
    required this.stock,
    required this.pendingOrders,
  });

  String get _hours {
    if (day.slots.isEmpty) return 'Sin horarios';
    final first = slotLabel(day.slots.first, minutes: day.slotMinutes).split(' a ').first;
    final last = slotLabel(day.slots.last, minutes: day.slotMinutes).split(' a ').last;
    return day.slotMinutes == 60 ? '$first a $last' : '$first a $last · cada ${day.slotMinutes} min';
  }

  void _editStock(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _StockSheet(day: day, allDays: allDays, groups: groups, stock: stock),
      );

  void _editPickup(BuildContext context) {
    if (pendingOrders > 0) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Este día ya tiene pedidos'),
          content: Text(
            'Hay $pendingOrders ${pendingOrders == 1 ? 'pedido' : 'pedidos'} con su lugar de entrega ya puesto. '
            'Para cambiar a dónde entregas, primero mueve o cancela esos pedidos.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickupSheet(day: day),
    );
  }

  void _move(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _MoveDaySheet(day: day, allDays: allDays, pendingOrders: pendingOrders),
      );

  Future<void> _delete(BuildContext context) async {
    if (pendingOrders > 0) {
      final move = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Este día tiene pedidos'),
          content: Text(
            'Hay $pendingOrders ${pendingOrders == 1 ? 'pedido pendiente' : 'pedidos pendientes'} '
            'para el ${dayLabel(day.date)}. Si quitas el día, esos pedidos se quedan sin día.\n\n'
            'Mejor muévelo a otra fecha: los pedidos se pasan solos y a cada cliente le llega un aviso.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mover día')),
          ],
        ),
      );
      if (move == true && context.mounted) _move(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar este día?'),
        content: Text('El ${dayLabel(day.date)} ya no aparecerá para pedir. No tiene pedidos pendientes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Pan.terracota),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, quitar'),
          ),
        ],
      ),
    );
    if (ok == true) await Repo.instance.deleteDeliveryDay(day.date);
  }

  @override
  Widget build(BuildContext context) {
    final date = parseDateKey(day.date);
    final theme = Theme.of(context);
    final limited = [
      for (final g in groups)
        if (day.stock.containsKey(g.key)) g
    ];
    final total = totalRemaining(day, stock);
    return PanCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 12),
      onTap: () => _editStock(context),
      child: AnimatedOpacity(
        opacity: day.open ? 1 : 0.55,
        duration: Motion.of(context, Motion.medio),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: Motion.of(context, Motion.medio),
                  width: 58,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: day.open ? Pan.gradienteMiel : null,
                    color: day.open ? null : Pan.harina,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(DateFormat('EEE', 'es_MX').format(date).replaceAll('.', '').toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Pan.tostado)),
                      Text('${date.day}',
                          style: const TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Pan.cacao,
                              height: 1.1)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(capitalize(dayLabel(day.date)), style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        pendingOrders == 0
                            ? _hours
                            : '$_hours · $pendingOrders ${pendingOrders == 1 ? 'pedido' : 'pedidos'}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (day.pickup != null)
                        Text('📍 Especial: entrega en ${day.pickup!.name}',
                            style: theme.textTheme.bodySmall!
                                .copyWith(color: Pan.caramelo, fontWeight: FontWeight.w800)),
                      // Si ese día hay otro reparto, que se vea cuál es el de a domicilio.
                      if (day.pickup == null && allDays.any((d) => d.day == day.day && d.date != day.date))
                        Text('🏠 A domicilio',
                            style: theme.textTheme.bodySmall!
                                .copyWith(color: Pan.tostado, fontWeight: FontWeight.w800)),
                      Text(
                        day.closed
                            ? 'Repartiendo · pedidos cerrados'
                            : day.open
                                ? 'Recibiendo pedidos'
                                : 'Apagado: no se ve en la app',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: day.closed ? Pan.ciruela : (day.open ? Pan.salvia : Pan.canela),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: day.open,
                  onChanged: (v) => Repo.instance.setDayOpen(day.date, v),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Más opciones',
                  icon: const Icon(Icons.more_vert_rounded, color: Pan.canela),
                  onSelected: (v) => switch (v) {
                    'cupo' => _editStock(context),
                    'mover' => _move(context),
                    'lugar' => _editPickup(context),
                    _ => _delete(context),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'cupo',
                      child:
                          ListTile(leading: Icon(Icons.bakery_dining_rounded), title: Text('Cupo de panes')),
                    ),
                    PopupMenuItem(
                      value: 'mover',
                      child:
                          ListTile(leading: Icon(Icons.edit_calendar_rounded), title: Text('Mover o editar')),
                    ),
                    PopupMenuItem(
                      value: 'lugar',
                      child:
                          ListTile(leading: Icon(Icons.location_on_rounded), title: Text('Lugar de entrega')),
                    ),
                    PopupMenuItem(
                      value: 'quitar',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: Pan.terracota),
                        title: Text('Quitar día'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 10, 0),
              child: limited.isEmpty
                  ? Row(
                      children: [
                        const Icon(Icons.all_inclusive_rounded, size: 16, color: Pan.canela),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('Sin cupo: se puede pedir lo que sea. Toca para poner cupo.',
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (total != null) StockTotal(left: total),
                        const SizedBox(height: 4),
                        for (final g in limited)
                          StockMeter(
                            label: g.label,
                            detail: g.shared ? g.productNames : null,
                            left: remainingFor(day, stock, g.key) ?? 0,
                            limit: day.stock[g.key]!,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campos de cupo, uno por grupo de masa. Vacío = sin límite.
class _StockFields extends StatelessWidget {
  final List<StockGroup> groups;
  final Map<String, TextEditingController> controllers;
  final Map<String, int> used;
  const _StockFields({required this.groups, required this.controllers, this.used = const {}});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Text('Todavía no hay productos.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(
      children: [
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: controllers[g.key],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: g.shared ? '${g.label} (${g.products.length} productos)' : g.label,
                helperText: [
                  if ((used[g.key] ?? 0) > 0) 'Ya pedidos: ${used[g.key]}',
                  if (g.shared) g.productNames,
                ].join(' · '),
                helperMaxLines: 2,
                hintText: 'Sin límite',
                suffixText: 'panes',
                prefixIcon: const Icon(Icons.bakery_dining_outlined),
              ),
            ),
          ),
      ],
    );
  }
}

Map<String, int> _readStock(Map<String, TextEditingController> c) => {
      for (final e in c.entries)
        if (int.tryParse(e.value.text.trim()) != null) e.key: int.parse(e.value.text.trim()),
    };

/// Cupo de un día (y, si quiere, de todos los días abiertos).
class _StockSheet extends StatefulWidget {
  final DeliveryDay day;
  final List<DeliveryDay> allDays;
  final List<StockGroup> groups;
  final DayStock? stock;
  const _StockSheet({required this.day, required this.allDays, required this.groups, required this.stock});

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<_StockSheet> {
  late final _c = {
    for (final g in widget.groups)
      g.key: TextEditingController(text: widget.day.stock[g.key]?.toString() ?? ''),
  };
  bool _allDays = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final stock = _readStock(_c);
    final dates = _allDays ? widget.allDays.where((d) => !d.closed).map((d) => d.date).toSet() : <String>{};
    dates.add(widget.day.date);
    for (final date in dates) {
      await Repo.instance.setDayStock(date, stock);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = widget.allDays.where((d) => !d.closed && d.date != widget.day.date).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cupo de panes', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(capitalize(dayLabel(widget.day.date)), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              '¿Cuántos puedes hacer ese día? Los productos de la misma masa comparten un solo cupo. '
              'Déjalo vacío si no tiene límite.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            _StockFields(groups: widget.groups, controllers: _c, used: widget.stock?.used ?? const {}),
            if (others > 0)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _allDays,
                onChanged: (v) => setState(() => _allDays = v ?? false),
                title: Text('Usar el mismo cupo en los otros $others días'),
              ),
            const SizedBox(height: 8),
            HoneyButton(label: 'Guardar cupo', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Qué productos salen de la misma masa. Los que comparten grupo comparten cupo.
class _GroupsSheet extends StatefulWidget {
  final List<Product> products;
  const _GroupsSheet({required this.products});

  @override
  State<_GroupsSheet> createState() => _GroupsSheetState();
}

class _GroupsSheetState extends State<_GroupsSheet> {
  static const _own = '';
  static const _new = '\u0000nuevo';
  late final Map<String, String> _group = {for (final p in widget.products) p.id: p.stockGroup.trim()};
  final List<String> _extraNames = [];
  bool _busy = false;

  List<String> get _names {
    final seen = <String>{};
    return [
      for (final n in [...groupNames(widget.products), ..._extraNames, ..._group.values])
        if (n.isNotEmpty && seen.add(n.toLowerCase())) n,
    ];
  }

  Future<void> _pick(Product p, String? v) async {
    if (v == null) return;
    if (v == _new) {
      final name = await _askName();
      if (name == null || name.trim().isEmpty) return;
      setState(() {
        _extraNames.add(name.trim());
        _group[p.id] = name.trim();
      });
      return;
    }
    setState(() => _group[p.id] = v);
  }

  Future<String?> _askName() {
    final c = TextEditingController(text: _names.isEmpty ? 'Masa de croissant' : '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo grupo de masa'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Masa de croissant'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Crear')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    for (final p in widget.products) {
      final g = _group[p.id] ?? '';
      if (g != p.stockGroup.trim()) await Repo.instance.setProductGroup(p.id, g);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = _names;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cupos por masa', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Pon en el mismo grupo los panes que salen de la misma masa. Por ejemplo chocolatín, '
              'jamón y queso y pizza en "Masa de croissant": un cupo de 30 es para los tres juntos. '
              'Los demás llevan su propio cupo.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final p in widget.products)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(p.name, style: theme.textTheme.titleSmall)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _group[p.id] ?? _own,
                      borderRadius: BorderRadius.circular(16),
                      items: [
                        const DropdownMenuItem(value: _own, child: Text('Cupo propio')),
                        for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
                        const DropdownMenuItem(
                          value: _new,
                          child: Text('+ Nuevo grupo…', style: TextStyle(color: Pan.caramelo)),
                        ),
                      ],
                      onChanged: (v) => _pick(p, v),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            HoneyButton(label: 'Guardar grupos', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// Mover un día a otra fecha o cambiarle el horario. Los pedidos se pasan solos
/// y a cada cliente le llega un aviso.
class _MoveDaySheet extends StatefulWidget {
  final DeliveryDay day;
  final List<DeliveryDay> allDays;
  final int pendingOrders;
  const _MoveDaySheet({required this.day, required this.allDays, required this.pendingOrders});

  @override
  State<_MoveDaySheet> createState() => _MoveDaySheetState();
}

class _MoveDaySheetState extends State<_MoveDaySheet> {
  /// Fecha elegida (AAAA-MM-DD, sin número de reparto).
  late String _date = widget.day.day;
  late int _every = slotLengths.contains(widget.day.slotMinutes) ? widget.day.slotMinutes : 60;
  late int _start = _nearestChoice(widget.day.slots.isEmpty ? 8 * 60 : slotMinute(widget.day.slots.first));
  late int _end = _nearestChoice(
      widget.day.slots.isEmpty ? 11 * 60 : slotMinute(widget.day.slots.last) + widget.day.slotMinutes);
  bool _busy = false;

  /// Hoy y los próximos 4 semanas.
  List<String> get _dates {
    final t = DateTime.now();
    return [for (var i = 0; i < 29; i++) dateKey(DateTime(t.year, t.month, t.day + i))];
  }

  /// Otros repartos que ya hay en [date] (se puede mover ahí: queda como otro reparto).
  int _others(String date) => widget.allDays.where((d) => d.day == date && d.date != widget.day.date).length;

  /// Id del reparto en su fecha nueva: el mismo si no cambia de día.
  String get _target => _date == widget.day.day
      ? widget.day.date
      : newDayId(_date, widget.allDays.where((d) => d.date != widget.day.date).map((d) => d.date));

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final told = await Repo.instance.moveDeliveryDay(
        from: widget.day.date,
        to: _target,
        slots: slotsBetween(_start, _end, _every),
        slotMinutes: _every,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(told == 0
            ? 'Día actualizado ✓'
            : 'Día actualizado ✓ Se avisó a $told ${told == 1 ? 'cliente' : 'clientes'}.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = _dates;
    final newSlots = slotsBetween(_start, _end, _every);
    final changed = _date != widget.day.day ||
        newSlots.join() != widget.day.slots.join() ||
        _every != widget.day.slotMinutes;
    final valid = newSlots.isNotEmpty && changed;
    final n = widget.pendingOrders;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mover o editar día', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text('Ahora: ${dayLabel(widget.day.date)}', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text('Nueva fecha', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dates.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final key = dates[i];
                final d = parseDateKey(key);
                final selected = key == _date;
                final taken = _others(key) > 0;
                return Pressable(
                  onTap: () => setState(() => _date = key),
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.medio),
                    width: 60,
                    decoration: BoxDecoration(
                      gradient: selected ? Pan.gradienteMiel : null,
                      color: selected ? null : Pan.papel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: selected ? Colors.transparent : const Color(0xFFEADCC4)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('EEE', 'es_MX').format(d).replaceAll('.', '').toUpperCase(),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800, color: Pan.tostado)),
                        Text('${d.day}',
                            style: const TextStyle(
                                fontFamily: 'Fraunces',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 1.15)),
                        Text(DateFormat('MMM', 'es_MX').format(d).replaceAll('.', ''),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: Pan.canela)),
                        if (taken)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [for (var i = 0; i < _others(key).clamp(0, 3); i++) const _Dot()],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _SlotPicker(
            start: _start,
            end: _end,
            every: _every,
            onChanged: (start, end, every) => setState(() {
              _start = start;
              _end = end;
              _every = every;
            }),
          ),
          const SizedBox(height: 6),
          if (_date != widget.day.day && _others(_date) > 0) ...[
            Text(
              'Ese día ya tiene ${widget.allDays.where((d) => d.day == _date && d.date != widget.day.date).map(repartoShort).join(' y ')}. '
              'Este se agrega como otro reparto.',
              style: theme.textTheme.bodySmall!.copyWith(color: Pan.cielo, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            n == 0
                ? 'Este día no tiene pedidos pendientes.'
                : 'Sus $n ${n == 1 ? 'pedido se pasa' : 'pedidos se pasan'} al día nuevo con su cupo, '
                    'y a cada cliente le llega un aviso de que su entrega se movió.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          HoneyButton(
            label: _date == widget.day.day ? 'Guardar horario' : 'Mover al ${dayLabel(_date)}',
            icon: Icons.edit_calendar_rounded,
            busy: _busy,
            onPressed: valid ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// Cambiar un día ya abierto (sin pedidos) entre "a domicilio" y "especial".
class _PickupSheet extends StatefulWidget {
  final DeliveryDay day;
  const _PickupSheet({required this.day});

  @override
  State<_PickupSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends State<_PickupSheet> {
  final _key = GlobalKey<PickupPointFieldsState>();
  late PickupPoint? _point = widget.day.pickup;
  late bool _special = widget.day.pickup != null;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final p = _special ? _point : null;
      if (p != null && _key.currentState?.remember == true) {
        await Repo.instance.savePickupPoint(p).catchError((_) {});
      }
      await Repo.instance.setDayPickup(widget.day.date, p);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar ($e)')));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lugar de entrega', style: Theme.of(context).textTheme.headlineSmall),
              Text(capitalize(dayLabel(widget.day.date)), style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              PickupPointFields(
                key: _key,
                initial: widget.day.pickup,
                onChanged: (p) => setState(() => _point = p),
                onModeChanged: (v) => setState(() => _special = v),
              ),
              const SizedBox(height: 12),
              HoneyButton(
                label: 'Guardar',
                icon: Icons.check_rounded,
                busy: _busy,
                onPressed: _busy || (_special && _point == null) ? null : _save,
              ),
            ],
          ),
        ),
      );
}

/// Abrir días sueltos eligiéndolos en un calendario, con sus horarios, lugar y
/// cupo. Si un día ya tiene reparto se le agrega otro (por ejemplo Acuity a
/// las 7:45 y a domicilio al mediodía).
class _OpenDaysSheet extends StatefulWidget {
  final List<StockGroup> groups;

  /// Para abrir ya marcado el día que piden los clientes.
  final String? onlyDate;
  final int? start;
  final int? end;
  const _OpenDaysSheet({required this.groups, this.onlyDate, this.start, this.end});

  @override
  State<_OpenDaysSheet> createState() => _OpenDaysSheetState();
}

class _OpenDaysSheetState extends State<_OpenDaysSheet> {
  /// Fechas elegidas en el calendario (AAAA-MM-DD).
  late final Set<String> _picked = {if (widget.onlyDate != null) widget.onlyDate!};
  late int _start = _nearestChoice(widget.start ?? 8 * 60);
  late int _end = _nearestChoice(widget.end ?? 11 * 60);
  int _every = 60;
  bool _busy = false;
  late final _stock = {for (final g in widget.groups) g.key: TextEditingController()};
  final _pointKey = GlobalKey<PickupPointFieldsState>();

  /// Repartos que ya hay, para marcarlos en el calendario.
  late final _days = Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now()));

  /// Día especial: entrega en un solo lugar (null = a domicilio o falta completar).
  PickupPoint? _point;
  bool _special = false;

  @override
  void dispose() {
    for (final c in _stock.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _dates => _picked.toList()..sort();

  Future<void> _save() async {
    setState(() => _busy = true);
    final stock = _readStock(_stock);
    final point = _special ? _point : null;
    if (point != null && _pointKey.currentState?.remember == true) {
      await Repo.instance.savePickupPoint(point).catchError((_) {});
    }
    // Cada vez que abres un día se agrega un reparto nuevo: si ese día ya
    // tenía uno (por ejemplo Acuity a las 7:45), el otro queda igual.
    final today = dateKey(DateTime.now());
    final ids = {for (final d in await Repo.instance.deliveryDays(fromDate: today).first) d.date};
    for (final date in _dates) {
      final id = newDayId(date, ids);
      ids.add(id);
      await Repo.instance.saveDeliveryDay(DeliveryDay(
        date: id,
        open: true,
        slots: slotsBetween(_start, _end, _every),
        slotMinutes: _every,
        pickup: point,
      ));
      if (stock.isNotEmpty) await Repo.instance.setDayStock(id, stock);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // ¿Algún cliente había pedido estos días? Se les ofrece avisar.
    final opened = _dates;
    final waiting =
        toNotify(await Repo.instance.allDayRequests().first.catchError((_) => <DayRequest>[]), opened);
    if (!mounted) return;
    final note = await notifyRequesters(context, opened, waiting);
    if (note != null) messenger.showSnackBar(SnackBar(content: Text(note)));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = _dates;
    final valid =
        slotsBetween(_start, _end, _every).isNotEmpty && dates.isNotEmpty && (!_special || _point != null);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: StreamBuilder<List<DeliveryDay>>(
          stream: _days,
          builder: (context, snap) {
            final existing = snap.data ?? const <DeliveryDay>[];
            final byDate = <String, List<DeliveryDay>>{};
            for (final d in existing.toList()..sort(compareDays)) {
              byDate.putIfAbsent(d.day, () => []).add(d);
            }
            final repeated = [
              for (final date in dates)
                if (byDate[date] != null) date,
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Abrir días de entrega', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text('Toca en el calendario los días que vas a repartir.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                _DatePickerCalendar(
                  picked: _picked,
                  repartos: {for (final e in byDate.entries) e.key: e.value.length},
                  onToggle: (date) =>
                      setState(() => _picked.contains(date) ? _picked.remove(date) : _picked.add(date)),
                ),
                const SizedBox(height: 10),
                AnimatedSize(
                  duration: Motion.of(context, Motion.medio),
                  curve: Motion.curva,
                  alignment: Alignment.topCenter,
                  child: dates.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final d in dates)
                              InputChip(
                                label: Text(_chipLabel(d)),
                                onDeleted: () => setState(() => _picked.remove(d)),
                                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                                backgroundColor: Pan.mielClara,
                                side: BorderSide.none,
                                labelStyle: const TextStyle(fontWeight: FontWeight.w800, color: Pan.cacao),
                              ),
                          ],
                        ),
                ),
                if (repeated.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(color: Pan.cieloClaro, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.add_road_rounded, size: 18, color: Pan.cielo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            [
                              for (final date in repeated)
                                '${capitalize(_chipLabel(date))} ya tiene '
                                    '${byDate[date]!.map(repartoShort).join(' y ')}.',
                              'Se agrega otro reparto ese día, con sus propios horarios, lugar y cupo.',
                            ].join('\n'),
                            style: theme.textTheme.bodySmall!.copyWith(color: Pan.cacao),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _SlotPicker(
                  start: _start,
                  end: _end,
                  every: _every,
                  onChanged: (start, end, every) => setState(() {
                    _start = start;
                    _end = end;
                    _every = every;
                  }),
                ),
                const SizedBox(height: 8),
                PickupPointFields(
                  key: _pointKey,
                  onChanged: (p) => setState(() => _point = p),
                  onModeChanged: (v) => setState(() => _special = v),
                ),
                if (widget.groups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Cupo de panes por reparto (opcional)', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  _StockFields(groups: widget.groups, controllers: _stock),
                ],
                const SizedBox(height: 4),
                Text(
                  dates.isEmpty
                      ? 'Elige al menos un día en el calendario.'
                      : _special && _point == null
                          ? 'Escribe el nombre del lugar y márcalo en el mapa.'
                          : 'Se ${dates.length == 1 ? 'abre 1 día' : 'abren ${dates.length} días'}${_point != null ? ' de entrega en ${_point!.name}' : ''}. '
                              'Se puede pedir hasta que empieces a repartir o se acabe el cupo.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                HoneyButton(
                  label: dates.isEmpty
                      ? 'Abrir'
                      : dates.length == 1
                          ? 'Abrir ${_chipLabel(dates.single)}'
                          : 'Abrir ${dates.length} días',
                  icon: Icons.event_available_rounded,
                  busy: _busy,
                  onPressed: valid ? _save : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "mié 25 nov"
String _chipLabel(String date) =>
    DateFormat("EEE d MMM", 'es_MX').format(parseDateKey(date)).replaceAll('.', '');

/// Calendario de un mes para elegir días sueltos (de hoy a 3 meses).
/// Los días que ya tienen reparto llevan un puntito por cada reparto.
class _DatePickerCalendar extends StatefulWidget {
  final Set<String> picked;

  /// Cuántos repartos hay ya en cada fecha.
  final Map<String, int> repartos;
  final ValueChanged<String> onToggle;
  const _DatePickerCalendar({required this.picked, required this.repartos, required this.onToggle});

  @override
  State<_DatePickerCalendar> createState() => _DatePickerCalendarState();
}

class _DatePickerCalendarState extends State<_DatePickerCalendar> {
  static const _weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _monthsAhead = 3;
  late final DateTime _today = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();
  late DateTime _month = DateTime(_today.year, _today.month);

  bool get _canBack => _month.isAfter(DateTime(_today.year, _today.month));
  bool get _canNext => _month.isBefore(DateTime(_today.year, _today.month + _monthsAhead));

  void _go(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1; // lunes primero
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();
    final limit = DateTime(_today.year, _today.month + _monthsAhead + 1, 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      decoration: BoxDecoration(
        color: Pan.papel,
        borderRadius: BorderRadius.circular(Pan.radio),
        border: Border.all(color: const Color(0xFFEADCC4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Mes anterior',
                onPressed: _canBack ? () => _go(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                color: Pan.caramelo,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.rapido),
                  child: Text(
                    capitalize(DateFormat('MMMM yyyy', 'es_MX').format(_month)),
                    key: ValueKey(_month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium!
                        .copyWith(fontFamily: 'Fraunces', fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Mes siguiente',
                onPressed: _canNext ? () => _go(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
                color: Pan.caramelo,
              ),
            ],
          ),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Pan.canela)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final n = r * 7 + c - lead + 1;
                      if (n < 1 || n > daysInMonth) return const SizedBox(height: 46);
                      final d = DateTime(_month.year, _month.month, n);
                      final key = dateKey(d);
                      final past = d.isBefore(_today) || d.isAfter(limit);
                      return _CalendarDay(
                        day: n,
                        selected: widget.picked.contains(key),
                        today: d == _today,
                        disabled: past,
                        repartos: widget.repartos[key] ?? 0,
                        onTap: past ? null : () => widget.onToggle(key),
                      );
                    }),
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _Dot(),
              const SizedBox(width: 6),
              Text('Ya tiene reparto', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({this.color = Pan.caramelo});

  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _CalendarDay extends StatelessWidget {
  final int day;
  final bool selected;
  final bool today;
  final bool disabled;
  final int repartos;
  final VoidCallback? onTap;
  const _CalendarDay({
    required this.day,
    required this.selected,
    required this.today,
    required this.disabled,
    required this.repartos,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !disabled,
      selected: selected,
      label: '$day${repartos > 0 ? ', ya tiene $repartos ${repartos == 1 ? 'reparto' : 'repartos'}' : ''}',
      child: Pressable(
        onTap: onTap,
        haptic: true,
        child: SizedBox(
          height: 46,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.rapido),
              curve: Motion.curva,
              width: 40,
              height: 42,
              decoration: BoxDecoration(
                gradient: selected ? Pan.gradienteMiel : null,
                borderRadius: BorderRadius.circular(14),
                border: today && !selected ? Border.all(color: Pan.miel, width: 1.6) : null,
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x44E8960F), blurRadius: 10, offset: Offset(0, 4))]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: selected || today ? FontWeight.w900 : FontWeight.w600,
                      color: disabled ? const Color(0xFFCDBCA6) : Pan.cacao,
                    ),
                  ),
                  SizedBox(
                    height: 7,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < repartos.clamp(0, 3); i++)
                          _Dot(color: selected ? Pan.cacao : Pan.caramelo),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Redondea a la hora elegible más cercana (cuartos de hora de 5:00 a 22:00).
int _nearestChoice(int minutes) =>
    dayTimeChoices.reduce((a, b) => (a - minutes).abs() <= (b - minutes).abs() ? a : b);

/// Hora de inicio, hora final y cada cuánto hay horario (15, 30 o 60 minutos),
/// con una vista previa de los horarios que van a ver los clientes.
class _SlotPicker extends StatelessWidget {
  final int start;
  final int end;
  final int every;
  final void Function(int start, int end, int every) onChanged;
  const _SlotPicker({required this.start, required this.end, required this.every, required this.onChanged});

  Widget _time(String label, int value, ValueChanged<int> pick) => Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<int>(
            value: value,
            menuMaxHeight: 320,
            items: [
              for (final m in dayTimeChoices) DropdownMenuItem(value: m, child: Text(clockLabel(m))),
            ],
            onChanged: (v) => pick(v!),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = slotsBetween(start, end, every);
    final String preview;
    if (end <= start) {
      preview = 'La última entrega tiene que ser después de la primera.';
    } else if (slots.isEmpty) {
      preview = 'No cabe ni un horario de $every min. Amplía las horas o elige horarios más cortos.';
    } else {
      final labels = [for (final s in slots) clockLabel(slotMinute(s))];
      final shown = labels.length <= 8 ? labels.join(', ') : '${labels.take(6).join(', ')} … ${labels.last}';
      final last = slotMinute(slots.last) + every;
      preview = '${slots.length} ${slots.length == 1 ? 'horario' : 'horarios'} de $every min: $shown'
          '${last < end ? ' (lo último que no cabe completo se queda fuera)' : ''}.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _time('Primera entrega desde', start, (v) => onChanged(v, end, every)),
        _time('Última entrega hasta', end, (v) => onChanged(start, v, every)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(child: Text('Cada horario dura')),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final m in slotLengths)
                  ButtonSegment(value: m, label: Text(m == 60 ? '1 hora' : '$m min')),
              ],
              selected: {every},
              onSelectionChanged: (s) => onChanged(start, end, s.first),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(preview, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
