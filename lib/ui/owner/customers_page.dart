import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../logic/customers.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../customer/my_orders_page.dart' show whatsAppUrl;
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'loyalty_customers_page.dart';
import 'send_message_page.dart' show NotificationPreview, maxMessageLength, quickMessages;

/// Mensajes rápidos para clientes elegidos (no solo los del reparto).
const customerQuickMessages = [
  '¡Ya puedes hacer tu pedido para esta semana! 🥐',
  'Mañana horneamos, ¿te aparto algo? 🐻',
  'Recuerda que tu pedido llega mañana ⏰',
  '¡Gracias por tu pedido! Que lo disfrutes 🐻',
];

/// "Hoy", "Mañana" o "Vie 28".
String shortDayChip(String date, DateTime now) {
  if (date == dateKey(now)) return 'Hoy';
  if (date == dateKey(DateTime(now.year, now.month, now.day + 1))) return 'Mañana';
  final d = parseDateKey(date);
  const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  return '${days[d.weekday - 1]} ${d.day}';
}

/// "15 nov".
String shortDate(String date) => DateFormat('d MMM', 'es_MX').format(parseDateKey(date)).replaceAll('.', '');

Future<void> _openWhatsApp(BuildContext context, String phone, String text) async {
  final ok = await launchUrl(whatsAppUrl(phone, text), mode: LaunchMode.externalApplication)
      .catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.')));
  }
}

/// Todos los clientes: datos, direcciones, cuántos pedidos y si tienen avisos.
/// Se pueden elegir varios (o a todos los de un día) y mandarles un aviso.
class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

/// Filtro de arriba: todos, sin avisos o los que tienen pedido un día.
sealed class _Filter {
  const _Filter();
}

class _All extends _Filter {
  const _All();
}

class _NoPush extends _Filter {
  const _NoPush();
}

class _Day extends _Filter {
  final String date;
  const _Day(this.date);
}

