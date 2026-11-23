import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/archive.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'orders_page.dart' show DeleteOrderButton;

/// Historial: los días ya repartidos, mes por mes, con lo que se vendió.
/// Aquí llegan solos los pedidos de días que ya pasaron, y los de hoy en cuanto
/// se entrega todo (ver logic/archive.dart). Nada se borra: sigue contando para
/// la tarjeta de lealtad de cada cliente.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late DateTime _month = _firstOf(DateTime.now());

  /// Días de hoy en adelante (para saber si hoy ya se cerró o se quitó).
  late final Stream<List<DeliveryDay>> _days = Repo.instance.deliveryDays(fromDate: dateKey(DateTime.now()));

  late Stream<List<BakeryOrder>> _orders = _ordersOf(_month);

  static DateTime _firstOf(DateTime d) => DateTime(d.year, d.month);

  static Stream<List<BakeryOrder>> _ordersOf(DateTime month) => Repo.instance.ordersBetween(
        dateKey(month),
        dateKey(DateTime(month.year, month.month + 1)),
      );

  bool get _isCurrentMonth => _month == _firstOf(DateTime.now());

  void _go(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _orders = _ordersOf(_month);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: Column(
        children: [
          _MonthSwitcher(
            label: capitalize(DateFormat('MMMM y', 'es_MX').format(_month)),
            onPrev: () => _go(-1),
            onNext: _isCurrentMonth ? null : () => _go(1),
          ),
          Expanded(
            child: StreamBuilder<List<DeliveryDay>>(
              stream: _days,
              builder: (context, daysSnap) => StreamBuilder<List<BakeryOrder>>(
                key: ValueKey(_month),
                stream: _orders,
                builder: (context, snap) => _body(context, snap, daysSnap),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncSnapshot<List<BakeryOrder>> snap,
    AsyncSnapshot<List<DeliveryDay>> daysSnap,
  ) {
    if (snap.hasError) {
      return EmptyState(title: 'No cargó el historial', message: '${snap.error}');
    }
    if (!snap.hasData) return const SkeletonList(count: 3);
    final today = dateKey(DateTime.now());
    final days = {for (final d in daysSnap.data ?? const <DeliveryDay>[]) d.date: d};
    final finished = finishedDates(snap.data!, today: today, days: days, daysLoaded: daysSnap.hasData);
    // Un día donde todo se canceló no tiene nada que mostrar.
    final withSales = {
      for (final o in snap.data!)
        if (o.status != OrderStatus.cancelado && finished.contains(o.deliveryDate)) o.deliveryDate,
    };
    final orders = snap.data!.where((o) => withSales.contains(o.deliveryDate)).toList();
    if (orders.isEmpty) {
      return EmptyState(
        title: 'Nada archivado ${_isCurrentMonth ? 'este mes' : 'en este mes'}',
        message: 'Cuando termines de repartir un día, sus pedidos se guardan aquí con lo que vendiste.',
      );
    }
    final dates = orders.map((o) => o.deliveryDate).toSet().toList()..sort((a, b) => b.compareTo(a));
    final children = <Widget>[
      _SummaryCard(summary: SalesSummary.of(orders)),
      for (final d in dates) _DayCard(date: d, orders: orders.where((o) => o.deliveryDate == d).toList()),
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: children.length,
      itemBuilder: (context, i) => FadeSlideIn(index: i, child: children[i]),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _MonthSwitcher({required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Mes anterior',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: AnimatedCount(
                label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Mes siguiente',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      );
}

/// Totales del mes: lo vendido, cómo se pagó y lo que falta cobrar.
class _SummaryCard extends StatelessWidget {
  final SalesSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return PanCard(
      gradient: const LinearGradient(
        colors: [Pan.mielClara, Pan.harina],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vendiste', style: small),
          Text(money(s.sold), style: theme.textTheme.headlineMedium!.copyWith(color: Pan.caramelo)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Stat(icon: Icons.calendar_today_rounded, text: '${s.days} ${s.days == 1 ? 'día' : 'días'}'),
              _Stat(
                icon: Icons.check_circle_rounded,
                text: '${s.delivered} ${s.delivered == 1 ? 'pedido' : 'pedidos'}',
              ),
              _Stat(icon: Icons.bakery_dining_rounded, text: '${s.pieces} ${s.pieces == 1 ? 'pieza' : 'piezas'}'),
              if (s.giftPieces > 0) _Stat(icon: Icons.card_giftcard_rounded, text: '${s.giftPieces} regaladas'),
            ],
          ),
          const SizedBox(height: 12),
          _Line(icon: Icons.payments_rounded, label: 'Efectivo', value: money(s.cash)),
          _Line(icon: Icons.account_balance_rounded, label: 'Transferencia', value: money(s.transfer)),
          if (s.shipping > 0) _Line(icon: Icons.delivery_dining_rounded, label: 'Envíos', value: money(s.shipping)),
          if (s.unpaidCount > 0)
            _Line(
              icon: Icons.error_outline_rounded,
              label: 'Sin marcar como cobrado (${s.unpaidCount})',
              value: money(s.unpaid),
              color: Pan.terracota,
            ),
          if (s.notDelivered > 0)
            _Line(
              icon: Icons.help_outline_rounded,
              label: 'Sin marcar como entregado',
              value: '${s.notDelivered}',
              color: Pan.terracota,
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Stat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Pan.papel, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Pan.tostado),
            const SizedBox(width: 5),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w800, color: Pan.tostado)),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _Line({required this.icon, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color ?? Pan.canela),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: style)),
          Text(value, style: style.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Un día repartido, plegado: al abrirlo se ven sus pedidos.
class _DayCard extends StatelessWidget {
  final String date;
  final List<BakeryOrder> orders;
  const _DayCard({required this.date, required this.orders});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SalesSummary.of(orders);
    final sorted = [...orders]..sort((a, b) {
        final c = a.slot.compareTo(b.slot);
        return c != 0 ? c : a.customerName.compareTo(b.customerName);
      });
    return PanCard(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      // Recorta el brillo al tocar para que no se salga de las esquinas redondas.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Pan.radio - 6),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(capitalize(dayLabel(date)), style: theme.textTheme.titleSmall),
          subtitle: Text(
            '${s.delivered} ${s.delivered == 1 ? 'pedido' : 'pedidos'} · ${s.pieces} '
            '${s.pieces == 1 ? 'pieza' : 'piezas'}'
            '${s.notDelivered > 0 ? ' · ${s.notDelivered} sin entregar' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Text(
            money(s.sold),
            style: theme.textTheme.titleMedium!.copyWith(color: Pan.caramelo, fontWeight: FontWeight.w800),
          ),
          children: [
            for (final o in sorted)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 12, right: 4),
                title: Text(
                  o.customerName,
                  style: theme.textTheme.titleSmall!.copyWith(
                    decoration: o.status == OrderStatus.cancelado ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  '${o.items.map((i) => '${i.qty} ${i.name}').join(', ')}\n'
                  '${money(o.total)} · ${_payLabel(o)}',
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: true,
                trailing: DeleteOrderButton(order: o),
              ),
          ],
        ),
      ),
    );
  }

  static String _payLabel(BakeryOrder o) {
    if (o.status == OrderStatus.cancelado) return 'Cancelado';
    if (o.status != OrderStatus.entregado) return 'Sin marcar como entregado';
    if (o.paymentMethod == PaymentMethod.efectivo) {
      return o.cashCollected ? 'Efectivo, cobrado' : 'Efectivo, sin marcar cobrado';
    }
    return o.paymentVerified ? 'Transferencia verificada' : 'Transferencia sin verificar';
  }
}
