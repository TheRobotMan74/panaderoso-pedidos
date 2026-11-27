import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/archive.dart';
import '../../logic/flavors.dart';
import '../../logic/market.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../market/market_pos_page.dart' show MarketSaleTile;
import '../product_image.dart';
import '../theme.dart';
import '../widgets.dart';
import 'orders_page.dart' show DeleteOrderButton;

/// Historial: los días ya repartidos, mes por mes, con lo que se vendió.
/// Aquí llegan solos los pedidos de días que ya pasaron, y los de hoy en cuanto
/// se entrega todo (ver logic/archive.dart). Nada se borra: sigue contando para
/// la tarjeta de lealtad de cada cliente. También van los mercaditos ya cerrados
/// (ver logic/market.dart), sumados a lo vendido del mes.
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
  late Stream<List<Market>> _markets = _marketsOf(_month);
  late Stream<List<MarketSale>> _marketSales = _marketSalesOf(_month);

  static DateTime _firstOf(DateTime d) => DateTime(d.year, d.month);

  static String _end(DateTime month) => dateKey(DateTime(month.year, month.month + 1));

  static Stream<List<BakeryOrder>> _ordersOf(DateTime month) =>
      Repo.instance.ordersBetween(dateKey(month), _end(month));

  /// Si el mercadito no carga (por ejemplo, reglas viejas), el Historial sigue igual.
  static Stream<List<Market>> _marketsOf(DateTime month) =>
      Repo.instance.marketsBetween(dateKey(month), _end(month)).handleError((_) {});

  static Stream<List<MarketSale>> _marketSalesOf(DateTime month) =>
      Repo.instance.marketSalesBetween(dateKey(month), _end(month)).handleError((_) {});

  bool get _isCurrentMonth => _month == _firstOf(DateTime.now());

  void _go(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _orders = _ordersOf(_month);
    _markets = _marketsOf(_month);
    _marketSales = _marketSalesOf(_month);
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
                builder: (context, snap) => StreamBuilder<List<Market>>(
                  key: ValueKey('m$_month'),
                  stream: _markets,
                  builder: (context, mSnap) => StreamBuilder<List<MarketSale>>(
                    key: ValueKey('v$_month'),
                    stream: _marketSales,
                    builder: (context, vSnap) => _body(
                      context,
                      snap,
                      daysSnap,
                      mSnap.data ?? const [],
                      vSnap.data ?? const [],
                    ),
                  ),
                ),
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
    List<Market> markets,
    List<MarketSale> marketSales,
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
    // Mercaditos ya cerrados (o de días pasados), con sus ventas.
    final doneMarkets = markets.where((m) => marketFinished(m, today: today)).toList();
    final salesOf = <String, List<MarketSale>>{};
    for (final v in marketSales) {
      salesOf.putIfAbsent(v.marketId, () => []).add(v);
    }
    final doneSales = [for (final m in doneMarkets) ...?salesOf[m.id]];
    if (orders.isEmpty && doneMarkets.isEmpty) {
      return EmptyState(
        title: 'Nada archivado ${_isCurrentMonth ? 'este mes' : 'en este mes'}',
        message: 'Cuando termines de repartir un día (o cierres un mercadito), aquí se guarda con lo que vendiste.',
      );
    }
    final dates = orders.map((o) => o.deliveryDate).toSet().toList();
    // Días distintos con algo vendido (a domicilio o en el mercadito).
    final soldDays = {
      for (final o in orders)
        if (o.status == OrderStatus.entregado) dayDateOf(o.deliveryDate),
      for (final m in doneMarkets)
        if (MarketSummary.of(salesOf[m.id] ?? const []).sales > 0) m.date,
    };
    // Tarjetas del mes, la más nueva primero; el mercadito va después de los repartos de su día.
    final cards = <(String, int, Widget)>[
      for (final d in dates)
        (
          d,
          0,
          _DayCard(
            date: d,
            orders: orders.where((o) => o.deliveryDate == d).toList(),
            // Si ese día hubo más de un reparto, se dice cuál es cuál.
            several: dates.where((x) => dayDateOf(x) == dayDateOf(d)).length > 1,
          ),
        ),
      for (final m in doneMarkets) (m.date, 1, _MarketCard(market: m, sales: salesOf[m.id] ?? const [])),
    ]..sort((a, b) {
        final c = dayDateOf(b.$1).compareTo(dayDateOf(a.$1));
        if (c != 0) return c;
        final k = a.$2.compareTo(b.$2);
        return k != 0 ? k : a.$1.compareTo(b.$1);
      });
    final children = <Widget>[
      _SummaryCard(
        summary: SalesSummary.of(orders),
        market: MarketSummary.of(doneSales, markets: doneMarkets),
        days: soldDays.length,
      ),
      for (final c in cards) c.$3,
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
        IconButton(tooltip: 'Mes anterior', onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(child: AnimatedCount(label, style: Theme.of(context).textTheme.titleLarge)),
        IconButton(tooltip: 'Mes siguiente', onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
      ],
    ),
  );
}

