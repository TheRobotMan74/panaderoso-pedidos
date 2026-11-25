import 'package:material_ui/material_ui.dart';

import '../../logic/day_requests.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';

/// Días que piden los clientes: cuántos quieren cada día, a qué hora, dónde y
/// qué pan, para decidir qué días abrir. [onOpenDay] abre la hoja de "Abrir días"
/// ya con ese día y ese horario.
class DayRequestsPage extends StatefulWidget {
  final void Function(BuildContext context, RequestedDay day) onOpenDay;
  const DayRequestsPage({super.key, required this.onOpenDay});

  @override
  State<DayRequestsPage> createState() => _DayRequestsPageState();
}

class _DayRequestsPageState extends State<DayRequestsPage> {
  late final _requests = Repo.instance.allDayRequests();
  late final _days = Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now()));

  /// Las que eran nuevas al abrir la pantalla siguen con su etiqueta "Nueva".
  final _newIds = <String>{};

  void _markSeen(List<DayRequest> list) {
    final ids = [
      for (final r in list)
        if (!r.seen && !_newIds.contains(r.id)) r.id,
    ];
    if (ids.isEmpty) return;
    _newIds.addAll(ids);
    Repo.instance.markDayRequests(ids, seen: true).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Días que piden')),
      body: StreamBuilder<List<DayRequest>>(
        stream: _requests,
        builder: (context, snap) => StreamBuilder<List<DeliveryDay>>(
          stream: _days,
          builder: (context, daysSnap) {
            if (snap.hasError) {
              return EmptyState(title: 'No cargaron las sugerencias', message: '${snap.error}');
            }
            if (!snap.hasData) return const SkeletonList(count: 3);
            final groups = groupRequests(snap.data!, DateTime.now());
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _markSeen([for (final g in groups) ...g.requests]));
            if (groups.isEmpty) {
              return const EmptyState(
                title: 'Nadie ha sugerido días',
                message: 'Cuando un cliente no encuentre un día que le acomode, '
                    'aquí vas a ver qué día y a qué hora le gustaría su pan.',
              );
            }
            final open = {
              for (final d in orderableDays(daysSnap.data ?? const [], DateTime.now())) d.date: d
            };
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: groups.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  final people = {
                    for (final g in groups)
                      for (final r in g.requests) r.customerId
                  }.length;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                    child: Text(
                      '$people ${people == 1 ? 'cliente sugirió' : 'clientes sugirieron'} '
                      '${groups.length} ${groups.length == 1 ? 'día' : 'días'}. '
                      'Los más pedidos tienen la barra más llena.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                final g = groups[i - 1];
                final most = groups.map((x) => x.customers).reduce((a, b) => a > b ? a : b);
                return FadeSlideIn(
                  index: i,
                  child: RequestedDayCard(
                    day: g,
                    most: most,
                    openDay: open[g.date],
                    newIds: _newIds,
                    onOpen: () => widget.onOpenDay(context, g),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Un día que piden: "Viernes 28 · 4 clientes", las horas, dónde, qué pan, y quiénes.
class RequestedDayCard extends StatelessWidget {
  final RequestedDay day;

  /// El día con más clientes (para la barra).
  final int most;

  /// Si ese día ya está abierto.
  final DeliveryDay? openDay;
  final Set<String> newIds;
  final VoidCallback onOpen;
  const RequestedDayCard({
    super.key,
    required this.day,
    required this.most,
    required this.onOpen,
    this.openDay,
    this.newIds = const {},
  });

  Future<void> _notify(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    final sent = await notifyRequesters(context, [day.date], day.pending);
    if (sent != null) m.showSnackBar(SnackBar(content: Text(sent)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = day;
    final isNew = g.requests.any((r) => !r.seen || newIds.contains(r.id));
    final pending = g.pending.length;
    return PanCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(capitalize(dayLabel(g.date)), style: theme.textTheme.titleMedium)),
              if (isNew) const _Pill('Nueva', Pan.miel, Pan.cacao),
              if (openDay != null) ...[
                const SizedBox(width: 6),
                const _Pill('Abierto', Pan.salviaClara, Color(0xFF3D5A31)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('🙋 ${g.customers} ${g.customers == 1 ? 'cliente' : 'clientes'}',
                  style: theme.textTheme.titleSmall!.copyWith(color: Pan.caramelo)),
              if (g.totalPieces > 0)
                Text('  ·  ${g.totalPieces} ${g.totalPieces == 1 ? 'pieza' : 'piezas'}',
                    style: theme.textTheme.titleSmall!.copyWith(color: Pan.canela)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: most == 0 ? 0 : g.customers / most,
              minHeight: 8,
              color: Pan.miel,
              backgroundColor: Pan.harina,
            ),
          ),
          const SizedBox(height: 12),
          for (final (b, n) in g.bands)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text('${b.name} ',
                        style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(child: Text(b.hours, style: theme.textTheme.bodySmall)),
                  Text('$n', style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (place, n) in g.places)
                _Chip(place.isEmpty ? '🏠 A domicilio · $n' : '📍 $place · $n'),
              for (final (name, n) in g.pieces) _Chip('${productArt(name).$1} $n $name'),
            ],
          ),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title:
                  Text('Quiénes', style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
              children: [
                for (final r in g.requests)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.notified ? '✅' : '•', style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.customerName.isEmpty ? 'Cliente' : r.customerName,
                                  style: theme.textTheme.titleSmall),
                              Text(requestSummary(r), style: theme.textTheme.bodySmall),
                              if (r.items.isNotEmpty)
                                Text(r.items.entries.map((e) => '${e.value} ${e.key}').join(', '),
                                    style: theme.textTheme.bodySmall),
                              if (r.note.isNotEmpty)
                                Text('“${r.note}”',
                                    style: theme.textTheme.bodySmall!.copyWith(fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Borrar',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                          onPressed: () => Repo.instance.deleteDayRequest(r.id).catchError((_) {}),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (openDay == null)
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Abrir este día'),
            )
          else if (pending > 0)
            FilledButton.tonalIcon(
              onPressed: () => _notify(context),
              icon: const Icon(Icons.notifications_active_rounded),
              label: Text('Avisarles que ya está abierto ($pending)'),
            )
          else
            Text('✅ Ya les avisaste.', style: theme.textTheme.bodySmall!.copyWith(color: Pan.salvia)),
        ],
      ),
    );
  }
}

/// Pregunta si se les avisa a quienes pidieron estos días y les manda el aviso.
/// Regresa el texto para el aviso de abajo (null si dijo que no).
Future<String?> notifyRequesters(BuildContext context, List<String> dates, List<DayRequest> requests) async {
  if (requests.isEmpty) return null;
  final people = {for (final r in requests) r.customerId}.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(people == 1
          ? '1 cliente pidió ${dates.length == 1 ? 'este día' : 'estos días'}'
          : '$people clientes pidieron ${dates.length == 1 ? 'este día' : 'estos días'}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Les mando un aviso? Les va a llegar así:'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Pan.crema, borderRadius: BorderRadius.circular(14)),
            child: Text(openedDayMessage(dayLabel(requests.first.date))),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Avisarles')),
      ],
    ),
  );
  if (ok != true) return null;
  var sent = 0, off = 0;
  try {
    // Un mensaje por día, cada uno con su fecha.
    final byDate = <String, List<DayRequest>>{};
    for (final r in requests) {
      byDate.putIfAbsent(r.date, () => []).add(r);
    }
    for (final e in byDate.entries) {
      final (s, o) = await Repo.instance.sendOwnerMessage(
        openedDayMessage(dayLabel(e.key)),
        customerIds: [for (final r in e.value) r.customerId],
      );
      sent += s;
      off += o;
      await Repo.instance.markDayRequests([for (final r in e.value) r.id], notified: true, seen: true);
    }
  } catch (e) {
    return 'No se pudo mandar el aviso: $e';
  }
  return off == 0
      ? 'Listo, les llegó el aviso a $sent.'
      : 'Les llegó a $sent. $off ${off == 1 ? 'no tiene' : 'no tienen'} avisos prendidos '
          '(cuando abran la app lo ven en "Lo que has sugerido").';
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Pill(this.text, this.bg, this.fg);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: fg)),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Pan.crema, borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Pan.tostado)),
      );
}