class _CustomersPageState extends State<CustomersPage> {
  final _search = TextEditingController();
  late final _users = Repo.instance.customers();
  late final _orders = Repo.instance.allOrders();
  _Filter _filter = const _All();
  bool _selecting = false;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String uid) {
    HapticFeedback.selectionClick();
    setState(() {
      _selecting = true;
      _picked.contains(uid) ? _picked.remove(uid) : _picked.add(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Tarjetas de lealtad',
            icon: const Icon(Icons.card_giftcard_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const LoyaltyCustomersPage())),
          ),
        ],
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: _users,
        builder: (context, uSnap) => StreamBuilder<List<BakeryOrder>>(
          stream: _orders,
          builder: (context, oSnap) {
            if (uSnap.hasError || oSnap.hasError) {
              return EmptyState(
                title: 'No se pudieron cargar los clientes',
                message: 'Revisa tu conexión e intenta de nuevo. (${uSnap.error ?? oSnap.error})',
              );
            }
            if (!uSnap.hasData || !oSnap.hasData) return const SkeletonList(count: 6);
            final all = summarizeCustomers(uSnap.data!, oSnap.data!);
            if (all.isEmpty) {
              return const EmptyState(
                title: 'Todavía no hay clientes',
                message: 'Aquí vas a ver a cada quien en cuanto se registre en la app.',
              );
            }
            return _body(context, all);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<CustomerSummary> all) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final days = pendingDays(all, dateKey(now));
    final noPush = all.where((c) => c.push == PushState.off).toList();
    final f = _filter;
    if (f is _Day && !days.any((d) => d.$1 == f.date)) _filter = const _All();
    final filtered = switch (_filter) {
      _All() => all,
      _NoPush() => noPush,
      _Day(:final date) => all.where((c) => c.pendingDates.contains(date)).toList(),
    };
    final list = filtered.where((c) => c.matches(_search.text)).toList();
    final byUid = {for (final c in all) c.uid: c};
    _picked.retainAll(byUid.keys);
    final allPicked = list.isNotEmpty && list.every((c) => _picked.contains(c.uid));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                '${all.length == 1 ? '1 cliente' : '${all.length} clientes'}'
                '${noPush.isEmpty ? '' : ' · ${noPush.length} con avisos apagados 🔕'}',
                style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Buscar por nombre, teléfono o dirección',
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('Todos (${all.length})', _filter is _All, const _All()),
                    if (noPush.isNotEmpty)
                      _chip('🔕 Sin avisos (${noPush.length})', _filter is _NoPush, const _NoPush()),
                    for (final (date, n) in days)
                      _chip('Pedido ${shortDayChip(date, now).toLowerCase()} ($n)',
                          f is _Day && f.date == date, _Day(date)),
                  ],
                ),
              ),
              if (_filter is _NoPush) ...[
                const SizedBox(height: 8),
                PanCard(
                  color: Pan.mielClara.withValues(alpha: 0.45),
                  child: Text(
                    'A ellos no les llegan los avisos de la app. Toca 💬 para mandarle a cada uno '
                    'un WhatsApp ya escrito que le explica cómo prender las notificaciones.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
              SectionTitle(
                list.isEmpty
                    ? 'Nadie con esa búsqueda'
                    : (list.length == 1 ? '1 cliente' : '${list.length} clientes'),
                trailing: list.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => setState(() {
                          if (!_selecting) {
                            _selecting = true;
                          } else if (allPicked) {
                            _picked.removeAll(list.map((c) => c.uid));
                          } else {
                            _picked.addAll(list.map((c) => c.uid));
                          }
                        }),
                        child: Text(!_selecting ? 'Elegir' : (allPicked ? 'Quitar todos' : 'Elegir todos')),
                      ),
              ),
              for (final c in list)
                _CustomerTile(
                  c: c,
                  now: now,
                  selecting: _selecting,
                  selected: _picked.contains(c.uid),
                  onTap: _selecting ? () => _toggle(c.uid) : () => _showDetail(context, c),
                  onLongPress: () => _toggle(c.uid),
                ),
            ],
          ),
        ),
        if (_selecting)
          _selectionBar(context, [
            for (final id in _picked)
              if (byUid[id] != null) byUid[id]!
          ]),
      ],
    );
  }

  Widget _chip(String label, bool selected, _Filter value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          showCheckmark: false,
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _filter = value),
        ),
      );

  Widget _selectionBar(BuildContext context, List<CustomerSummary> picked) {
    final n = picked.length;
    return Material(
      color: Pan.papel,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Dejar de elegir',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _selecting = false;
                  _picked.clear();
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: HoneyButton(
                  label: n == 0 ? 'Elige clientes' : (n == 1 ? 'Mandar aviso a 1' : 'Mandar aviso a $n'),
                  icon: Icons.notifications_active_rounded,
                  onPressed: n == 0 ? null : () => _compose(context, picked),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _compose(BuildContext context, List<CustomerSummary> people) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CustomerMessagePage(people: people)),
    );
    if (sent == true && mounted) {
      setState(() {
        _selecting = false;
        _picked.clear();
      });
    }
  }

  void _showDetail(BuildContext context, CustomerSummary c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CustomerDetail(
        c: c,
        onMessage: () {
          Navigator.pop(ctx);
          _compose(context, [c]);
        },
      ),
    );
  }
}

class _PushBadge extends StatelessWidget {
  final PushState push;
  const _PushBadge(this.push);