/// Totales del mes: lo vendido (a domicilio y en el mercadito), cómo se pagó
/// y lo que falta cobrar.
class _SummaryCard extends StatelessWidget {
  final SalesSummary summary;
  final MarketSummary market;

  /// Días distintos con algo vendido.
  final int days;
  const _SummaryCard({required this.summary, this.market = const MarketSummary(), required this.days});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final mk = market;
    final both = s.delivered > 0 && mk.sales > 0;
    final pieces = s.pieces + mk.pieces;
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
          Text(money(s.sold + mk.total), style: theme.textTheme.headlineMedium!.copyWith(color: Pan.caramelo)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Stat(icon: Icons.calendar_today_rounded, text: '$days ${days == 1 ? 'día' : 'días'}'),
              if (s.delivered > 0 || mk.sales == 0)
                _Stat(
                  icon: Icons.check_circle_rounded,
                  text: '${s.delivered} ${s.delivered == 1 ? 'pedido' : 'pedidos'}',
                ),
              if (mk.sales > 0)
                _Stat(
                  icon: Icons.shopping_bag_rounded,
                  text: '${mk.sales} ${mk.sales == 1 ? 'venta' : 'ventas'} en mercadito',
                ),
              _Stat(icon: Icons.bakery_dining_rounded, text: '$pieces ${pieces == 1 ? 'pieza' : 'piezas'}'),
              if (s.giftPieces > 0) _Stat(icon: Icons.card_giftcard_rounded, text: '${s.giftPieces} regaladas'),
            ],
          ),
          const SizedBox(height: 12),
          if (both) ...[
            _Line(icon: Icons.delivery_dining_rounded, label: 'A domicilio', value: money(s.sold)),
            _Line(icon: Icons.shopping_bag_rounded, label: 'Mercadito', value: money(mk.total)),
            const Divider(height: 14),
          ],
          _Line(icon: Icons.payments_rounded, label: 'Efectivo', value: money(s.cash + mk.cash)),
          _Line(icon: Icons.account_balance_rounded, label: 'Transferencia', value: money(s.transfer + mk.transfer)),
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
          if (mk.pending > 0)
            _Line(
              icon: Icons.upload_rounded,
              label: 'Ventas del mercadito por subir',
              value: '${mk.pending}',
              color: Pan.caramelo,
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
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w800, color: Pan.tostado),
        ),
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
  final bool several;
  const _DayCard({required this.date, required this.orders, this.several = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SalesSummary.of(orders);
    final sorted = [...orders]
      ..sort((a, b) {
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
          title: Text(
            several
                ? '${capitalize(dayLabel(date))} · ${clockLabel(slotMinute(sorted.first.slot))} · '
                    '${sorted.first.pickupName ?? 'a domicilio'}'
                : capitalize(dayLabel(date)),
            style: theme.textTheme.titleSmall,
          ),
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
                  '${itemsLabel(o.items)}\n'
                  '${money(o.total)} · ${payLabel(o)}',
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: true,
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => _OrderSheet(order: o),
                ),
                trailing: DeleteOrderButton(order: o),
              ),
          ],
        ),
      ),
    );
  }

  
}

/// Un mercadito ya cerrado: lo vendido de cada pan, lo que sobró y sus ventas.
class _MarketCard extends StatelessWidget {
  final Market market;
  final List<MarketSale> sales;
  const _MarketCard({required this.market, required this.sales});

