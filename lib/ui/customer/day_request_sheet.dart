import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/day_requests.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';
import 'customer_home.dart' show QtyStepper;

/// "¿Ningún día te acomoda?": el cliente sugiere un día y una hora aproximada.
/// [items] llega con lo que trae en el carrito (nombre → piezas), si viene de ahí.
Future<void> showDayRequestSheet(BuildContext context, AppUser user,
    {Map<String, int> items = const {}}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Pan.papel,
    builder: (_) => DayRequestSheet(user: user, initialItems: items),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('¡Listo! 🐻 Si abrimos ese día te llega un aviso.'),
    ));
  }
}

class DayRequestSheet extends StatefulWidget {
  final AppUser user;
  final Map<String, int> initialItems;
  const DayRequestSheet({super.key, required this.user, this.initialItems = const {}});

  @override
  State<DayRequestSheet> createState() => _DayRequestSheetState();
}

class _DayRequestSheetState extends State<DayRequestSheet> {
  late final _dates = suggestableDates(DateTime.now());
  late final _days = Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now()));
  late final _points = Repo.instance.pickupPoints();
  late final _products = Repo.instance.products(onlyAvailable: true);
  late final _mine = Repo.instance.myDayRequests(widget.user.uid);
  late final Map<String, int> _items = {...widget.initialItems};
  final _note = TextEditingController();

  String? _date;
  String? _band;
  String _place = '';
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _setQty(String name, int qty) => setState(() => qty <= 0 ? _items.remove(name) : _items[name] = qty);

  /// Para cambiar una sugerencia que ya mandó: se llena con lo de antes.
  void _edit(DayRequest r) => setState(() {
        _date = r.date;
        _band = r.band;
        _place = r.place;
        _items
          ..clear()
          ..addAll(r.items);
        _note.text = r.note;
      });

  Future<void> _send() async {
    final date = _date, band = _band;
    if (date == null || band == null) return;
    setState(() => _busy = true);
    try {
      await Repo.instance.sendDayRequest(DayRequest(
        id: DayRequest.idFor(widget.user.uid, date),
        customerId: widget.user.uid,
        customerName: widget.user.name,
        date: date,
        band: band,
        place: _place,
        items: {
          for (final e in _items.entries)
            if (e.value > 0) e.key: e.value,
        },
        note: cleanRequestNote(_note.text),
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo mandar. Revisa tu internet e intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: StreamBuilder<List<DeliveryDay>>(
          stream: _days,
          builder: (context, daysSnap) {
            final open = {
              for (final d in orderableDays(daysSnap.data ?? const [], DateTime.now())) d.day: d
            };
            final openDay = _date == null ? null : open[_date];
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Sugiere un día', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    '¿Ningún día te acomoda? Dinos cuándo te gustaría tu pan. '
                    'Si abrimos ese día, te avisamos.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SectionTitle('¿Qué día?', padding: EdgeInsets.fromLTRB(4, 16, 4, 8)),
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: _dates.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => _DateChip(
                        date: _dates[i],
                        selected: _dates[i] == _date,
                        open: open.containsKey(_dates[i]),
                        onTap: () => setState(() => _date = _dates[i]),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: Motion.of(context, Motion.medio),
                    curve: Motion.curva,
                    alignment: Alignment.topCenter,
                    child: openDay == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _OpenDayNote(day: openDay),
                          ),
                  ),
                  const SectionTitle('¿A qué hora, más o menos?', padding: EdgeInsets.fromLTRB(4, 18, 4, 8)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in requestBands)
                        ChoiceChip(
                          selected: _band == b.key,
                          showCheckmark: false,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _band = b.key);
                          },
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(b.hours, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                    ],
                  ),
                  StreamBuilder<List<PickupPoint>>(
                    stream: _points,
                    builder: (context, snap) {
                      final points = snap.data ?? const <PickupPoint>[];
                      if (points.isEmpty && _place.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionTitle('¿Dónde?', padding: EdgeInsets.fromLTRB(4, 18, 4, 8)),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('🏠 A mi domicilio'),
                                selected: _place.isEmpty,
                                onSelected: (_) => setState(() => _place = ''),
                              ),
                              for (final name in {
                                for (final p in points) p.name,
                                if (_place.isNotEmpty) _place
                              })
                                ChoiceChip(
                                  label: Text('📍 $name'),
                                  selected: _place == name,
                                  onSelected: (_) => setState(() => _place = name),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SectionTitle('¿Qué pan te gustaría?', padding: EdgeInsets.fromLTRB(4, 18, 4, 2)),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child:
                        Text('Opcional. Nos ayuda a saber cuánto hornear.', style: theme.textTheme.bodySmall),
                  ),
                  StreamBuilder<List<Product>>(
                    stream: _products,
                    builder: (context, snap) => Column(
                      children: [
                        for (final p in snap.data ?? const <Product>[])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Pan.mielClara,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(productArt(p.name).$1, style: const TextStyle(fontSize: 19)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(p.name, style: theme.textTheme.titleSmall)),
                                QtyStepper(
                                  size: 32,
                                  qty: _items[p.name] ?? 0,
                                  onAdd: () => _setQty(p.name, (_items[p.name] ?? 0) + 1),
                                  onRemove: () => _setQty(p.name, (_items[p.name] ?? 0) - 1),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    maxLength: requestNoteMaxChars,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Algo más (opcional)',
                      hintText: 'Ej. Para un desayuno en la oficina',
                    ),
                  ),
                  const SizedBox(height: 8),
                  HoneyButton(
                    icon: Icons.send_rounded,
                    label: 'Mandar sugerencia',
                    busy: _busy,
                    onPressed: _date == null || _band == null ? null : _send,
                  ),
                  if (_date == null || _band == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _date == null ? 'Elige un día.' : 'Elige una hora aproximada.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  _MyRequests(stream: _mine, openDates: open.keys.toSet(), onEdit: _edit),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Un día para elegir: "VIE 28 nov". Los días que ya están abiertos llevan un puntito verde.
class _DateChip extends StatelessWidget {
  final String date;
  final bool selected;
  final bool open;
  final VoidCallback onTap;
  const _DateChip({required this.date, required this.selected, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = parseDateKey(date);
    final sub = selected ? Pan.tostado : Pan.canela;
    return Pressable(
      onTap: onTap,
      haptic: true,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medio),
        curve: Motion.curva,
        width: 62,
        decoration: BoxDecoration(
          gradient: selected ? Pan.gradienteMiel : null,
          color: selected ? null : Pan.crema,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Colors.transparent : const Color(0xFFEADCC4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(DateFormat('EEE', 'es_MX').format(d).replaceAll('.', '').toUpperCase(),
                style:
                    TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: sub)),
            Text('${d.day}',
                style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: Pan.cacao,
                    height: 1.15)),
            Text(DateFormat('MMM', 'es_MX').format(d).replaceAll('.', ''),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: sub)),
            if (open)
              Container(
                margin: const EdgeInsets.only(top: 3),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: Pan.salvia, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

/// Si el día que eligió ya está abierto: a qué hora hay entrega.
class _OpenDayNote extends StatelessWidget {
  final DeliveryDay day;
  const _OpenDayNote({required this.day});

  @override
  Widget build(BuildContext context) {
    final first = slotMinute(day.slots.first);
    final last = slotMinute(day.slots.last) + day.slotMinutes;
    final where = day.pickup == null ? 'a domicilio' : 'en ${day.pickup!.name}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: Pan.salviaClara, borderRadius: BorderRadius.circular(14)),
      child: Text(
        'Ese día ya hay entrega $where de ${clockLabel(first)} a ${clockLabel(last)}. '
        'Si te queda, mejor haz tu pedido; si no, sugiere otra hora.',
        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: const Color(0xFF3D5A31)),
      ),
    );
  }
}

/// Lo que ya sugirió (de hoy en adelante), con opción de cambiarlo o quitarlo.
class _MyRequests extends StatelessWidget {
  final Stream<List<DayRequest>> stream;
  final Set<String> openDates;
  final void Function(DayRequest) onEdit;
  const _MyRequests({required this.stream, required this.openDates, required this.onEdit});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<DayRequest>>(
        stream: stream,
        builder: (context, snap) {
          final today = dateKey(DateTime.now());
          final mine = [
            for (final r in snap.data ?? const <DayRequest>[])
              if (r.date.compareTo(today) >= 0) r
          ];
          if (mine.isEmpty) return const SizedBox.shrink();
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Lo que has sugerido'),
              for (final r in mine)
                PanCard(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  color: Pan.crema,
                  onTap: () => onEdit(r),
                  child: Row(
                    children: [
                      Text(r.notified || openDates.contains(r.date) ? '✅' : '🗓️',
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(capitalize(dayLabel(r.date)), style: theme.textTheme.titleSmall),
                            Text(requestSummary(r), style: theme.textTheme.bodySmall),
                            if (r.notified || openDates.contains(r.date))
                              Text(
                                '¡Ese día ya está abierto! Ya puedes pedir.',
                                style: theme.textTheme.bodySmall!
                                    .copyWith(color: Pan.salvia, fontWeight: FontWeight.w800),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Repo.instance.deleteDayRequest(r.id).catchError((_) {}),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

/// Tarjeta para el inicio del cliente. Con [noDays] es la grande de
/// "Todavía no hay días abiertos"; si no, la chiquita de "¿Ningún día te acomoda?".
class DayRequestCard extends StatelessWidget {
  final AppUser user;
  final bool noDays;
  const DayRequestCard({super.key, required this.user, this.noDays = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanCard(
      margin: const EdgeInsets.only(top: 12),
      color: noDays ? Pan.mielClara : Pan.harina,
      onTap: () => showDayRequestSheet(context, user),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Pan.papel, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('🗓️', style: TextStyle(fontSize: 26, height: 1)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noDays ? 'Todavía no hay días abiertos' : '¿Ningún día te acomoda?',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  noDays
                      ? 'Dinos qué día y a qué hora te gustaría tu pan, y te avisamos si lo abrimos.'
                      : 'Sugiérenos un día y una hora, y te avisamos si lo abrimos.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Pan.caramelo),
        ],
      ),
    );
  }
}
