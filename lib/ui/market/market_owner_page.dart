import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../logic/flavors.dart';
import '../../logic/market.dart';
import '../../logic/schedule.dart';
import '../../models.dart';
import '../../services/repo.dart';
import '../format.dart';
import '../stock_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'market_pos_page.dart';
import 'market_stock_page.dart';

/// Panel del dueño → Mercadito: abrirlo con lo que llevas, ver en vivo lo que
/// se vende y lo que queda, cerrarlo, y escoger la cuenta de la tablet.
class MarketOwnerPage extends StatefulWidget {
  const MarketOwnerPage({super.key});

  @override
  State<MarketOwnerPage> createState() => _MarketOwnerPageState();
}

class _MarketOwnerPageState extends State<MarketOwnerPage> {
  late final Stream<Market?> _open = Repo.instance.openMarket();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mercadito')),
      body: StreamBuilder<Market?>(
        stream: _open,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(title: 'No cargó el mercadito', message: '${snap.error}');
          }
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
            return const SkeletonList(count: 3);
          }
          final m = snap.data;
          return FadeThroughSwitcher(
            child: m == null
                ? const _ClosedView(key: ValueKey('cerrado'))
                : _LiveView(key: ValueKey(m.id), market: m),
          );
        },
      ),
    );
  }
}

void _openPos(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MarketPosPage()));

// ---------------------------------------------------------------------------
// Abierto: lo vendido en vivo
// ---------------------------------------------------------------------------

class _LiveView extends StatefulWidget {
  final Market market;
  const _LiveView({super.key, required this.market});

  @override
  State<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<_LiveView> {
  late final _sales = Repo.instance.marketSales(widget.market.id);

  Future<void> _close(MarketSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar el mercadito?'),
        content: Text(
          'Vendiste ${money(s.total)} (${s.pieces} ${s.pieces == 1 ? 'pieza' : 'piezas'}).'
          '${s.left > 0 ? ' Sobraron ${s.left}.' : ''}\n\n'
          'La tablet deja de vender y todo queda en el Historial.'
          '${s.pending > 0 ? '\n\nOjo: hay ${s.pending} ventas en este celular que todavía no se suben; '
              'se suben solas en cuanto haya señal.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Todavía no')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cerrar')),
        ],
      ),
    );
    if (ok != true) return;
    unawaited(Repo.instance.closeMarket(widget.market.id).catchError((Object e) => debugPrint('$e')));
  }

  void _edit(Map<String, int> sold) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MarketStockPage(editing: widget.market, sold: sold),
      ));

  @override
  Widget build(BuildContext context) {
    final m = widget.market;
    final theme = Theme.of(context);
    return StreamBuilder<({List<MarketSale> sales, bool offline})>(
      stream: _sales,
      builder: (context, snap) {
        final sales = snap.data?.sales ?? const <MarketSale>[];
        final s = MarketSummary.of(sales, markets: [m]);
        final units = marketUnits(m);
        final sold = soldByUnit(sales);
        final children = <Widget>[
          _LiveCard(market: m, summary: s, offline: snap.data?.offline ?? false),
          const SizedBox(height: 10),
          HoneyButton(
            label: 'Abrir la caja aquí',
            icon: Icons.payments_rounded,
            onPressed: () => _openPos(context),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _edit(sold),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Cambiar panes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Pan.terracota),
                  onPressed: () => _close(s),
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('Cerrar mercadito'),
                ),
              ),
            ],
          ),
          const SectionTitle('Lo que queda'),
          PanCard(
            child: Column(
              children: [
                for (final u in units)
                  StockMeter(
                    label: u.label,
                    left: (u.brought - (sold[u.key] ?? 0)).clamp(0, 1 << 30),
                    limit: u.brought,
                  ),
              ],
            ),
          ),
          SectionTitle(
            'Ventas',
            trailing: sales.length > 6
                ? TextButton(
                    onPressed: () => _showAllSales(context, sales),
                    child: Text('Ver las ${sales.length}'),
                  )
                : null,
          ),
          if (sales.isEmpty)
            PanCard(
              child: Text('Aquí van apareciendo las ventas de la tablet, al momento.',
                  style: theme.textTheme.bodyMedium!.copyWith(color: Pan.canela)),
            )
          else
            PanCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final sale in sales.take(6))
                    MarketSaleTile(
                      sale: sale,
                      onCancel: () => _cancel(context, sale),
                      onRestore: () => _restore(sale.id),
                    ),
                ],
              ),
            ),
          const SectionTitle('Tablet del puesto'),
          const CajaAccountsCard(),
        ];
        return ReadableList(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          builder: (context, pad) => ListView.builder(
            padding: pad,
            itemCount: children.length,
            itemBuilder: (context, i) => FadeSlideIn(index: i, child: children[i]),
          ),
        );
      },
    );
  }

  void _showAllSales(BuildContext context, List<MarketSale> sales) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => MarketSalesSheet(
          sales: sales,
          canRestore: true,
          onCancel: (id) => unawaited(Repo.instance.setMarketSaleCancelled(id, true).catchError((_) {})),
          onRestore: _restore,
        ),
      );

  Future<void> _cancel(BuildContext context, MarketSale s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar esta venta?'),
        content: Text('${itemsLabel(s.items)} · ${money(s.total)}\n\nSus panes vuelven a estar disponibles.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (ok == true) unawaited(Repo.instance.setMarketSaleCancelled(s.id, true).catchError((_) {}));
  }

  void _restore(String id) => unawaited(Repo.instance.setMarketSaleCancelled(id, false).catchError((_) {}));
}