  Future<void> _cancel(BuildContext context, MarketSale v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar esta venta?'),
        content: Text('${itemsLabel(v.items)} · ${money(v.total)}\n\nYa no cuenta en lo vendido.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (ok == true) await Repo.instance.setMarketSaleCancelled(v.id, true).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = MarketSummary.of(sales, markets: [market]);
    final sold = soldByUnit(sales);
    final sorted = [...sales]..sort((a, b) => (a.at ?? DateTime(2000)).compareTo(b.at ?? DateTime(2000)));
    return PanCard(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Pan.radio - 6),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Text('🧺', style: TextStyle(fontSize: 24)),
          title: Text('${capitalize(dayLabel(market.date))} · ${market.title}', style: theme.textTheme.titleSmall),
          subtitle: Text(
            '${s.sales} ${s.sales == 1 ? 'venta' : 'ventas'} · ${s.pieces} de ${s.brought} piezas'
            '${s.left > 0 ? ' · sobraron ${s.left}' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Text(
            money(s.total),
            style: theme.textTheme.titleMedium!.copyWith(color: Pan.caramelo, fontWeight: FontWeight.w800),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final u in marketUnits(market))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(u.label, style: theme.textTheme.bodyMedium)),
                    Text('${sold[u.key] ?? 0} de ${u.brought}',
                        style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Efectivo ${money(s.cash)} · Transferencia ${money(s.transfer)}',
              style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700),
            ),
            if (sorted.isNotEmpty) const Divider(height: 18),
            for (final v in sorted)
              MarketSaleTile(sale: v, onCancel: v.cancelled ? null : () => _cancel(context, v)),
          ],
        ),
      ),
    );
  }
}

String payLabel(BakeryOrder o) {
  if (o.status == OrderStatus.cancelado) return 'Cancelado';
  if (o.status != OrderStatus.entregado) return 'Sin marcar como entregado';
  if (o.paymentMethod == PaymentMethod.efectivo) {
    return o.cashCollected ? 'Efectivo, cobrado' : 'Efectivo, sin marcar cobrado';
  }
  return o.paymentVerified ? 'Transferencia verificada' : 'Transferencia sin verificar';
}

/// Al tocar un pedido del Historial: ver la captura y marcar que ya pagó
/// (o que sí se entregó, si se quedó sin marcar).
class _OrderSheet extends StatefulWidget {
  final BakeryOrder order;
  const _OrderSheet({required this.order});

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  late final Future<String?> _proof = widget.order.paymentProofPath == null
      ? Future.value(null)
      : Repo.instance.paymentProofUrl(widget.order.paymentProofPath!).then<String?>((u) => u, onError: (_) => null);
  bool _busy = false;

  Future<void> _save(Map<String, dynamic> changes, String done) async {
    setState(() => _busy = true);
    try {
      await Repo.instance.updateOrder(widget.order.id, changes);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar. Intenta de nuevo. ($e)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final theme = Theme.of(context);
    final isCash = o.paymentMethod == PaymentMethod.efectivo;
    final paid = isCash ? o.cashCollected : o.paymentVerified;
    final cancelled = o.status == OrderStatus.cancelado;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(o.customerName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${capitalize(dayLabel(o.deliveryDate))} · ${money(o.total)}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(payLabel(o), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            for (final it in o.items)
              Text('${productArt(it.name).$1} ${itemLabel(it)}${it.isGift ? ' · regalo' : ''}',
                  style: theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700)),
            if (!isCash) ...[
              const SizedBox(height: 14),
              FutureBuilder<String?>(
                future: _proof,
                builder: (context, snap) {
                  if (o.paymentProofPath == null) {
                    return Text('No subió captura del pago.', style: theme.textTheme.bodySmall);
                  }
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                    );
                  }
                  final url = snap.data;
                  if (url == null) return Text('No cargó la captura.', style: theme.textTheme.bodySmall);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                      child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            if (!cancelled && o.status != OrderStatus.entregado)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _save({'status': OrderStatus.entregado.name}, 'Marcado como entregado ✓'),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Sí se entregó'),
                ),
              ),
            if (!cancelled && !paid)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _save({
                        isCash ? 'cashCollected' : 'paymentVerified': true,
                      }, isCash ? 'Marcado como cobrado ✓' : 'Pago verificado ✓'),
                icon: const Icon(Icons.payments_rounded),
                label: Text(isCash ? 'Ya me pagó (cobrado)' : 'Ya me pagó (verificar transferencia)'),
              )
            else if (!cancelled)
              Text('Ya está pagado ✓', textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}