  @override
  Widget build(BuildContext context) {
    if (push == PushState.unknown) return const SizedBox.shrink();
    final off = push == PushState.off;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: off ? const Color(0xFFF8E1DC) : Pan.salviaClara,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        off ? '🔕 Avisos apagados' : '🔔 Avisos',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: off ? Pan.terracota : Pan.salvia),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerSummary c;
  final DateTime now;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _CustomerTile({
    required this.c,
    required this.now,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addr = c.addresses.isEmpty ? null : c.addresses.first;
    final next = c.nextDate(dateKey(now));
    final stats = c.orders == 0
        ? 'Todavía no ha pedido'
        : '${c.orders == 1 ? '1 pedido' : '${c.orders} pedidos'} · '
            '${next != null ? 'próximo ${shortDayChip(next, now).toLowerCase()}' : 'último ${shortDate(c.lastDate!)}'}';
    return GestureDetector(
      onLongPress: onLongPress,
      child: PanCard(
        onTap: onTap,
        color: selected ? Pan.mielClara.withValues(alpha: 0.55) : null,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            if (selecting)
              Checkbox(value: selected, onChanged: (_) => onTap())
            else
              CircleAvatar(
                radius: 20,
                backgroundColor: Pan.harina,
                child: Text(
                  c.displayName.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Pan.tostado),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.displayName, style: theme.textTheme.titleMedium),
                  if (c.phone.isNotEmpty) Text(c.phone, style: theme.textTheme.bodySmall),
                  if (addr != null)
                    Text(
                      c.addresses.length > 1 ? '${addr.address} (+${c.addresses.length - 1})' : addr.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(color: Pan.canela),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(stats, style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600)),
                      _PushBadge(c.push),
                    ],
                  ),
                ],
              ),
            ),
            if (!selecting && c.push == PushState.off && c.phone.isNotEmpty)
              IconButton(
                tooltip: 'WhatsApp para que active los avisos',
                icon: const Icon(Icons.chat_rounded, color: Pan.salvia),
                onPressed: () => _openWhatsApp(context, c.phone, pushReminderText(c.name)),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomerDetail extends StatelessWidget {
  final CustomerSummary c;
  final VoidCallback onMessage;
  const _CustomerDetail({required this.c, required this.onMessage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final upcoming = (c.pendingDates.where((d) => d.compareTo(dateKey(now)) >= 0).toList()..sort());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.displayName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            _PushBadge(c.push),
            if (c.push == PushState.unknown)
              Text('Todavía no sabemos si tiene los avisos prendidos.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(
              c.orders == 0
                  ? 'Todavía no ha pedido.'
                  : '${c.orders == 1 ? '1 pedido' : '${c.orders} pedidos'} · ${c.pieces} piezas · '
                      'el más reciente: ${dayLabel(c.lastDate!)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (upcoming.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tiene pedido: ${upcoming.map((d) => shortDayChip(d, now)).join(', ')}',
                  style:
                      theme.textTheme.bodyMedium!.copyWith(color: Pan.caramelo, fontWeight: FontWeight.w700),
                ),
              ),
            if (c.phone.isNotEmpty) ...[
              const SectionTitle('Teléfono'),
              SelectableText(c.phone, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.phone_outlined),
                    label: const Text('Llamar'),
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.phone)),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('WhatsApp'),
                    onPressed: () => _openWhatsApp(context, c.phone, ''),
                  ),
                  if (c.push == PushState.off)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.notifications_active_rounded),
                      label: const Text('Recordarle activar avisos'),
                      onPressed: () => _openWhatsApp(context, c.phone, pushReminderText(c.name)),
                    ),
                ],
              ),
            ],
            if (c.addresses.isNotEmpty) ...[
              SectionTitle(c.addresses.length == 1 ? 'Dirección' : 'Direcciones'),
              for (final a in c.addresses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place_outlined, size: 20, color: Pan.caramelo),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (a.label.isNotEmpty)
                              Text(a.label, style: theme.textTheme.labelLarge!.copyWith(color: Pan.canela)),
                            Text(a.address, style: theme.textTheme.bodyMedium),
                            if (a.notes.isNotEmpty) Text(a.notes, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            HoneyButton(
              label: 'Mandarle un aviso',
              icon: Icons.notifications_active_rounded,
              onPressed: onMessage,
            ),
          ],
        ),
      ),
    );
  }
}

/// Escribir un aviso para los clientes elegidos en la sección Clientes.
/// Les llega como notificación; a los que tienen los avisos apagados se les
/// puede mandar el mismo texto por WhatsApp, uno por uno.
class CustomerMessagePage extends StatefulWidget {
  final List<CustomerSummary> people;
  const CustomerMessagePage({super.key, required this.people});

