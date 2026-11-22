import 'package:material_ui/material_ui.dart';

import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';

/// Días de entrega: el dueño abre días con sus horarios.
/// Se puede pedir hasta que el dueño pica "Empezar a repartir" ese día.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<DeliveryDay>>(
        stream: Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now())),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final days = snap.data!;
          if (days.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay días abiertos. Toca "Abrir días" para publicar tus próximas entregas.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [for (final d in days) _DayTile(day: d)],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _OpenDaysSheet(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Abrir días'),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  final DeliveryDay day;
  const _DayTile({required this.day});

  @override
  Widget build(BuildContext context) {
    final first = day.slots.isEmpty ? '' : day.slots.first;
    final last = day.slots.isEmpty ? '' : day.slots.last;
    final hours = day.slots.isEmpty
        ? 'Sin horarios'
        : '${slotLabel(first, minutes: day.slotMinutes).split(' a ').first} a '
            '${slotLabel(last, minutes: day.slotMinutes).split(' a ').last}';
    return Card(
      child: ListTile(
        title: Text(dayLabel(day.date)),
        subtitle: Text(day.closed ? '$hours · repartiendo, pedidos cerrados' : hours),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: day.open,
              onChanged: (v) => Repo.instance.saveDeliveryDay(DeliveryDay(
                date: day.date,
                open: v,
                slots: day.slots,
                slotMinutes: day.slotMinutes,
                closed: day.closed,
              )),
            ),
            IconButton(
              tooltip: 'Quitar día',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Repo.instance.deleteDeliveryDay(day.date),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abrir varios días de golpe, por ejemplo lunes, miércoles y viernes de 8 a 11.
class _OpenDaysSheet extends StatefulWidget {
  const _OpenDaysSheet();

  @override
  State<_OpenDaysSheet> createState() => _OpenDaysSheetState();
}

class _OpenDaysSheetState extends State<_OpenDaysSheet> {
  static const _weekdayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  final Set<int> _weekdays = {DateTime.monday, DateTime.wednesday, DateTime.friday};
  int _weeks = 1;
  int _startHour = 8;
  int _endHour = 11;
  bool _busy = false;

  /// Fechas que se van a abrir: los días elegidos en las próximas [_weeks] semanas.
  List<String> get _dates {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day + 1);
    return [
      for (var i = 0; i < 7 * _weeks; i++)
        DateTime(start.year, start.month, start.day + i),
    ].where((d) => _weekdays.contains(d.weekday)).map(dateKey).toList();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    for (final date in _dates) {
      await Repo.instance.saveDeliveryDay(DeliveryDay(
        date: date,
        open: true,
        slots: hourlySlots(_startHour, _endHour),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _hourPicker(String label, int value, ValueChanged<int> onChanged,
      {int min = 5, int max = 22}) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<int>(
          value: value,
          items: [
            for (var h = min; h <= max; h++) DropdownMenuItem(value: h, child: Text('$h:00')),
          ],
          onChanged: (v) => setState(() => onChanged(v!)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    final valid = _endHour > _startHour && dates.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Abrir días de entrega', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (var wd = 1; wd <= 7; wd++)
                FilterChip(
                  label: Text(_weekdayNames[wd - 1]),
                  selected: _weekdays.contains(wd),
                  onSelected: (s) => setState(() => s ? _weekdays.add(wd) : _weekdays.remove(wd)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Semanas')),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {_weeks},
                onSelectionChanged: (s) => setState(() => _weeks = s.first),
              ),
            ],
          ),
          _hourPicker('Primera entrega desde', _startHour, (v) => _startHour = v),
          _hourPicker('Última entrega hasta', _endHour, (v) => _endHour = v),
          const SizedBox(height: 8),
          Text(
            dates.isEmpty ? 'Elige al menos un día.' : 'Se abren ${dates.length} días, en horarios de una hora. '
                    'Se puede pedir hasta que empieces a repartir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: valid && !_busy ? _save : null,
              child: const Text('Abrir'),
            ),
          ),
        ],
      ),
    );
  }
}
