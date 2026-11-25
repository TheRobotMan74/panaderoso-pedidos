import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Mensajes rápidos: se tocan y quedan escritos (se pueden cambiar antes de mandar).
const quickMessages = [
  'No te preocupes, ya voy en camino 🚗',
  'Voy un poquito tarde, ¡gracias por tu paciencia! 🙏',
  'Ya estoy afuera de tu casa 🏠',
  'Llego en unos 10 minutos ⏰',
  'Hoy se nos atrasó el horno, llegamos un poco más tarde. ¡Perdón! 🥐',
  '¡Gracias por tu pedido! Que lo disfrutes 🐻',
];

/// Máximo de letras (igual que en functions/index.js → mandarMensaje).
const maxMessageLength = 300;

/// Un cliente con pedido pendiente en el día elegido.
class MessageRecipient {
  final String uid;
  final String name;
  final List<String> slots;
  const MessageRecipient(this.uid, this.name, this.slots);

  /// "Entrega 8:00 · 9:30"
  String get slotsText => 'Entrega ${slots.map((s) => s.startsWith('0') ? s.substring(1) : s).join(' · ')}';
}

/// Clientes con pedido pendiente en [date] (uno por cliente, por hora de entrega).
List<MessageRecipient> recipientsFor(List<BakeryOrder> orders, String date) {
  final byUid = <String, List<BakeryOrder>>{};
  for (final o in orders) {
    if (o.deliveryDate != date || !o.isPending || o.customerId.isEmpty) continue;
    byUid.putIfAbsent(o.customerId, () => []).add(o);
  }
  final list = [
    for (final e in byUid.entries)
      MessageRecipient(
        e.key,
        e.value.first.customerName.trim().isEmpty ? 'Cliente' : e.value.first.customerName.trim(),
        (e.value.map((o) => o.slot).toSet().toList()..sort()),
      ),
  ];
  list.sort((a, b) {
    final c = a.slots.first.compareTo(b.slots.first);
    return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}

/// El dueño escribe un mensaje y le llega como notificación a todos los clientes
/// con pedido ese día, o solo a los que él elija.
class SendMessagePage extends StatefulWidget {
  const SendMessagePage({super.key});

  @override
  State<SendMessagePage> createState() => _SendMessagePageState();
}

class _SendMessagePageState extends State<SendMessagePage> {
  final _text = TextEditingController();
  late final Stream<List<BakeryOrder>> _orders = Repo.instance.ordersFrom(dateKey(DateTime.now()));
  String? _date;
  bool _everyone = true;
  final Set<String> _picked = {};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Lugar de los repartos especiales (id del día → "Acuity"), para distinguir
  /// dos repartos del mismo día.
  Map<String, String> _places = const {};

  String _dayChip(String date) {
    final now = DateTime.now();
    final day = dayDateOf(date);
    final String text;
    if (day == dateKey(now)) {
      text = 'Hoy';
    } else if (day == dateKey(DateTime(now.year, now.month, now.day + 1))) {
      text = 'Mañana';
    } else {
      text = capitalize(dayLabel(date));
    }
    final place = _places[date];
    return place != null ? '$text · 📍 $place' : text;
  }

  Future<void> _send(List<MessageRecipient> people) async {
    final text = _text.text.trim();
    final targets = _everyone ? people : people.where((p) => _picked.contains(p.uid)).toList();
    if (text.isEmpty || targets.isEmpty) return;
    final n = targets.length;
    final who = _everyone
        ? (n == 1 ? 'al cliente con pedido ${_dayChip(_date!).toLowerCase()}' : 'a los $n clientes con pedido ${_dayChip(_date!).toLowerCase()}')
        : (n == 1 ? 'a ${targets.first.name}' : 'a $n clientes');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded, color: Pan.caramelo, size: 32),
        title: const Text('¿Mandar el mensaje?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Le llega como notificación $who.'),
            const SizedBox(height: 14),
            NotificationPreview(text: text),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, mandar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _sending = true);
    try {
      final (sent, noPush) = _everyone
          ? await Repo.instance.sendOwnerMessage(text, date: _date)
          : await Repo.instance.sendOwnerMessage(text, customerIds: [for (final t in targets) t.uid]);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _text.clear();
      });
      final msg = StringBuffer(sent == 1 ? 'Le llegó a 1 cliente ✓' : 'Les llegó a $sent clientes ✓');
      if (noPush > 0) {
        msg.write(noPush == 1
            ? '\n1 no tiene los avisos activados: mejor mándale WhatsApp.'
            : '\n$noPush no tienen los avisos activados: mejor mándales WhatsApp.');
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
    } on RejectedByServer catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo mandar. Revisa tu internet e intenta de nuevo. ($e)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mandar mensaje')),
      body: StreamBuilder<List<BakeryOrder>>(
        stream: _orders,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(title: 'No se pudieron cargar los pedidos', message: '${snap.error}');
          }
          if (!snap.hasData) return const SkeletonList();
          final orders = snap.data!;
          final dates = {for (final o in orders) if (o.isPending) o.deliveryDate}.toList()..sort();
          _places = {for (final o in orders) if (o.isPickup) o.deliveryDate: o.pickupName!};
          if (dates.isEmpty) {
            return const EmptyState(
              title: 'No hay pedidos pendientes',
              message: 'Cuando alguien tenga un pedido por entregar, aquí le puedes mandar un mensaje.',
            );
          }
          if (_date == null || !dates.contains(_date)) _date = dates.first;
          final people = recipientsFor(orders, _date!);
          _picked.retainAll(people.map((p) => p.uid));
          return _form(context, dates, people);
        },
      ),
    );
  }

  Widget _form(BuildContext context, List<String> dates, List<MessageRecipient> people) {
    final theme = Theme.of(context);
    final count = _everyone ? people.length : _picked.length;
    final canSend = _text.text.trim().isNotEmpty && count > 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const SectionTitle('Tu mensaje'),
        TextField(
          controller: _text,
          minLines: 3,
          maxLines: 6,
          maxLength: maxMessageLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ej. No te preocupes, ya voy en camino'),
        ),
        Text('Mensajes rápidos', style: theme.textTheme.labelLarge!.copyWith(color: Pan.canela)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in quickMessages)
              ActionChip(
                label: Text(q),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _text.value = TextEditingValue(
                    text: q,
                    selection: TextSelection.collapsed(offset: q.length),
                  );
                },
              ),
          ],
        ),
        const SectionTitle('¿Para quién?'),
        if (dates.length > 1) ...[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final d in dates)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(_dayChip(d)),
                      selected: d == _date,
                      onSelected: (_) => setState(() => _date = d),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4),
            child: Text('Pedidos de ${_dayChip(_date!).toLowerCase()}',
                style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela)),
          ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text('Todos (${people.length})')),
              const ButtonSegment(value: false, label: Text('Elegir clientes')),
            ],
            selected: {_everyone},
            onSelectionChanged: (s) => setState(() => _everyone = s.first),
          ),
        ),
        const SizedBox(height: 8),
        PanCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              if (!_everyone)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() {
                      if (_picked.length == people.length) {
                        _picked.clear();
                      } else {
                        _picked.addAll(people.map((p) => p.uid));
                      }
                    }),
                    child: Text(_picked.length == people.length ? 'Quitar todos' : 'Elegir todos'),
                  ),
                ),
              for (final p in people)
                _everyone
                    ? ListTile(
                        dense: true,
                        title: Text(p.name),
                        subtitle: Text(p.slotsText),
                      )
                    : CheckboxListTile(
                        dense: true,
                        value: _picked.contains(p.uid),
                        title: Text(p.name),
                        subtitle: Text(p.slotsText),
                        onChanged: (v) => setState(() {
                          v == true ? _picked.add(p.uid) : _picked.remove(p.uid);
                        }),
                      ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_text.text.trim().isNotEmpty) ...[
          Text('Así le llega', style: theme.textTheme.labelLarge!.copyWith(color: Pan.canela)),
          const SizedBox(height: 6),
          NotificationPreview(text: _text.text.trim()),
          const SizedBox(height: 20),
        ],
        HoneyButton(
          label: count == 0
              ? 'Elige a quién mandarle'
              : (count == 1 ? 'Mandar a 1 cliente' : 'Mandar a $count clientes'),
          icon: Icons.notifications_active_rounded,
          busy: _sending,
          onPressed: canSend ? () => _send(people) : null,
        ),
      ],
    );
  }
}

/// Cómo se ve la notificación en el celular del cliente.
class NotificationPreview extends StatelessWidget {
  final String text;
  const NotificationPreview({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Pan.harina,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BearLogo(size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Panaderoso 🥐', style: theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