  @override
  State<CustomerMessagePage> createState() => _CustomerMessagePageState();
}

class _CustomerMessagePageState extends State<CustomerMessagePage> {
  final _text = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  final Set<String> _whatsapped = {};

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

  Future<void> _send() async {
    final text = _text.text.trim();
    final people = widget.people;
    if (text.isEmpty || people.isEmpty) return;
    final who = people.length == 1 ? 'a ${people.first.displayName}' : 'a ${people.length} clientes';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded, color: Pan.caramelo, size: 32),
        title: const Text('¿Mandar el aviso?'),
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
      var sent = 0, noPush = 0;
      for (final part in chunked([for (final p in people) p.uid], 200)) {
        final (s, n) = await Repo.instance.sendOwnerMessage(text, customerIds: part);
        sent += s;
        noPush += n;
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
      final msg = StringBuffer(sent == 1 ? 'Le llegó a 1 cliente ✓' : 'Les llegó a $sent clientes ✓');
      if (noPush > 0) {
        msg.write(noPush == 1
            ? '\n1 no tiene los avisos activados: mándale WhatsApp.'
            : '\n$noPush no tienen los avisos activados: mándales WhatsApp.');
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
      if (noPush == 0 && !people.any((p) => p.push == PushState.off)) Navigator.of(context).pop(true);
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
    final theme = Theme.of(context);
    final people = widget.people;
    final off = people.where((p) => p.push == PushState.off).toList();
    final text = _text.text.trim();
    final quick = [
      ...customerQuickMessages,
      ...quickMessages.where((q) => !customerQuickMessages.contains(q))
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
            people.length == 1 ? 'Aviso a ${people.first.displayName}' : 'Aviso a ${people.length} clientes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(_sent),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const SectionTitle('Tu mensaje'),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            maxLength: maxMessageLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Ej. ¡Ya puedes hacer tu pedido para el viernes!'),
          ),
          Text('Mensajes rápidos', style: theme.textTheme.labelLarge!.copyWith(color: Pan.canela)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in quick)
                ActionChip(
                  label: Text(q),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _text.value =
                        TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
                  },
                ),
            ],
          ),
          const SectionTitle('Para'),
          Text(
            people.map((p) => p.displayName).join(', '),
            style: theme.textTheme.bodyMedium,
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Así le llega', style: theme.textTheme.labelLarge!.copyWith(color: Pan.canela)),
            const SizedBox(height: 6),
            NotificationPreview(text: text),
          ],
          const SizedBox(height: 20),
          HoneyButton(
            label: _sent
                ? 'Mandado ✓'
                : (people.length == 1 ? 'Mandar a 1 cliente' : 'Mandar a ${people.length} clientes'),
            icon: Icons.notifications_active_rounded,
            busy: _sending,
            onPressed: text.isEmpty || _sent ? null : _send,
          ),
          if (off.isNotEmpty) ...[
            const SectionTitle('🔕 A estos no les llega la notificación'),
            Text(
              text.isEmpty
                  ? 'Tienen los avisos apagados. Escribe el mensaje y mándaselo por WhatsApp, o recuérdales que los activen.'
                  : 'Tienen los avisos apagados. Toca WhatsApp para mandarle a cada uno este mismo mensaje.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            for (final p in off)
              PanCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_whatsapped.contains(p.uid) ? '✓ ' : ''}${p.displayName}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (p.phone.isEmpty)
                      Text('Sin teléfono', style: theme.textTheme.bodySmall)
                    else ...[
                      TextButton(
                        onPressed: () {
                          setState(() => _whatsapped.add(p.uid));
                          _openWhatsApp(context, p.phone, pushReminderText(p.name));
                        },
                        child: const Text('Recordar avisos'),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: const Text('WhatsApp'),
                        onPressed: text.isEmpty
                            ? null
                            : () {
                                setState(() => _whatsapped.add(p.uid));
                                _openWhatsApp(context, p.phone, text);
                              },
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