/// Arriba de "Días de entrega": "4 clientes piden días → Ver".
class DayRequestsBanner extends StatelessWidget {
  final void Function(BuildContext context, RequestedDay day) onOpenDay;
  const DayRequestsBanner({super.key, required this.onOpenDay});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<DayRequest>>(
        stream: Repo.instance.allDayRequests(),
        builder: (context, snap) {
          final groups = groupRequests(snap.data ?? const [], DateTime.now());
          final child = groups.isEmpty ? const SizedBox(width: double.infinity) : _card(context, groups);
          return AnimatedSize(
            duration: Motion.of(context, Motion.medio),
            curve: Motion.curva,
            alignment: Alignment.topCenter,
            child: child,
          );
        },
      );

  Widget _card(BuildContext context, List<RequestedDay> groups) {
    final theme = Theme.of(context);
    final people = {
      for (final g in groups)
        for (final r in g.requests) r.customerId
    }.length;
    final unseen = groups.fold(0, (a, g) => a + g.requests.where((r) => !r.seen).length);
    final top = [...groups]..sort((a, b) => b.customers.compareTo(a.customers));
    return PanCard(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      color: Pan.mielClara,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DayRequestsPage(onOpenDay: onOpenDay)),
      ),
      child: Row(
        children: [
          Badge(
            isLabelVisible: unseen > 0,
            label: Text('$unseen'),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: Pan.papel, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('🙋', style: TextStyle(fontSize: 24, height: 1)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$people ${people == 1 ? 'cliente pide' : 'clientes piden'} días',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'El más pedido: ${dayLabel(top.first.date)} '
                  '(${top.first.customers} ${top.first.customers == 1 ? 'cliente' : 'clientes'})',
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