/// Tarjeta de miel: abierto desde qué hora, cuánto llevas vendido y cómo te pagaron.
class _LiveCard extends StatelessWidget {
  final Market market;
  final MarketSummary summary;
  final bool offline;
  const _LiveCard({required this.market, required this.summary, required this.offline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final since = market.openedAt == null
        ? ''
        : '\ndesde las ${DateFormat('h:mm a', 'es_MX').format(market.openedAt!)}';
    return PanCard(
      gradient: Pan.gradienteMiel,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PulseDot(color: Colors.white, size: 8),
              const SizedBox(width: 4),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Abierto · ${market.title}'),
                    TextSpan(text: since, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Pan.cacao),
                ),
              ),
              if (s.pending > 0 || offline) SyncPill(offline: offline, pending: s.pending, compact: true),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Llevas vendido', style: TextStyle(fontWeight: FontWeight.w700, color: Pan.tostado)),
          AnimatedCount(
            money(s.total),
            alignment: Alignment.centerLeft,
            style: theme.textTheme.displaySmall!.copyWith(color: Pan.cacao),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                  icon: Icons.receipt_long_rounded, text: '${s.sales} ${s.sales == 1 ? 'venta' : 'ventas'}'),
              _Chip(icon: Icons.bakery_dining_rounded, text: '${s.pieces} de ${s.brought} piezas'),
              _Chip(icon: Icons.payments_rounded, text: 'Efectivo ${money(s.cash)}'),
              if (s.transfer > 0)
                _Chip(icon: Icons.phone_iphone_rounded, text: 'Transferencia ${money(s.transfer)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: Pan.papel.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(14)),
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

// ---------------------------------------------------------------------------
// Cerrado: abrir uno nuevo y los anteriores
// ---------------------------------------------------------------------------

class _ClosedView extends StatefulWidget {
  const _ClosedView({super.key});

  @override
  State<_ClosedView> createState() => _ClosedViewState();
}

class _ClosedViewState extends State<_ClosedView> {
  late final Stream<List<Market>> _recent = Repo.instance.recentMarkets(limit: 6);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReadableList(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      builder: (context, pad) => ListView(
        padding: pad,
        children: [
          FadeSlideIn(
            child: PanCard(
              gradient: Pan.gradienteMiel,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('¿Hoy vas al mercadito?',
                            style: theme.textTheme.headlineSmall!.copyWith(color: Pan.cacao)),
                      ),
                      const Text('🧺', style: TextStyle(fontSize: 40)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pon cuántos panes llevas. En la tablet tus clientes tocan su pan, ven el total, '
                    'y tú cobras con un toque. Aquí ves lo vendido y lo que queda, al momento.',
                    style: TextStyle(color: Pan.cacao, fontWeight: FontWeight.w600, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Pan.cacao),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const MarketStockPage())),
                    icon: const Icon(Icons.shopping_bag_rounded),
                    label: const Text('Abrir mercadito'),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Tablet del puesto'),
          const FadeSlideIn(index: 1, child: CajaAccountsCard()),
          StreamBuilder<List<Market>>(
            stream: _recent,
            builder: (context, snap) {
              final list = snap.data ?? const <Market>[];
              if (list.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('Anteriores'),
                  _RecentMarkets(markets: list),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Los últimos mercaditos con lo que se vendió en cada uno.
class _RecentMarkets extends StatefulWidget {
  final List<Market> markets;
  const _RecentMarkets({required this.markets});

  @override
  State<_RecentMarkets> createState() => _RecentMarketsState();
}

class _RecentMarketsState extends State<_RecentMarkets> {
  late Stream<List<MarketSale>> _sales = _salesFor(widget.markets);
  late String _range = _rangeOf(widget.markets);

  static String _rangeOf(List<Market> l) => l.isEmpty ? '' : '${l.last.date}_${l.first.date}';

  static Stream<List<MarketSale>> _salesFor(List<Market> l) {
    if (l.isEmpty) return const Stream.empty();
    final to = dateKey(parseDateKey(l.first.date).add(const Duration(days: 1)));
    return Repo.instance.marketSalesBetween(l.last.date, to);
  }

  @override
  void didUpdateWidget(_RecentMarkets old) {
    super.didUpdateWidget(old);
    final r = _rangeOf(widget.markets);
    if (r != _range) {
      _range = r;
      _sales = _salesFor(widget.markets);
    }
  }

  Future<void> _menu(Market m, String action) async {
    if (action == 'abrir') {
      unawaited(Repo.instance.reopenMarket(m.id).catchError((_) {}));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar este mercadito?'),
        content: const Text('Se borra con todas sus ventas y ya no sale en el Historial. '
            'Úsalo para quitar los de prueba.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Pan.terracota),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.instance.deleteMarket(m.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo borrar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dateKey(DateTime.now());
    return StreamBuilder<List<MarketSale>>(
      stream: _sales,
      builder: (context, snap) {
        final all = snap.data ?? const <MarketSale>[];
        return PanCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final m in widget.markets)
                Builder(builder: (context) {
                  final s = MarketSummary.of(all.where((x) => x.marketId == m.id), markets: [m]);
                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 4),
                    leading: const Text('🧺', style: TextStyle(fontSize: 24)),
                    title: Text('${capitalize(dayLabel(m.date))} · ${m.title}',
                        style: theme.textTheme.titleSmall),
                    subtitle: Text(
                      snap.hasData
                          ? '${money(s.total)} · ${s.pieces} de ${s.brought} piezas · ${s.sales} '
                              '${s.sales == 1 ? 'venta' : 'ventas'}'
                          : '${m.pieces} piezas',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      onSelected: (a) => _menu(m, a),
                      itemBuilder: (_) => [
                        if (m.date == today)
                          const PopupMenuItem(value: 'abrir', child: Text('Volver a abrir')),
                        const PopupMenuItem(value: 'borrar', child: Text('Borrar (de prueba)')),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// La cuenta de la tablet
// ---------------------------------------------------------------------------

/// Qué cuentas abren directo la caja (la tablet del puesto). Se agregan con su correo.
class CajaAccountsCard extends StatefulWidget {
  const CajaAccountsCard({super.key});

  @override
  State<CajaAccountsCard> createState() => _CajaAccountsCardState();
}

class _CajaAccountsCardState extends State<CajaAccountsCard> {
  late final _accounts = Repo.instance.cajaAccounts();

  Future<void> _add() async {
    final email = await showDialog<String>(context: context, builder: (_) => const _CajaDialog());
    if (email == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Listo. En la tablet entra con $email y se abre la caja.')),
    );
  }

  Future<void> _remove(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar esta cuenta de la tablet?'),
        content: Text('$email ya no abre la caja (queda como cuenta normal).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, quitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.instance.setCajaAccount(email, remove: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<({String uid, String email, String name})>>(
      stream: _accounts,
      builder: (context, snap) {
        final list = snap.data ?? const [];
        return PanCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Pan.cieloClaro, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.phone_android_rounded, color: Pan.cielo),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      list.isEmpty
                          ? 'Escoge una cuenta para la tablet. Al entrar con ella se abre directo la caja: '
                              'no ve tus pedidos ni tus clientes.'
                          : 'Estas cuentas abren directo la caja:',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              for (final a in list)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 4),
                  leading: const Icon(Icons.payments_rounded),
                  title: Text(a.email.isEmpty ? a.name : a.email, style: theme.textTheme.titleSmall),
                  trailing: TextButton(
                    onPressed: a.email.isEmpty ? null : () => _remove(a.email),
                    child: const Text('Quitar'),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(list.isEmpty ? 'Escoger cuenta de la tablet' : 'Agregar otra'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Correo de la cuenta de la tablet. Si no existe, pide contraseña y la crea.
class _CajaDialog extends StatefulWidget {
  const _CajaDialog();

  @override
  State<_CajaDialog> createState() => _CajaDialogState();
}

class _CajaDialogState extends State<_CajaDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _needsPassword = false;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Escribe el correo de la cuenta.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Repo.instance.setCajaAccount(email, password: _needsPassword ? _password.text : null);
      if (mounted) Navigator.pop(context, email);
    } on RejectedByServer catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.code == 'sin-cuenta' && !_needsPassword) {
          _needsPassword = true;
          _error = null;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo guardar. Revisa tu internet. ($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Cuenta de la tablet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Usa un correo que no sea el tuyo de dueño (por ejemplo, una cuenta de prueba). '
              'Al entrar con él en la tablet se abre directo la caja.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              enabled: !_busy && !_needsPassword,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline_rounded)),
            ),
            AnimatedSize(
              duration: Motion.of(context, Motion.medio),
              child: _needsPassword
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Esa cuenta no existe todavía. Ponle una contraseña y la creamos.',
                              style: theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _password,
                            enabled: !_busy,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña (6 o más)',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: theme.textTheme.bodyMedium!.copyWith(color: Pan.terracota)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Text(_needsPassword ? 'Crear y usar' : 'Usar esta cuenta'),
        ),
      ],
    );
  }
}
